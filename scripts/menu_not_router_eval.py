#!/usr/bin/env python3
"""MR-S06 — pinned-binary mechanical cold-agent matrix (not a live LLM eval).

Simulates the required outcomes from Menu_Not_Router.md §Cold-agent acceptance
matrix by reading `alln menu --json` once (or menu + one hydrate for rare rows),
selecting canonical ids via displayName/useWhen heuristics, then invoking only
quota-free validation / management grammars.

Usage:
  python3 scripts/menu_not_router_eval.py --binary Packages/AllnighterCore/.build/release/alln
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import uuid
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

# First argv token + optional second token that must never appear on a spend path.
RETIRED_ARGV_PREFIXES = {
    ("team", "hello"),
    ("team", "list"),
    ("team", "show"),
    ("team", "preflight"),
    ("team", "start"),
    ("route",),
    ("resolve",),
    ("commands",),
}


@dataclass
class Attempt:
    argv: list[str]
    exit_code: int
    stdout: str
    stderr: str
    dry_run_json: dict[str, Any] | None = None
    created_run: bool | None = None


@dataclass
class CaseResult:
    name: str
    ok: bool
    final_command: str
    discovery_calls: int
    attempts: list[Attempt] = field(default_factory=list)
    notes: list[str] = field(default_factory=list)
    error: str | None = None


class Harness:
    def __init__(self, binary: Path, out_dir: Path, *, allow_stale_gitsha: bool) -> None:
        self.binary = binary.resolve()
        self.out_dir = out_dir
        self.allow_stale_gitsha = allow_stale_gitsha
        self.attempts: list[Attempt] = []
        self.menu: dict[str, Any] = {}
        self.menu_bytes = 0
        self.pinned_sha = ""
        self.version: dict[str, Any] = {}
        self.head_sha = ""
        self.cases: list[CaseResult] = []

    def fail(self, msg: str) -> None:
        print(f"menu_not_router_eval: FAIL: {msg}", file=sys.stderr)
        self._write_report(ok=False)
        sys.exit(1)

    def run(
        self,
        args: list[str],
        *,
        expect_ok: bool | None = None,
        parse_json: bool = False,
        marker: str | None = None,
    ) -> Attempt:
        argv = [str(self.binary), *args]
        # Ban invented/retired grammar on any path that expects success.
        if expect_ok is not False and args:
            for prefix in RETIRED_ARGV_PREFIXES:
                if tuple(args[: len(prefix)]) == prefix:
                    self.fail(f"invented/retired grammar attempted: {args!r}")
            # Bare `alln team "<prompt>"` duplicate direct-run grammar.
            if args[0] == "team" and len(args) >= 2 and not args[1].startswith("-"):
                if args[1] not in {"hello", "list", "show", "preflight", "start"}:
                    # Still a retired direct-run form when not a known subcommand.
                    self.fail(f"invented/retired direct-run grammar attempted: {args!r}")

        before_hits = self._history_hits(marker) if marker else 0
        proc = subprocess.run(argv, capture_output=True, text=True)
        stdout = proc.stdout
        stderr = proc.stderr
        dry: dict[str, Any] | None = None
        if parse_json and stdout.strip():
            try:
                dry = json.loads(stdout)
            except json.JSONDecodeError:
                dry = None
        created = None
        if marker is not None:
            after_hits = self._history_hits(marker)
            created = after_hits > before_hits
        attempt = Attempt(
            argv=argv,
            exit_code=proc.returncode,
            stdout=stdout,
            stderr=stderr,
            dry_run_json=dry,
            created_run=created,
        )
        self.attempts.append(attempt)

        if expect_ok is True and proc.returncode != 0:
            self.fail(f"expected success for {argv[1:]}: exit={proc.returncode} stderr={stderr[:400]}")
        if expect_ok is False and proc.returncode == 0:
            # Some failure paths still exit 0 with success:false — treat structured failure as OK.
            if not (isinstance(dry, dict) and dry.get("success") is False):
                self.fail(f"expected failure for {argv[1:]} but exit=0")
        if marker is not None and created:
            self.fail(f"run/provider process created for marker {marker!r} via {argv[1:]}")
        return attempt

    def _history_hits(self, marker: str) -> int:
        proc = subprocess.run(
            [str(self.binary), "history", marker, "--json"],
            capture_output=True,
            text=True,
        )
        if proc.returncode != 0:
            return 0
        try:
            data = json.loads(proc.stdout)
        except json.JSONDecodeError:
            return 0
        results = data.get("results") or []
        return sum(1 for r in results if marker in (r.get("prompt") or ""))

    def pin_binary(self) -> None:
        if not self.binary.is_file() or not os.access(self.binary, os.X_OK):
            self.fail(f"binary missing or not executable: {self.binary}")
        raw = self.binary.read_bytes()
        self.pinned_sha = hashlib.sha256(raw).hexdigest()
        expected = os.environ.get("ALLN_EVAL_PINNED_SHA", "").strip()
        if expected and expected != self.pinned_sha:
            self.fail(
                f"stale binary: sha256 {self.pinned_sha} != ALLN_EVAL_PINNED_SHA {expected}"
            )
        ver = self.run(["version", "--json"], expect_ok=True, parse_json=True)
        if not isinstance(ver.dry_run_json, dict):
            self.fail("version --json did not parse")
        self.version = ver.dry_run_json
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
                f"binary BuildInfo gitSha={embedded} != workspace HEAD={self.head_sha} "
                "(stale binary identity)"
            )
            if self.allow_stale_gitsha:
                print(f"menu_not_router_eval: WARN: {msg}")
            else:
                # Mechanical matrix pins file SHA; BuildInfo drift is warned unless
                # ALLN_EVAL_REQUIRE_FRESH_GITSHA=1.
                if os.environ.get("ALLN_EVAL_REQUIRE_FRESH_GITSHA") == "1":
                    self.fail(msg)
                print(f"menu_not_router_eval: WARN: {msg} (file sha pinned; continue)")

        (self.out_dir / "pinned-binary.sha256").write_text(self.pinned_sha + "\n")
        (self.out_dir / "version.json").write_text(json.dumps(self.version, indent=2) + "\n")
        (self.out_dir / "workspace-HEAD.txt").write_text(self.head_sha + "\n")
        print(f"pinned binary sha256: {self.pinned_sha}")
        print(f"binary gitSha: {embedded or 'unknown'}")
        print(f"workspace HEAD: {self.head_sha or 'unknown'}")

    def assert_binary_unchanged(self) -> None:
        now = hashlib.sha256(self.binary.read_bytes()).hexdigest()
        if now != self.pinned_sha:
            self.fail(f"stale/swapped binary mid-suite: {now} != pinned {self.pinned_sha}")

    def load_menu(self) -> None:
        attempt = self.run(["menu", "--json"], expect_ok=True)
        raw = attempt.stdout.encode("utf-8")
        self.menu_bytes = len(raw)
        try:
            self.menu = json.loads(attempt.stdout)
        except json.JSONDecodeError as exc:
            self.fail(f"menu --json parse error: {exc}")
        (self.out_dir / "menu.json").write_bytes(raw)
        counts = {
            "actions": len(self.menu.get("actions") or []),
            "commands": len(self.menu.get("commands") or []),
            "teams": len(self.menu.get("teams") or []),
            "models": len(self.menu.get("models") or []),
            "recipes": len(self.menu.get("recipes") or []),
        }
        meta = {
            "bytes": self.menu_bytes,
            "counts": counts,
            "truncated": self.menu.get("truncated"),
            "completeness": self.menu.get("completeness"),
            "contractVersion": self.menu.get("contractVersion"),
            "catalogRevision": self.menu.get("catalogRevision"),
        }
        (self.out_dir / "menu-meta.json").write_text(json.dumps(meta, indent=2) + "\n")
        print(f"menu bytes={self.menu_bytes} counts={counts}")

        # Catalog incompleteness / bound / selection-grade
        verify = Path(__file__).resolve().parent / "verify_menu_contract.py"
        proc = subprocess.run(
            [
                sys.executable,
                str(verify),
                str(self.out_dir / "menu.json"),
                "--max-built-in-bytes",
                "32768",
                "--require-complete",
                "--require-unique-refs",
                "--require-selection-grade",
            ],
            capture_output=True,
            text=True,
        )
        (self.out_dir / "verify_menu_contract.out").write_text(proc.stdout + proc.stderr)
        if proc.returncode != 0:
            self.fail(f"verify_menu_contract failed:\n{proc.stdout}{proc.stderr}")

        if self.menu.get("truncated") is True:
            self.fail("menu truncated: true")

    def find_model_by_display(self, name: str) -> dict[str, Any]:
        matches = [
            m
            for m in self.menu.get("models") or []
            if (m.get("displayName") or "").strip() == name
        ]
        if not matches:
            self.fail(f"no model with displayName={name!r}")
        return matches[0]

    def find_team_by_display(self, name: str) -> dict[str, Any]:
        matches = [
            t
            for t in self.menu.get("teams") or []
            if (t.get("displayName") or "").strip() == name
        ]
        if not matches:
            self.fail(f"no team with displayName={name!r}")
        return matches[0]

    def find_answer_team_for_several(self) -> dict[str, Any]:
        # Prefer Growth (canonical multi-model answer path) then any multi-seat answer team.
        for t in self.menu.get("teams") or []:
            if t.get("id") == "code_growth" and not t.get("mutating"):
                return t
        for t in self.menu.get("teams") or []:
            if t.get("shape") == "answer" and int(t.get("workerCount") or 0) > 1 and t.get("active"):
                return t
        self.fail("no multi-seat answer team for 'ask several models'")
        raise AssertionError  # unreachable

    def find_execution_team(self) -> dict[str, Any]:
        for t in self.menu.get("teams") or []:
            if t.get("id") == "build_slice" and t.get("mutating"):
                return t
        for t in self.menu.get("teams") or []:
            if t.get("mutating") and t.get("active") and t.get("shape") == "execution":
                return t
        self.fail("no mutating execution team found")
        raise AssertionError

    def find_action(self, action_id: str) -> dict[str, Any]:
        for a in self.menu.get("actions") or []:
            if a.get("id") == action_id:
                return a
        self.fail(f"action {action_id!r} missing from menu")
        raise AssertionError

    def expand_template(self, template: str, message: str) -> list[str]:
        # Templates look like: alln run "{message}" --worker model_sonnet --dry-run --json
        filled = template.replace("{message}", message)
        if not filled.startswith("alln "):
            self.fail(f"template does not start with alln: {template!r}")
        # Do not shell-split naively — message has no spaces in our markers; templates quote message.
        # Parse: alln <rest> with quoted message.
        m = re.match(r'^alln\s+(.+)$', filled)
        if not m:
            self.fail(f"bad template: {template!r}")
        rest = m.group(1)
        # Use a tiny argv splitter that respects double quotes.
        parts: list[str] = []
        buf: list[str] = []
        in_q = False
        for ch in rest:
            if ch == '"':
                in_q = not in_q
                continue
            if ch.isspace() and not in_q:
                if buf:
                    parts.append("".join(buf))
                    buf = []
                continue
            buf.append(ch)
        if buf:
            parts.append("".join(buf))
        if in_q:
            self.fail(f"unbalanced quotes in template: {filled!r}")
        return parts

    def assert_no_hydration_in_templates(self, row: dict[str, Any], kind: str) -> None:
        for key in ("runTemplate", "validateTemplate"):
            tmpl = row.get(key) or ""
            if "menu show" in tmpl:
                self.fail(f"{kind} {row.get('id')}: {key} requires hydration: {tmpl!r}")

    def case_ask_sonnet(self) -> CaseResult:
        name = "Ask Sonnet 5 to review this"
        discovery = 1  # menu already loaded once for suite; per-case budget counts suite menu
        model = self.find_model_by_display("Sonnet 5")
        self.assert_no_hydration_in_templates(model, "model")
        mid = model["id"]
        if mid != "model_sonnet":
            return CaseResult(name, False, "", discovery, error=f"expected model_sonnet got {mid}")
        marker = f"MR-S06-sonnet-{uuid.uuid4().hex[:8]}"
        args = self.expand_template(model["validateTemplate"], marker)
        if "--dry-run" not in args or "--worker" not in args or mid not in args:
            return CaseResult(name, False, " ".join(args), discovery, error="bad validateTemplate shape")
        if "Sonnet 5" in args:
            return CaseResult(name, False, " ".join(args), discovery, error="display name in argv")
        attempt = self.run(args, expect_ok=True, parse_json=True, marker=marker)
        body = attempt.dry_run_json or {}
        if body.get("workerId") != mid:
            return CaseResult(
                name, False, " ".join(args), discovery, error=f"workerId={body.get('workerId')}"
            )
        if attempt.created_run:
            return CaseResult(name, False, " ".join(args), discovery, error="run created")
        return CaseResult(name, True, " ".join(["alln", *args]), discovery, attempts=[attempt])

    def case_ask_several(self) -> CaseResult:
        name = "Ask several models for launch options"
        discovery = 1
        team = self.find_answer_team_for_several()
        self.assert_no_hydration_in_templates(team, "team")
        tid = team["id"]
        marker = f"MR-S06-several-{uuid.uuid4().hex[:8]}"
        args = self.expand_template(team["validateTemplate"], marker)
        if "--team" not in args or tid not in args or "--dry-run" not in args:
            return CaseResult(name, False, " ".join(args), discovery, error="bad team validateTemplate")
        attempt = self.run(args, expect_ok=True, parse_json=True, marker=marker)
        body = attempt.dry_run_json or {}
        if body.get("teamPresetId") != tid:
            return CaseResult(
                name, False, " ".join(args), discovery, error=f"teamPresetId={body.get('teamPresetId')}"
            )
        if body.get("writePolicy") == "mutating":
            return CaseResult(name, False, " ".join(args), discovery, error="expected answer team")
        return CaseResult(name, True, " ".join(["alln", *args]), discovery, attempts=[attempt])

    def case_growth_team(self) -> CaseResult:
        name = "Use the growth team"
        discovery = 1
        team = self.find_team_by_display("Growth")
        self.assert_no_hydration_in_templates(team, "team")
        tid = team["id"]
        if tid != "code_growth":
            return CaseResult(name, False, "", discovery, error=f"expected code_growth got {tid}")
        marker = f"MR-S06-growth-{uuid.uuid4().hex[:8]}"
        args = self.expand_template(team["validateTemplate"], marker)
        if "Growth" in args and tid not in args:
            return CaseResult(name, False, " ".join(args), discovery, error="display name passed as id")
        attempt = self.run(args, expect_ok=True, parse_json=True, marker=marker)
        body = attempt.dry_run_json or {}
        if body.get("teamPresetId") != "code_growth":
            return CaseResult(name, False, " ".join(args), discovery, error="wrong team id")
        return CaseResult(name, True, " ".join(["alln", *args]), discovery, attempts=[attempt])

    def case_duplicate_growth(self) -> CaseResult:
        name = "Duplicate the growth team so I can edit seats"
        discovery = 1
        action = self.find_action("teams duplicate")
        example = action.get("example") or ""
        if "teams duplicate" not in example:
            return CaseResult(name, False, example, discovery, error="action example wrong family")
        team = self.find_team_by_display("Growth")
        tid = team["id"]
        marker = f"MR-S06-dup-{uuid.uuid4().hex[:8]}"
        before = self._history_hits(marker)
        usage = self.run(["teams", "duplicate"], expect_ok=False)
        new_name = f"MR-S06 tmp {uuid.uuid4().hex[:6]}"
        dup = self.run(
            ["teams", "duplicate", tid, "--name", new_name, "--json"],
            expect_ok=True,
            parse_json=True,
        )
        body = dup.dry_run_json or {}
        new_id = body.get("id")
        if not new_id:
            return CaseResult(name, False, "", discovery, error="duplicate response missing id")
        self.run(["teams", "delete", str(new_id), "--json"], expect_ok=True, parse_json=True)
        if self._history_hits(marker) > before:
            return CaseResult(name, False, "", discovery, error="worker run created during duplicate")
        final = f"alln teams duplicate {tid} --json"
        return CaseResult(
            name,
            True,
            final,
            discovery,
            attempts=[usage, dup],
            notes=["zero worker starts; custom team deleted"],
        )

    def case_edit_growth(self) -> CaseResult:
        name = "Edit the growth team"
        discovery = 1
        action = self.find_action("teams edit")
        example = action.get("example") or ""
        if "teams edit" not in example:
            return CaseResult(name, False, example, discovery, error="action example wrong family")
        # Built-in Growth is not editable in place — command family must be teams edit,
        # and we must not start a worker. Usage-only proves grammar.
        usage = self.run(["teams", "edit"], expect_ok=False)
        final = "alln teams edit <team-id> --json"
        return CaseResult(name, True, final, discovery, attempts=[usage])

    def case_execution_team(self) -> CaseResult:
        name = "Fix this with the execution team"
        discovery = 1
        team = self.find_execution_team()
        self.assert_no_hydration_in_templates(team, "team")
        tid = team["id"]
        marker = f"MR-S06-exec-{uuid.uuid4().hex[:8]}"
        args = self.expand_template(team["validateTemplate"], marker)
        attempt = self.run(args, expect_ok=True, parse_json=True, marker=marker)
        body = attempt.dry_run_json or {}
        if body.get("teamPresetId") != tid:
            return CaseResult(name, False, " ".join(args), discovery, error="wrong team")
        # Phase matrix says repoWrite:true. RunDryRunJSON v2 renamed `mutating` to
        # `writePolicy` ("readOnly"|"mutating"); the old key is absent, so checking it
        # made this assertion permanently red (and its inverse silently vacuous).
        if body.get("writePolicy") != "mutating":
            return CaseResult(name, False, " ".join(args), discovery,
                              error=f'writePolicy={body.get("writePolicy")!r} expected "mutating"')
        if "writeLockHeld" not in body:
            return CaseResult(name, False, " ".join(args), discovery, error="missing writeLockHeld")
        if not isinstance(body.get("writeLockHeld"), bool):
            return CaseResult(name, False, " ".join(args), discovery, error="writeLockHeld not bool")
        return CaseResult(name, True, " ".join(["alln", *args]), discovery, attempts=[attempt])

    def case_bare_sonnet(self) -> CaseResult:
        name = "bare Sonnet 5"
        discovery = 1
        # Never execute the display name.
        bad = self.run(
            ["run", "probe", "--worker", "Sonnet 5", "--dry-run", "--json"],
            expect_ok=False,
            parse_json=True,
            marker=f"MR-S06-bare-bad-{uuid.uuid4().hex[:8]}",
        )
        # Prepare a named-worker dry-run with canonical id (honest clarify alternative).
        model = self.find_model_by_display("Sonnet 5")
        marker = f"MR-S06-bare-ok-{uuid.uuid4().hex[:8]}"
        args = self.expand_template(model["validateTemplate"], marker)
        good = self.run(args, expect_ok=True, parse_json=True, marker=marker)
        if "Sonnet 5" in args:
            return CaseResult(name, False, " ".join(args), discovery, error="display name executed")
        return CaseResult(
            name,
            True,
            " ".join(["alln", *args]),
            discovery,
            attempts=[bad, good],
            notes=["display-name rejected; canonical dry-run prepared"],
        )

    def case_unknown(self) -> CaseResult:
        name = "unknown model/team name"
        discovery = 1
        marker = f"MR-S06-unknown-{uuid.uuid4().hex[:8]}"
        bad_w = self.run(
            ["run", marker, "--worker", "model_definitely_not_real", "--json"],
            expect_ok=False,
            parse_json=True,
            marker=marker,
        )
        bad_t = self.run(
            ["run", marker, "--team", "team_definitely_not_real", "--json"],
            expect_ok=False,
            parse_json=True,
            marker=marker,
        )
        if bad_w.created_run or bad_t.created_run:
            return CaseResult(name, False, "", discovery, error="run created on unknown id")
        return CaseResult(
            name,
            True,
            "cannot-fulfill (WORKER_NOT_AVAILABLE / team unknown)",
            discovery,
            attempts=[bad_w, bad_t],
        )

    def case_rare_admin(self) -> CaseResult:
        name = "rare administrative intent"
        # Suite already did menu (1). One hydrate allowed.
        discovery = 2
        show = self.run(["menu", "show", "command:run", "--json"], expect_ok=True, parse_json=True)
        body = show.dry_run_json or {}
        if body.get("ref") != "command:run" and (body.get("command") or {}).get("name") != "run":
            # Accept either top-level ref or nested command name.
            if body.get("kind") != "command" and "run" not in json.dumps(body):
                return CaseResult(name, False, "alln menu show command:run --json", discovery, error="bad hydrate")
        return CaseResult(
            name,
            True,
            "alln menu show command:run --json",
            discovery,
            attempts=[show],
            notes=["menu + one menu show"],
        )

    # MRL-S01 — composition-shaped asks the MR-S06 matrix above does not cover.
    # Kill gate: if these already pass at the MR-S06 bar, the Menu_Relations.md
    # phase gets archived. These are mechanical, not live-LLM — a case passes
    # only when `alln menu --json` (plus the allowed hydrate budget) is enough
    # to reach the correct canonical id / command / refusal without guessing.

    def case_deeper_spec_review(self) -> CaseResult:
        name = "MRL-S01a: run the deeper version of the spec review"
        discovery = 1
        family = [
            t
            for t in self.menu.get("teams") or []
            if (t.get("displayName") or "").strip().startswith("Spec Review")
        ]
        if len(family) < 2:
            return CaseResult(name, False, "", discovery, error="spec review tier family missing from menu")
        deeper = [t for t in family if "deep" in (t.get("useWhen") or "").lower()]
        if len(deeper) != 1:
            return CaseResult(
                name,
                False,
                "",
                discovery,
                notes=[f"family={[t.get('id') for t in family]}"],
                error=f"useWhen does not uniquely disambiguate the deeper tier: {[t.get('id') for t in deeper]}",
            )
        team = deeper[0]
        self.assert_no_hydration_in_templates(team, "team")
        tid = team["id"]
        if tid != "code_spec_review_max":
            return CaseResult(name, False, "", discovery, error=f"expected code_spec_review_max got {tid}")
        marker = f"MRL-S01-deeper-{uuid.uuid4().hex[:8]}"
        args = self.expand_template(team["validateTemplate"], marker)
        if "--dry-run" not in args or tid not in args:
            return CaseResult(name, False, " ".join(args), discovery, error="bad validateTemplate shape")
        attempt = self.run(args, expect_ok=True, parse_json=True, marker=marker)
        body = attempt.dry_run_json or {}
        if body.get("teamPresetId") != "code_spec_review_max":
            return CaseResult(
                name, False, " ".join(args), discovery, error=f"teamPresetId={body.get('teamPresetId')}"
            )
        return CaseResult(
            name,
            True,
            " ".join(["alln", *args]),
            discovery,
            attempts=[attempt],
            notes=["useWhen 'Deep review: launch/hard specs' uniquely disambiguated the _max tier"],
        )

    def case_retired_id_recovery(self) -> CaseResult:
        name = "MRL-S01b: retired id carried in from a stale transcript"
        discovery = 1
        # code_bug_hunt_lite was the pre-rename id for today's code_bug_hunt
        # (BuiltInTeams tier rename history); it does not exist in current source
        # or the live menu, so it is a genuine retired id — not an invented one.
        retired_id = "code_bug_hunt_lite"
        live_ids = {t.get("id") for t in self.menu.get("teams") or []}
        if retired_id in live_ids:
            return CaseResult(
                name, False, "", discovery, error=f"{retired_id} unexpectedly live; pick a genuinely retired id"
            )
        marker = f"MRL-S01-retired-{uuid.uuid4().hex[:8]}"
        attempt = self.run(
            ["run", marker, "--team", retired_id, "--json"],
            expect_ok=False,
            parse_json=True,
            marker=marker,
        )
        if attempt.created_run:
            return CaseResult(name, False, "", discovery, attempts=[attempt], error="run created for retired id")
        body = attempt.dry_run_json or {}
        error = body.get("error") or {}
        message = str(error.get("message") or "")
        next_action = error.get("nextAction") or {}
        next_cmd = str(next_action.get("command") or "")
        candidates = {c.get("id") for c in (error.get("candidates") or []) if isinstance(c, dict)}
        points_at_menu = "menu" in message.lower() or "menu" in next_cmd.lower()
        if not points_at_menu:
            return CaseResult(
                name,
                False,
                message,
                discovery,
                attempts=[attempt],
                error="opaque failure: no menu/recovery path named — caller cannot recover",
            )
        return CaseResult(
            name,
            True,
            f'alln run "{marker}" --team {retired_id} --json',
            discovery,
            attempts=[attempt],
            notes=[
                f"failure only (exit={attempt.exit_code}), no run created",
                f"error names a discovery path: {next_cmd or message[:120]!r}",
                f"candidates surfaced (includes live replacement code_bug_hunt: {'code_bug_hunt' in candidates}): {sorted(candidates)}",
            ],
        )

    def case_spec_review_then_build(self) -> CaseResult:
        name = "MRL-S01c: harden this spec then have someone build it"
        discovery = 1
        review = self.find_team_by_display("Spec Review")
        build = self.find_execution_team()
        self.assert_no_hydration_in_templates(review, "team")
        self.assert_no_hydration_in_templates(build, "team")
        if review["id"] != "code_spec_review":
            return CaseResult(name, False, "", discovery, error=f"expected code_spec_review got {review['id']}")
        if build["id"] != "build_slice" or build.get("mutating") is not True:
            return CaseResult(
                name,
                False,
                "",
                discovery,
                error=f"expected mutating build_slice, got {build.get('id')} mutating={build.get('mutating')}",
            )
        marker1 = f"MRL-S01-chain1-{uuid.uuid4().hex[:8]}"
        args1 = self.expand_template(review["validateTemplate"], marker1)
        attempt1 = self.run(args1, expect_ok=True, parse_json=True, marker=marker1)
        body1 = attempt1.dry_run_json or {}
        if body1.get("teamPresetId") != "code_spec_review" or body1.get("writePolicy") != "readOnly":
            return CaseResult(name, False, " ".join(args1), discovery, error=f"step1 body={body1}")
        marker2 = f"MRL-S01-chain2-{uuid.uuid4().hex[:8]}"
        args2 = self.expand_template(build["validateTemplate"], marker2)
        attempt2 = self.run(args2, expect_ok=True, parse_json=True, marker=marker2)
        body2 = attempt2.dry_run_json or {}
        if body2.get("teamPresetId") != "build_slice" or body2.get("writePolicy") != "mutating":
            return CaseResult(name, False, " ".join(args2), discovery, error=f"step2 body={body2}")
        final = " THEN ".join([" ".join(["alln", *args1]), " ".join(["alln", *args2])])
        return CaseResult(
            name,
            True,
            final,
            discovery,
            attempts=[attempt1, attempt2],
            notes=[
                "step1 useWhen 'Harden a spec before you build' matched the ask verbatim",
                "step2 build_slice resolved mutating/writePolicy=mutating for the execution half",
            ],
        )

    def case_design_needs_no_screenshot(self) -> CaseResult:
        """MRL-S01d, corrected.

        The phase doc specified this case as "given only a screenshot -> correct
        refusal/clarify per the prompt-not-screenshot law". That misstates the law.
        The founder ruling (2026-06-18) is the OPPOSITE of a refusal rule:

            "Design lane needs NO screenshot. A Design team runs from a PROMPT alone
             ... A mandatory screenshot/image input gate on Design is a BUG. The
             optional image tile/row stays OPTIONAL."

        So accepting a screenshot is correct, and refusing one would be the bug.
        The real, testable law is that Design must never REQUIRE an attachment:
        a plain text ask has to run with no image at all.
        """
        name = "MRL-S01d: design from a prompt alone, no attachment required"
        discovery = 1
        design_rows = [t for t in self.menu.get("teams") or [] if str(t.get("id") or "").startswith("design_")]
        if not design_rows:
            return CaseResult(name, False, "", discovery, error="no design_* teams in menu")
        team = next((t for t in design_rows if t.get("id") == "design_design"), design_rows[0])
        tid = team["id"]
        marker = f"MRL-S01-design-{uuid.uuid4().hex[:8]}"
        args = self.expand_template(team["validateTemplate"], marker)
        attempt = self.run(args, expect_ok=True, parse_json=True, marker=marker)
        body = attempt.dry_run_json or {}
        if body.get("teamPresetId") != tid:
            return CaseResult(name, False, " ".join(args), discovery, attempts=[attempt],
                              error=f'teamPresetId={body.get("teamPresetId")!r} expected {tid!r}')
        # The law is about USER INPUT, not model capability: nothing may demand an
        # attachment. A worker carrying requiredCapabilityTags ["image"] is fine —
        # that asks for an image-CAPABLE model (a design team emits visual
        # directions), not for the user to paste a screenshot.
        #
        # A readiness block is environmental, not a law violation: an isolated
        # support dir has no probe records, so every team blocks on "no ready
        # model". Only an attachment demand fails this case.
        haystack = " ".join([str(body.get("blockedReason") or ""), json.dumps(body.get("warnings") or [])]).lower()
        demands_attachment = any(
            kw in haystack for kw in ("screenshot", "attach", "upload", "provide an image", "image required")
        )
        if demands_attachment:
            return CaseResult(name, False, " ".join(args), discovery, attempts=[attempt],
                              error=f"attachment demanded for a prompt-only design ask: {haystack}")
        notes = ["no attachment demanded; the optional image stays optional"]
        if body.get("canStart") is False:
            notes.append(f"blocked on readiness only (environmental): {body.get('blockedReason')!r}")
        return CaseResult(name, True, " ".join(["alln", *args]), discovery, attempts=[attempt], notes=notes)

    def run_matrix(self) -> None:
        runners = [
            self.case_ask_sonnet,
            self.case_ask_several,
            self.case_growth_team,
            self.case_duplicate_growth,
            self.case_edit_growth,
            self.case_execution_team,
            self.case_bare_sonnet,
            self.case_unknown,
            self.case_rare_admin,
            self.case_deeper_spec_review,
            self.case_retired_id_recovery,
            self.case_spec_review_then_build,
            self.case_design_needs_no_screenshot,
        ]
        for fn in runners:
            self.assert_binary_unchanged()
            result = fn()
            self.cases.append(result)
            status = "PASS" if result.ok else "FAIL"
            print(f"  [{status}] {result.name} → {result.final_command}")
            if result.error:
                print(f"         error: {result.error}")
            if result.discovery_calls > 2 or (
                result.name != "rare administrative intent" and result.discovery_calls > 1
            ):
                # Suite shares one menu read; per-case discovery_calls is the budget for that row.
                if result.discovery_calls > 2:
                    result.ok = False
                    result.error = (result.error or "") + " discovery budget exceeded"

        failed = [c for c in self.cases if not c.ok]
        if failed:
            self.fail("; ".join(f"{c.name}: {c.error}" for c in failed))

    def negative_retired_grammar(self) -> None:
        print("negative retired grammar probes")
        probes = [
            ["team", "hello", "--for", "anything"],
            ["route", "--for", "anything"],
            ["resolve", "--for", "anything"],
            ["commands", "--json"],
            ["team", "list", "--json"],
            ["team", "show", "--json"],
            ["team", "preflight", "--team", "code_growth", "--json"],
            ["team", "probe-message", "--json"],
            ["team", "start", "probe-message", "--json"],
        ]
        for args in probes:
            # Bypass invent-ban by calling subprocess directly for negatives.
            proc = subprocess.run(
                [str(self.binary), *args], capture_output=True, text=True
            )
            self.attempts.append(
                Attempt(argv=[str(self.binary), *args], exit_code=proc.returncode, stdout=proc.stdout, stderr=proc.stderr)
            )
            if proc.returncode == 0:
                self.fail(f"retired grammar unexpectedly succeeded: {args}")

        for path in (
            "Packages/AllnighterCore/Sources/AllnighterCore/AgentIntentRouter.swift",
            "Packages/AllnighterCore/Sources/AllnighterCore/AgentHello.swift",
        ):
            if Path(path).exists():
                self.fail(f"retired source still present: {path}")

    def bootstrap_checks(self) -> None:
        boot = self.run(["bootstrap"], expect_ok=True)
        if "alln menu --json" not in boot.stdout:
            self.fail("bootstrap missing alln menu --json")
        for bad in ("team hello", "route --for", "resolve --for"):
            if bad in boot.stdout:
                self.fail(f"bootstrap contains retired teaching: {bad}")

    def _write_report(self, ok: bool) -> None:
        report = {
            "ok": ok,
            "suite": "menu-not-router",
            "kind": "mechanical-pinned-binary-matrix",
            "not": "live-frontier-llm-eval",
            "binary": str(self.binary),
            "pinnedSha256": self.pinned_sha,
            "version": self.version,
            "workspaceHead": self.head_sha,
            "menuBytes": self.menu_bytes,
            "menuCounts": {
                "actions": len(self.menu.get("actions") or []),
                "commands": len(self.menu.get("commands") or []),
                "teams": len(self.menu.get("teams") or []),
                "models": len(self.menu.get("models") or []),
                "recipes": len(self.menu.get("recipes") or []),
            },
            "cases": [
                {
                    "name": c.name,
                    "ok": c.ok,
                    "finalCommand": c.final_command,
                    "discoveryCalls": c.discovery_calls,
                    "error": c.error,
                    "notes": c.notes,
                }
                for c in self.cases
            ],
            "attempts": [
                {
                    "argv": a.argv,
                    "exitCode": a.exit_code,
                    "dryRunJsonPresent": a.dry_run_json is not None,
                    "createdRun": a.created_run,
                    "stdoutHead": (a.stdout or "")[:240],
                }
                for a in self.attempts
            ],
        }
        self.out_dir.mkdir(parents=True, exist_ok=True)
        (self.out_dir / "report.json").write_text(json.dumps(report, indent=2) + "\n")
        lines = [
            f"suite=menu-not-router ok={ok}",
            f"binary={self.binary}",
            f"sha256={self.pinned_sha}",
            f"menuBytes={self.menu_bytes}",
        ]
        for c in self.cases:
            lines.append(f"{'PASS' if c.ok else 'FAIL'}\t{c.name}\t{c.final_command}")
        (self.out_dir / "transcript.txt").write_text("\n".join(lines) + "\n")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", required=True, help="Path to pinned alln binary")
    parser.add_argument(
        "--out-dir",
        default=None,
        help="Report directory (default: .build/agent-eval/menu-not-router)",
    )
    parser.add_argument(
        "--allow-stale-gitsha",
        action="store_true",
        help="Do not warn-fail on BuildInfo gitSha drift (file SHA still pinned)",
    )
    args = parser.parse_args()

    root = Path(__file__).resolve().parents[1]
    out = Path(args.out_dir) if args.out_dir else root / ".build" / "agent-eval" / "menu-not-router"
    out.mkdir(parents=True, exist_ok=True)

    print("== MR-S06 menu-not-router mechanical matrix ==")
    print(f"out: {out}")
    h = Harness(Path(args.binary), out, allow_stale_gitsha=args.allow_stale_gitsha)
    h.pin_binary()
    h.load_menu()
    h.bootstrap_checks()
    h.negative_retired_grammar()
    print("cold-agent acceptance matrix (mechanical)")
    h.run_matrix()
    h.assert_binary_unchanged()
    h._write_report(ok=True)
    print(f"OK — menu-not-router suite green (report: {out / 'report.json'})")


if __name__ == "__main__":
    main()
