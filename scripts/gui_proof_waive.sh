#!/usr/bin/env bash
# GUI Visual Proof Gate — waive a NON-VISIBLE change to a view file.
#
# Use only when a file the gate treats as a view changed but the change renders
# nothing different (a comment, a rename, a pure-logic refactor). Binds the
# waiver to the file's current content hash, so any later visible edit
# invalidates it and re-requires real proof.
#
# Usage:
#   bash scripts/gui_proof_waive.sh "<reason>" <file>...
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

[ "$#" -ge 2 ] || { echo 'usage: gui_proof_waive.sh "<reason>" <file>...' >&2; exit 2; }
reason="$1"; shift
[ -n "$reason" ] || { echo "waive: reason must be non-empty" >&2; exit 2; }

PACKET_ROOT="docs/qa/gui"
man="$PACKET_ROOT/WAIVERS.manifest"
mkdir -p "$PACKET_ROOT"
[ -f "$man" ] || printf '# GUI proof waivers — non-visible changes to view files.\n# <hash>  <path>  # <reason> (<date>)\n' > "$man"

DATE="$(date +%F)"
for f in "$@"; do
  [ -f "$f" ] || { echo "waive: no such file: $f" >&2; exit 1; }
  h="$(git hash-object "$f")"
  printf '%s  %s  # %s (%s)\n' "$h" "$f" "$reason" "$DATE" >> "$man"
  echo "waived: $f ($h)"
done
echo "recorded in $man"
