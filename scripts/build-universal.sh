#!/usr/bin/env bash
# OPC-S00 — Build a universal (arm64 + x86_64) release binary for `alln`.
#
# Multi-arch finding (Swift 6.2 / Apple Silicon host, 2026-07-31):
#   Single invocation `swift build --arch arm64 --arch x86_64` fails here
#   with a BuildInfoPlugin workspace-resolution error
#   ("missing target with GUID 'PACKAGE-TARGET:BuildInfoPlugin@…'").
#   Two separate `--arch` release builds + `lipo -create` works reliably.
#   Prefer that path; do not reintroduce dual-arch SPM until the plugin
#   path is fixed.
#
# Dogfood track only: ad-hoc codesign (`codesign --sign -`). Developer ID
# / notarization is OPC-S05 and requires founder credentials.
#
# Output (override with ALLN_UNIVERSAL_OUT):
#   <repo>/dist/alln-macos-universal
#
# Scratch builds (override with ALLN_UNIVERSAL_SCRATCH):
#   $HOME/Library/Developer/Allnighter/CLI-universal/{arm64,x86_64}
# Never the repo tree: a Documents checkout bakes that path into SPM's
# Bundle.module fallback, and every later `alln` stats it (Documents TCC).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PACKAGE="$ROOT/Packages/AllnighterCore"
PRODUCT="alln"

# Same reason rebuild_cli.sh keeps the debug image out of ~/Documents.
SCRATCH="${ALLN_UNIVERSAL_SCRATCH:-$HOME/Library/Developer/Allnighter/CLI-universal}"
OUT="${ALLN_UNIVERSAL_OUT:-$ROOT/dist/alln-macos-universal}"

die() {
  echo "build-universal: $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

require_cmd swift
require_cmd lipo
require_cmd codesign
require_cmd file

mkdir -p "$(dirname "$OUT")"
mkdir -p "$SCRATCH"

# Build one thin arch. Path is printed on stdout only (last line); all progress
# and diagnostics go to stderr so command-substitution capture stays clean.
build_arch() {
  local arch="$1"
  local scratch="$SCRATCH/$arch"
  mkdir -p "$scratch"
  echo "build-universal: building $arch (release) …" >&2
  # Progress belongs on stderr — stdout is reserved for the resulting path.
  swift build \
    --disable-sandbox \
    --package-path "$PACKAGE" \
    --scratch-path "$scratch" \
    --product "$PRODUCT" \
    -c release \
    --arch "$arch" >&2
  local bin_dir
  bin_dir="$(
    swift build \
      --disable-sandbox \
      --package-path "$PACKAGE" \
      --scratch-path "$scratch" \
      --product "$PRODUCT" \
      -c release \
      --arch "$arch" \
      --show-bin-path
  )"
  # --show-bin-path can still emit a planning line on some toolchains; take the last non-empty line.
  bin_dir="$(printf '%s\n' "$bin_dir" | awk 'NF { line=$0 } END { print line }')"
  local bin="$bin_dir/$PRODUCT"
  [[ -x "$bin" ]] || die "expected executable missing for $arch: $bin"
  # Single-arch slice only (never a fat intermediate).
  if lipo -info "$bin" 2>/dev/null | grep -qi 'are:'; then
    die "expected thin $arch binary, got fat: $bin ($(lipo -info "$bin"))"
  fi
  if ! lipo -info "$bin" 2>/dev/null | grep -q "$arch"; then
    die "binary is not $arch: $bin ($(lipo -info "$bin" 2>&1 || file "$bin"))"
  fi
  printf '%s\n' "$bin"
}

ARM_BIN="$(build_arch arm64)"
X86_BIN="$(build_arch x86_64)"
[[ -x "$ARM_BIN" ]] || die "arm64 path not executable: $ARM_BIN"
[[ -x "$X86_BIN" ]] || die "x86_64 path not executable: $X86_BIN"

STAGE="$OUT.tmp.$$"
rm -f "$STAGE"
echo "build-universal: lipo -create → $OUT" >&2
lipo -create "$ARM_BIN" "$X86_BIN" -output "$STAGE"
chmod 755 "$STAGE"

copy_required_bundles() {
  local src_bin="$1"
  local dest_bin="$2"
  local src_dir dest_dir name
  src_dir="$(cd "$(dirname "$src_bin")" && pwd)"
  dest_dir="$(cd "$(dirname "$dest_bin")" && pwd)"
  for name in AgentOS_AgentOSCLI.bundle AllnighterCore_AllnighterCore.bundle; do
    [[ -d "$src_dir/$name" ]] || die "SPM resource bundle missing next to $src_bin: $name"
    rm -rf "$dest_dir/$name"
    cp -R "$src_dir/$name" "$dest_dir/$name"
  done
}

copy_required_bundles "$ARM_BIN" "$STAGE"

echo "build-universal: ad-hoc codesign (dogfood track)" >&2
codesign --sign - --force "$STAGE" >/dev/null

# --- hard proof gates (never succeed on a partial) ---
LIPO_INFO="$(lipo -info "$STAGE")"
echo "build-universal: $LIPO_INFO" >&2
echo "$LIPO_INFO" | grep -q arm64 || die "lipo missing arm64: $LIPO_INFO"
echo "$LIPO_INFO" | grep -q x86_64 || die "lipo missing x86_64: $LIPO_INFO"
# Fat file wording: "Architectures in the fat file: … are: x86_64 arm64"
echo "$LIPO_INFO" | grep -qi 'are:' || die "expected fat universal binary, got: $LIPO_INFO"

codesign --verify "$STAGE" || die "codesign --verify failed for $STAGE"

# Relocate-proof with build-scratch bundles hidden. Running `version` next to
# the compile scratch is a false green on the builder (1.1.5–1.1.8 outage).
"$SCRIPT_DIR/relocate-cli-proof.sh" "$STAGE"

mv -f "$STAGE" "$OUT"
# Re-sign after rename is unnecessary (rename preserves signature); re-verify final path.
codesign --verify "$OUT" || die "codesign --verify failed for final $OUT"

echo "build-universal: OK"
echo "  binary:  $OUT"
echo "  lipo:    $(lipo -info "$OUT")"
echo "  codesign: verified (ad-hoc)"
echo "  bundles: AgentOS_AgentOSCLI.bundle AllnighterCore_AllnighterCore.bundle"
echo "  version: $("$OUT" version </dev/null | head -n 1)"
