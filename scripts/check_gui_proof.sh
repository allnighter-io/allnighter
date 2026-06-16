#!/usr/bin/env bash
# GUI Visual Proof Gate — wall enforcement (S05).
#
# Fails when a visible SwiftUI surface changed without a proof packet or an
# explicit waiver. It does NOT verify the layout-watcher's verdict (a script
# cannot judge pixels) — it enforces that the evidence ritual happened, so an
# agent cannot silently skip the gate. The watcher PASS is the real check; this
# makes producing one non-optional.
#
# Scope is grandfathered to a BASELINE commit so introducing the gate does not
# retroactively flag GUI work that predates it. Only changes AFTER the baseline
# are enforced.
#
# Pass when:
#   - no visible View file changed since the baseline; or
#   - a proof packet under docs/qa/gui/<surface>/... changed/was added; or
#   - a since-baseline commit carries a `GUI-proof-waiver: <reason>` trailer; or
#   - ALLNIGHTER_GUI_PROOF_WAIVER="<reason>" is set (deliberate local override).
#
# Config:
#   ALLNIGHTER_GUI_PROOF_BASE    override the baseline rev (CI may set origin/main)
#   ALLNIGHTER_GUI_PROOF_WAIVER  one-shot waiver reason (must be non-empty)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SRC_DIR="Apps/AllnighterMac/Sources"
PACKET_ROOT="docs/qa/gui"

# Deliberate one-shot override (CI never sets this).
if [ -n "${ALLNIGHTER_GUI_PROOF_WAIVER:-}" ]; then
  echo "check-gui-proof: waived — ${ALLNIGHTER_GUI_PROOF_WAIVER}"
  exit 0
fi

# Not a git repo / git unavailable → cannot scope a diff; do not block.
if ! command -v git >/dev/null 2>&1 || ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "check-gui-proof: no git context — skipping"
  exit 0
fi

BASE="${ALLNIGHTER_GUI_PROOF_BASE:-$(cat "$ROOT/scripts/.gui_proof_baseline" 2>/dev/null || true)}"
if [ -z "$BASE" ] || ! git rev-parse --verify --quiet "${BASE}^{commit}" >/dev/null; then
  echo "check-gui-proof: no valid baseline (scripts/.gui_proof_baseline) — skipping"
  exit 0
fi

# All paths changed since the baseline under a dir: committed-since-baseline,
# uncommitted-modified, AND untracked (so a brand-new packet/view counts).
changed_under() {
  { git diff --name-only "$BASE" -- "$1" 2>/dev/null || true
    git ls-files --others --exclude-standard -- "$1" 2>/dev/null || true
  } | sort -u
}

# Visible GUI = changed Swift files under Sources that declare a SwiftUI surface.
# Logic/model/presenter files (no `View`/`App` conformance) are not gated.
visible=()
while IFS= read -r f; do
  [ -z "$f" ] && continue
  case "$f" in *.swift) ;; *) continue ;; esac
  [ -f "$f" ] || continue   # deleted file: nothing to render
  if grep -qE ':[[:space:]]*View\b|some View\b|:[[:space:]]*App\b|PreviewProvider' "$f"; then
    visible+=("$f")
  fi
done < <(changed_under "$SRC_DIR")

if [ "${#visible[@]}" -eq 0 ]; then
  echo "check-gui-proof: no visible GUI surface changed since baseline — ok"
  exit 0
fi

# Proof packet present? Any change under docs/qa/gui/ that is a real packet
# (not the transient _captures/ dir and not the top-level README).
packet_found=false
while IFS= read -r p; do
  [ -z "$p" ] && continue
  case "$p" in
    "$PACKET_ROOT"/_captures/*) continue ;;
    "$PACKET_ROOT"/README.md)   continue ;;
    "$PACKET_ROOT"/*/*)         packet_found=true; break ;;
  esac
done < <(changed_under "$PACKET_ROOT")

# Waiver trailer in any commit since baseline (only if baseline is an ancestor).
waiver_found=false
if git merge-base --is-ancestor "$BASE" HEAD 2>/dev/null; then
  if git log "$BASE"..HEAD --format='%B' 2>/dev/null | grep -qiE '^GUI-proof-waiver:[[:space:]]*\S'; then
    waiver_found=true
  fi
fi

if $packet_found || $waiver_found; then
  why=$($packet_found && echo "proof packet present" || echo "waiver trailer present")
  echo "check-gui-proof: visible GUI change with $why — ok"
  exit 0
fi

echo "✗ check-gui-proof: visible GUI surface changed without a proof packet or waiver." >&2
echo "  Changed visible views (since $BASE):" >&2
for f in "${visible[@]}"; do echo "    - $f" >&2; done
cat >&2 <<EOF
  Resolve one of:
    1. Render + look, then commit a packet under $PACKET_ROOT/<surface>/<date>-<slug>/:
         bash scripts/gui_proof.sh <fixture>
         # spawn .claude/agents/layout-watcher.md on the PNG; it must PASS (no P1)
         # save native.png + watcher.md into the packet dir
    2. Waive a non-visible change with a commit trailer:
         GUI-proof-waiver: <why this change renders nothing / is pure logic>
    3. One-shot local override (states a reason; CI cannot use it):
         ALLNIGHTER_GUI_PROOF_WAIVER="<reason>" bash scripts/check.sh
  See docs/phases/GUI_Visual_Proof_Gate.md.
EOF
exit 1
