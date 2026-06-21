"""MCP stdio client using Content-Length framing (matches MCPServer/FrameReader)."""
from __future__ import annotations

import json
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


class MCPStdioClient:
    def __init__(self, proc: subprocess.Popen[bytes], transcript_path: Path | None = None):
        self.proc = proc
        self.req_id = 0
        self.transcript_path = transcript_path

    def _log(self, entry: dict[str, Any]) -> None:
        if not self.transcript_path:
            return
        entry = {"ts": datetime.now(timezone.utc).isoformat(), **entry}
        with self.transcript_path.open("a") as f:
            f.write(json.dumps(entry) + "\n")

    def _read_frame(self) -> dict[str, Any] | None:
        assert self.proc.stdout is not None
        headers: dict[str, str] = {}
        while True:
            line = self.proc.stdout.readline()
            if not line:
                return None
            line = line.rstrip(b"\r\n")
            if line == b"":
                break
            decoded = line.decode("ascii", errors="replace")
            if ":" in decoded:
                k, v = decoded.split(":", 1)
                headers[k.strip().lower()] = v.strip()
        length = int(headers.get("content-length", "0"))
        if length <= 0:
            return None
        body = self.proc.stdout.read(length)
        if len(body) < length:
            return None
        return json.loads(body)

    def _write_frame(self, payload: dict[str, Any]) -> None:
        assert self.proc.stdin is not None
        body = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        header = f"Content-Length: {len(body)}\r\n\r\n".encode("ascii")
        self.proc.stdin.write(header + body)
        self.proc.stdin.flush()

    def request(self, method: str, params: dict[str, Any] | None = None) -> dict[str, Any]:
        self.req_id += 1
        msg: dict[str, Any] = {"jsonrpc": "2.0", "id": self.req_id, "method": method}
        if params is not None:
            msg["params"] = params
        self._log({"direction": "request", "method": method, "id": self.req_id, "params": params})
        self._write_frame(msg)
        while True:
            resp = self._read_frame()
            if resp is None:
                raise RuntimeError("MCP server closed stdout")
            self._log({"direction": "response", **resp})
            if resp.get("id") == self.req_id:
                if "error" in resp:
                    raise RuntimeError(f"MCP error: {resp['error']}")
                return resp.get("result") or {}

    def notify(self, method: str, params: dict[str, Any] | None = None) -> None:
        msg: dict[str, Any] = {"jsonrpc": "2.0", "method": method}
        if params is not None:
            msg["params"] = params
        self._log({"direction": "notify", "method": method, "params": params})
        self._write_frame(msg)

    def call_tool(self, name: str, arguments: dict[str, Any]) -> dict[str, Any]:
        result = self.request("tools/call", {"name": name, "arguments": arguments})
        return parse_tool_result(result)

    def close(self) -> None:
        try:
            if self.proc.stdin:
                self.proc.stdin.close()
        except Exception:
            pass
        try:
            self.proc.terminate()
        except Exception:
            pass
        try:
            self.proc.wait(timeout=10)
        except Exception:
            try:
                self.proc.kill()
            except Exception:
                pass


def parse_tool_result(result: dict[str, Any]) -> dict[str, Any]:
    if result.get("isError"):
        content = result.get("content", [])
        text_parts = [c.get("text", "") for c in content if c.get("type") == "text"]
        msg = "\n".join(text_parts).strip() or "MCP tool error"
        raise RuntimeError(msg)
    content = result.get("content", [])
    text_parts = [c.get("text", "") for c in content if c.get("type") == "text"]
    structured = None
    sc = result.get("structuredContent")
    if isinstance(sc, dict) and isinstance(sc.get("json"), str):
        try:
            structured = json.loads(sc["json"])
        except json.JSONDecodeError:
            pass
    if structured is None:
        for c in content:
            if c.get("type") != "text":
                continue
            text = (c.get("text") or "").strip()
            if text.startswith("{"):
                try:
                    structured = json.loads(text)
                    break
                except json.JSONDecodeError:
                    pass
    return {"raw": result, "text": "\n".join(text_parts), "structured": structured}


def parse_tool_json(call: dict[str, Any]) -> dict[str, Any]:
    if call.get("structured"):
        return call["structured"]
    text = (call.get("text") or "").strip()
    for line in text.splitlines():
        line = line.strip()
        if line.startswith("{"):
            return json.loads(line)
    raise ValueError(f"Could not parse tool JSON from: {text[:500]}")
