#!/usr/bin/env bash
# GUI Visual Proof Gate — wall enforcement (S05).
#
# Fails when a visible SwiftUI surface changed without FRESH, SURFACE-BOUND proof.
#
# Proof is bound to file CONTENT, not to "any packet since the baseline". Each
# changed visible view must have its CURRENT git blob hash recorded in a proof
# packet (`docs/qa/gui/<surface>/<date>-<slug>/proof.manifest`, watcher PASS) or
# in `docs/qa/gui/WAIVERS.manifest`. Re-editing a view changes its hash, so old
# proof goes stale automatically; and a Team-dropdown packet can never satisfy a
# Composer change because it does not carry Composer's hash. That closes the
# stale/unrelated-proof loophole.
#
# It enforces that proof was produced for THIS content — not that the pixels are
# correct. The separate layout-watcher PASS is the real check; this makes
# producing one, for the actual change, non-optional.
#
# Scope is grandfathered to a BASELINE commit so the gate does not retroactively
# flag GUI work that predates it.
#
# Config:
#   ALLNIGHTER_GUI_PROOF_BASE    override baseline rev (CI may set origin/main)
#   ALLNIGHTER_GUI_PROOF_WAIVER  deliberate one-shot bypass (non-empty reason)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SRC_DIR="Apps/AllnighterMac/Sources"
PACKET_ROOT="docs/qa/gui"

if [ -n "${ALLNIGHTER_GUI_PROOF_WAIVER:-}" ]; then
  echo "check-gui-proof: waived — ${ALLNIGHTER_GUI_PROOF_WAIVER}"
  exit 0
fi

if ! command -v git >/dev/null 2>&1 || ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "check-gui-proof: no git context — skipping"
  exit 0
fi

BASE="${ALLNIGHTER_GUI_PROOF_BASE:-$(cat "$ROOT/scripts/.gui_proof_baseline" 2>/dev/null || true)}"
if [ -z "$BASE" ] || ! git rev-parse --verify --quiet "${BASE}^{commit}" >/dev/null; then
  echo "check-gui-proof: no valid baseline (scripts/.gui_proof_baseline) — skipping"
  exit 0
fi

# Is this file a visible SwiftUI surface (vs pure logic/model/presenter)?
is_view() { grep -qE ':[[:space:]]*View\b|some View\b|:[[:space:]]*App\b|PreviewProvider' "$1"; }

# Files changed since baseline under a dir: committed-since-baseline,
# uncommitted-modified, and untracked (so a new packet/view counts).
changed_under() {
  { git diff --name-only "$BASE" -- "$1" 2>/dev/null || true
    git ls-files --others --exclude-standard -- "$1" 2>/dev/null || true
  } | sort -u
}

# Coverage = "<hash> <path>" pairs from every proof.manifest that carries a
# watcher PASS, plus WAIVERS.manifest. Comment lines (#...) are ignored.
TMP_ROOT="${ALLNIGHTER_TMPDIR:-/tmp}"
COVER="$(mktemp "$TMP_ROOT/alln-gui-proof.XXXXXX")"; trap 'rm -f "$COVER"' EXIT
while IFS= read -r m; do
  [ -n "$m" ] || continue
  grep -qiE '^#[[:space:]]*watcher:[[:space:]]*PASS\b' "$m" || continue
  grep -vE '^[[:space:]]*#' "$m" | awk 'NF>=2 {print $1, $2}' >> "$COVER"
done < <(find "$PACKET_ROOT" -name proof.manifest 2>/dev/null || true)
if [ -f "$PACKET_ROOT/WAIVERS.manifest" ]; then
  grep -vE '^[[:space:]]*#' "$PACKET_ROOT/WAIVERS.manifest" | awk 'NF>=2 {print $1, $2}' >> "$COVER"
fi

# Pre-existing unproven views, frozen at a specific content hash and attributed
# to the commit that left them unproven. These are DEBT, not proof: they are
# reported every run but do not block an unrelated change.
#
# This exists because the gate's scope is cumulative — "changed since baseline" —
# so one unproven refactor blocked EVERY later closeout by everyone, including
# doc-only ones. Attribution fixes that without weakening the gate: entries are
# hash-bound, so the moment anyone edits a debt file its hash changes, it drops
# out of this list automatically, and it blocks again. Debt cannot hide new work.
DEBT="$(mktemp "$TMP_ROOT/alln-gui-debt.XXXXXX")"; trap 'rm -f "$COVER" "$DEBT"' EXIT
if [ -f "$PACKET_ROOT/DEBT.manifest" ]; then
  grep -vE '^[[:space:]]*#' "$PACKET_ROOT/DEBT.manifest" | awk 'NF>=2 {print $1, $2}' >> "$DEBT"
fi

uncovered=()
debt=()
visible=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  case "$f" in *.swift) ;; *) continue ;; esac
  [ -f "$f" ] || continue   # deleted: nothing to render
  is_view "$f" || continue  # pure logic: not gated
  visible=$((visible + 1))
  h="$(git hash-object "$f")"
  if ! awk -v h="$h" -v f="$f" '($1==h && $2==f){ok=1} END{exit ok?0:1}' "$COVER"; then
    if awk -v h="$h" -v f="$f" '($1==h && $2==f){ok=1} END{exit ok?0:1}' "$DEBT"; then
      debt+=("$f")
    else
      uncovered+=("$f")
    fi
  fi
done < <(changed_under "$SRC_DIR")

if [ "$visible" -eq 0 ]; then
  echo "check-gui-proof: no visible GUI surface changed since baseline — ok"
  exit 0
fi
if [ "${#debt[@]}" -gt 0 ]; then
  echo "check-gui-proof: ${#debt[@]} view(s) carry PRE-EXISTING proof debt (docs/qa/gui/DEBT.manifest)."
  echo "    Not blocking this run. Editing any of them re-requires real proof."
fi
if [ "${#uncovered[@]}" -eq 0 ]; then
  echo "check-gui-proof: $visible visible view(s) changed; all proven, waived, or recorded debt — ok"
  exit 0
fi

echo "✗ check-gui-proof: visible view(s) changed without fresh proof for their CURRENT content:" >&2
for f in "${uncovered[@]}"; do echo "    - $f" >&2; done
cat >&2 <<EOF
  Old/unrelated packets do not count — proof is bound to each file's content hash.
  Resolve, for the surface(s) these views render:
    1. Render the impacted state(s), look, then seal:
         bash scripts/gui_proof.sh <fixture>           # one per affected state
         # spawn .claude/agents/layout-watcher.md on the PNG(s); require PASS (no P1)
         bash scripts/gui_proof_seal.sh <surface> <slug> <fixture> [<fixture>...]
         # then paste the watcher verdict into the packet's watcher.md
    2. Non-visible view change (comment/refactor with no visual effect):
         bash scripts/gui_proof_waive.sh "<reason>" <file>...
    3. One-shot local override (states a reason; CI cannot use it):
         ALLNIGHTER_GUI_PROOF_WAIVER="<reason>" bash scripts/check.sh
  See docs/gui/Visual_Proof_Gate.md.
EOF
exit 1
