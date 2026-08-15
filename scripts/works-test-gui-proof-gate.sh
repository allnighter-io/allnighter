#!/usr/bin/env bash
# Works Test for the GUI Visual Proof Gate rewrite (docs/gui/Visual_Proof_Gate.md).
#
# Proves, in a throwaway temp git repo (never touches the real Allnighter
# checkout's Apps/ or docs/qa/gui/), via ALLNIGHTER_GUI_PROOF_ROOT / _SRC_DIR /
# _PACKET_ROOT / _DEBT_BASELINE env overrides on the REAL scripts:
#
#   A. A repo with pre-existing debt + a change touching NO view => the gate
#      does not block.
#   B. A change touching one view => only that view is required (untouched
#      pre-existing debt is reported, not blocking).
#   C. Sealing surface X does not mark an unrelated, unreviewed-but-changed
#      view Y as proven — Y is recorded as DEBT, and still blocks if it's in
#      the diff.
#   D. The ratchet rejects a debt increase, even with an empty diff (a
#      backstop independent of per-diff blocking — catches debt smuggled in
#      by a bypass).
#
# Plus a structural check for §D "tests after the gate, not before": the
# gate is wired into check.sh (not check-fast.sh) and check.sh's capture
# pattern lets a later phase run even when the gate fails.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK_GUI_PROOF="$REPO_ROOT/scripts/check_gui_proof.sh"
GUI_PROOF_SEAL="$REPO_ROOT/scripts/gui_proof_seal.sh"
GUI_PROOF_WAIVE="$REPO_ROOT/scripts/gui_proof_waive.sh"

FAILURES=0
WORK_DIR=""

log()  { echo "works-test-gui-proof: $*"; }
pass() { echo "works-test-gui-proof: PASS — $*"; }
fail() { echo "works-test-gui-proof: FAIL — $*" >&2; FAILURES=$((FAILURES + 1)); }

cleanup() { [[ -n "$WORK_DIR" && -d "$WORK_DIR" ]] && rm -rf "$WORK_DIR"; }
trap cleanup EXIT

fresh_repo() {
  WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/alln-gui-proof-works-test.XXXXXX")"
  git init -q "$WORK_DIR"
  git -C "$WORK_DIR" config user.email "test@allnighter.test"
  git -C "$WORK_DIR" config user.name "GUI Proof Works Test"
  git -C "$WORK_DIR" config commit.gpgsign false
  mkdir -p "$WORK_DIR/Sources" "$WORK_DIR/qa/gui"
  export ALLNIGHTER_GUI_PROOF_ROOT="$WORK_DIR"
  export ALLNIGHTER_GUI_PROOF_SRC_DIR="Sources"
  export ALLNIGHTER_GUI_PROOF_PACKET_ROOT="qa/gui"
  export ALLNIGHTER_GUI_PROOF_DEBT_BASELINE="$WORK_DIR/.gui_proof_debt_baseline"
  unset ALLNIGHTER_GUI_PROOF_BASE ALLNIGHTER_GUI_PROOF_WAIVER
}

view_src() { # $1 = struct name -> SwiftUI View source
  cat <<EOF
struct $1: View {
    var body: some View { Text("$1") }
}
EOF
}

logic_src() { # $1 = type name -> non-view Swift source (not gated)
  cat <<EOF
struct $1 {
    func run() -> Int { 1 }
}
EOF
}

commit_all() {
  git -C "$WORK_DIR" add -A
  git -C "$WORK_DIR" commit -q -m "$1"
}

# ===========================================================================
# A. Pre-existing debt + a change touching NO view => gate does not block.
# ===========================================================================
test_a() {
  fresh_repo
  view_src ViewA > "$WORK_DIR/Sources/ViewA.swift"      # committed, never proven -> debt
  logic_src Logic > "$WORK_DIR/Sources/Logic.swift"
  commit_all "seed: ViewA (unproven), Logic"
  printf '1\n' > "$ALLNIGHTER_GUI_PROOF_DEBT_BASELINE"   # ceiling matches the 1 pre-existing debt

  # A change touching NO view: edit the non-view file only.
  printf 'struct Logic { func run() -> Int { 2 } }\n' > "$WORK_DIR/Sources/Logic.swift"

  out="$(bash "$CHECK_GUI_PROOF" 2>&1)"; rc=$?
  if [[ $rc -ne 0 ]]; then
    fail "A: gate blocked a change touching no view (rc=$rc):"$'\n'"$out"
    return
  fi
  if ! grep -q "no visible GUI surface in your diff" <<<"$out"; then
    fail "A: gate passed but didn't report 'no visible GUI surface in your diff':"$'\n'"$out"
    return
  fi
  if ! grep -q "1 view(s) repo-wide carry unproven content" <<<"$out"; then
    fail "A: pre-existing debt (ViewA) was not reported:"$'\n'"$out"
    return
  fi
  pass "A: pre-existing debt reported but did not block a change touching no view"
}

# ===========================================================================
# B. A change touching one view => only that view is required.
# ===========================================================================
test_b() {
  fresh_repo
  view_src ViewA > "$WORK_DIR/Sources/ViewA.swift"      # will stay unproven debt, untouched
  view_src ViewB > "$WORK_DIR/Sources/ViewB.swift"
  commit_all "seed: ViewA (unproven), ViewB"

  # Touch ONLY ViewB.
  view_src ViewB2Body > "$WORK_DIR/Sources/ViewB.swift"
  printf '2\n' > "$ALLNIGHTER_GUI_PROOF_DEBT_BASELINE"   # ceiling matches current total (ViewA + ViewB); isolates the per-diff selection check from the ratchet (covered separately by test_d)

  out="$(bash "$CHECK_GUI_PROOF" 2>&1)"; rc=$?
  if [[ $rc -eq 0 ]]; then
    fail "B: gate passed but ViewB.swift is genuinely unproven and touched:"$'\n'"$out"
    return
  fi
  block_section="$(sed -n '/YOUR diff changed without fresh proof/,/Old\/unrelated packets/p' <<<"$out")"
  if ! grep -q "ViewB.swift" <<<"$block_section"; then
    fail "B: blocking list didn't require ViewB.swift:"$'\n'"$out"
    return
  fi
  if grep -q "ViewA.swift" <<<"$block_section"; then
    fail "B: blocking list wrongly required untouched debt ViewA.swift:"$'\n'"$out"
    return
  fi
  pass "B: only the touched view (ViewB) was required; untouched debt (ViewA) did not block"
}

# ===========================================================================
# C. Sealing surface X does not mark unrelated unproven view Y as proven.
# ===========================================================================
test_c() {
  fresh_repo
  view_src ViewX > "$WORK_DIR/Sources/ViewX.swift"
  view_src ViewY > "$WORK_DIR/Sources/ViewY.swift"
  commit_all "seed: ViewX, ViewY (both unproven)"
  printf '2\n' > "$ALLNIGHTER_GUI_PROOF_DEBT_BASELINE"

  # Both change in the same working tree (only X gets reviewed/sealed).
  view_src ViewXEdited > "$WORK_DIR/Sources/ViewX.swift"
  view_src ViewYEdited > "$WORK_DIR/Sources/ViewY.swift"

  mkdir -p "$WORK_DIR/qa/gui/_captures"
  printf 'fake-png' > "$WORK_DIR/qa/gui/_captures/fixtureX.png"

  seal_out="$(bash "$GUI_PROOF_SEAL" surfaceX slug1 --fixtures fixtureX --views Sources/ViewX.swift 2>&1)"
  seal_rc=$?
  if [[ $seal_rc -ne 0 ]]; then
    fail "C: seal.sh failed unexpectedly (rc=$seal_rc):"$'\n'"$seal_out"
    return
  fi

  man="$(find "$WORK_DIR/qa/gui/surfaceX" -name proof.manifest | head -1)"
  if [[ -z "$man" ]]; then
    fail "C: no proof.manifest written by seal"
    return
  fi
  if grep -q "ViewY.swift" "$man"; then
    fail "C: proof.manifest for surfaceX wrongly bound ViewY.swift:"$'\n'"$(cat "$man")"
    return
  fi
  if ! grep -q "ViewX.swift" "$man"; then
    fail "C: proof.manifest for surfaceX is missing ViewX.swift:"$'\n'"$(cat "$man")"
    return
  fi
  if ! grep -q "ViewY.swift" "$WORK_DIR/qa/gui/DEBT.manifest" 2>/dev/null; then
    fail "C: ViewY.swift was not recorded into DEBT.manifest by the seal"
    return
  fi
  if ! grep -q "recorded as DEBT, not proven" <<<"$seal_out"; then
    fail "C: seal did not announce the collateral DEBT recording:"$'\n'"$seal_out"
    return
  fi

  # Now the gate: ViewX is proven (should not block); ViewY is still
  # genuinely unproven AND still in the diff, so it must still block.
  gate_out="$(bash "$CHECK_GUI_PROOF" 2>&1)"; gate_rc=$?
  if [[ $gate_rc -eq 0 ]]; then
    fail "C: gate passed after sealing X, but Y is unreviewed and still changed:"$'\n'"$gate_out"
    return
  fi
  block_section="$(sed -n '/YOUR diff changed without fresh proof/,/Old\/unrelated packets/p' <<<"$gate_out")"
  if grep -q "ViewX.swift" <<<"$block_section"; then
    fail "C: gate still required ViewX.swift even though it was just proven:"$'\n'"$gate_out"
    return
  fi
  if ! grep -q "ViewY.swift" <<<"$block_section"; then
    fail "C: gate did not require ViewY.swift, which was never reviewed:"$'\n'"$gate_out"
    return
  fi
  pass "C: sealing surfaceX proved only ViewX; ViewY was recorded as DEBT (never PASS) and still gates"
}

# ===========================================================================
# D. The ratchet rejects an increase — even with an empty diff.
# ===========================================================================
test_d() {
  fresh_repo
  logic_src Logic > "$WORK_DIR/Sources/Logic.swift"
  commit_all "seed: no views at all"
  printf '0\n' > "$ALLNIGHTER_GUI_PROOF_DEBT_BASELINE"

  out0="$(bash "$CHECK_GUI_PROOF" 2>&1)"; rc0=$?
  if [[ $rc0 -ne 0 ]]; then
    fail "D: gate should pass with zero debt at a zero ceiling (rc=$rc0):"$'\n'"$out0"
    return
  fi

  # Debt sneaks in via a direct commit (bypass) — never went through the
  # gate at all. Working tree is otherwise clean: "your diff" touches
  # nothing.
  view_src ViewSneaky > "$WORK_DIR/Sources/ViewSneaky.swift"
  commit_all "bypass: unproven view landed directly"

  if [[ -n "$(git -C "$WORK_DIR" status --porcelain)" ]]; then
    fail "D: setup error — working tree should be clean (all committed) for this scenario"
    return
  fi

  out1="$(bash "$CHECK_GUI_PROOF" 2>&1)"; rc1=$?
  if [[ $rc1 -eq 0 ]]; then
    fail "D: ratchet did not fire on a debt increase (rc=0):"$'\n'"$out1"
    return
  fi
  if ! grep -q "RATCHET FAILED" <<<"$out1"; then
    fail "D: gate failed but not via the ratchet message:"$'\n'"$out1"
    return
  fi
  pass "D: ratchet rejected the debt increase (0 -> 1) even though the working diff was empty"
}

# ===========================================================================
# Structural: §D "tests after the gate, not before" wiring.
# ===========================================================================
test_wiring() {
  if grep -q "bash \"\$ROOT/scripts/check_gui_proof.sh\"" "$REPO_ROOT/scripts/check-fast.sh"; then
    fail "wiring: check-fast.sh still calls check_gui_proof.sh directly (would hard-stop before tests)"
    return
  fi
  fast_line="$(grep -n 'check_gui_proof.sh' "$REPO_ROOT/scripts/check.sh" | head -1 | cut -d: -f1)"
  mac_test_line="$(grep -n 'xcodebuild test' "$REPO_ROOT/scripts/check.sh" | head -1 | cut -d: -f1)"
  swift_test_line="$(grep -n 'swift-test.sh"$' "$REPO_ROOT/scripts/check.sh" | head -1 | cut -d: -f1)"
  if [[ -z "$fast_line" ]]; then
    fail "wiring: check.sh no longer calls check_gui_proof.sh"
    return
  fi
  if [[ -n "$swift_test_line" && "$fast_line" -lt "$swift_test_line" ]]; then
    fail "wiring: check_gui_proof.sh (line $fast_line) runs before swift-test.sh (line $swift_test_line)"
    return
  fi
  if [[ -n "$mac_test_line" && "$fast_line" -lt "$mac_test_line" ]]; then
    fail "wiring: check_gui_proof.sh (line $fast_line) runs before xcodebuild test (line $mac_test_line)"
    return
  fi
  if ! grep -q 'gui_proof_status=0' "$REPO_ROOT/scripts/check.sh" || ! grep -q '|| gui_proof_status=\$?' "$REPO_ROOT/scripts/check.sh"; then
    fail "wiring: check.sh does not capture the gate's exit code non-fatally"
    return
  fi

  # Behavioral: prove the actual bash pattern used in check.sh — a failing
  # gate must not stop a later phase from running under set -euo pipefail.
  sim_dir="$(mktemp -d "${TMPDIR:-/tmp}/alln-gui-proof-sim.XXXXXX")"
  cat > "$sim_dir/failing_gate.sh" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
  chmod +x "$sim_dir/failing_gate.sh"
  cat > "$sim_dir/sim_check.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
echo "swift-test-phase-ran" > "$sim_dir/swift_test.marker"
gui_proof_status=0
bash "$sim_dir/failing_gate.sh" || gui_proof_status=\$?
echo "reached-end-of-script"
if [[ "\$gui_proof_status" -ne 0 ]]; then
  exit "\$gui_proof_status"
fi
EOF
  sim_out="$(bash "$sim_dir/sim_check.sh" 2>&1)"; sim_rc=$?
  rm -rf "$sim_dir" 2>/dev/null
  if [[ $sim_rc -eq 0 ]]; then
    fail "wiring sim: overall script should still fail when the gate fails"
    return
  fi
  if ! grep -q "reached-end-of-script" <<<"$sim_out"; then
    fail "wiring sim: script aborted before reaching the end — a failing gate is still hard-stopping later phases"
    return
  fi
  pass "wiring: gate runs after swift-test/xcodebuild in check.sh, captured non-fatally, wall still fails at the end"
}

test_a
test_b
test_c
test_d
test_wiring

echo ""
if [[ "$FAILURES" -eq 0 ]]; then
  echo "works-test-gui-proof: ALL PASS"
  exit 0
else
  echo "works-test-gui-proof: $FAILURES FAILURE(S)"
  exit 1
fi
