#!/usr/bin/env bash
# Developer ID–sign and notarize the universal `alln` unix executable.
# Staple is N/A on a bare executable (Public_Release.md).
#
# Usage:
#   scripts/sign-cli.sh [binary]
#
# Env:
#   ALLN_SIGN_IDENTITY   default Developer ID Application: Happy Moose Apps Inc. (LP5YNK7A36)
#   NOTARY_PROFILE       default xterminal-notary
#   ALLN_SIGN_CLI_SKIP_NOTARY=1  sign only (dogfood)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BINARY="${1:-$ROOT/dist/alln-macos-universal}"
SIGN_IDENTITY="${ALLN_SIGN_IDENTITY:-Developer ID Application: Happy Moose Apps Inc. (LP5YNK7A36)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-xterminal-notary}"

die() { echo "sign-cli: $*" >&2; exit 1; }

[[ -x "$BINARY" ]] || die "not executable: $BINARY"
security find-identity -v -p codesigning 2>/dev/null | grep -qF "$SIGN_IDENTITY" \
  || die "signing identity not in Keychain: $SIGN_IDENTITY"

SRC_DIR="$(cd "$(dirname "$BINARY")" && pwd)"
ABS_BIN="$SRC_DIR/$(basename "$BINARY")"

echo "sign-cli: Developer ID ($SIGN_IDENTITY)"
codesign --force --options runtime --timestamp \
  --sign "$SIGN_IDENTITY" \
  --identifier com.allnighter.cli \
  "$ABS_BIN"
codesign --verify --strict "$ABS_BIN" || die "codesign --verify failed"
codesign -dv --verbose=2 "$ABS_BIN" 2>&1 | grep -E 'Authority=|Identifier=|TeamIdentifier=|Signature=' || true

if [[ "${ALLN_SIGN_CLI_SKIP_NOTARY:-}" == "1" ]]; then
  echo "sign-cli: skip notary (ALLN_SIGN_CLI_SKIP_NOTARY=1)"
else
  command -v xcrun >/dev/null || die "xcrun not found"
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/alln-sign.XXXXXX")"
  trap 'rm -rf "$WORK"' EXIT
  PAYLOAD="$WORK/payload"
  mkdir -p "$PAYLOAD"
  cp "$ABS_BIN" "$PAYLOAD/alln-macos-universal"
  for name in AgentOS_AgentOSCLI.bundle AllnighterCore_AllnighterCore.bundle; do
    [[ -d "$SRC_DIR/$name" ]] || die "missing $name next to $ABS_BIN"
    cp -R "$SRC_DIR/$name" "$PAYLOAD/$name"
  done
  ZIP="$WORK/alln-macos-universal.zip"
  ditto -c -k "$PAYLOAD" "$ZIP"
  echo "sign-cli: notarize ($NOTARY_PROFILE)"
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
fi

"$SCRIPT_DIR/relocate-cli-proof.sh" "$ABS_BIN"

echo "sign-cli: OK"
echo "  binary: $ABS_BIN"
echo "  sha256: $(shasum -a 256 "$ABS_BIN" | awk '{print $1}')"
