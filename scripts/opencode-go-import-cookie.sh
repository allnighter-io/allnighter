#!/usr/bin/env bash
# Import the OpenCode Go dashboard session cookie from Chrome into alln.
#
# WHAT THIS PROMPTS FOR
#   Chrome encrypts every cookie VALUE with a key held in your login keychain
#   ("Chrome Safe Storage"). Reading your own cookie therefore requires
#   unlocking that key, so macOS will ask once. Click "Always Allow" and it
#   never asks again. This is Chrome's design — no tool can read Chrome
#   cookies without it.
#
#   The cookie is decrypted in memory, piped straight into
#   `alln opencode-go configure`, and stored AES-GCM encrypted. It is never
#   printed, never written to a temp file, and never enters shell history.
#
# USAGE
#   bash scripts/opencode-go-import-cookie.sh
set -euo pipefail

command -v alln >/dev/null || { echo "alln not on PATH" >&2; exit 1; }

python3 - "$@" <<'PY'
import os, shutil, sqlite3, subprocess, sys, hashlib, tempfile
from pathlib import Path

CHROME = Path.home()/"Library/Application Support/Google/Chrome"
if not CHROME.exists():
    sys.exit("Chrome not found. If you use Safari or Firefox, tell Fable — those "
             "store cookie values in plaintext and need a different reader.")

# Search every profile: the logged-in one is often not "Default".
found = None
for db in sorted(CHROME.glob("*/Cookies")):
    tmp = Path(tempfile.mkdtemp())/"c.db"
    try:
        shutil.copy(db, tmp)                      # copy: Chrome holds a lock
        row = sqlite3.connect(tmp).execute(
            "select encrypted_value from cookies "
            "where host_key like '%opencode.ai%' and name='auth' "
            "order by length(encrypted_value) desc limit 1").fetchone()
    except Exception:
        row = None
    finally:
        shutil.rmtree(tmp.parent, ignore_errors=True)
    if row and row[0]:
        found = (db.parent.name, row[0])
        break

if not found:
    sys.exit("No opencode.ai 'auth' cookie in any Chrome profile.\n"
             "Log in at https://opencode.ai in Chrome, then re-run this.")

profile, enc = found

# Disclosure BEFORE the prompt. Founder ruling 2026-08-06: a permission prompt
# is fine when the surface has already said what it wants and why; a SURPRISE
# prompt is the defect. Printed to stderr so stdout stays pipeable.
print(f"""
Found the opencode.ai 'auth' cookie in Chrome profile: {profile}

macOS is about to ask for your login keychain password.

  WHAT   Chrome's "Chrome Safe Storage" key — nothing else.
  WHY    Chrome encrypts every cookie VALUE with that key. Reading your own
         cookie is impossible without it; this is Chrome's design, not ours.
  WHERE  The cookie is decrypted in memory and piped straight into
         `alln opencode-go configure`, which stores it AES-GCM encrypted at
         rest. It is never printed, never written to a file, never passed as a
         command argument, and never enters your shell history.
  ONCE   Choose "Always Allow" and macOS stops asking.

  DECLINE  Press Deny and nothing is read. You can still set it up by hand:
             pbpaste | alln opencode-go configure
""", file=sys.stderr)

pw = subprocess.run(
    ["security", "find-generic-password", "-w",
     "-s", "Chrome Safe Storage", "-a", "Chrome"],
    capture_output=True, text=True)
if pw.returncode != 0:
    sys.exit("Keychain access was denied, so the cookie cannot be decrypted.\n"
             "Re-run and choose Always Allow, or paste manually:\n"
             "  pbpaste | alln opencode-go configure")

key = hashlib.pbkdf2_hmac("sha1", pw.stdout.strip().encode(), b"saltysalt", 1003, 16)

if enc[:3] not in (b"v10", b"v11"):
    sys.exit(f"Unexpected cookie encryption prefix {enc[:3]!r} — Chrome changed format.")

# AES-128-CBC, IV = 16 spaces. openssl ships with macOS; no pip install.
dec = subprocess.run(
    ["openssl", "enc", "-aes-128-cbc", "-d", "-nopad",
     "-K", key.hex(), "-iv", "20" * 16],
    input=enc[3:], capture_output=True)
if dec.returncode != 0:
    sys.exit("openssl could not decrypt the cookie.")

data = dec.stdout
data = data[:-data[-1]]          # strip PKCS#7 padding
if len(data) > 32:               # Chrome v24+ prepends a sha256 domain hash
    data = data[32:]
cookie = data.decode("utf-8", "ignore").strip()
if not cookie:
    sys.exit("Decrypted cookie was empty.")

# Straight into configure over stdin — never argv, never a file, never printed.
r = subprocess.run(["alln", "opencode-go", "configure"],
                   input=cookie + "\n", text=True)
sys.exit(r.returncode)
PY
