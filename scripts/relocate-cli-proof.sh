#!/usr/bin/env bash
# Prove a relocated `alln` actually runs. The 1.1.5–1.1.8 production outage
# shipped because `build-universal.sh` ran `version` on the builder, where
# SPM's hardcoded fallback still found AgentOS_AgentOSCLI.bundle in the
# original scratch path. That check is a lie on any other machine.
# 1.1.10's relocate-proof still ran `version`, which never loads the catalog
# (`alln serve` does). 1.1.11 ran `menu --json` by absolute path — a false
# green. PATH invocation sets argv[0] to the bare name `alln`; after
# adoptNeutral chdirs, argv[0] lookup misses the sidecars and SIGTRAPs.
# This gate runs `menu --json` as a bare name on PATH from a different cwd.
#
# This gate:
#   1. Requires the two SPM resource bundles next to the binary.
#   2. Refuses a binary that bakes a protected-folder `.bundle` path or a
#      hardcoded `/Documents/GitHub/{AgentOS,Allnighter}` allow-root.
#      Bare `Documents` is too broad (DWARF `#filePath`, folder-name arrays).
#   3. Copies binary + bundles into a fresh temp dir.
#   4. Hides every copy of those bundles under known build scratches so the
#      compile-time fallback cannot save the run.
#   5. `cd "$HOME"` then execs bare `alln menu --json` with PATH=$STAGE
#      (catalog load the way users invoke).
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

# Compile-time resource-bundle fallback and hardcoded GitHub allow-roots.
# Bare `Documents` is too broad (`protectedHomeFolders`, DWARF `#filePath`).
# The TCC landmine is an absolute `.bundle` path under a protected folder, or
# the literal `/Documents/GitHub/AgentOS` / `.../Allnighter` allow-root.
# Run `strings` once — a 70MB Mach-O scanned four times looks wedged.
STRINGS_DUMP="$(mktemp "${TMPDIR:-/tmp}/alln-strings.XXXXXX")"
strings "$BINARY" >"$STRINGS_DUMP"
if grep -E '/Users/[^/]+/(Documents|Desktop|Downloads)/[^[:space:]]+\.bundle' "$STRINGS_DUMP" >/dev/null; then
  echo "relocate-cli-proof: baked protected-folder .bundle path:" >&2
  grep -E '/Users/[^/]+/(Documents|Desktop|Downloads)/[^[:space:]]+\.bundle' "$STRINGS_DUMP" | sed 's/^/  | /' >&2
  rm -f "$STRINGS_DUMP"
  die "binary stats a protected-folder resource bundle — do not ship"
fi
if grep -E '/Documents/GitHub/(AgentOS|Allnighter)$' "$STRINGS_DUMP" >/dev/null; then
  echo "relocate-cli-proof: baked Documents/GitHub allow-root:" >&2
  grep -E '/Documents/GitHub/(AgentOS|Allnighter)$' "$STRINGS_DUMP" | sed 's/^/  | /' >&2
  rm -f "$STRINGS_DUMP"
  die "binary contains a hardcoded Documents/GitHub allow-root — TCC landmine"
fi
rm -f "$STRINGS_DUMP"

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
hide_root "${ALLN_UNIVERSAL_SCRATCH:-$HOME/Library/Developer/Allnighter/CLI-universal}"
hide_root "$HOME/Library/Developer/Allnighter/Build"

# Do not hide $SRC_DIR — the proof runs from $STAGE. Build scratches are the lie.
#
# Invoke the way users invoke: bare name on PATH, cwd is not the binary
# directory. Absolute `"$STAGE/alln"` is a false green — argv[0] is then
# absolute and hides the 1.1.11 PATH-invocation trap.

if ! ( cd "$HOME" && env PATH="$STAGE:$PATH" alln menu --json </dev/null >/dev/null ); then
  echo "relocate-cli-proof: relocated binary failed bare \`alln menu --json\` via PATH (catalog load; build-path fallback was hidden)" >&2
  echo "  staged: $STAGE/alln" >&2
  echo "  argv0: alln  PATH-prefix: $STAGE" >&2
  ( cd "$HOME" && env PATH="$STAGE:$PATH" alln menu --json </dev/null ) 2>&1 | sed 's/^/  | /' >&2 || true
  exit 1
fi

echo "relocate-cli-proof: OK — $BINARY loads catalog after relocate with build bundles hidden"
