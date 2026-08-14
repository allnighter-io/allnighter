#!/usr/bin/env bash
# One command to ship the CLI. Replaces the tribal
# build-universal → (maybe sign) → publish-release → upload sequence that
# let a builder-only `version` check reach get.allnighter.io.
#
# Usage:
#   scripts/ship-cli.sh <version>           # build, relocate-proof, sign, notarize, layout
#   scripts/ship-cli.sh <version> --upload  # also put objects on R2 (flips latest.json last)
#
# Version must already equal AllnighterVersionIdentity.binaryVersion.
# Never overwrite an existing v<version>/ prefix.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

die() { echo "ship-cli: $*" >&2; exit 1; }

UPLOAD=0
VERSION=""
for arg in "$@"; do
  case "$arg" in
    --upload) UPLOAD=1 ;;
    -h|--help)
      echo "usage: scripts/ship-cli.sh <version> [--upload]"
      exit 0
      ;;
    *)
      [[ -z "$VERSION" ]] || die "unexpected argument: $arg"
      VERSION="$arg"
      ;;
  esac
done
[[ -n "$VERSION" ]] || die "usage: scripts/ship-cli.sh <version> [--upload]"
case "$VERSION" in
  */*|*\\*|*..*) die "version must be a single path segment" ;;
esac

IDENTITY_FILE="$ROOT/Packages/AllnighterCore/Sources/AllnighterCore/VersionJSON.swift"
[[ -f "$IDENTITY_FILE" ]] || die "missing $IDENTITY_FILE"
PINNED="$(sed -n 's/.*public static let binaryVersion = "\([^"]*\)".*/\1/p' "$IDENTITY_FILE" | head -n 1)"
[[ "$PINNED" == "$VERSION" ]] || die "AllnighterVersionIdentity.binaryVersion is '$PINNED', not '$VERSION' — bump first"

cd "$ROOT"
HEAD="$(git rev-parse HEAD)"

echo "ship-cli: build universal $VERSION"
"$SCRIPT_DIR/build-universal.sh"

BIN="${ALLN_UNIVERSAL_OUT:-$ROOT/dist/alln-macos-universal}"
[[ -x "$BIN" ]] || die "universal binary missing: $BIN"

echo "ship-cli: Developer ID + notary"
"$SCRIPT_DIR/sign-cli.sh" "$BIN"

REPORTED="$("$BIN" version --json </dev/null)"
ALLN_SHIP_JSON="$REPORTED" python3 - "$VERSION" "$HEAD" <<'PY' \
  || die "built binary identity mismatch (want version+HEAD)"
import json, os, sys
version, head = sys.argv[1], sys.argv[2]
doc = json.loads(os.environ["ALLN_SHIP_JSON"])
got_v = doc.get("binaryVersion")
got_sha = doc.get("gitSha")
if got_v != version:
    sys.stderr.write(f"binaryVersion {got_v!r} != {version!r}\n")
    sys.exit(1)
if got_sha != head:
    sys.stderr.write(
        f"gitSha {got_sha!r} != HEAD {head!r} — stale BuildInfo. "
        "Delete CLI scratch / dist/.build-universal and rebuild.\n"
    )
    sys.exit(1)
PY

NOTES="${ALLN_RELEASE_NOTES:-CLI payload includes SPM resource bundles. Relocate-proof is a ship gate.}"
APP_VERSION="${ALLN_APP_VERSION:-}"
if [[ -z "${ALLN_APP_URL:-}" || -z "${ALLN_APP_DMG_SHA256:-}" || -z "$APP_VERSION" ]]; then
  echo "ship-cli: inherit Mac app pointer from live latest.json"
  LIVE_JSON="$(curl -fsSL https://get.allnighter.io/latest.json </dev/null)" || die "could not fetch live latest.json to keep the Mac app pointer"
  eval "$(ALLN_LIVE_JSON="$LIVE_JSON" python3 - <<'PY'
import json, os, shlex
doc = json.loads(os.environ["ALLN_LIVE_JSON"])
app = doc.get("app") or {}
url = app.get("url") or ""
sha = app.get("sha256") or ""
ver = doc.get("appVersion") or ""
if url and sha:
    print("ALLN_APP_URL=" + shlex.quote(url))
    print("ALLN_APP_DMG_SHA256=" + shlex.quote(sha))
if ver:
    print("ALLN_APP_VERSION=" + shlex.quote(ver))
PY
)"
fi
if [[ -z "${ALLN_APP_URL:-}" || -z "${ALLN_APP_DMG_SHA256:-}" ]]; then
  die "CLI-only ship would drop the Mac app pointer — set ALLN_APP_URL and ALLN_APP_DMG_SHA256, or keep a live latest.json app block"
fi
export ALLN_RELEASE_NOTES="$NOTES"
export ALLN_APP_VERSION="$APP_VERSION"
export ALLN_APP_URL="${ALLN_APP_URL:-}"
export ALLN_APP_DMG_SHA256="${ALLN_APP_DMG_SHA256:-}"

echo "ship-cli: publish layout v$VERSION"
"$SCRIPT_DIR/publish-release.sh" "$VERSION"

if [[ "$UPLOAD" -eq 1 ]]; then
  echo "ship-cli: upload R2 (assets, install script, latest.json last)"
  "$SCRIPT_DIR/upload-release-to-r2.sh"
  echo "ship-cli: live check"
  LIVE_JSON="$(curl -fsSL https://get.allnighter.io/latest.json </dev/null)"
  echo "$LIVE_JSON" | grep -q "\"cliVersion\": \"$VERSION\"" \
    || die "live latest.json did not flip to $VERSION"
  echo "ship-cli: OK — strangers get $VERSION from curl -fsSL https://get.allnighter.io | sh"
else
  echo "ship-cli: OK — layout at dist/releases (pass --upload to publish)"
  echo "  next: scripts/ship-cli.sh $VERSION --upload"
fi
