#!/usr/bin/env python3
"""SH-S09 — diversified, quota-free sharpening regression gate (no score — D5).

Drives `alln` the way a cold agent must after bootstrap: one menu discovery
read per case budget, then the exact grammars for preview / run / inspect /
author / detach / recover / docs. Fixture drivers on a curated PATH + isolated
ALLNIGHTER_SUPPORT_DIR ensure no paid provider starts.

Usage:
  python3 scripts/sharpening_eval.py --binary Packages/AllnighterCore/.build/release/alln
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import uuid
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

ENVELOPE_OVERHEAD_BUDGET = 4096  # SH-S02
MENU_BUDGET_BYTES = 32768

# Driver id → bin name(s) installed into fakebin.
FIXTURE_BINS: dict[str, list[str]] = {
    "claude_code": ["claude"],
    "codex": ["codex"],
    "cursor_agent": ["agent", "cursor-agent"],
    "grok": ["grok"],
    "kimi": ["kimi"],
    "antigravity": ["agy"],
    "opencode": ["opencode"],
}

FIXTURE_DRIVER_SCRIPT = r"""#!/bin/bash
# Quota-free fixture driver for SH-S09. Never talks to a real provider.
if [ "${1:-}" = "--version" ] || [ "${1:-}" = "version" ] || [ "${1:-}" = "-v" ]; then
  echo "alln-fixture-driver 0.0.1"
  exit 0
fi
if [ -n "${ALLN_FIXTURE_LOG:-}" ]; then
  printf 'HIT bin=%s cwd=%s\n' "$(basename "$0")" "$PWD" >> "$ALLN_FIXTURE_LOG"
fi
printf '%s\n' "${ALLN_FIXTURE_ANSWER:-success}"
exit 0
"""


@dataclass
class Attempt:
    argv: list[str]
    exit_code: int
    stdout: str
    stderr: str
    response_bytes: int
    parsed: dict[str, Any] | None = None
    provider_hits_before: int = 0
    provider_hits_after: int = 0

    @property
    def provider_started(self) -> bool:
        return self.provider_hits_after > self.provider_hits_before


@dataclass
class CaseResult:
    name: str
    ok: bool
    calls: int
    max_calls: int
    response_bytes: int = 0
    notes: list[str] = field(default_factory=list)
    error: str | None = None
    attempts: list[Attempt] = field(default_factory=list)
    hard_failure: bool = False


@dataclass
class Claim:
    claim: str
    binary_sha: str
    receipt: str
    verdict: str  # confirmed | refuted | noted


class Harness:
    def __init__(
        self,
        binary: Path,
        out_dir: Path,
        *,
        allow_stale_gitsha: bool,
    ) -> None:
        self.binary = binary.resolve()
        self.out_dir = out_dir
        self.allow_stale_gitsha = allow_stale_gitsha
        self.pinned_sha = ""
        self.version: dict[str, Any] = {}
        self.head_sha = ""
        self.state_dir = Path(tempfile.mkdtemp(prefix="alln-sharpening-"))
        self.support = self.state_dir / "support"
        self.fakebin = self.state_dir / "fakebin"
        self.repo = self.state_dir / "repo"
        self.home = self.state_dir / "home"
        self.provider_log = self.state_dir / "provider.log"
        self.menu: dict[str, Any] = {}
        self.menu_bytes = 0
        self.cases: list[CaseResult] = []
        self.claims: list[Claim] = []
        self.attempts: list[Attempt] = []
        self.env: dict[str, str] = {}
        self.hard_failures = 0
        self._menu_budget_checked = False

    # --- lifecycle ---------------------------------------------------------

    def fail_hard(self, msg: str) -> None:
        self.hard_failures += 1
        print(f"sharpening_eval: HARD FAIL: {msg}", file=sys.stderr)
        self._write_report(ok=False)
        self._cleanup()
        sys.exit(1)

    def setup(self) -> None:
        for d in (self.support / "Config", self.fakebin, self.repo, self.home):
            d.mkdir(parents=True, exist_ok=True)
        self.provider_log.write_text("")

        for bins in FIXTURE_BINS.values():
            for name in bins:
                path = self.fakebin / name
                path.write_text(FIXTURE_DRIVER_SCRIPT)
                path.chmod(0o755)

        self._seed_setup_cache()
        self._init_git_repo(self.repo)

        self.env = {
            **os.environ,
            "ALLNIGHTER_SUPPORT_DIR": str(self.support),
            "ALLNIGHTER_SKIP_LOGIN_PATH_BOOTSTRAP": "1",
            "PATH": f"{self.fakebin}:/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": str(self.home),
            "TMPDIR": str(self.home),
            "ALLN_FIXTURE_LOG": str(self.provider_log),
            "ALLN_FIXTURE_ANSWER": "success",
        }
        # Drop ambient provider paths that could shadow fixtures.
        for drop in ("ANTHROPIC_API_KEY", "OPENAI_API_KEY", "XAI_API_KEY"):
            self.env.pop(drop, None)

        add = self.run(
            ["project", "add", str(self.repo), "--json"],
            expect_ok=True,
            parse_json=True,
            cwd=self.repo,
            count_as_case=False,
        )
        body = add.parsed or {}
        project = body.get("project") or {}
        if not str(project.get("id") or ""):
            self.fail_hard("project add did not return project.id")

    def _seed_setup_cache(self) -> None:
        from datetime import datetime, timezone

        now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        records = [
            {
                "driverId": driver_id,
                "status": {"kind": "ready", "version": "fixture-0.0.1"},
                "version": "fixture-0.0.1",
                "lastProbeAt": now,
            }
            for driver_id in FIXTURE_BINS
        ]
        payload = {"records": records, "setupCompletedAt": now}
        (self.support / "Config" / "cli_setup.json").write_text(
            json.dumps(payload, indent=2) + "\n"
        )

    def _init_git_repo(self, path: Path) -> None:
        subprocess.run(["git", "init", "-q"], cwd=path, check=True)
        (path / "README.md").write_text("# sharpening fixture\n")
        subprocess.run(["git", "add", "README.md"], cwd=path, check=True)
        subprocess.run(
            [
                "git",
                "-c",
                "user.email=sharpening@alln.local",
                "-c",
                "user.name=Sharpening",
                "commit",
                "-q",
                "-m",
                "init",
            ],
            cwd=path,
            check=True,
        )

    def _cleanup(self) -> None:
        shutil.rmtree(self.state_dir, ignore_errors=True)

    # --- binary pin --------------------------------------------------------

    def pin_binary(self) -> None:
        if not self.binary.is_file() or not os.access(self.binary, os.X_OK):
            self.fail_hard(f"binary missing or not executable: {self.binary}")
        self.pinned_sha = hashlib.sha256(self.binary.read_bytes()).hexdigest()
        expected = os.environ.get("ALLN_EVAL_PINNED_SHA", "").strip()
        if expected and expected != self.pinned_sha:
            self.fail_hard(
                f"stale binary: sha256 {self.pinned_sha} != ALLN_EVAL_PINNED_SHA {expected}"
            )
        ver = self.run(
            ["version", "--json"],
            expect_ok=True,
            parse_json=True,
            count_as_case=False,
        )
        if not isinstance(ver.parsed, dict):
            self.fail_hard("version --json did not parse")
        self.version = ver.parsed
        head = subprocess.run(
            ["git", "rev-parse", "HEAD"], capture_output=True, text=True, check=False
        )
        self.head_sha = (head.stdout or "").strip()
        embedded = str(self.version.get("gitSha") or "")
        if (
            self.head_sha
            and embedded
            and embedded != "unknown"
            and not embedded.startswith(self.head_sha[:12])
            and self.head_sha[:12] not in embedded
            and embedded != self.head_sha
        ):
            msg = (
                f"binary BuildInfo gitSha={embedded} != workspace HEAD={self.head_sha}"
            )
            if self.allow_stale_gitsha or os.environ.get("ALLN_EVAL_ALLOW_STALE_GITSHA") == "1":
                print(f"sharpening_eval: WARN: {msg}")
            elif os.environ.get("ALLN_EVAL_REQUIRE_FRESH_GITSHA") == "1":
                self.fail_hard(msg)
            else:
                print(f"sharpening_eval: WARN: {msg} (file sha pinned; continue)")

        (self.out_dir / "pinned-binary.sha256").write_text(self.pinned_sha + "\n")
        (self.out_dir / "version.json").write_text(json.dumps(self.version, indent=2) + "\n")
        (self.out_dir / "workspace-HEAD.txt").write_text(self.head_sha + "\n")
        (self.out_dir / "state-dir.txt").write_text(str(self.state_dir) + "\n")
        print(f"pinned binary sha256: {self.pinned_sha}")
        print(f"binary contractVersion: {self.version.get('contractVersion')}")
        print(f"workspace HEAD: {self.head_sha or 'unknown'}")
        print(f"isolated state: {self.state_dir}")

    def assert_binary_unchanged(self) -> None:
        now = hashlib.sha256(self.binary.read_bytes()).hexdigest()
        if now != self.pinned_sha:
            self.fail_hard(f"stale/swapped binary mid-suite: {now} != pinned {self.pinned_sha}")

    # --- process runner ----------------------------------------------------

    def provider_hits(self) -> int:
        if not self.provider_log.is_file():
            return 0
        return sum(1 for line in self.provider_log.read_text().splitlines() if line.startswith("HIT "))

    def run(
        self,
        args: list[str],
        *,
        expect_ok: bool | None = None,
        parse_json: bool = False,
        cwd: Path | None = None,
        count_as_case: bool = True,
        forbid_provider: bool = False,
    ) -> Attempt:
        argv = [str(self.binary), *args]
        before = self.provider_hits()
        work_dir = cwd or (self.repo if self.repo.is_dir() else Path.cwd())
        env = self.env if self.env else os.environ
        proc = subprocess.run(
            argv,
            capture_output=True,
            text=True,
            cwd=str(work_dir),
            env=env,
        )
        after = self.provider_hits()
        parsed: dict[str, Any] | None = None
        if parse_json and proc.stdout.strip():
            try:
                loaded = json.loads(proc.stdout)
                if isinstance(loaded, dict):
                    parsed = loaded
            except json.JSONDecodeError:
                parsed = None
        attempt = Attempt(
            argv=argv,
            exit_code=proc.returncode,
            stdout=proc.stdout,
            stderr=proc.stderr,
            response_bytes=len(proc.stdout.encode("utf-8")),
            parsed=parsed,
            provider_hits_before=before,
            provider_hits_after=after,
        )
        if count_as_case:
            self.attempts.append(attempt)

        if expect_ok is True and proc.returncode != 0:
            self.fail_hard(
                f"expected success for {args}: exit={proc.returncode} stderr={proc.stderr[:400]}"
            )
        if expect_ok is False and proc.returncode == 0:
            if not (isinstance(parsed, dict) and parsed.get("success") is False):
                self.fail_hard(f"expected failure for {args} but exit=0")
        if forbid_provider and attempt.provider_started:
            self.fail_hard(f"provider process started on forbidden path: {args}")
        return attempt

    # --- helpers -----------------------------------------------------------

    def load_menu(self) -> Attempt:
        attempt = self.run(["menu", "--json"], expect_ok=True, forbid_provider=True)
        raw = attempt.stdout.encode("utf-8")
        self.menu_bytes = len(raw)
        try:
            self.menu = json.loads(attempt.stdout)
        except json.JSONDecodeError as exc:
            self.fail_hard(f"menu --json parse error: {exc}")
        (self.out_dir / "menu.json").write_bytes(raw)
        # Tier-1 ≤32 KiB is the built-in bound (MNR / SH-S10). Custom teams from
        # authoring cases legitimately grow the live menu — check the budget once
        # before customs exist, then only fail on truncation afterward.
        if not self._menu_budget_checked:
            if self.menu_bytes > MENU_BUDGET_BYTES:
                self.fail_hard(f"built-in menu exceeds 32 KiB budget: {self.menu_bytes}")
            self._menu_budget_checked = True
        if self.menu.get("truncated") is True:
            self.fail_hard("menu truncated: true")
        if str(self.menu.get("contractVersion") or "") != "3.0.0":
            self.fail_hard(
                f"expected contractVersion 3.0.0, got {self.menu.get('contractVersion')}"
            )
        print(f"menu bytes={self.menu_bytes}")
        return attempt

    def find_model(self, model_id: str) -> dict[str, Any]:
        for m in self.menu.get("models") or []:
            if m.get("id") == model_id:
                return m
        self.fail_hard(f"model {model_id!r} missing from menu")
        raise AssertionError

    def find_team(self, team_id: str) -> dict[str, Any]:
        for t in self.menu.get("teams") or []:
            if t.get("id") == team_id:
                return t
        self.fail_hard(f"team {team_id!r} missing from menu")
        raise AssertionError

    def record_claim(self, claim: str, receipt: str, verdict: str) -> None:
        self.claims.append(
            Claim(
                claim=claim,
                binary_sha=self.pinned_sha,
                receipt=receipt,
                verdict=verdict,
            )
        )

    def finish_case(self, result: CaseResult) -> None:
        if result.calls > result.max_calls:
            result.ok = False
            result.error = (
                (result.error + "; " if result.error else "")
                + f"call budget exceeded: {result.calls}>{result.max_calls}"
            )
        if result.hard_failure:
            self.hard_failures += 1
        self.cases.append(result)
        status = "PASS" if result.ok else "FAIL"
        print(
            f"  [{status}] {result.name}  calls={result.calls}/{result.max_calls}"
            f"  bytes={result.response_bytes}"
            + (f"  error={result.error}" if result.error else "")
        )

    # --- cases -------------------------------------------------------------

    def case_ask_one_named_worker(self) -> None:
        name = "Ask one named worker"
        max_calls = 3
        calls = 0
        attempts: list[Attempt] = []
        bytes_total = 0

        menu = self.load_menu()
        calls += 1
        attempts.append(menu)
        bytes_total += menu.response_bytes
        model = self.find_model("model_sonnet")
        if not model.get("validateTemplate"):
            return self.finish_case(
                CaseResult(name, False, calls, max_calls, error="missing validateTemplate")
            )

        marker = f"SH-S09-one-{uuid.uuid4().hex[:8]}"
        dry = self.run(
            ["run", marker, "--worker", "model_sonnet", "--dry-run", "--json"],
            expect_ok=True,
            parse_json=True,
            forbid_provider=True,
        )
        calls += 1
        attempts.append(dry)
        bytes_total += dry.response_bytes
        body = dry.parsed or {}
        if body.get("workerId") != "model_sonnet":
            return self.finish_case(
                CaseResult(
                    name,
                    False,
                    calls,
                    max_calls,
                    bytes_total,
                    attempts=attempts,
                    error=f"dry-run workerId={body.get('workerId')}",
                    hard_failure=True,
                )
            )

        run = self.run(
            ["run", marker, "--worker", "model_sonnet", "--json"],
            expect_ok=True,
            parse_json=True,
        )
        calls += 1
        attempts.append(run)
        bytes_total += run.response_bytes
        result = run.parsed or {}
        answer = result.get("answer") or {}
        md = answer.get("markdown")
        if md != "success":
            return self.finish_case(
                CaseResult(
                    name,
                    False,
                    calls,
                    max_calls,
                    bytes_total,
                    attempts=attempts,
                    error=f"answer.markdown={md!r}",
                )
            )
        overhead = run.response_bytes - len(str(md).encode("utf-8"))
        if overhead > ENVELOPE_OVERHEAD_BUDGET:
            return self.finish_case(
                CaseResult(
                    name,
                    False,
                    calls,
                    max_calls,
                    bytes_total,
                    attempts=attempts,
                    error=f"envelope overhead {overhead} > {ENVELOPE_OVERHEAD_BUDGET}",
                    hard_failure=True,
                )
            )
        team_run = result.get("teamRun") or {}
        if team_run.get("workerId") != "model_sonnet":
            return self.finish_case(
                CaseResult(
                    name,
                    False,
                    calls,
                    max_calls,
                    bytes_total,
                    attempts=attempts,
                    error="result dropped worker selector",
                    hard_failure=True,
                )
            )
        self.record_claim(
            "One-worker answer.markdown first try within SH-S02 envelope budget",
            f"overhead={overhead} answer={md!r}",
            "confirmed",
        )
        self.finish_case(
            CaseResult(
                name,
                True,
                calls,
                max_calls,
                bytes_total,
                notes=[f"overhead={overhead}", f"provider_hits={run.provider_hits_after - run.provider_hits_before}"],
                attempts=attempts,
            )
        )

    def case_send_answer_team(self) -> None:
        name = "Send to one answer team"
        max_calls = 3
        calls = 0
        attempts: list[Attempt] = []
        bytes_total = 0
        team_id = "code_growth"

        menu = self.load_menu()
        calls += 1
        attempts.append(menu)
        bytes_total += menu.response_bytes
        self.find_team(team_id)

        marker = f"SH-S09-team-{uuid.uuid4().hex[:8]}"
        dry = self.run(
            ["run", marker, "--team", team_id, "--dry-run", "--json"],
            expect_ok=True,
            parse_json=True,
            forbid_provider=True,
        )
        calls += 1
        attempts.append(dry)
        bytes_total += dry.response_bytes
        dry_body = dry.parsed or {}
        dry_team = dry_body.get("teamPresetId")
        dry_seats = (dry_body.get("counts") or {}).get("seatCount")
        if dry_team != team_id or not isinstance(dry_seats, int):
            return self.finish_case(
                CaseResult(
                    name,
                    False,
                    calls,
                    max_calls,
                    bytes_total,
                    attempts=attempts,
                    error=f"dry team/seats={dry_team}/{dry_seats}",
                    hard_failure=True,
                )
            )

        run = self.run(
            ["run", marker, "--team", team_id, "--json"],
            expect_ok=True,
            parse_json=True,
        )
        calls += 1
        attempts.append(run)
        bytes_total += run.response_bytes
        result = run.parsed or {}
        team_run = result.get("teamRun") or {}
        run_team = team_run.get("teamPresetId")
        run_seats = len(result.get("workers") or [])
        if run_team != dry_team or run_seats != dry_seats:
            return self.finish_case(
                CaseResult(
                    name,
                    False,
                    calls,
                    max_calls,
                    bytes_total,
                    attempts=attempts,
                    error=f"preview/result mismatch team {dry_team}/{run_team} seats {dry_seats}/{run_seats}",
                    hard_failure=True,
                )
            )
        self.record_claim(
            "Answer-team preview/result team+seats identical",
            f"team={run_team} seats={run_seats}",
            "confirmed",
        )
        self.finish_case(
            CaseResult(
                name,
                True,
                calls,
                max_calls,
                bytes_total,
                notes=[f"team={run_team}", f"seats={run_seats}"],
                attempts=attempts,
            )
        )

    def case_inspect_team(self) -> None:
        name = "Inspect one team"
        max_calls = 2
        calls = 0
        attempts: list[Attempt] = []
        bytes_total = 0
        team_id = "code_bug_hunt"

        menu = self.load_menu()
        calls += 1
        attempts.append(menu)
        bytes_total += menu.response_bytes
        menu_team = self.find_team(team_id)
        menu_seats = menu_team.get("seatCount")

        show = self.run(
            ["teams", "show", team_id, "--json"],
            expect_ok=True,
            parse_json=True,
            forbid_provider=True,
        )
        calls += 1
        attempts.append(show)
        bytes_total += show.response_bytes
        body = show.parsed or {}
        if body.get("lead") is None:
            return self.finish_case(
                CaseResult(name, False, calls, max_calls, bytes_total, attempts=attempts, error="missing lead")
            )
        if not body.get("crew"):
            return self.finish_case(
                CaseResult(name, False, calls, max_calls, bytes_total, attempts=attempts, error="missing crew")
            )
        if body.get("seatCount") != menu_seats:
            return self.finish_case(
                CaseResult(
                    name,
                    False,
                    calls,
                    max_calls,
                    bytes_total,
                    attempts=attempts,
                    error=f"seatCount menu={menu_seats} show={body.get('seatCount')}",
                    hard_failure=True,
                )
            )
        self.record_claim(
            "teams show exposes lead+crew+exact seatCount matching menu",
            f"seatCount={body.get('seatCount')}",
            "confirmed",
        )
        self.finish_case(
            CaseResult(
                name,
                True,
                calls,
                max_calls,
                bytes_total,
                notes=[f"seatCount={body.get('seatCount')}"],
                attempts=attempts,
            )
        )

    def case_custom_bug_hunt(self) -> None:
        name = "Make a custom Bug Hunt"
        max_calls = 4
        calls = 0
        attempts: list[Attempt] = []
        bytes_total = 0
        custom_id = f"custom_code_sh_s09_bh_{uuid.uuid4().hex[:6]}"

        menu = self.load_menu()
        calls += 1
        attempts.append(menu)
        bytes_total += menu.response_bytes

        dup = self.run(
            [
                "teams",
                "duplicate",
                "code_bug_hunt",
                "--id",
                custom_id,
                "--name",
                "SH-S09 Bug Hunt",
                "--json",
            ],
            expect_ok=True,
            parse_json=True,
            forbid_provider=True,
        )
        calls += 1
        attempts.append(dup)
        bytes_total += dup.response_bytes
        if (dup.parsed or {}).get("id") != custom_id:
            return self.finish_case(
                CaseResult(
                    name,
                    False,
                    calls,
                    max_calls,
                    bytes_total,
                    attempts=attempts,
                    error=f"duplicate id={(dup.parsed or {}).get('id')}",
                )
            )

        definition = self.run(
            ["teams", "definition", custom_id, "--json"],
            expect_ok=True,
            parse_json=True,
            forbid_provider=True,
        )
        calls += 1
        attempts.append(definition)
        bytes_total += definition.response_bytes
        preset = dict(definition.parsed or {})
        if preset.get("id") != custom_id:
            return self.finish_case(
                CaseResult(name, False, calls, max_calls, bytes_total, attempts=attempts, error="definition id mismatch")
            )
        preset["displayName"] = "SH-S09 Bug Hunt Edited"
        edit_path = self.state_dir / f"{custom_id}.edit.json"
        edit_path.write_text(json.dumps(preset, indent=2) + "\n")

        edit = self.run(
            ["teams", "edit", custom_id, "--file", str(edit_path), "--json"],
            expect_ok=True,
            parse_json=True,
            forbid_provider=True,
        )
        calls += 1
        attempts.append(edit)
        bytes_total += edit.response_bytes
        if (edit.parsed or {}).get("id") != custom_id:
            return self.finish_case(
                CaseResult(
                    name,
                    False,
                    calls,
                    max_calls,
                    bytes_total,
                    attempts=attempts,
                    error="caller-chosen id did not survive edit",
                )
            )
        self.record_claim(
            "Deterministic Bug Hunt duplicate --id survives definition→edit",
            f"id={custom_id}",
            "confirmed",
        )
        self.finish_case(
            CaseResult(
                name,
                True,
                calls,
                max_calls,
                bytes_total,
                notes=[f"id={custom_id}"],
                attempts=attempts,
            )
        )

    def case_novel_team(self) -> None:
        name = "Create a novel team"
        max_calls = 3
        calls = 0
        attempts: list[Attempt] = []
        bytes_total = 0
        novel_id = f"custom_code_sh_s09_novel_{uuid.uuid4().hex[:6]}"

        menu = self.load_menu()
        calls += 1
        attempts.append(menu)
        bytes_total += menu.response_bytes

        definition = self.run(
            ["teams", "definition", "code_bug_hunt", "--json"],
            expect_ok=True,
            parse_json=True,
            forbid_provider=True,
        )
        calls += 1
        attempts.append(definition)
        bytes_total += definition.response_bytes
        preset = dict(definition.parsed or {})
        preset["id"] = novel_id
        preset["displayName"] = "SH-S09 Novel"
        preset["builtIn"] = False
        preset["isDefaultForLane"] = False
        novel_path = self.state_dir / f"{novel_id}.json"
        novel_path.write_text(json.dumps(preset, indent=2) + "\n")

        created = self.run(
            ["teams", "new", novel_id, "--file", str(novel_path), "--json"],
            expect_ok=True,
            parse_json=True,
            forbid_provider=True,
        )
        calls += 1
        attempts.append(created)
        bytes_total += created.response_bytes
        body = created.parsed or {}
        if body.get("id") != novel_id:
            return self.finish_case(
                CaseResult(
                    name,
                    False,
                    calls,
                    max_calls,
                    bytes_total,
                    attempts=attempts,
                    error=f"expected caller id {novel_id}, got {body.get('id')} (generated-id parse?)",
                )
            )
        self.record_claim(
            "teams new accepts caller-chosen id with no generated-id parse",
            f"id={novel_id}",
            "confirmed",
        )
        self.finish_case(
            CaseResult(
                name,
                True,
                calls,
                max_calls,
                bytes_total,
                notes=[f"id={novel_id}"],
                attempts=attempts,
            )
        )

    def case_detach_retrieve(self) -> None:
        name = "Detach and retrieve"
        max_calls = 5
        calls = 0
        attempts: list[Attempt] = []
        bytes_total = 0
        team_id = "code_growth"

        menu = self.load_menu()
        calls += 1
        attempts.append(menu)
        bytes_total += menu.response_bytes

        marker = f"SH-S09-detach-{uuid.uuid4().hex[:8]}"
        dry = self.run(
            ["run", marker, "--team", team_id, "--dry-run", "--json"],
            expect_ok=True,
            parse_json=True,
            forbid_provider=True,
        )
        calls += 1
        attempts.append(dry)
        bytes_total += dry.response_bytes

        detach = self.run(
            ["run", marker, "--team", team_id, "--detach", "--json"],
            expect_ok=True,
            parse_json=True,
        )
        calls += 1
        attempts.append(detach)
        bytes_total += detach.response_bytes
        run_id = (detach.parsed or {}).get("runId")
        if not run_id or not isinstance(run_id, str):
            return self.finish_case(
                CaseResult(name, False, calls, max_calls, bytes_total, attempts=attempts, error="missing runId")
            )

        status = self.run(
            ["team", "status", run_id, "--json", "--wait-for", "terminal", "--timeout", "60"],
            expect_ok=True,
            parse_json=True,
            forbid_provider=False,
        )
        calls += 1
        attempts.append(status)
        bytes_total += status.response_bytes

        result = self.run(
            ["team", "result", run_id, "--json"],
            expect_ok=True,
            parse_json=True,
        )
        calls += 1
        attempts.append(result)
        bytes_total += result.response_bytes
        body = result.parsed or {}
        result_id = (body.get("teamRun") or {}).get("id")
        if result_id != run_id:
            return self.finish_case(
                CaseResult(
                    name,
                    False,
                    calls,
                    max_calls,
                    bytes_total,
                    attempts=attempts,
                    error=f"run id drift detach={run_id} result={result_id}",
                    hard_failure=True,
                )
            )
        if not (body.get("answer") or {}).get("markdown"):
            return self.finish_case(
                CaseResult(name, False, calls, max_calls, bytes_total, attempts=attempts, error="missing answer.markdown")
            )
        self.record_claim(
            "Detach→wait→result preserves one run id",
            f"runId={run_id}",
            "confirmed",
        )
        self.finish_case(
            CaseResult(
                name,
                True,
                calls,
                max_calls,
                bytes_total,
                notes=[f"runId={run_id}"],
                attempts=attempts,
            )
        )

    def case_recover_bad_id(self) -> None:
        name = "Recover bad id"
        max_calls = 4
        calls = 0
        attempts: list[Attempt] = []
        bytes_total = 0

        menu = self.load_menu()
        calls += 1
        attempts.append(menu)
        bytes_total += menu.response_bytes

        marker = f"SH-S09-bad-{uuid.uuid4().hex[:8]}"
        bad = self.run(
            ["run", marker, "--worker", "model_definitely_not_real", "--json"],
            expect_ok=False,
            parse_json=True,
            forbid_provider=True,
        )
        calls += 1
        attempts.append(bad)
        bytes_total += bad.response_bytes
        err = (bad.parsed or {}).get("error") or {}
        if err.get("code") != "WORKER_NOT_AVAILABLE":
            return self.finish_case(
                CaseResult(
                    name,
                    False,
                    calls,
                    max_calls,
                    bytes_total,
                    attempts=attempts,
                    error=f"code={err.get('code')}",
                )
            )
        next_action = err.get("nextAction") or {}
        agent_action = str(err.get("agentAction") or "")
        if "menu" not in str(next_action.get("command") or "") and "menu" not in agent_action:
            return self.finish_case(
                CaseResult(
                    name,
                    False,
                    calls,
                    max_calls,
                    bytes_total,
                    attempts=attempts,
                    error="structured error missing menu next action",
                )
            )

        # Exact next action: re-read menu, then retry with a ready canonical worker
        # from the live menu (Sonnet is seeded ready via fixture drivers).
        retry_menu = self.run(["menu", "--json"], expect_ok=True, forbid_provider=True)
        calls += 1
        attempts.append(retry_menu)
        bytes_total += retry_menu.response_bytes
        try:
            menu_body = json.loads(retry_menu.stdout)
        except json.JSONDecodeError:
            return self.finish_case(
                CaseResult(name, False, calls, max_calls, bytes_total, attempts=attempts, error="retry menu parse")
            )
        sonnet = next(
            (m for m in (menu_body.get("models") or []) if m.get("id") == "model_sonnet"),
            None,
        )
        if sonnet is None:
            return self.finish_case(
                CaseResult(
                    name,
                    False,
                    calls,
                    max_calls,
                    bytes_total,
                    attempts=attempts,
                    error="menu missing model_sonnet after next action",
                )
            )
        # Suggestions are advisory; never execute a display name or a disabled seat.
        suggestions = err.get("suggestions") or []
        if suggestions and not any(isinstance(s, str) and s.startswith("model_") for s in suggestions):
            return self.finish_case(
                CaseResult(
                    name,
                    False,
                    calls,
                    max_calls,
                    bytes_total,
                    attempts=attempts,
                    error=f"suggestions not canonical ids: {suggestions!r}",
                )
            )

        retry = self.run(
            ["run", marker, "--worker", "model_sonnet", "--json"],
            expect_ok=True,
            parse_json=True,
        )
        calls += 1
        attempts.append(retry)
        bytes_total += retry.response_bytes
        if (retry.parsed or {}).get("answer", {}).get("markdown") != "success":
            return self.finish_case(
                CaseResult(name, False, calls, max_calls, bytes_total, attempts=attempts, error="retry failed")
            )
        self.record_claim(
            "Bad-id recovery: structured error → menu next action → retry; zero spend before retry",
            f"code={err.get('code')} provider_before_retry={bad.provider_hits_after - bad.provider_hits_before}",
            "confirmed",
        )
        self.finish_case(
            CaseResult(name, True, calls, max_calls, bytes_total, attempts=attempts)
        )

    def case_recover_unregistered_root(self) -> None:
        name = "Recover unregistered root"
        max_calls = 4
        calls = 0
        attempts: list[Attempt] = []
        bytes_total = 0

        menu = self.load_menu()
        calls += 1
        attempts.append(menu)
        bytes_total += menu.response_bytes

        unreg = self.state_dir / f"unreg-{uuid.uuid4().hex[:6]}"
        unreg.mkdir(parents=True)
        self._init_git_repo(unreg)

        marker = f"SH-S09-unreg-{uuid.uuid4().hex[:8]}"
        bad = self.run(
            ["run", marker, "--worker", "model_sonnet", "--json"],
            expect_ok=False,
            parse_json=True,
            cwd=unreg,
            forbid_provider=True,
        )
        calls += 1
        attempts.append(bad)
        bytes_total += bad.response_bytes
        err = (bad.parsed or {}).get("error") or {}
        if err.get("code") != "PROJECT_NOT_FOUND":
            return self.finish_case(
                CaseResult(
                    name,
                    False,
                    calls,
                    max_calls,
                    bytes_total,
                    attempts=attempts,
                    error=f"code={err.get('code')}",
                )
            )
        message = str(err.get("message") or "")
        match = re.search(r"alln project add (\S+)", message)
        if not match:
            return self.finish_case(
                CaseResult(
                    name,
                    False,
                    calls,
                    max_calls,
                    bytes_total,
                    attempts=attempts,
                    error="message missing exact project add next action",
                )
            )
        add_path = match.group(1).rstrip("`'\"")
        if (
            Path(add_path).resolve() != unreg.resolve()
            and os.path.normpath(add_path) != os.path.normpath(str(unreg))
        ):
            return self.finish_case(
                CaseResult(
                    name,
                    False,
                    calls,
                    max_calls,
                    bytes_total,
                    attempts=attempts,
                    error=f"add path {add_path!r} != {str(unreg)!r}",
                )
            )

        add = self.run(
            ["project", "add", str(unreg), "--json"],
            expect_ok=True,
            parse_json=True,
            cwd=unreg,
            forbid_provider=True,
        )
        calls += 1
        attempts.append(add)
        bytes_total += add.response_bytes

        retry = self.run(
            ["run", marker, "--worker", "model_sonnet", "--json"],
            expect_ok=True,
            parse_json=True,
            cwd=unreg,
        )
        calls += 1
        attempts.append(retry)
        bytes_total += retry.response_bytes
        if (retry.parsed or {}).get("answer", {}).get("markdown") != "success":
            return self.finish_case(
                CaseResult(name, False, calls, max_calls, bytes_total, attempts=attempts, error="retry failed")
            )
        self.record_claim(
            "Unregistered-root recovery: PROJECT_NOT_FOUND → project add → retry; zero spend before retry",
            f"add={add_path}",
            "confirmed",
        )
        self.finish_case(
            CaseResult(name, True, calls, max_calls, bytes_total, attempts=attempts)
        )

    def case_docs_from_menu_ref(self) -> None:
        name = "Open docs from a menu ref"
        max_calls = 2
        calls = 0
        attempts: list[Attempt] = []
        bytes_total = 0

        menu = self.load_menu()
        calls += 1
        attempts.append(menu)
        bytes_total += menu.response_bytes

        # Typed ref grammar emitted by menu surfaces (SH-S03): command:<dotted-id>.
        # Confirm the command row exists, then open docs with that ref — no spelling
        # translation (never rewrite to spaced "teams duplicate").
        cmd_ids = {
            (c.get("id") or c.get("name") or "")
            for c in (self.menu.get("commands") or [])
        }
        if "teams duplicate" not in cmd_ids:
            return self.finish_case(
                CaseResult(
                    name,
                    False,
                    calls,
                    max_calls,
                    bytes_total,
                    attempts=attempts,
                    error="menu missing teams duplicate command row",
                )
            )
        ref = "command:teams.duplicate"

        docs = self.run(
            ["docs", ref],
            expect_ok=True,
            forbid_provider=True,
        )
        calls += 1
        attempts.append(docs)
        bytes_total += docs.response_bytes
        if "teams duplicate" not in docs.stdout and "Duplicate" not in docs.stdout:
            return self.finish_case(
                CaseResult(
                    name,
                    False,
                    calls,
                    max_calls,
                    bytes_total,
                    attempts=attempts,
                    error="docs output missing teams duplicate content",
                )
            )
        self.record_claim(
            "Menu typed ref resolves on docs without spelling translation",
            f"ref={ref}",
            "confirmed",
        )
        self.finish_case(
            CaseResult(
                name,
                True,
                calls,
                max_calls,
                bytes_total,
                notes=[f"ref={ref}"],
                attempts=attempts,
            )
        )

    # --- report ------------------------------------------------------------

    def run_all(self) -> None:
        runners = [
            self.case_ask_one_named_worker,
            self.case_send_answer_team,
            self.case_inspect_team,
            self.case_custom_bug_hunt,
            self.case_novel_team,
            self.case_detach_retrieve,
            self.case_recover_bad_id,
            self.case_recover_unregistered_root,
            self.case_docs_from_menu_ref,
        ]
        print("sharpening mechanical pass/fail gate (no score — D5)")
        for fn in runners:
            self.assert_binary_unchanged()
            fn()
        self.assert_binary_unchanged()

        failed = [c for c in self.cases if not c.ok]
        ok = not failed and self.hard_failures == 0
        self._write_report(ok=ok)
        self._print_summary(ok=ok)
        self._cleanup()
        if not ok:
            sys.exit(1)

    def _write_report(self, ok: bool) -> None:
        self.out_dir.mkdir(parents=True, exist_ok=True)
        report = {
            "ok": ok,
            "suite": "sharpening",
            "kind": "mechanical-pass-fail-gate",
            "score": None,  # D5 — alln never rates itself
            "binary": str(self.binary),
            "pinnedSha256": self.pinned_sha,
            "version": self.version,
            "workspaceHead": self.head_sha,
            "stateDir": str(self.state_dir),
            "menuBytes": self.menu_bytes,
            "hardFailures": self.hard_failures,
            "envelopeOverheadBudget": ENVELOPE_OVERHEAD_BUDGET,
            "cases": [
                {
                    "name": c.name,
                    "ok": c.ok,
                    "calls": c.calls,
                    "maxCalls": c.max_calls,
                    "responseBytes": c.response_bytes,
                    "error": c.error,
                    "notes": c.notes,
                    "hardFailure": c.hard_failure,
                }
                for c in self.cases
            ],
            "attempts": [
                {
                    "argv": a.argv[1:],
                    "exitCode": a.exit_code,
                    "responseBytes": a.response_bytes,
                    "providerStarted": a.provider_started,
                    "stdoutHead": (a.stdout or "")[:240],
                }
                for a in self.attempts
            ],
            "claimLedger": [
                {
                    "claim": c.claim,
                    "binarySha": c.binary_sha,
                    "receipt": c.receipt,
                    "verdict": c.verdict,
                }
                for c in self.claims
            ],
            "providerLog": self.provider_log.read_text() if self.provider_log.is_file() else "",
        }
        (self.out_dir / "report.json").write_text(json.dumps(report, indent=2) + "\n")
        (self.out_dir / "claim-ledger.json").write_text(
            json.dumps(report["claimLedger"], indent=2) + "\n"
        )
        lines = [
            f"suite=sharpening ok={ok} hardFailures={self.hard_failures} score=none",
            f"binary={self.binary}",
            f"sha256={self.pinned_sha}",
            f"contractVersion={self.version.get('contractVersion')}",
            f"stateDir={self.state_dir}",
            f"menuBytes={self.menu_bytes}",
        ]
        for c in self.cases:
            lines.append(
                f"{'PASS' if c.ok else 'FAIL'}\t{c.name}\tcalls={c.calls}/{c.max_calls}\tbytes={c.response_bytes}"
                + (f"\t{c.error}" if c.error else "")
            )
        (self.out_dir / "transcript.txt").write_text("\n".join(lines) + "\n")

    def _print_summary(self, ok: bool) -> None:
        print()
        print("== sharpening gate summary (no score — D5) ==")
        print(f"hard_failures={self.hard_failures}")
        print(f"binary_sha256={self.pinned_sha}")
        print(f"contractVersion={self.version.get('contractVersion')}")
        print(f"state_dir={self.state_dir}")
        for c in self.cases:
            mark = "PASS" if c.ok else "FAIL"
            print(f"  {mark}  {c.name}  calls={c.calls}/{c.max_calls}  bytes={c.response_bytes}")
        if ok:
            print(f"OK — sharpening suite green (report: {self.out_dir / 'report.json'})")
        else:
            print(f"FAIL — sharpening suite red (report: {self.out_dir / 'report.json'})")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", required=True, help="Path to pinned alln binary")
    parser.add_argument(
        "--out-dir",
        default=None,
        help="Report directory (default: .build/agent-eval/sharpening)",
    )
    parser.add_argument(
        "--allow-stale-gitsha",
        action="store_true",
        help="Do not fail on BuildInfo gitSha drift (file SHA still pinned)",
    )
    args = parser.parse_args()

    root = Path(__file__).resolve().parents[1]
    out = Path(args.out_dir) if args.out_dir else root / ".build" / "agent-eval" / "sharpening"
    out.mkdir(parents=True, exist_ok=True)

    print("== SH-S09 sharpening mechanical pass/fail gate ==")
    print(f"out: {out}")
    h = Harness(Path(args.binary), out, allow_stale_gitsha=args.allow_stale_gitsha)
    h.pin_binary()
    h.setup()
    h.run_all()


if __name__ == "__main__":
    main()
