#!/usr/bin/env bash
# Bootstrap or refresh local Supabase relay credentials for alln serve + iOS live dev.
#
# Usage:
#   scripts/bootstrap_remote_env.sh              # link, migrate, ensure users, write .env
#   scripts/bootstrap_remote_env.sh --refresh    # refresh JWTs in existing .env only
#   scripts/bootstrap_remote_env.sh --reset-mac    # also delete local mac_agent_credentials.json
#
# Requires: supabase CLI (logged in), python3, curl optional (python urllib used).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$ROOT/.env"
EXAMPLE_FILE="$ROOT/.env.example"

PROJECT_REF="${ALLNIGHTER_SUPABASE_PROJECT_REF:-kfqwpozmntqpxiveafld}"
SUPABASE_URL="https://${PROJECT_REF}.supabase.co"

MAC_EMAIL="${ALLNIGHTER_DEV_MAC_EMAIL:-dev-mac@allnighter.dev}"
IOS_EMAIL="${ALLNIGHTER_DEV_IOS_EMAIL:-dev-ios@allnighter.dev}"
DEV_PASSWORD="${ALLNIGHTER_DEV_AUTH_PASSWORD:-AllnighterDevRelay2026!}"

# Stable dev fixtures — keep constant so credential files and RLS proofs stay aligned.
MAC_AGENT_ID="${ALLNIGHTER_REMOTE_MAC_AGENT_ID:-8f4e2c1a-9b3d-4f5e-a6c7-1d2e3f4a5b6c}"
MAC_DISPLAY_NAME="${ALLNIGHTER_REMOTE_MAC_DISPLAY_NAME:-Studio Mac}"
RLS_DEVICE_A_ID="${ALLNIGHTER_SUPABASE_RLS_DEVICE_A_ID:-dev_ios_device_1}"

REFRESH_ONLY=0
RESET_MAC=0
for arg in "$@"; do
  case "$arg" in
    --refresh) REFRESH_ONLY=1 ;;
    --reset-mac) RESET_MAC=1 ;;
    -h|--help)
      sed -n '2,8p' "$0"
      exit 0
      ;;
    *)
      echo "Unknown option: $arg" >&2
      exit 1
      ;;
  esac
done

mac_cred_file="$HOME/Library/Application Support/Allnighter/Config/Remote/mac_agent_credentials.json"
if [[ "$RESET_MAC" -eq 1 ]]; then
  rm -f "$mac_cred_file"
  echo "Removed $mac_cred_file"
fi

python3 - "$ROOT" "$ENV_FILE" "$EXAMPLE_FILE" "$PROJECT_REF" "$SUPABASE_URL" \
  "$MAC_EMAIL" "$IOS_EMAIL" "$DEV_PASSWORD" "$MAC_AGENT_ID" "$MAC_DISPLAY_NAME" \
  "$RLS_DEVICE_A_ID" "$REFRESH_ONLY" <<'PY'
import json
import os
import pathlib
import subprocess
import sys
import urllib.error
import urllib.request

root, env_file, example_file, project_ref, supabase_url, mac_email, ios_email, password, \
    mac_agent_id, mac_display_name, rls_device_a_id, refresh_only = sys.argv[1:13]
refresh_only = refresh_only == "1"
env_path = pathlib.Path(env_file)


def run_supabase_json(args: list[str]) -> list[dict]:
    proc = subprocess.run(
        ["supabase", *args],
        cwd=root,
        check=True,
        capture_output=True,
        text=True,
    )
    raw = proc.stdout
    start, end = raw.find("["), raw.rfind("]") + 1
    if start < 0 or end <= start:
        raise RuntimeError(f"supabase {' '.join(args)} did not return JSON array")
    return json.loads(raw[start:end])


def api_keys() -> tuple[str, str]:
    keys = run_supabase_json(["projects", "api-keys", "--project-ref", project_ref, "-o", "json"])
    publishable = None
    service_role = None
    for entry in keys:
        name = entry.get("name") or ""
        api_key = entry["api_key"]
        if name == "service_role":
            service_role = api_key
        elif api_key.startswith("sb_publishable_"):
            publishable = api_key
        elif name == "anon" and publishable is None:
            publishable = api_key
    if not publishable or not service_role:
        raise RuntimeError("Could not resolve publishable and service_role API keys")
    return publishable, service_role


def request_json(method: str, url: str, headers: dict, body: dict | None = None) -> dict:
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(url, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req) as response:
            payload = response.read().decode()
            return json.loads(payload) if payload else {}
    except urllib.error.HTTPError as error:
        detail = error.read().decode()
        raise RuntimeError(f"{method} {url} failed ({error.code}): {detail}") from error


def ensure_user(service_role: str, email: str) -> str:
    admin_url = f"{supabase_url}/auth/v1/admin/users"
    headers = {
        "apikey": service_role,
        "Authorization": f"Bearer {service_role}",
        "Content-Type": "application/json",
    }
    try:
        created = request_json(
            "POST",
            admin_url,
            headers,
            {"email": email, "password": password, "email_confirm": True},
        )
        return created["id"]
    except RuntimeError as error:
        if "email_exists" not in str(error):
            raise
    signed = sign_in(publishable_key_holder["key"], email)
    return signed["user"]["id"]


def sign_in(publishable_key: str, email: str) -> dict:
    url = f"{supabase_url}/auth/v1/token?grant_type=password"
    headers = {
        "apikey": publishable_key,
        "Content-Type": "application/json",
    }
    return request_json(
        "POST",
        url,
        headers,
        {"email": email, "password": password},
    )


publishable_key_holder: dict[str, str] = {}

def main() -> None:
    global publishable_key_holder
    publishable, service_role = api_keys()
    publishable_key_holder["key"] = publishable

    if not refresh_only:
        link = subprocess.run(
            ["supabase", "link", "--project-ref", project_ref],
            cwd=root,
            capture_output=True,
            text=True,
        )
        if link.returncode != 0 and "already" not in (link.stderr + link.stdout).lower():
            print(link.stdout, link.stderr, sep="\n")
            link.check_returncode()

        push = subprocess.run(
            ["supabase", "db", "push"],
            cwd=root,
            capture_output=True,
            text=True,
        )
        print(push.stdout.strip() or "supabase db push: ok")
        if push.returncode != 0:
            print(push.stderr, file=sys.stderr)
            push.check_returncode()

        mac_account_id = ensure_user(service_role, mac_email)
        ios_account_id = ensure_user(service_role, ios_email)
    else:
        if not env_path.exists():
            raise SystemExit(f"{env_path} missing; run without --refresh first")
        existing = parse_env(env_path.read_text())
        mac_account_id = existing.get("ALLNIGHTER_REMOTE_ACCOUNT_ID")
        if not mac_account_id:
            raise SystemExit("ALLNIGHTER_REMOTE_ACCOUNT_ID missing from .env")
        ios_account_id = jwt_sub(existing.get("ALLNIGHTER_SUPABASE_RLS_ACCOUNT_B_JWT", ""))

    mac_session = sign_in(publishable, mac_email)
    ios_session = sign_in(publishable, ios_email)
    mac_account_id = mac_session["user"]["id"]
    ios_account_id = ios_session["user"]["id"]

    lines = [
        "# Allnighter cloud relay — generated by scripts/bootstrap_remote_env.sh",
        "# Never commit this file.",
        f"ALLNIGHTER_SUPABASE_URL={supabase_url}",
        f"ALLNIGHTER_SUPABASE_PUBLISHABLE_KEY={publishable}",
        f"ALLNIGHTER_SUPABASE_ACCESS_TOKEN={mac_session['access_token']}",
        f"ALLNIGHTER_SUPABASE_DEVICE_ACCESS_TOKEN={mac_session['access_token']}",
        f"ALLNIGHTER_REMOTE_ACCOUNT_ID={mac_account_id}",
        "ALLNIGHTER_REMOTE_ACCOUNT_PROVIDER=local",
        f"ALLNIGHTER_REMOTE_MAC_AGENT_ID={mac_agent_id}",
        f'ALLNIGHTER_REMOTE_MAC_DISPLAY_NAME="{mac_display_name}"',
        "",
        "# Live RLS proof fixtures (swift test filter testLiveSupabaseRLS...)",
        f"ALLNIGHTER_SUPABASE_RLS_ACCOUNT_A_ID={mac_account_id}",
        f"ALLNIGHTER_SUPABASE_RLS_ACCOUNT_A_JWT={mac_session['access_token']}",
        f"ALLNIGHTER_SUPABASE_RLS_ACCOUNT_B_JWT={ios_session['access_token']}",
        f"ALLNIGHTER_SUPABASE_RLS_MAC_A_ID={mac_agent_id}",
        f"ALLNIGHTER_SUPABASE_RLS_DEVICE_A_ID={rls_device_a_id}",
        "",
    ]
    env_path.write_text("\n".join(lines))

    if not pathlib.Path(example_file).exists():
        print(f"warning: {example_file} missing")

    print(f"Wrote {env_path}")
    print(f"  Mac account:  {mac_account_id} ({mac_email})")
    print(f"  iOS account:  {ios_account_id} ({ios_email}) [RLS account B]")
    print(f"  Mac agent id: {mac_agent_id}")
    print()
    print("Next:")
    print("  scripts/serve_remote.sh")
    print("  scripts/ios_live.sh")


def parse_env(text: str) -> dict[str, str]:
    out: dict[str, str] = {}
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        out[key] = value.strip().strip('"')
    return out


def jwt_sub(token: str) -> str | None:
    if not token or token.count(".") < 2:
        return None
    import base64
    payload = token.split(".")[1]
    payload += "=" * (-len(payload) % 4)
    data = json.loads(base64.urlsafe_b64decode(payload))
    return data.get("sub")


if __name__ == "__main__":
    main()
PY
