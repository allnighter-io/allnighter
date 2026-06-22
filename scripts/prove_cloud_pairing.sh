#!/usr/bin/env bash
# Headless cloud pairing proof: device requests trust, Mac approves, relay shows trusted row.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$ROOT/.env"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing $ENV_FILE — run scripts/bootstrap_remote_env.sh first" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

DEVICE_ROOT="$(mktemp -d)"
trap 'rm -rf "$DEVICE_ROOT"' EXIT

ALLN_BIN="${ALLN_BIN:-$(swift build --package-path "$ROOT/Packages/AllnighterCore" --disable-sandbox --product alln --show-bin-path 2>/dev/null)/alln}"

echo "==> Starting remote Mac agent"
( "$ALLN_BIN" serve 2>&1 & echo $! > "$DEVICE_ROOT/serve.pid" )
SERVE_PID="$(cat "$DEVICE_ROOT/serve.pid")"
sleep 12

cleanup() {
  if [[ -n "${SERVE_PID:-}" ]]; then
    kill "$SERVE_PID" 2>/dev/null || true
    wait "$SERVE_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

export ROOT
export ALLN_BIN

python3 - "$DEVICE_ROOT" <<'PY'
import json, os, pathlib, subprocess, sys, time, urllib.error, urllib.request

device_root = pathlib.Path(sys.argv[1])
url = os.environ["ALLNIGHTER_SUPABASE_URL"]
key = os.environ["ALLNIGHTER_SUPABASE_PUBLISHABLE_KEY"]
mac_token = os.environ["ALLNIGHTER_SUPABASE_ACCESS_TOKEN"]
account_id = os.environ["ALLNIGHTER_REMOTE_ACCOUNT_ID"]
mac_id = os.environ["ALLNIGHTER_REMOTE_MAC_AGENT_ID"]

device_id = "prove_pair_device"
sign = "dGVzdF9zaWduaW5nX2tleV9kYXRh" * 2
seal = "dGVzdF9zZWFsaW5nX2tleV9kYXRh" * 2
now = time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime())
expires = time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime(time.time() + 300))

def request(method, path, token, body=None):
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(
        f"{url}{path}",
        data=data,
        method=method,
        headers={
            "apikey": key,
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
            "Prefer": "return=representation",
        },
    )
    with urllib.request.urlopen(req) as response:
        payload = response.read().decode()
        return json.loads(payload) if payload else {}

pair_body = {
    "account_id": account_id,
    "mac_agent_id": mac_id,
    "device_id": device_id,
    "display_name": "Pairing Proof iPhone",
    "device_signing_pubkey": sign[:88],
    "device_sealing_pubkey": seal[:88],
    "status": "pending",
    "requested_at": now,
    "expires_at": expires,
}
created = request("POST", "/rest/v1/pair_requests", mac_token, pair_body)
request_id = created[0]["id"]
print(f"submitted pair request {request_id} for {device_id}")

root = pathlib.Path(os.environ["HOME"]) / "Library/Application Support/Allnighter/Config/Remote"
trusted_file = root / "trusted_remotes.json"
for _ in range(20):
  time.sleep(1)
  if trusted_file.exists():
    registry = json.loads(trusted_file.read_text())
    pending = [r for r in registry.get("pendingRequests", []) if r.get("deviceId") == device_id]
    if pending:
      break
else:
  raise SystemExit("Mac agent did not import pending pair request into trusted_remotes.json")

subprocess.run(
    [os.environ.get("ALLN_BIN", "alln"), "pair", "approve", device_id],
    check=True,
    cwd=os.environ.get("ROOT", "."),
)
print(f"approved {device_id} locally")

for _ in range(30):
  time.sleep(1)
  rows = request(
      "GET",
      f"/rest/v1/trusted_devices?account_id=eq.{account_id}&mac_agent_id=eq.{mac_id}&device_id=eq.{device_id}&select=device_id,revoked",
      mac_token,
  )
  if rows and not rows[0].get("revoked", False):
    print("trusted device visible in Supabase")
    sys.exit(0)

raise SystemExit("trusted device never appeared in Supabase after approval")
PY

echo "==> Cloud pairing proof passed"
