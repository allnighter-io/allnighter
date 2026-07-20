#!/usr/bin/env bash
# AE-S09 — reproducible cold-agent evaluation harness.
# Pins a freshly built alln binary, records its gitSha, runs a fixed probe script,
# and captures the transcript so dogfood feedback is attributable to a known SHA.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

OUT_DIR="${ALLN_EVAL_OUT:-$ROOT/.build/agent-eval}"
mkdir -p "$OUT_DIR"

echo "== AE-S09 cold-agent eval =="
echo "repo: $ROOT"
echo "out:  $OUT_DIR"

# 1. Build a release binary from this checkout.
swift build -c release --package-path Packages/AllnighterCore --product alln
B="$ROOT/Packages/AllnighterCore/.build/release/alln"
test -x "$B"

# 2. Pin identity.
VERSION_JSON="$OUT_DIR/version.json"
"$B" version --json > "$VERSION_JSON"
GIT_SHA="$(/usr/bin/python3 -c 'import json; print(json.load(open("'"$VERSION_JSON"'")).get("gitSha") or "unknown")')"
HEAD_SHA="$(git rev-parse HEAD)"
echo "binary gitSha: $GIT_SHA"
echo "workspace HEAD: $HEAD_SHA"
printf '%s\n' "$GIT_SHA" > "$OUT_DIR/pinned-gitSha.txt"
printf '%s\n' "$HEAD_SHA" > "$OUT_DIR/workspace-HEAD.txt"

# 3. Fixed probe script (discovery → route → dry-run).
PROBE="$OUT_DIR/probe.sh"
cat > "$PROBE" <<'PROBE'
#!/usr/bin/env bash
set -euo pipefail
B="${ALLN_BIN:?}"
echo "--- help ---"
"$B" --help | tail -5
echo "--- commands count ---"
"$B" commands --json | /usr/bin/python3 -c 'import json,sys; print(len(json.load(sys.stdin)["commands"]))'
echo "--- route ---"
"$B" route --for "ask Sonnet 5 a question" --json | /usr/bin/python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("recommended",{}).get("command") or d.get("nextActions",[{}])[0].get("command"))'
echo "--- dry-run ---"
"$B" run "probe" --dry-run --json | /usr/bin/python3 -c 'import json,sys; d=json.load(sys.stdin); print("canStart=", d.get("canStart"), "project=", d.get("projectId"))'
echo "--- unknown flag (must fail) ---"
set +e
"$B" version --bogus-flag >/dev/null 2>&1
echo "exit=$?"
set -e
PROBE
chmod +x "$PROBE"

# 4. Run and capture transcript.
export ALLN_BIN="$B"
TRANSCRIPT="$OUT_DIR/transcript.txt"
bash "$PROBE" > "$TRANSCRIPT" 2>&1
echo "transcript: $TRANSCRIPT"
echo "OK — eval harness complete for gitSha=$GIT_SHA"
