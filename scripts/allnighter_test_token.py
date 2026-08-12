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
# urlsafe_b64encode of "{expires}:{32-hex-nonce}." + 32-byte HMAC-SHA256.
# expires is a decimal unix timestamp (9–12 digits covers well past 2286).
_SHAPE_PREFIX_BYTES = 24
_SHAPE_SUFFIX_BYTES = 8
_SHAPE_MIN_HIDDEN = 8


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


def _token_bytes(token: str) -> bytes:
    return token.encode("utf-8", errors="surrogateescape")


def _plausible_captured_length_range() -> tuple[int, int]:
    def b64_len(n: int) -> int:
        return ((n + 2) // 3) * 4

    # payload digits + ":" + 32 hex + "." + 32-byte digest
    min_blob = 9 + 1 + 32 + 1 + 32
    max_blob = 12 + 1 + 32 + 1 + 32
    return b64_len(min_blob), b64_len(max_blob)


def _escape_preview(raw: bytes) -> str:
    out: list[str] = []
    for byte in raw:
        if byte == 0x0A:
            out.append("\\n")
        elif byte == 0x0D:
            out.append("\\r")
        elif byte == 0x09:
            out.append("\\t")
        elif 0x20 <= byte < 0x7F and byte != 0x27:
            out.append(chr(byte))
        else:
            out.append(f"\\x{byte:02x}")
    return "".join(out)


def _safe_affixes(raw: bytes) -> tuple[str, str]:
    """Prefix/suffix short enough to spot a leading warning; never the whole token."""
    n = len(raw)
    if n == 0:
        return "", ""
    pre_n = _SHAPE_PREFIX_BYTES
    suf_n = _SHAPE_SUFFIX_BYTES
    if pre_n + suf_n + _SHAPE_MIN_HIDDEN > n:
        budget = max(0, n - _SHAPE_MIN_HIDDEN)
        pre_n = budget // 2
        suf_n = budget - pre_n
        if pre_n == 0 and suf_n == 0:
            return "(omitted — too short to preview)", "(omitted)"
    return _escape_preview(raw[:pre_n]), _escape_preview(raw[-suf_n:])


def _contaminants(token: str) -> list[str]:
    found: list[str] = []
    seen: set[str] = set()
    for ch in token:
        if ch == "\n":
            name = "newline"
        elif ch == "\r":
            name = "carriage return"
        elif ch == "\t":
            name = "tab"
        elif ch == " ":
            name = "space"
        elif ch.isspace():
            name = f"whitespace U+{ord(ch):04X}"
        elif ord(ch) < 32 or ord(ch) == 127:
            name = f"control U+{ord(ch):04X}"
        else:
            continue
        if name not in seen:
            seen.add(name)
            found.append(name)
    return found


def describe_token_shape(token: str) -> str:
    """Length, contaminant verdict, truncated affixes. Never the whole token."""
    raw = _token_bytes(token)
    contaminants = _contaminants(token)
    if contaminants:
        verdict = "contains " + ", ".join(contaminants)
    else:
        verdict = "clean (no whitespace/newline/control)"
    prefix, suffix = _safe_affixes(raw)
    return (
        f"token shape: {len(raw)} bytes; {verdict}; "
        f"prefix='{prefix}' suffix='{suffix}'"
    )


def check_captured_shape(token: str) -> tuple[bool, str | None]:
    """Shape-only. Does not consume and does not verify HMAC."""
    if not token:
        return False, "minted token is empty — mint produced no stdout (or it was lost)"
    raw = _token_bytes(token)
    if "\n" in token or "\r" in token:
        return False, (
            "minted token contains a newline — something wrote to stdout during mint"
        )
    if any(ord(c) < 32 or ord(c) == 127 for c in token):
        return False, (
            "minted token contains a control character — something wrote to stdout during mint"
        )
    if any(c.isspace() for c in token):
        return False, (
            "minted token contains whitespace — something wrote to stdout during mint"
        )
    lo, hi = _plausible_captured_length_range()
    if not (lo <= len(raw) <= hi):
        return False, (
            f"minted token has implausible length ({len(raw)} bytes) — "
            f"expected {lo}–{hi} for this token scheme"
        )
    return True, None


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
