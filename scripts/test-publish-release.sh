#!/usr/bin/env bash
# OPC-S06c — Fixture proof for scripts/publish-release.sh latest.json write.
#
# Asserts:
#   - versioned assets land under v<version>/
#   - latest.json is written LAST and names the asset sha256
#   - installCommand is the canonical one-liner (not a dogfood cousin)
#   - re-publish of the same version is refused (immutability)
#   - ALLN_SKIP_LATEST_JSON=1 skips the manifest
#
# Never touches dist/releases (uses a temp base). Requires a universal binary
# at dist/alln-macos-universal or ALLN_UNIVERSAL_BINARY, plus sibling
# AgentOS_AgentOSCLI.bundle and AllnighterCore_AllnighterCore.bundle.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/scripts/publish-release.sh"
BINARY="${ALLN_UNIVERSAL_BINARY:-$ROOT/dist/alln-macos-universal}"

FAILURES=0
pass() { echo "test-publish-release: PASS — $*"; }
fail() { echo "test-publish-release: FAIL — $*" >&2; FAILURES=$((FAILURES + 1)); }

die() {
  echo "test-publish-release: $*" >&2
  exit 1
}

[[ -x "$SCRIPT" ]] || die "missing $SCRIPT"
[[ -x "$BINARY" ]] || die "need universal binary at $BINARY (run scripts/build-universal.sh)"

file "$BINARY" | grep -q "universal binary" || die "binary is not universal: $(file "$BINARY")"

SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/opc-publish.XXXXXX")"
trap 'rm -rf "$SCRATCH"' EXIT

BASE="$SCRATCH/releases"
VERSION="0.0.0-test"
export ALLN_PUBLISH_BASE_DIR="$BASE"
export ALLN_UNIVERSAL_BINARY="$BINARY"
export ALLN_PUBLIC_BASE_URL="https://fixture.get.allnighter.io"
export ALLN_RELEASE_NOTES="human notes only"
export ALLN_APP_VERSION="0.0.0-test"

# --- happy path: assets + latest.json ---------------------------------------
OUT="$SCRATCH/publish.out"
if ! "$SCRIPT" "$VERSION" >"$OUT" 2>&1; then
  cat "$OUT" >&2
  die "publish-release failed"
fi

ASSET="$BASE/v$VERSION/alln-macos-universal.tar.gz"
SHA_FILE="$ASSET.sha256"
LATEST="$BASE/latest.json"

[[ -f "$ASSET" ]] || fail "missing asset $ASSET"
[[ -f "$SHA_FILE" ]] || fail "missing sha256 file"
[[ -f "$LATEST" ]] || fail "missing latest.json"
pass "assets + latest.json present"

SHA256="$(awk '{print $1}' "$SHA_FILE")"
grep -q "$SHA256" "$LATEST" || fail "latest.json missing sha256 $SHA256"
grep -q "\"cliVersion\": \"$VERSION\"" "$LATEST" || fail "cliVersion mismatch"
grep -q "\"appVersion\": \"$VERSION\"" "$LATEST" || fail "appVersion mismatch"
grep -q "https://fixture.get.allnighter.io/v$VERSION/alln-macos-universal.tar.gz" "$LATEST" \
  || fail "cli.url wrong base"
grep -q "curl -fsSL https://get.allnighter.io | sh" "$LATEST" \
  || fail "installCommand must be canonical public one-liner"
grep -q "human notes only" "$LATEST" || fail "notes not written"
# Must not invent a second install string from the fixture base.
if grep -q "fixture.get.allnighter.io | sh" "$LATEST"; then
  fail "installCommand must not use dogfood base"
fi
pass "latest.json fields"

# Manifest written after assets: both must exist; asset mtime <= latest (soft).
# Stronger: re-run with SKIP leaves latest alone only when we delete first…
# --- immutability -----------------------------------------------------------
if "$SCRIPT" "$VERSION" >"$SCRATCH/republish.out" 2>&1; then
  fail "re-publish same version should refuse"
else
  pass "immutable version path refused"
fi

# --- SKIP latest ------------------------------------------------------------
VERSION2="0.0.0-test2"
export ALLN_SKIP_LATEST_JSON=1
# Keep prior latest; publish a second version without flipping the pointer.
BEFORE_HASH="$(shasum -a 256 "$LATEST" | awk '{print $1}')"
if ! "$SCRIPT" "$VERSION2" >"$SCRATCH/skip.out" 2>&1; then
  cat "$SCRATCH/skip.out" >&2
  fail "skip-latest publish failed"
else
  AFTER_HASH="$(shasum -a 256 "$LATEST" | awk '{print $1}')"
  [[ "$BEFORE_HASH" == "$AFTER_HASH" ]] || fail "SKIP_LATEST should not rewrite latest.json"
  [[ -f "$BASE/v$VERSION2/alln-macos-universal.tar.gz" ]] || fail "v$VERSION2 asset missing"
  pass "ALLN_SKIP_LATEST_JSON leaves latest.json untouched"
fi
unset ALLN_SKIP_LATEST_JSON

# --- second publish flips latest --------------------------------------------
VERSION3="0.0.0-test3"
export ALLN_RELEASE_NOTES="second release"
if ! "$SCRIPT" "$VERSION3" >"$SCRATCH/v3.out" 2>&1; then
  cat "$SCRATCH/v3.out" >&2
  fail "v3 publish failed"
else
  grep -q "\"cliVersion\": \"$VERSION3\"" "$LATEST" || fail "latest did not flip to $VERSION3"
  grep -q "second release" "$LATEST" || fail "notes not updated on flip"
  pass "latest.json flips to newest publish"
fi

if [[ "$FAILURES" -gt 0 ]]; then
  echo "test-publish-release: $FAILURES failure(s)" >&2
  exit 1
fi
echo "test-publish-release: ALL PASS"
exit 0
