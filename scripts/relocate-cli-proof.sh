#!/usr/bin/env bash
# Prove a relocated `alln` actually runs. The 1.1.5–1.1.8 production outage
# shipped because `build-universal.sh` ran `version` on the builder, where
# SPM's hardcoded fallback still found AgentOS_AgentOSCLI.bundle in the
# original scratch path. That check is a lie on any other machine.
#
# This gate:
#   1. Requires the two SPM resource bundles next to the binary.
#   2. Copies binary + bundles into a fresh temp dir.
#   3. Hides every copy of those bundles under known build scratches so the
#      compile-time fallback cannot save the run.
#   4. `cd "$HOME"` then execs `version` from the temp copy.
#
# Usage:
#   scripts/relocate-cli-proof.sh <binary>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

die() { echo "relocate-cli-proof: $*" >&2; exit 1; }

[[ $# -eq 1 ]] || die "usage: scripts/relocate-cli-proof.sh <binary>"
BINARY="$1"
[[ -x "$BINARY" ]] || die "not executable: $BINARY"

REQUIRED=(AgentOS_AgentOSCLI.bundle AllnighterCore_AllnighterCore.bundle)
SRC_DIR="$(cd "$(dirname "$BINARY")" && pwd)"
for name in "${REQUIRED[@]}"; do
  [[ -d "$SRC_DIR/$name" ]] || die "missing $name next to $BINARY — a relocated CLI will crash on launch"
done

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/alln-reloc.XXXXXX")"
ASIDE="$(mktemp -d "${TMPDIR:-/tmp}/alln-reloc-aside.XXXXXX")"
RESTORE_MAP="$ASIDE/restore.tsv"
: >"$RESTORE_MAP"

restore_hidden() {
  if [[ -f "$RESTORE_MAP" ]]; then
    while IFS=$'\t' read -r aside original; do
      [[ -n "$aside" && -n "$original" ]] || continue
      rm -rf "$original"
      mkdir -p "$(dirname "$original")"
      mv "$aside" "$original" 2>/dev/null || true
    done <"$RESTORE_MAP"
  fi
  rm -rf "$STAGE" "$ASIDE"
}

trap restore_hidden EXIT INT HUP TERM

cp "$BINARY" "$STAGE/alln"
chmod 755 "$STAGE/alln"
for name in "${REQUIRED[@]}"; do
  cp -R "$SRC_DIR/$name" "$STAGE/$name"
done

hide_root() {
  local root="$1"
  [[ -d "$root" ]] || return 0
  local path
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    local id aside
    id="$(printf '%s' "$path" | shasum -a 256 | awk '{print $1}')"
    aside="$ASIDE/$id"
    mv "$path" "$aside"
    printf '%s\t%s\n' "$aside" "$path" >>"$RESTORE_MAP"
  done < <(find "$root" \( -name 'AgentOS_AgentOSCLI.bundle' -o -name 'AllnighterCore_AllnighterCore.bundle' \) -prune -print 2>/dev/null || true)
}

hide_root "$ROOT/dist/.build-universal"
hide_root "${ALLNIGHTER_CLI_SCRATCH:-$HOME/Library/Developer/Allnighter/CLI}"
hide_root "$HOME/Library/Developer/Allnighter/Build"

# Do not hide $SRC_DIR — the proof runs from $STAGE. Build scratches are the lie.

if ! ( cd "$HOME" && "$STAGE/alln" version </dev/null >/dev/null ); then
  echo "relocate-cli-proof: relocated binary failed \`version\` (build-path fallback was hidden)" >&2
  echo "  staged: $STAGE/alln" >&2
  ( cd "$HOME" && "$STAGE/alln" version </dev/null ) 2>&1 | sed 's/^/  | /' >&2 || true
  exit 1
fi

echo "relocate-cli-proof: OK — $BINARY runs after relocate with build bundles hidden"
