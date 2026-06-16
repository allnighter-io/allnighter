#!/usr/bin/env bash
# GUI Visual Proof Gate — seal a proof packet (run AFTER a layout-watcher PASS).
#
# Binds the CURRENT content of every changed visible view to this packet via git
# blob hashes, so the wall (scripts/check_gui_proof.sh) accepts the change. Run
# this only after rendering the impacted surface(s) and getting a watcher PASS —
# it records "watcher: PASS" as your attestation for this exact content.
#
# Usage:
#   bash scripts/gui_proof_seal.sh <surface> <slug> <fixture> [<fixture>...]
# Example:
#   bash scripts/gui_proof_seal.sh team-dropdown anchor-refactor team-open-mixed
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

[ "$#" -ge 3 ] || { echo "usage: gui_proof_seal.sh <surface> <slug> <fixture> [<fixture>...]" >&2; exit 2; }
surface="$1"; slug="$2"; shift 2; fixtures=("$@")

SRC_DIR="Apps/AllnighterMac/Sources"
PACKET_ROOT="docs/qa/gui"
DATE="$(date +%F)"
pkt="$PACKET_ROOT/$surface/$DATE-$slug"
mkdir -p "$pkt"

# Copy the rendered capture(s) into the packet.
single=$([ "${#fixtures[@]}" -eq 1 ] && echo 1 || echo 0)
for fx in "${fixtures[@]}"; do
  src="$PACKET_ROOT/_captures/$fx.png"
  [ -s "$src" ] || { echo "seal: missing capture $src — run: bash scripts/gui_proof.sh $fx" >&2; exit 1; }
  dest=$([ "$single" -eq 1 ] && echo "$pkt/native.png" || echo "$pkt/native-$fx.png")
  cp "$src" "$dest"
done

# Resolve the changed visible views the same way the gate does.
BASE="${ALLNIGHTER_GUI_PROOF_BASE:-$(cat "$ROOT/scripts/.gui_proof_baseline" 2>/dev/null || true)}"
is_view() { grep -qE ':[[:space:]]*View\b|some View\b|:[[:space:]]*App\b|PreviewProvider' "$1"; }
changed_views() {
  { git diff --name-only "$BASE" -- "$SRC_DIR" 2>/dev/null || true
    git ls-files --others --exclude-standard -- "$SRC_DIR" 2>/dev/null || true
  } | sort -u | while IFS= read -r f; do
      case "$f" in *.swift) ;; *) continue ;; esac
      [ -f "$f" ] && is_view "$f" && echo "$f"
    done
}

man="$pkt/proof.manifest"
{
  echo "# surface: $surface"
  echo "# fixtures: ${fixtures[*]}"
  echo "# watcher: PASS"
  echo "# sealed: $DATE"
  echo "# Binds each proven view to its exact content hash. Re-editing any view"
  echo "# changes its hash and invalidates this proof — re-render and re-seal."
  count=0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    echo "$(git hash-object "$f")  $f"
    count=$((count + 1))
  done < <(changed_views)
} > "$man"

if ! grep -qvE '^[[:space:]]*#' "$man"; then
  echo "seal: no changed visible views found to bind — nothing to prove." >&2
  rm -f "$man"; exit 1
fi

# Watcher verdict stub (agent must fill with the real verdict).
if [ ! -f "$pkt/watcher.md" ]; then
  cat > "$pkt/watcher.md" <<EOF
# $surface — layout-watcher verdict

Fixtures: ${fixtures[*]}
Command: bash scripts/gui_proof.sh ${fixtures[0]}

## VERDICT: PASS  (replace with the actual layout-watcher output)

P1 — broken (blocks): none
P2 — advisory:
- (none)
EOF
fi

echo "sealed $pkt"
echo "  fixtures: ${fixtures[*]}"
echo "  bound views:"
grep -vE '^[[:space:]]*#' "$man" | sed 's/^/    /'
echo "NEXT: paste the layout-watcher's actual verdict into $pkt/watcher.md"
