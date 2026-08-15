#!/usr/bin/env bash
# GUI Visual Proof Gate — wall enforcement.
#
# BLOCKS ON THE DIFF, REPORTS THE REPO (docs/gui/Visual_Proof_Gate.md §A):
# only a visible view YOUR diff changed can gate YOUR closeout. Diff is
# "working tree vs BASE" — default BASE is HEAD, i.e. your own uncommitted
# edits (staged, unstaged, and untracked). CI has no uncommitted state, so it
# must set ALLNIGHTER_GUI_PROOF_BASE to the PR's merge base (e.g.
# origin/main) to get full-PR scope. Pre-existing repo-wide debt (any visible
# view whose CURRENT content isn't covered by a proof/waiver, regardless of
# whether it is in your diff) is always printed loudly — names + count — but
# never blocks a change that does not touch it. "If you work on NO gui
# surface you should not even need to run the GUI proof at all."
#
# RATCHET (§B): repo-wide debt is also compared to a persisted ceiling
# (scripts/.gui_proof_debt_baseline). The count may go DOWN (proving/waiving
# views) but never UP — if it does, the wall fails even though the failing
# diff may not be yours; that is the point, it means debt was smuggled in
# without going through this gate (bypass, force-push, manual manifest edit).
# scripts/gui_proof_seal.sh tightens the ceiling automatically when sealing
# reduces total debt. Nothing here ever raises it — only an explicit,
# reviewed edit to that file does.
#
# Proof is bound to file CONTENT, not to "a packet exists" or "since some
# fixed baseline". Each view in scope must have its CURRENT git blob hash
# recorded in a proof packet (`docs/qa/gui/<surface>/<date>-<slug>/proof.manifest`,
# watcher PASS) or in `docs/qa/gui/WAIVERS.manifest`. Re-editing a view
# changes its hash, so old proof goes stale automatically, and a
# Team-dropdown packet can never satisfy a Composer change.
#
# It enforces that proof was produced for THIS content — not that the pixels
# are correct. The separate layout-watcher PASS is the real check; this makes
# producing one, for the actual change, non-optional.
#
# Config:
#   ALLNIGHTER_GUI_PROOF_BASE     diff base (default: HEAD — your own
#                                  uncommitted changes). CI: set to the PR
#                                  base, e.g. origin/main, for full-PR scope.
#   ALLNIGHTER_GUI_PROOF_WAIVER   deliberate one-shot bypass (non-empty reason)
#   ALLNIGHTER_GUI_PROOF_ROOT     override repo root (works-tests only)
#   ALLNIGHTER_GUI_PROOF_SRC_DIR  override the gated source dir (works-tests only)
#   ALLNIGHTER_GUI_PROOF_PACKET_ROOT   override the proof packet root (works-tests only)
#   ALLNIGHTER_GUI_PROOF_DEBT_BASELINE override the ratchet ceiling file (works-tests only)
set -euo pipefail
ROOT="${ALLNIGHTER_GUI_PROOF_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

SRC_DIR="${ALLNIGHTER_GUI_PROOF_SRC_DIR:-Apps/AllnighterMac/Sources}"
PACKET_ROOT="${ALLNIGHTER_GUI_PROOF_PACKET_ROOT:-docs/qa/gui}"
DEBT_BASELINE_FILE="${ALLNIGHTER_GUI_PROOF_DEBT_BASELINE:-$ROOT/scripts/.gui_proof_debt_baseline}"

if [ -n "${ALLNIGHTER_GUI_PROOF_WAIVER:-}" ]; then
  echo "check-gui-proof: waived — ${ALLNIGHTER_GUI_PROOF_WAIVER}"
  exit 0
fi

if ! command -v git >/dev/null 2>&1 || ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "check-gui-proof: no git context — skipping"
  exit 0
fi

BASE="${ALLNIGHTER_GUI_PROOF_BASE:-HEAD}"
if [ "$BASE" != "HEAD" ] && ! git rev-parse --verify --quiet "${BASE}^{commit}" >/dev/null; then
  echo "check-gui-proof: ALLNIGHTER_GUI_PROOF_BASE='$BASE' is not a valid ref — skipping" >&2
  exit 0
fi

# Is this file a visible SwiftUI surface (vs pure logic/model/presenter)?
is_view() { grep -qE ':[[:space:]]*View\b|some View\b|:[[:space:]]*App\b|PreviewProvider' "$1"; }

# Files that differ between BASE and the working tree under a dir — THIS IS
# YOUR DIFF: committed-since-BASE, uncommitted-modified, and untracked (so a
# brand-new view counts).
changed_under() {
  { git diff --name-only "$BASE" -- "$1" 2>/dev/null || true
    git ls-files --others --exclude-standard -- "$1" 2>/dev/null || true
  } | sort -u
}

# Every visible view currently in the tree — repo-wide, independent of any
# diff or baseline. This is the debt report + ratchet's source of truth.
all_views_under() {
  find "$1" -name '*.swift' 2>/dev/null | sort | while IFS= read -r f; do
    [ -f "$f" ] || continue
    is_view "$f" && printf '%s\n' "$f"
  done
}

# Coverage = "<hash> <path>" pairs from every proof.manifest that carries a
# watcher PASS, plus WAIVERS.manifest. Comment lines (#...) are ignored.
TMP_ROOT="${ALLNIGHTER_TMPDIR:-/tmp}"
COVER="$(mktemp "$TMP_ROOT/alln-gui-proof.XXXXXX")"
DEBT_LIST="$(mktemp "$TMP_ROOT/alln-gui-debt.XXXXXX")"
trap 'rm -f "$COVER" "$DEBT_LIST"' EXIT
while IFS= read -r m; do
  [ -n "$m" ] || continue
  grep -qiE '^#[[:space:]]*watcher:[[:space:]]*PASS\b' "$m" || continue
  grep -vE '^[[:space:]]*#' "$m" | awk 'NF>=2 {print $1, $2}' >> "$COVER"
done < <(find "$PACKET_ROOT" -name proof.manifest 2>/dev/null || true)
if [ -f "$PACKET_ROOT/WAIVERS.manifest" ]; then
  grep -vE '^[[:space:]]*#' "$PACKET_ROOT/WAIVERS.manifest" | awk 'NF>=2 {print $1, $2}' >> "$COVER"
fi
is_covered() {
  awk -v h="$1" -v f="$2" '($1==h && $2==f){ok=1} END{exit ok?0:1}' "$COVER"
}

# --- Repo-wide debt scan: report + ratchet input. NOT diff-scoped. ---------
debt_count=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  h="$(git hash-object "$f")"
  if ! is_covered "$h" "$f"; then
    printf '%s  %s\n' "$h" "$f" >> "$DEBT_LIST"
    debt_count=$((debt_count + 1))
  fi
done < <(all_views_under "$SRC_DIR")

if [ "$debt_count" -gt 0 ]; then
  echo "check-gui-proof: ${debt_count} view(s) repo-wide carry unproven content:"
  sed 's/^/    /' "$DEBT_LIST"
  echo "    (reported, not blocking — unless your diff touches one of them, see below)"
fi

# --- Ratchet: repo-wide debt may never exceed the persisted ceiling. -------
ceiling=""
if [ -f "$DEBT_BASELINE_FILE" ]; then
  ceiling="$(tr -dc '0-9' < "$DEBT_BASELINE_FILE")"
fi
if [ -z "$ceiling" ]; then
  echo "check-gui-proof: no ratchet ceiling at $DEBT_BASELINE_FILE — treating current count (${debt_count}) as the ceiling this run." >&2
  echo "    Create it (a single integer) and commit it so the ratchet has a real floor:" >&2
  echo "    printf '%s\n' ${debt_count} > $DEBT_BASELINE_FILE" >&2
  ceiling="$debt_count"
fi
if [ "$debt_count" -gt "$ceiling" ]; then
  echo "✗ check-gui-proof: RATCHET FAILED — repo-wide unproven-view count is ${debt_count}, ceiling is ${ceiling}." >&2
  echo "  Debt may only go down, never up. New/newly-invalidated views must be" >&2
  echo "  proven or waived before anyone's wall can pass again. See the debt list" >&2
  echo "  above and docs/gui/Visual_Proof_Gate.md §Ratchet." >&2
  exit 1
elif [ "$debt_count" -lt "$ceiling" ]; then
  echo "check-gui-proof: debt count ${debt_count} is below ceiling ${ceiling} — tighten $DEBT_BASELINE_FILE (scripts/gui_proof_seal.sh does this automatically on seal)."
fi

# --- Diff-scoped block: ONLY views your diff touches can fail this run. ----
uncovered=()
visible=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  case "$f" in *.swift) ;; *) continue ;; esac
  [ -f "$f" ] || continue   # deleted: nothing to render
  is_view "$f" || continue  # pure logic: not gated
  visible=$((visible + 1))
  h="$(git hash-object "$f")"
  is_covered "$h" "$f" || uncovered+=("$f")
done < <(changed_under "$SRC_DIR")

if [ "$visible" -eq 0 ]; then
  echo "check-gui-proof: no visible GUI surface in your diff (base=${BASE}) — ok"
  exit 0
fi
if [ "${#uncovered[@]}" -eq 0 ]; then
  echo "check-gui-proof: $visible visible view(s) in your diff; all proven or waived — ok"
  exit 0
fi

echo "✗ check-gui-proof: visible view(s) in YOUR diff changed without fresh proof for their CURRENT content:" >&2
for f in "${uncovered[@]}"; do echo "    - $f" >&2; done
cat >&2 <<EOF
  Old/unrelated packets do not count — proof is bound to each file's content hash.
  Resolve, for the surface(s) these views render:
    1. Render the impacted state(s), look, then seal:
         bash scripts/gui_proof.sh <fixture>           # one per affected state
         # spawn .claude/agents/layout-watcher.md on the PNG(s); require PASS (no P1)
         bash scripts/gui_proof_seal.sh <surface> <slug> --fixtures <fixture>... --views <file>...
         # then paste the watcher verdict into the packet's watcher.md
    2. Non-visible view change (comment/refactor with no visual effect):
         bash scripts/gui_proof_waive.sh "<reason>" <file>...
    3. One-shot local override (states a reason; CI cannot use it):
         ALLNIGHTER_GUI_PROOF_WAIVER="<reason>" bash scripts/check.sh
  See docs/gui/Visual_Proof_Gate.md.
EOF
exit 1
