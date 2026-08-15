#!/usr/bin/env bash
# Allnighter green wall — extend as Swift targets land.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK_STARTED_AT=$SECONDS

# ---------------------------------------------------------------------------
# Wall admission control — refuse fix→test hammering of the full wall.
# Does not change what the wall does when admitted. CI is never blocked.
# State: .wmd/wall-last-run.json  Override log: .wmd/wall-runs.log
# Closeout override:
#   ALLNIGHTER_WALL_REASON="<why this run is needed>" bash scripts/check.sh
# Cooldown minutes (default 45): ALLNIGHTER_WALL_COOLDOWN_MINUTES
# ---------------------------------------------------------------------------
WALL_STATE_DIR="${ALLNIGHTER_WALL_STATE_DIR:-$ROOT/.wmd}"
WALL_LAST_RUN="$WALL_STATE_DIR/wall-last-run.json"
WALL_RUNS_LOG="$WALL_STATE_DIR/wall-runs.log"
WALL_COOLDOWN_MINUTES="${ALLNIGHTER_WALL_COOLDOWN_MINUTES:-45}"
WALL_FINAL_RESULT="aborted"
WALL_ADMITTED=0

wall_is_ci() {
  # Never block real CI. Prefer platform-specific signals over bare CI=true —
  # agent hosts (and some local tools) set CI=true, and those are exactly who
  # must not hammer the wall. GitHub Actions always sets GITHUB_ACTIONS=true;
  # GitLab/Circle/Buildkite/Azure/Jenkins set their own markers. Escape hatch
  # for unusual CI: ALLNIGHTER_WALL_CI=1.
  [[ -n "${ALLNIGHTER_WALL_CI:-}" || -n "${GITHUB_ACTIONS:-}" \
    || -n "${GITLAB_CI:-}" || -n "${CIRCLECI:-}" || -n "${BUILDKITE:-}" \
    || -n "${TF_BUILD:-}" || -n "${JENKINS_URL:-}" || -n "${TRAVIS:-}" \
    || -n "${APPVEYOR:-}" ]]
}

wall_iso_now() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

wall_head_sha() {
  git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo "unknown"
}

wall_write_state() {
  local started_at="$1" head_sha="$2" reason="$3" result="$4"
  mkdir -p "$WALL_STATE_DIR"
  python3 - "$WALL_LAST_RUN" "$started_at" "$head_sha" "$reason" "$result" <<'PY'
import json, sys
path, started, sha, reason, result = sys.argv[1:6]
obj = {
    "startedAt": started,
    "headSha": sha,
    "reason": reason if reason else None,
    "result": result,
}
with open(path, "w", encoding="utf-8") as f:
    json.dump(obj, f, indent=2)
    f.write("\n")
PY
}

wall_update_result() {
  local result="$1"
  [[ -f "$WALL_LAST_RUN" ]] || return 0
  python3 - "$WALL_LAST_RUN" "$result" <<'PY'
import json, sys
path, result = sys.argv[1:3]
try:
    with open(path, encoding="utf-8") as f:
        obj = json.load(f)
except (OSError, ValueError):
    raise SystemExit(0)
obj["result"] = result
with open(path, "w", encoding="utf-8") as f:
    json.dump(obj, f, indent=2)
    f.write("\n")
PY
}

wall_append_override_log() {
  local reason="$1" head_sha="$2"
  mkdir -p "$WALL_STATE_DIR"
  printf '%s head=%s reason=%s\n' "$(wall_iso_now)" "$head_sha" "$reason" >> "$WALL_RUNS_LOG"
}

wall_on_exit() {
  local ec=$?
  # Only finalize if this invocation was admitted (started real work / probe).
  if [[ "$WALL_ADMITTED" -eq 1 ]]; then
    if [[ "$WALL_FINAL_RESULT" == "aborted" ]]; then
      if [[ $ec -eq 0 ]]; then
        WALL_FINAL_RESULT="pass"
      else
        WALL_FINAL_RESULT="fail"
      fi
    fi
    wall_update_result "$WALL_FINAL_RESULT" 2>/dev/null || true
  fi
  return "$ec"
}
trap wall_on_exit EXIT

if ! wall_is_ci; then
  # Cooldown 0 = always admit (used by works-tests / emergency).
  if [[ "${WALL_COOLDOWN_MINUTES}" != "0" ]] && [[ -f "$WALL_LAST_RUN" ]]; then
    # age_seconds, result, headSha, startedAt — empty if unreadable
    wall_prev="$(
      python3 - "$WALL_LAST_RUN" <<'PY'
import json, sys
from datetime import datetime, timezone
path = sys.argv[1]
try:
    with open(path, encoding="utf-8") as f:
        obj = json.load(f)
except (OSError, ValueError):
    raise SystemExit(0)
started = obj.get("startedAt") or ""
try:
    if started.endswith("Z"):
        dt = datetime.strptime(started, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
    else:
        dt = datetime.fromisoformat(started.replace("Z", "+00:00"))
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
except ValueError:
    raise SystemExit(0)
age = (datetime.now(timezone.utc) - dt).total_seconds()
result = obj.get("result") if obj.get("result") is not None else "unknown"
sha = obj.get("headSha") or "unknown"
print(f"{age:.0f}\t{result}\t{sha}\t{started}")
PY
    )"
    if [[ -n "$wall_prev" ]]; then
      IFS=$'\t' read -r wall_age_s wall_prev_result wall_prev_sha wall_prev_started <<< "$wall_prev"
      wall_cooldown_s=$(( WALL_COOLDOWN_MINUTES * 60 ))
      if [[ -n "${wall_age_s:-}" ]] && [[ "$wall_age_s" -lt "$wall_cooldown_s" ]]; then
        wall_reason_trim="${ALLNIGHTER_WALL_REASON:-}"
        # Strip whitespace-only reasons (count as empty).
        wall_reason_trim="${wall_reason_trim#"${wall_reason_trim%%[![:space:]]*}"}"
        wall_reason_trim="${wall_reason_trim%"${wall_reason_trim##*[![:space:]]}"}"
        if [[ -z "$wall_reason_trim" ]]; then
          remaining=$(( wall_cooldown_s - wall_age_s ))
          remaining_m=$(( remaining / 60 ))
          remaining_s=$(( remaining % 60 ))
          echo "check: REFUSED — wall cooldown active (last run started ${wall_prev_started}, result=${wall_prev_result}, head=${wall_prev_sha}; cooldown=${WALL_COOLDOWN_MINUTES}m, ~${remaining_m}m${remaining_s}s left)." >&2
          echo "" >&2
          echo "  Iteration proof (cheap — use this, not the full wall):" >&2
          echo "    scripts/swift-test.sh --filter <YourTests>" >&2
          echo "" >&2
          echo "  Genuine closeout override (non-empty reason required; logged):" >&2
          echo "    ALLNIGHTER_WALL_REASON=\"<why this run is needed>\" bash scripts/check.sh" >&2
          exit 2
        fi
        # Non-empty reason under cooldown → admit, but make hammering visible.
        wall_append_override_log "$wall_reason_trim" "$(wall_head_sha)"
        echo "check: wall cooldown overridden — reason logged to $WALL_RUNS_LOG"
      fi
    fi
  fi
fi

# Admitted: record start (result starts as aborted; trap finalizes pass/fail/instrumentFault).
WALL_STARTED_AT="$(wall_iso_now)"
WALL_HEAD_SHA="$(wall_head_sha)"
WALL_REASON_FOR_STATE="${ALLNIGHTER_WALL_REASON:-}"
wall_write_state "$WALL_STARTED_AT" "$WALL_HEAD_SHA" "$WALL_REASON_FOR_STATE" "aborted"
WALL_ADMITTED=1

# Test-only: prove admission without running the wall (works-test-wall-cooldown.sh).
# Leave result as aborted (wall never ran) and skip trap finalization to pass.
if [[ -n "${ALLNIGHTER_WALL_ADMISSION_PROBE:-}" ]]; then
  echo "check: admission probe ok (startedAt=${WALL_STARTED_AT}, head=${WALL_HEAD_SHA})"
  WALL_ADMITTED=0
  exit 0
fi

# shellcheck source=ensure-test-guard-path.sh disable=SC1091
source "$ROOT/scripts/ensure-test-guard-path.sh"

# TIU-S01: cheap hygiene first (no compile/test suites).
bash "$ROOT/scripts/check-fast.sh"
ran_any=true

# ASF-S06: BuildInfo is generated by BuildInfoPlugin whenever SwiftPM builds
# the `alln` target. There is deliberately no separate pre-build script for an
# agent to remember or for this wall to mutate.

if [[ -f "$ROOT/Packages/AllnighterCore/Package.swift" ]]; then
  echo "==> swift test AllnighterCore"
  ALLNIGHTER_SWIFT_TEST_TIMEOUT_SECONDS="${ALLNIGHTER_SWIFT_TEST_TIMEOUT_SECONDS:-3600}" \
    bash "$ROOT/scripts/swift-test.sh"
  ran_any=true

  # Structural fixture mode (policy + absence checks). Filtered swift tests are
  # skipped here when the full suite already ran above (TIU-S02).
  echo "==> code red structural works test"
  ALLNIGHTER_STRUCTURAL_SKIP_SWIFT_TEST=1 \
    bash "$ROOT/scripts/code_red_works_test.sh" structural
  ran_any=true

  # ASF-S08: contract drift gate (same check StandingInvariants runs opportunistically).
  echo "==> alln dev export-contracts --check (via rebuild_cli.sh)"
  bash "$ROOT/scripts/rebuild_cli.sh"
  ALLN_BIN="${ALLNIGHTER_CLI_INSTALL_DIR:-$HOME/.local/bin}/alln"
  ( cd "$ROOT" && "$ALLN_BIN" dev export-contracts --check )
  ran_any=true
fi

# Mac app (XcodeGen-generated project; regenerate so .xcodeproj need not be committed).
MAC_APP="$ROOT/Apps/AllnighterMac"
if [[ -f "$MAC_APP/project.yml" ]] && command -v xcodegen >/dev/null 2>&1; then
  echo "==> xcodegen generate (AllnighterMac)"
  ( cd "$MAC_APP" && xcodegen generate >/dev/null )
  echo "==> xcodebuild test AllnighterMac"
  # CR-S07: all three Code Red skips are RETIRED — every Mac test is on the wall.
  # The two relay tests were repaired by giving them their own stub driver and
  # workers instead of seating the user's live catalog; see their doc comments.
  #
  # Wall-local DerivedData (not Xcode's default ~/Library/.../DerivedData):
  # Core API renames can leave a stale AllnighterCore.swiftmodule that Engine
  # still imports, producing "missing argument for parameter …" compile errors
  # against sources that SPM already accepts. Isolate the wall from the IDE
  # cache, and wipe only when Core/Engine sources outrun the cached modules
  # (or modules disagree with each other) — warm incremental stays cheap.
  MAC_DD="${ALLNIGHTER_MAC_DERIVED_DATA:-$HOME/Library/Developer/Allnighter/DerivedData-AllnighterMac}"
  # Never default under the repo: checkouts often live in ~/Documents and a
  # test-host .app there raises macOS Documents TCC dialogs attributed to
  # Allnighter (same reason scripts/dev.sh builds under ~/Library). Override
  # with ALLNIGHTER_MAC_DERIVED_DATA if you need an alternate wall cache.
  CORE_SOURCES="$ROOT/Packages/AllnighterCore/Sources"
  if [[ -d "$MAC_DD" ]]; then
    # Exit 0 = stale/skewed (wipe); exit 1 = warm cache is fine.
    if python3 - "$MAC_DD" "$CORE_SOURCES" <<'PY'
import os, sys
dd, src_root = sys.argv[1], sys.argv[2]
mod_mtimes = []
for root, dirs, files in os.walk(dd):
    # Directory-style .swiftmodule bundles
    for d in dirs:
        if d == "AllnighterCore.swiftmodule" or (
            d.endswith(".swiftmodule") and "AllnighterCore" in d and "AllnighterEngine" not in d
        ):
            path = os.path.join(root, d)
            try:
                mod_mtimes.append(os.path.getmtime(path))
            except OSError:
                pass
    for f in files:
        if not f.endswith(".swiftmodule"):
            continue
        path = os.path.join(root, f)
        # Only AllnighterCore product modules (skip Engine / other packages).
        if "AllnighterCore" not in path or "AllnighterEngine" in path:
            continue
        try:
            mod_mtimes.append(os.path.getmtime(path))
        except OSError:
            pass
if not mod_mtimes:
    sys.exit(1)  # cold cache — nothing to invalidate
src_mtimes = []
for root, _dirs, files in os.walk(src_root):
    for f in files:
        if f.endswith(".swift"):
            try:
                src_mtimes.append(os.path.getmtime(os.path.join(root, f)))
            except OSError:
                pass
# Sources newer than the oldest cached Core module → wipe.
if src_mtimes and max(src_mtimes) > min(mod_mtimes):
    sys.exit(0)
# Dual-location module skew (e.g. Products/ vs PackageFrameworks/) → wipe.
if max(mod_mtimes) - min(mod_mtimes) > 1.0:
    sys.exit(0)
sys.exit(1)
PY
    then
      echo "check: stale/skewed AllnighterCore modules vs Packages/AllnighterCore/Sources; cleaning $MAC_DD"
      rm -rf "$MAC_DD"
    fi
  fi
  mkdir -p "$MAC_DD"

  # Signing for the Mac wall:
  # CODE_SIGNING_ALLOWED=NO shipped with Phase 03 (557eac95) so agents/CI without a
  # developer identity could still *build*. On modern macOS it leaves the XCTest
  # host unsigned; the runner then hangs ~5+ minutes ("test runner hung before
  # establishing connection") and executes ZERO tests — a wall that burns time and
  # trains people to ignore failures. Never reintroduce that flag.
  #
  # Prefer project signing (Automatic + DEVELOPMENT_TEAM in project.yml) when a
  # codesigning identity is present. With no identity, ad-hoc sign the host so the
  # runner can still load it (signed, just not team-signed).
  xcode_signing_args=()
  if security find-identity -v -p codesigning 2>/dev/null \
    | grep -Eq 'Apple Development|Mac Developer|Developer ID Application|Apple Distribution'; then
    echo "check: codesigning identity present — using project signing (no CODE_SIGNING_ALLOWED=NO)"
  else
    echo "check: no codesigning identity in keychain — ad-hoc signing Mac test host"
    xcode_signing_args+=(
      CODE_SIGN_IDENTITY=-
      CODE_SIGNING_REQUIRED=YES
      CODE_SIGNING_ALLOWED=YES
      DEVELOPMENT_TEAM=
      CODE_SIGN_STYLE=Manual
    )
  fi

  export ALLNIGHTER_TEST_TOKEN
  ALLNIGHTER_TEST_TOKEN="$(python3 "$ROOT/scripts/allnighter_test_token.py" mint "$ROOT")"
  xcode_log="$(mktemp "${TMPDIR:-/tmp}/alln-xcodebuild-test.XXXXXX")"
  xcode_status=0
  mac_phase_started=$SECONDS
  # Keep the last few progress lines on the console; full log is teed for diagnostics.
  # bash 3.2 + set -u: empty `"${arr[@]}"` is unbound (identity-present path
  # leaves xcode_signing_args empty). Use the same form as agent_eval.sh.
  xcodebuild test \
    -project "$MAC_APP/AllnighterMac.xcodeproj" \
    -scheme AllnighterMac \
    -destination 'platform=macOS' \
    -derivedDataPath "$MAC_DD" \
    ${xcode_signing_args[@]+"${xcode_signing_args[@]}"} \
    2>&1 | tee "$xcode_log" | tail -3 || xcode_status=${PIPESTATUS[0]}
  mac_phase_elapsed=$((SECONDS - mac_phase_started))

  # xcodebuild sometimes exits 0 even when the suite reports failures.
  if [[ "$xcode_status" -eq 0 ]] && rg -q 'TEST FAILED|with [1-9][0-9]* failures?' "$xcode_log" 2>/dev/null; then
    xcode_status=1
  fi

  # Count executed test cases from XCTest summary lines ("Executed N tests, …").
  # Prefer the largest N (outer "All tests" suite) so nested suite lines do not
  # under-count; missing summary → 0 (instrument fault below).
  mac_tests_executed="$(
    python3 - "$xcode_log" <<'PY'
import re, sys
path = sys.argv[1]
best = 0
try:
    text = open(path, errors="replace").read()
except OSError:
    print(0)
    raise SystemExit
for m in re.finditer(r"Executed\s+(\d+)\s+tests?", text):
    n = int(m.group(1))
    if n > best:
        best = n
print(best)
PY
  )"

  instrument_fault=0
  instrument_reason=""
  if rg -q 'test runner hung|hung before establishing connection' "$xcode_log" 2>/dev/null; then
    instrument_fault=1
    instrument_reason="Mac test runner hung before establishing connection (zero tests executed)"
  elif [[ "${mac_tests_executed:-0}" -eq 0 ]]; then
    # Build may have succeeded and xcodebuild may even have exited 0 — still a
    # wall instrument fault. A green wall that ran nothing is banned.
    instrument_fault=1
    instrument_reason="Mac suite executed ZERO test cases (not a pass, not an ordinary failure)"
  fi

  if [[ "$instrument_fault" -eq 1 ]]; then
    xcode_status=1
    WALL_FINAL_RESULT="instrumentFault"
    echo "check: INSTRUMENT FAULT — ${instrument_reason}"
    echo "check: Mac phase elapsed ${mac_phase_elapsed}s; executed=${mac_tests_executed:-0}"
    echo "check: this is not a product test failure — the wall could not run the suite."
  elif [[ "$xcode_status" -eq 0 ]]; then
    echo "check: Mac suite executed ${mac_tests_executed} tests in ${mac_phase_elapsed}s"
  fi

  if [[ "$xcode_status" -ne 0 ]]; then
    if [[ "$instrument_fault" -eq 0 ]]; then
      echo "check: xcodebuild failed (exit $xcode_status). Diagnostics:"
    else
      echo "check: xcodebuild instrument fault (exit $xcode_status). Diagnostics:"
    fi
    # Surface hang/zero-run, compile errors, and failing assertions — not just "(N failures)".
    if command -v rg >/dev/null 2>&1; then
      rg -n --no-heading \
        'test runner hung|hung before establishing connection|Executed 0 tests|error: |fatal error: |\.swift:[0-9]+:[0-9]+: error:|TEST FAILED|Testing failed|with [1-9][0-9]* failures?|XCTAssert|failed \(|error: -\[|\*\* TEST BUILD FAILED \*\*|\*\* TEST FAILED \*\*|\*\* BUILD FAILED \*\*|INSTRUMENT FAULT' \
        "$xcode_log" | head -100 || true
    else
      grep -nE 'test runner hung|Executed 0 tests|error: |TEST FAILED|XCTAssert|BUILD FAILED' "$xcode_log" | head -100 || true
    fi
    echo "check: full xcodebuild log preserved at: $xcode_log"
    # Do not delete the log on failure — evidence is the product.
  else
    rm -f "$xcode_log"
  fi
  python3 "$ROOT/scripts/allnighter_test_token.py" burn "$ROOT" "$ALLNIGHTER_TEST_TOKEN" 2>/dev/null || true
  unset ALLNIGHTER_TEST_TOKEN
  [[ "$xcode_status" -eq 0 ]] || exit "$xcode_status"
  ran_any=true
elif [[ -f "$MAC_APP/project.yml" ]]; then
  echo "check: xcodegen not installed; skipping Mac app (run: brew install xcodegen)"
fi

if [[ "$ran_any" == false ]]; then
  echo "check: no Swift targets yet (docs-only bootstrap OK)"
fi

# GUI Visual Proof Gate — deliberately runs AFTER every test phase above, and
# non-fatally (`|| gui_proof_status=$?`), so a GUI-proof failure can never
# prevent the Swift/Mac suites from being measured. It still fails the wall
# overall: see the deferred exit after the timing footer below.
# docs/gui/Visual_Proof_Gate.md §D "tests after the gate, not before".
echo "==> check GUI visual proof gate"
gui_proof_status=0
bash "$ROOT/scripts/check_gui_proof.sh" || gui_proof_status=$?

elapsed=$((SECONDS - CHECK_STARTED_AT))
# Integer tenths avoid nested-quote awk: `"$(awk "BEGIN {… \"%.1f\", …}")"` toggles
# quotes so bash brace-expands `{printf…, expr}` into two failed awks; printf then
# reuses the format and prints the footer twice (real Ns + spurious 0s / 0.0m).
mins_tenths=$((elapsed * 10 / 60))
printf 'check: done in %ds (%d.%dm wall)\n' "$elapsed" "$((mins_tenths / 10))" "$((mins_tenths % 10))"

if [[ "$gui_proof_status" -ne 0 ]]; then
  echo "check: GUI visual proof gate FAILED (see '==> check GUI visual proof gate' above) — wall fails despite any passing tests." >&2
  exit "$gui_proof_status"
fi
