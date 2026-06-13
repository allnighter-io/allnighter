#!/usr/bin/env python3
"""Local Codex -> Cursor commit handoff queue.

The queue is intentionally narrow: Codex records exact files + a commit message;
Cursor processes one pending item by staging only those files and committing.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
QUEUE_PATH = ROOT / ".wmd" / "commit-queue.jsonl"
ALLOWED_REPO = str(ROOT)
GIT_LOCK_RETRY_ATTEMPTS = 3
GIT_LOCK_RETRY_DELAY_SECONDS = 2


class HandoffError(Exception):
    pass


def git_failure_detail(result: subprocess.CompletedProcess[str]) -> str:
    return (result.stderr or result.stdout).strip()


def is_git_lock_failure(result: subprocess.CompletedProcess[str]) -> bool:
    detail = git_failure_detail(result)
    return (
        result.returncode != 0
        and ".git/index.lock" in detail
        and "Another git process seems to be running" in detail
    )


def utc_now() -> str:
    return (
        datetime.now(timezone.utc)
        .isoformat(timespec="seconds")
        .replace("+00:00", "Z")
    )


def run_git(
    args: list[str], *, check: bool = True, input_text: str | None = None
) -> subprocess.CompletedProcess[str]:
    attempts = GIT_LOCK_RETRY_ATTEMPTS if check else 1
    for attempt in range(attempts):
        result = subprocess.run(
            ["git", *args],
            cwd=ROOT,
            text=True,
            input=input_text,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        if not check or not is_git_lock_failure(result) or attempt == attempts - 1:
            break
        time.sleep(GIT_LOCK_RETRY_DELAY_SECONDS)
    if check and result.returncode != 0:
        detail = git_failure_detail(result)
        raise HandoffError(f"git {' '.join(args)} failed: {detail}")
    return result


def current_branch() -> str:
    result = run_git(["rev-parse", "--abbrev-ref", "HEAD"])
    return result.stdout.strip()


def read_queue() -> list[dict[str, Any]]:
    if not QUEUE_PATH.exists():
        return []
    items: list[dict[str, Any]] = []
    for line_no, raw_line in enumerate(
        QUEUE_PATH.read_text(encoding="utf-8").splitlines(), 1
    ):
        line = raw_line.strip()
        if not line:
            continue
        try:
            item = json.loads(line)
        except json.JSONDecodeError as exc:
            raise HandoffError(f"{QUEUE_PATH}:{line_no}: invalid JSON: {exc}") from exc
        if not isinstance(item, dict):
            raise HandoffError(f"{QUEUE_PATH}:{line_no}: queue item must be a JSON object")
        items.append(item)
    return items


def write_queue(items: list[dict[str, Any]]) -> None:
    QUEUE_PATH.parent.mkdir(parents=True, exist_ok=True)
    temp_path = QUEUE_PATH.with_name(f"{QUEUE_PATH.name}.tmp-{os.getpid()}-{uuid.uuid4().hex}")
    payload = "".join(
        json.dumps(item, separators=(",", ":"), sort_keys=True) + "\n"
        for item in items
    )
    temp_path.write_text(payload, encoding="utf-8")
    os.replace(temp_path, QUEUE_PATH)


def normalize_path(raw_path: str) -> str:
    if not isinstance(raw_path, str) or not raw_path.strip():
        raise HandoffError("paths must be non-empty strings")
    if raw_path != raw_path.strip():
        raise HandoffError(f"path has surrounding whitespace: {raw_path!r}")
    path = Path(raw_path)
    if path.is_absolute():
        raise HandoffError(f"absolute paths are not allowed: {raw_path}")
    if any(part in ("", ".", "..") for part in path.parts):
        raise HandoffError(f"path must stay inside repo: {raw_path}")
    if any(char in raw_path for char in "*?{}"):
        raise HandoffError(f"wildcards are not allowed: {raw_path}")
    repo_path = (ROOT / path).resolve()
    try:
        repo_path.relative_to(ROOT)
    except ValueError as exc:
        raise HandoffError(f"path escapes repo: {raw_path}") from exc
    if repo_path.exists() and repo_path.is_dir():
        raise HandoffError(f"directories are not allowed; list files explicitly: {raw_path}")
    if not repo_path.exists():
        tracked = run_git(["ls-files", "--error-unmatch", "--", raw_path], check=False)
        if tracked.returncode != 0:
            raise HandoffError(f"path does not exist and is not tracked: {raw_path}")
    return path.as_posix()


def validate_paths(paths: Any) -> list[str]:
    if not isinstance(paths, list) or not paths:
        raise HandoffError("paths must be a non-empty array")
    normalized: list[str] = []
    seen: set[str] = set()
    for raw_path in paths:
        path = normalize_path(raw_path)
        if path not in seen:
            normalized.append(path)
            seen.add(path)
    return normalized


def validate_commit_message(message: Any) -> str:
    if not isinstance(message, str) or not message.strip():
        raise HandoffError("commit_message must be a non-empty string")
    if "\n" in message or "\r" in message or "\x00" in message:
        raise HandoffError("commit_message must be a single line")
    return message


def validate_patch_text(raw_patch: Any) -> str | None:
    if raw_patch is None:
        return None
    if not isinstance(raw_patch, str) or not raw_patch.strip():
        raise HandoffError("patch must be a non-empty string when provided")
    if "\x00" in raw_patch:
        raise HandoffError("patch must not contain NUL bytes")
    return raw_patch


def validate_pending_item(item: dict[str, Any]) -> tuple[str, list[str], str, str | None]:
    if item.get("repo") != ALLOWED_REPO:
        raise HandoffError(f"repo must be {ALLOWED_REPO}")
    if item.get("status") != "pending":
        raise HandoffError("item status must be pending")
    branch = item.get("branch")
    if not isinstance(branch, str) or not branch:
        raise HandoffError("branch must be a non-empty string")
    paths = validate_paths(item.get("paths"))
    message = validate_commit_message(item.get("commit_message"))
    patch = validate_patch_text(item.get("patch"))
    return branch, paths, message, patch


def unstaged_tracked_paths() -> set[str]:
    result = run_git(["diff", "--name-only"])
    return {line.strip() for line in result.stdout.splitlines() if line.strip()}


def untracked_unignored_paths() -> set[str]:
    result = run_git(["ls-files", "--others", "--exclude-standard"])
    return {line.strip() for line in result.stdout.splitlines() if line.strip()}


def create_proof_isolation_stash(item_id: str, requested_paths: set[str]) -> str | None:
    outside_unstaged = (
        unstaged_tracked_paths() | untracked_unignored_paths()
    ) - requested_paths
    if not outside_unstaged:
        return None

    message = f"commit-handoff proof isolation {item_id}"
    run_git(
        [
            "stash",
            "push",
            "--keep-index",
            "--include-untracked",
            "--quiet",
            "--message",
            message,
        ]
    )
    top = run_git(["stash", "list", "--format=%gd %s"]).stdout.splitlines()
    if not top or message not in top[0]:
        raise HandoffError("failed to create proof isolation stash")
    return message


def restore_proof_isolation_stash(message: str) -> None:
    top = run_git(["stash", "list", "--format=%gd %s"]).stdout.splitlines()
    if not top or message not in top[0]:
        raise HandoffError("proof isolation stash is not on top; refusing to pop")
    run_git(["stash", "pop", "--quiet"])


def ensure_restore_worktree_is_quiet(message: str, requested_paths: set[str]) -> None:
    outside_changes = (
        unstaged_tracked_paths() | untracked_unignored_paths()
    ) - requested_paths
    if not outside_changes:
        return
    preview = ", ".join(sorted(outside_changes)[:8])
    suffix = "" if len(outside_changes) <= 8 else f", ... +{len(outside_changes) - 8} more"
    raise HandoffError(
        "proof isolation restore blocked: files outside the request changed "
        f"during the green wall: {preview}{suffix}. "
        f"Isolation stash left on top: {message}"
    )


def run_green_wall(item_id: str, requested_paths: set[str]) -> None:
    stash_message = create_proof_isolation_stash(item_id, requested_paths)
    try:
        result = subprocess.run(
            ["npm", "run", "check"],
            cwd=ROOT,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            check=False,
        )
        if result.returncode != 0:
            output = (result.stdout or "").strip()
            tail = output[-8000:] if len(output) > 8000 else output
            raise HandoffError(f"npm run check failed before commit:\n{tail}")
    finally:
        if stash_message is not None:
            ensure_restore_worktree_is_quiet(stash_message, requested_paths)
            restore_proof_isolation_stash(stash_message)


def staged_paths() -> set[str]:
    result = run_git(["diff", "--cached", "--name-only"])
    return {line.strip() for line in result.stdout.splitlines() if line.strip()}


def update_item_status(
    items: list[dict[str, Any]],
    item_id: str,
    *,
    status: str,
    commit_sha: str | None = None,
    failure_reason: str | None = None,
) -> None:
    for item in items:
        if item.get("id") == item_id:
            item["status"] = status
            item["completed_at"] = utc_now()
            item["commit_sha"] = commit_sha
            item["failure_reason"] = failure_reason
            write_queue(items)
            return
    raise HandoffError(f"queue item disappeared: {item_id}")


def read_patch_file(path: str | None) -> str | None:
    if path is None:
        return None
    patch_path = Path(path)
    if not patch_path.is_file():
        raise HandoffError(f"patch file does not exist: {path}")
    patch = patch_path.read_text(encoding="utf-8")
    return validate_patch_text(patch)


def enqueue_item(
    paths: list[str],
    message: str,
    branch: str | None,
    patch: str | None,
    *,
    check_only: bool = False,
) -> str:
    item_id = str(uuid.uuid4())
    item = {
        "id": item_id,
        "status": "pending",
        "branch": branch or current_branch(),
        "repo": ALLOWED_REPO,
        "paths": validate_paths(paths),
        "commit_message": validate_commit_message(message),
        "patch": validate_patch_text(patch),
        "created_at": utc_now(),
        "completed_at": None,
        "commit_sha": None,
        "failure_reason": None,
    }
    if check_only:
        item["check_only"] = True
    items = read_queue()
    items.append(item)
    write_queue(items)
    return item_id


def enqueue(
    paths: list[str], message: str, branch: str | None, patch: str | None = None
) -> str:
    return enqueue_item(paths, message, branch, patch)


def enqueue_check(paths: list[str], branch: str | None) -> str:
    return enqueue_item(paths, "check only", branch, None, check_only=True)


def find_item(item_id: str) -> dict[str, Any]:
    for item in read_queue():
        if item.get("id") == item_id:
            return item
    raise HandoffError(f"queue item not found: {item_id}")


def wait_for_item(item_id: str, timeout_seconds: int, interval_seconds: int) -> int:
    deadline = time.monotonic() + timeout_seconds
    while True:
        item = find_item(item_id)
        status = item.get("status")
        if status == "done":
            commit_sha = item.get("commit_sha")
            print(f"done {commit_sha}" if commit_sha else "done")
            return 0
        if status == "failed":
            print(f"failed {item.get('failure_reason')}", file=sys.stderr)
            return 2
        if time.monotonic() >= deadline:
            print(f"timeout waiting for {item_id}", file=sys.stderr)
            return 3
        time.sleep(interval_seconds)


def process_next() -> int:
    items = read_queue()
    item = next((candidate for candidate in items if candidate.get("status") == "pending"), None)
    if item is None:
        print("no pending commit handoff")
        return 0

    item_id = str(item.get("id", ""))
    staged_by_worker: list[str] = []
    try:
        if not item_id:
            raise HandoffError("id must be a non-empty string")
        expected_branch, paths, message, patch = validate_pending_item(item)
        actual_branch = current_branch()
        if actual_branch != expected_branch:
            raise HandoffError(f"branch mismatch: expected {expected_branch}, got {actual_branch}")
        if item.get("check_only") is True:
            if staged_paths():
                raise HandoffError("pre-existing staged changes would affect check-only proof")
            run_green_wall(item_id, set(paths))
            update_item_status(read_queue(), item_id, status="done")
            print(f"done {item_id} check")
            return 0
        before = staged_paths()
        requested = set(paths)
        unexpected_preexisting = before - requested
        if unexpected_preexisting:
            raise HandoffError(
                "pre-existing staged changes would be included: "
                + ", ".join(sorted(unexpected_preexisting))
            )
        if patch is None:
            run_git(["add", "--", *paths])
        else:
            run_git(["apply", "--cached", "--whitespace=nowarn", "-"], input_text=patch)
        staged_by_worker = paths
        after = staged_paths()
        unexpected = after - requested
        if unexpected:
            raise HandoffError("unexpected staged paths: " + ", ".join(sorted(unexpected)))
        if not after:
            raise HandoffError("requested paths produced no staged changes")
        run_green_wall(item_id, requested)
        run_git(["commit", "-m", message])
        commit_sha = run_git(["rev-parse", "HEAD"]).stdout.strip()
    except Exception as exc:
        failure_reason = str(exc)
        if staged_by_worker:
            cleanup = run_git(["restore", "--staged", "--", *staged_by_worker], check=False)
            if cleanup.returncode != 0:
                cleanup_detail = (cleanup.stderr or cleanup.stdout).strip()
                failure_reason = f"{failure_reason}; failed to unstage request: {cleanup_detail}"
        update_item_status(read_queue(), item_id, status="failed", failure_reason=failure_reason)
        print(f"failed {item_id}: {exc}", file=sys.stderr)
        return 2

    update_item_status(read_queue(), item_id, status="done", commit_sha=commit_sha)
    print(f"done {item_id} {commit_sha}")
    return 0


def status(item_id: str | None) -> int:
    items = read_queue()
    selected = items if item_id is None else [item for item in items if item.get("id") == item_id]
    for item in selected:
        print(json.dumps(item, sort_keys=True))
    if item_id is not None and not selected:
        print(f"queue item not found: {item_id}", file=sys.stderr)
        return 1
    return 0


def check_paths(paths: list[str]) -> int:
    normalized = validate_paths(paths)
    check_id = f"check-{uuid.uuid4()}"
    run_green_wall(check_id, set(normalized))
    print("check ok")
    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    request = subparsers.add_parser("request", help="append a pending commit request")
    request.add_argument("--message", required=True, help="single-line commit message")
    request.add_argument("--branch", help="expected branch; defaults to current branch")
    request.add_argument(
        "--patch-file",
        help="optional unified diff to apply to the index instead of staging whole paths",
    )
    request.add_argument(
        "--path",
        action="append",
        required=True,
        dest="paths",
        help="explicit file path",
    )
    request.add_argument("--wait", action="store_true", help="wait for Cursor to process the item")
    request.add_argument("--timeout-seconds", type=int, default=600)
    request.add_argument("--interval-seconds", type=int, default=60)

    check_request = subparsers.add_parser(
        "check-request",
        help="append a pending isolated green-wall request without committing",
    )
    check_request.add_argument("--branch", help="expected branch; defaults to current branch")
    check_request.add_argument(
        "--path",
        action="append",
        required=True,
        dest="paths",
        help="explicit file path to keep visible during the isolated check",
    )
    check_request.add_argument("--wait", action="store_true", help="wait for Cursor to process the item")
    check_request.add_argument("--timeout-seconds", type=int, default=600)
    check_request.add_argument("--interval-seconds", type=int, default=60)

    wait = subparsers.add_parser("wait", help="wait for a queue item by id")
    wait.add_argument("id")
    wait.add_argument("--timeout-seconds", type=int, default=600)
    wait.add_argument("--interval-seconds", type=int, default=60)

    check = subparsers.add_parser(
        "check",
        help="run the isolated green wall for explicit in-progress paths without committing",
    )
    check.add_argument(
        "--path",
        action="append",
        required=True,
        dest="paths",
        help="explicit file path to keep visible during the isolated check",
    )

    subparsers.add_parser("process-next", help="process the oldest pending item")

    show = subparsers.add_parser("status", help="print queue items")
    show.add_argument("id", nargs="?")

    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        if args.command == "request":
            item_id = enqueue(
                args.paths,
                args.message,
                args.branch,
                read_patch_file(args.patch_file),
            )
            print(item_id)
            if args.wait:
                return wait_for_item(item_id, args.timeout_seconds, args.interval_seconds)
            return 0
        if args.command == "check-request":
            item_id = enqueue_check(args.paths, args.branch)
            print(item_id)
            if args.wait:
                return wait_for_item(item_id, args.timeout_seconds, args.interval_seconds)
            return 0
        if args.command == "wait":
            return wait_for_item(args.id, args.timeout_seconds, args.interval_seconds)
        if args.command == "check":
            return check_paths(args.paths)
        if args.command == "process-next":
            return process_next()
        if args.command == "status":
            return status(args.id)
    except HandoffError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
