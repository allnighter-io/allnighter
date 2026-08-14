#!/usr/bin/env bash
# Public floor = the version GitHub README and Public_Release.md show strangers.
# SSOT is AllnighterVersionIdentity.binaryVersion + MARKETING_VERSION.
# This script is the only writer. Hand-editing those two lines is how they drift.
#
# Usage:
#   scripts/public-floor.sh check   # fail if README / Public_Release disagree
#   scripts/public-floor.sh sync    # rewrite those two lines from SSOT
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

die() { echo "public-floor: $*" >&2; exit 1; }

MODE="${1:-check}"
case "$MODE" in
  check|sync) ;;
  -h|--help)
    echo "usage: scripts/public-floor.sh check|sync"
    exit 0
    ;;
  *) die "usage: scripts/public-floor.sh check|sync" ;;
esac

IDENTITY="$ROOT/Packages/AllnighterCore/Sources/AllnighterCore/VersionJSON.swift"
PROJECT_YML="$ROOT/Apps/AllnighterMac/project.yml"
README="$ROOT/README.md"
RELEASE="$ROOT/docs/operations/Public_Release.md"

[[ -f "$IDENTITY" ]] || die "missing $IDENTITY"
[[ -f "$PROJECT_YML" ]] || die "missing $PROJECT_YML"
[[ -f "$README" ]] || die "missing $README"
[[ -f "$RELEASE" ]] || die "missing $RELEASE"

CLI="$(sed -n 's/.*public static let binaryVersion = "\([^"]*\)".*/\1/p' "$IDENTITY" | head -n 1)"
APP="$(sed -n 's/.*MARKETING_VERSION: *"\([^"]*\)".*/\1/p' "$PROJECT_YML" | head -n 1)"
[[ -n "$CLI" ]] || die "could not read binaryVersion from $IDENTITY"
[[ -n "$APP" ]] || die "could not read MARKETING_VERSION from $PROJECT_YML"

export ALLN_FLOOR_CLI="$CLI"
export ALLN_FLOOR_APP="$APP"
export ALLN_FLOOR_README="$README"
export ALLN_FLOOR_RELEASE="$RELEASE"
export ALLN_FLOOR_MODE="$MODE"

python3 - <<'PY'
import os, re, sys

cli = os.environ["ALLN_FLOOR_CLI"]
app = os.environ["ALLN_FLOOR_APP"]
mode = os.environ["ALLN_FLOOR_MODE"]
needle = f"CLI **{cli}** + Mac app **{app}**"
readme_line_re = re.compile(
    r"(Current floor: )CLI \*\*[^*]+\*\* \+ Mac app \*\*[^*]+\*\*"
)
release_line_re = re.compile(
    r"(Current public floor \([^)]+\): )CLI \*\*[^*]+\*\* \+ Mac app \*\*[^*]+\*\*"
)

def fail(msg):
    sys.stderr.write("public-floor: " + msg + "\n")
    sys.exit(1)

readme = open(os.environ["ALLN_FLOOR_README"], encoding="utf-8").read()
release = open(os.environ["ALLN_FLOOR_RELEASE"], encoding="utf-8").read()

if mode == "check":
    if f"Current floor: {needle}" not in readme:
        fail(
            f"README.md GitHub floor is stale (want 'Current floor: {needle}'). "
            "Run: scripts/public-floor.sh sync && git add README.md docs/operations/Public_Release.md"
        )
    if not release_line_re.search(release) or needle not in release:
        fail(
            f"Public_Release.md floor is stale (want '{needle}'). "
            "Run: scripts/public-floor.sh sync && git add README.md docs/operations/Public_Release.md"
        )
    # Exactly one GitHub landing line — extras mean someone added a cousin.
    if readme.count("Current floor:") != 1:
        fail("README.md must contain exactly one 'Current floor:' line")
    print(f"public-floor: OK — {needle}")
    sys.exit(0)

new_readme, n_readme = readme_line_re.subn(r"\1" + needle, readme, count=1)
if n_readme != 1:
    fail("README.md missing 'Current floor: CLI **…** + Mac app **…**' line to sync")

new_release, n_release = release_line_re.subn(r"\1" + needle, release, count=1)
if n_release != 1:
    fail("Public_Release.md missing 'Current public floor (…): CLI **…** + Mac app **…**' line to sync")

changed = False
if new_readme != readme:
    open(os.environ["ALLN_FLOOR_README"], "w", encoding="utf-8").write(new_readme)
    changed = True
if new_release != release:
    open(os.environ["ALLN_FLOOR_RELEASE"], "w", encoding="utf-8").write(new_release)
    changed = True

if changed:
    print(f"public-floor: synced {needle}")
else:
    print(f"public-floor: already current — {needle}")
PY
