#!/usr/bin/env python3
"""Mint and validate single-use HMAC test tokens for swift/xcodebuild shims."""
from __future__ import annotations

import base64
import hashlib
import hmac
import os
import secrets
import sys
import time

TTL_SECONDS = 120
ENV_VAR = "ALLNIGHTER_TEST_TOKEN"


def _secret_path(repo_root: str) -> str:
    return os.path.join(repo_root, ".alln-test.hmac-key")


def _token_dir(repo_root: str) -> str:
    return os.path.join(repo_root, ".alln-test.tokens")


def _load_secret(repo_root: str) -> bytes:
    path = _secret_path(repo_root)
    if not os.path.exists(path):
        os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
        with open(path, "wb") as handle:
            handle.write(secrets.token_bytes(32))
        os.chmod(path, 0o600)
    with open(path, "rb") as handle:
        return handle.read()


def _sign(secret: bytes, payload: bytes) -> str:
    digest = hmac.new(secret, payload, hashlib.sha256).digest()
    return base64.urlsafe_b64encode(payload + b"." + digest).decode("ascii")


def _unsign(secret: bytes, token: str) -> bytes | None:
    try:
        raw = base64.urlsafe_b64decode(token.encode("ascii"))
        payload, digest = raw.rsplit(b".", 1)
    except (ValueError, UnicodeError):
        return None
    expected = hmac.new(secret, payload, hashlib.sha256).digest()
    if not hmac.compare_digest(digest, expected):
        return None
    return payload


def mint(repo_root: str, ttl_seconds: int = TTL_SECONDS) -> str:
    secret = _load_secret(repo_root)
    nonce = secrets.token_hex(16)
    expires = int(time.time()) + ttl_seconds
    payload = f"{expires}:{nonce}".encode("ascii")
    token = _sign(secret, payload)
    os.makedirs(_token_dir(repo_root), exist_ok=True)
    marker = os.path.join(_token_dir(repo_root), hashlib.sha256(token.encode()).hexdigest())
    with open(marker, "w", encoding="utf-8") as handle:
        handle.write(str(expires))
    return token


def _expired_reason(expires: int, now: float) -> str:
    overdue = now - expires
    ago = f"{overdue:.1f}s" if overdue < 1 else f"{int(overdue)}s"
    return f"token: expired {ago} ago (TTL {TTL_SECONDS}s)"


def diagnose_and_maybe_consume(
    repo_root: str, token: str, *, consume: bool
) -> tuple[bool, str | None]:
    """Return (ok, reason). reason is set only on denial."""
    if not token:
        return False, "token: no token in the environment"
    secret = _load_secret(repo_root)
    payload = _unsign(secret, token)
    if payload is None:
        return False, "token: present but signature invalid"
    try:
        expires_text, _nonce = payload.decode("ascii").split(":", 1)
        expires = int(expires_text)
    except (ValueError, UnicodeError):
        return False, "token: present but signature invalid"
    now = time.time()
    if now > expires:
        return False, _expired_reason(expires, now)
    marker = os.path.join(_token_dir(repo_root), hashlib.sha256(token.encode()).hexdigest())
    if not os.path.exists(marker):
        return False, "token: valid but already consumed (marker gone)"
    if consume:
        os.remove(marker)
    return True, None


def validate_and_consume(repo_root: str, token: str) -> bool:
    ok, _reason = diagnose_and_maybe_consume(repo_root, token, consume=True)
    return ok


def burn(repo_root: str, token: str) -> None:
    if not token:
        return
    marker = os.path.join(_token_dir(repo_root), hashlib.sha256(token.encode()).hexdigest())
    if os.path.exists(marker):
        os.remove(marker)


def main() -> int:
    if len(sys.argv) < 3:
        print(f"usage: {sys.argv[0]} mint|validate|burn <repo-root> [token]", file=sys.stderr)
        return 2
    command = sys.argv[1]
    repo_root = os.path.abspath(sys.argv[2])
    if command == "mint":
        ttl = int(sys.argv[3]) if len(sys.argv) > 3 else TTL_SECONDS
        print(mint(repo_root, ttl_seconds=ttl))
        return 0
    if command == "validate":
        token = sys.argv[3] if len(sys.argv) > 3 else os.environ.get(ENV_VAR, "")
        ok, reason = diagnose_and_maybe_consume(repo_root, token, consume=True)
        if ok:
            return 0
        print(reason or "token: rejected", file=sys.stderr)
        return 1
    if command == "burn":
        token = sys.argv[3] if len(sys.argv) > 3 else os.environ.get(ENV_VAR, "")
        burn(repo_root, token)
        return 0
    print(f"unknown command: {command}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
