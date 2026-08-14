/**
 * feedback.allnighter.io — postcard inbox.
 *
 * POST /  { message, binaryVersion, os }
 * Forwards to WEBHOOK_URL (Discord `content` or Slack `text`) and/or emails
 * the verified support mailbox via the Email Routing send_email binding.
 * Never stores the message.
 *
 * Secrets: WEBHOOK_URL (optional if EMAIL is bound).
 */

import { EmailMessage } from "cloudflare:email";

const MAIL_FROM = "feedback@allnighter.io";
const MAIL_TO = "support@happymooseapps.com";

export interface Env {
  WEBHOOK_URL?: string;
  EMAIL?: { send: (message: EmailMessage) => Promise<void> };
}

const MAX_MESSAGE = 2000;
const MAX_FIELD = 80;
const MAX_BODY = 8_192;

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    if (request.method === "GET" && url.pathname === "/") {
      return json({ ok: true, service: "allnighter-feedback" });
    }
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: cors() });
    }
    if (request.method !== "POST" || url.pathname !== "/") {
      return json({ message: "not found" }, 404);
    }

    const raw = await request.text();
    if (raw.length > MAX_BODY) return json({ message: "payload too large" }, 413);

    let body: Record<string, unknown>;
    try {
      const parsed: unknown = JSON.parse(raw);
      if (typeof parsed !== "object" || parsed === null) {
        return json({ message: "invalid json" }, 400);
      }
      body = parsed as Record<string, unknown>;
    } catch {
      return json({ message: "invalid json" }, 400);
    }

    const message = field(body.message, MAX_MESSAGE);
    const binaryVersion = field(body.binaryVersion, MAX_FIELD);
    const os = field(body.os, MAX_FIELD);
    if (!message || !binaryVersion || !os) {
      return json({ message: "message, binaryVersion, and os are required" }, 400);
    }

    const text = `Allnighter feedback (${binaryVersion}, ${os})\n\n${message}`;
    const webhook = env.WEBHOOK_URL?.trim();
    let delivered = false;
    const errors: string[] = [];

    if (webhook) {
      try {
        const payload = webhook.includes("discord.com")
          ? { content: text.slice(0, 1900) }
          : { text, content: text.slice(0, 1900) };
        const res = await fetch(webhook, {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify(payload),
        });
        if (res.ok) delivered = true;
        else errors.push(`webhook ${res.status}`);
      } catch (err) {
        errors.push(`webhook ${String(err)}`);
      }
    }

    if (env.EMAIL) {
      try {
        const mime = [
          `From: Allnighter CLI <${MAIL_FROM}>`,
          `To: ${MAIL_TO}`,
          `Subject: CLI feedback (${binaryVersion})`,
          "MIME-Version: 1.0",
          "Content-Type: text/plain; charset=utf-8",
          "Content-Transfer-Encoding: 8bit",
          "",
          text,
        ].join("\r\n");
        await env.EMAIL.send(new EmailMessage(MAIL_FROM, MAIL_TO, mime));
        delivered = true;
      } catch (err) {
        errors.push(`email ${String(err)}`);
      }
    }

    if (!delivered) {
      return json(
        {
          message:
            errors.length > 0
              ? "could not deliver"
              : "inbox is not configured",
        },
        503
      );
    }
    return json({ ok: true });
  },
} satisfies ExportedHandler<Env>;

function field(value: unknown, max: number): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  if (!trimmed || trimmed.length > max) return null;
  return trimmed;
}

function json(value: unknown, status = 200): Response {
  return new Response(JSON.stringify(value), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", ...cors() },
  });
}

function cors(): Record<string, string> {
  return {
    "access-control-allow-origin": "*",
    "access-control-allow-methods": "POST, GET, OPTIONS",
    "access-control-allow-headers": "content-type",
  };
}
