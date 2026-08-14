/**
 * pay.allnighter.io — Stripe Checkout + machine-hash entitlement.
 *
 * POST /v1/status   { machineHash }
 * POST /v1/checkout { machineHash, plan: monthly|yearly|founding }
 * POST /v1/webhook  Stripe-Signature
 *
 * Secrets (wrangler secret put): STRIPE_SECRET_KEY, STRIPE_WEBHOOK_SECRET,
 * STRIPE_PRICE_MONTHLY, STRIPE_PRICE_YEARLY, STRIPE_PRICE_FOUNDING.
 */

export interface Env {
  DB: D1Database;
  STRIPE_SECRET_KEY?: string;
  STRIPE_WEBHOOK_SECRET?: string;
  STRIPE_PRICE_MONTHLY?: string;
  STRIPE_PRICE_YEARLY?: string;
  STRIPE_PRICE_FOUNDING?: string;
}

const TRIAL_DAYS = 14;
const FOUNDING_CAP = 100;
const HASH_RE = /^[a-f0-9]{16,64}$/;

const PLANS = new Set(["monthly", "yearly", "founding"]);

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    if (request.method === "GET" && url.pathname === "/") {
      return text("Allnighter pay");
    }
    if (request.method === "GET" && url.pathname === "/done") {
      return html(
        "<p>You're in. Return to the CLI and run <code>alln billing --json</code>.</p>"
      );
    }
    if (request.method === "GET" && url.pathname === "/cancel") {
      return html("<p>Checkout cancelled. No charge.</p>");
    }
    if (request.method === "POST" && url.pathname === "/v1/status") {
      return status(request, env);
    }
    if (request.method === "POST" && url.pathname === "/v1/checkout") {
      return checkout(request, env);
    }
    if (request.method === "POST" && url.pathname === "/v1/webhook") {
      return webhook(request, env);
    }
    return text("not found", 404);
  },
} satisfies ExportedHandler<Env>;

async function status(request: Request, env: Env): Promise<Response> {
  const body = await readJSON(request);
  if (!body) return json({ message: "invalid json" }, 400);
  const hash = machineHash(body.machineHash);
  if (!hash) return json({ message: "invalid machineHash" }, 400);

  const now = Date.now();
  await env.DB.prepare(
    `INSERT INTO machines (machine_hash, trial_started_at, plan, created_at, updated_at)
     VALUES (?, ?, 'none', ?, ?)
     ON CONFLICT(machine_hash) DO UPDATE SET updated_at = excluded.updated_at`
  )
    .bind(hash, now, now, now)
    .run();

  const row = await env.DB.prepare(
    `SELECT trial_started_at, plan FROM machines WHERE machine_hash = ?`
  )
    .bind(hash)
    .first<{ trial_started_at: number; plan: string }>();

  if (!row) return json({ message: "machine row missing" }, 500);

  const trialStartedAt = row.trial_started_at;
  const trialEndsAt = trialStartedAt + TRIAL_DAYS * 86400 * 1000;
  const paidPlan = paid(row.plan);
  let plan: string;
  if (paidPlan) plan = row.plan;
  else if (now < trialEndsAt) plan = "trial";
  else plan = "free";

  return json({
    plan,
    paid: Boolean(paidPlan),
    trialStartedAt,
    trialEndsAt,
  });
}

async function checkout(request: Request, env: Env): Promise<Response> {
  const body = await readJSON(request);
  if (!body) return json({ message: "invalid json" }, 400);
  const hash = machineHash(body.machineHash);
  if (!hash) return json({ message: "invalid machineHash" }, 400);
  const plan = typeof body.plan === "string" ? body.plan : "";
  if (!PLANS.has(plan)) {
    return json({ message: "plan must be monthly, yearly, or founding" }, 400);
  }

  const key = env.STRIPE_SECRET_KEY;
  const price = priceId(plan, env);
  if (!key || !price) {
    return json(
      {
        message:
          "Checkout is not configured yet. Create Allnighter Stripe prices and wrangler secret put STRIPE_SECRET_KEY plus STRIPE_PRICE_*.",
      },
      503
    );
  }

  if (plan === "founding") {
    const sold = await foundingSold(env);
    if (sold >= FOUNDING_CAP) {
      return json(
        { message: "Founding Builder is sold out. Use --plan yearly." },
        409
      );
    }
  }

  const origin = new URL(request.url).origin;
  const params = new URLSearchParams();
  params.set("client_reference_id", hash);
  params.set("success_url", `${origin}/done`);
  params.set("cancel_url", `${origin}/cancel`);
  params.set("line_items[0][price]", price);
  params.set("line_items[0][quantity]", "1");
  params.set("allow_promotion_codes", "true");
  params.set("payment_method_collection", "if_required");
  if (plan === "founding") {
    params.set("mode", "payment");
    params.set("customer_creation", "always");
  } else {
    params.set("mode", "subscription");
    params.set("subscription_data[metadata][machine_hash]", hash);
    params.set("subscription_data[metadata][plan]", plan);
  }
  params.set("metadata[machine_hash]", hash);
  params.set("metadata[plan]", plan);

  const stripe = await fetch("https://api.stripe.com/v1/checkout/sessions", {
    method: "POST",
    headers: {
      authorization: `Bearer ${key}`,
      "content-type": "application/x-www-form-urlencoded",
    },
    body: params,
  });
  const textBody = await stripe.text();
  if (!stripe.ok) {
    return json({ message: `Stripe error (${stripe.status})` }, 502);
  }
  let parsed: { url?: string };
  try {
    parsed = JSON.parse(textBody) as { url?: string };
  } catch {
    return json({ message: "Stripe returned invalid json" }, 502);
  }
  if (typeof parsed.url !== "string" || parsed.url.length === 0) {
    return json({ message: "Stripe session missing url" }, 502);
  }
  return json({ url: parsed.url, plan });
}

async function webhook(request: Request, env: Env): Promise<Response> {
  const secret = env.STRIPE_WEBHOOK_SECRET;
  if (!secret) return json({ message: "webhook secret missing" }, 503);
  const payload = await request.text();
  const header = request.headers.get("stripe-signature") ?? "";
  if (!(await verifyStripe(payload, header, secret))) {
    return json({ message: "invalid signature" }, 400);
  }
  let event: {
    type?: string;
    data?: { object?: Record<string, unknown> };
  };
  try {
    event = JSON.parse(payload) as typeof event;
  } catch {
    return json({ message: "invalid json" }, 400);
  }
  if (event.type !== "checkout.session.completed") {
    return json({ received: true });
  }
  const session = event.data?.object ?? {};
  const hash = String(
    session.client_reference_id ??
      (session.metadata as { machine_hash?: string } | undefined)?.machine_hash ??
      ""
  );
  if (!HASH_RE.test(hash)) {
    return json({ message: "missing machine hash" }, 400);
  }
  const metaPlan = (session.metadata as { plan?: string } | undefined)?.plan;
  const mode = session.mode;
  const plan =
    metaPlan && PLANS.has(metaPlan)
      ? metaPlan
      : mode === "subscription"
        ? "monthly"
        : "founding";
  const email =
    typeof session.customer_details === "object" &&
    session.customer_details &&
    "email" in session.customer_details
      ? String((session.customer_details as { email?: string }).email ?? "")
      : "";
  const customerId =
    typeof session.customer === "string" ? session.customer : "";
  const subscriptionId =
    typeof session.subscription === "string" ? session.subscription : "";
  const now = Date.now();

  if (plan === "founding") {
    await env.DB.prepare(
      `UPDATE founding_counter SET sold = sold + 1 WHERE id = 1 AND sold < ?`
    )
      .bind(FOUNDING_CAP)
      .run();
  }

  await env.DB.prepare(
    `INSERT INTO machines (machine_hash, trial_started_at, plan, stripe_customer_id, stripe_subscription_id, paid_at, email, created_at, updated_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
     ON CONFLICT(machine_hash) DO UPDATE SET
       plan = excluded.plan,
       stripe_customer_id = excluded.stripe_customer_id,
       stripe_subscription_id = excluded.stripe_subscription_id,
       paid_at = excluded.paid_at,
       email = excluded.email,
       updated_at = excluded.updated_at`
  )
    .bind(hash, now, plan, customerId, subscriptionId, now, email, now, now)
    .run();

  return json({ received: true });
}

function paid(plan: string): boolean {
  return plan === "monthly" || plan === "yearly" || plan === "founding";
}

function priceId(plan: string, env: Env): string | undefined {
  if (plan === "monthly") return env.STRIPE_PRICE_MONTHLY;
  if (plan === "yearly") return env.STRIPE_PRICE_YEARLY;
  if (plan === "founding") return env.STRIPE_PRICE_FOUNDING;
  return undefined;
}

async function foundingSold(env: Env): Promise<number> {
  const row = await env.DB.prepare(
    `SELECT sold FROM founding_counter WHERE id = 1`
  ).first<{ sold: number }>();
  return row?.sold ?? 0;
}

function machineHash(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const hash = value.trim().toLowerCase();
  return HASH_RE.test(hash) ? hash : null;
}

async function readJSON(request: Request): Promise<Record<string, unknown> | null> {
  const textBody = await request.text();
  try {
    const parsed: unknown = JSON.parse(textBody);
    if (typeof parsed === "object" && parsed !== null) {
      return parsed as Record<string, unknown>;
    }
    return null;
  } catch {
    return null;
  }
}

async function verifyStripe(
  payload: string,
  header: string,
  secret: string
): Promise<boolean> {
  const parts: Record<string, string> = {};
  for (const item of header.split(",")) {
    const idx = item.indexOf("=");
    if (idx === -1) continue;
    parts[item.slice(0, idx).trim()] = item.slice(idx + 1).trim();
  }
  const timestamp = parts.t;
  const v1 = parts.v1;
  if (!timestamp || !v1) return false;
  const ageMs = Math.abs(Date.now() - Number(timestamp) * 1000);
  if (!Number.isFinite(ageMs) || ageMs > 5 * 60 * 1000) return false;
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );
  const sig = await crypto.subtle.sign(
    "HMAC",
    key,
    encoder.encode(`${timestamp}.${payload}`)
  );
  const hex = [...new Uint8Array(sig)]
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
  return hex === v1;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

function text(body: string, status = 200): Response {
  return new Response(body, {
    status,
    headers: { "content-type": "text/plain; charset=utf-8" },
  });
}

function html(body: string): Response {
  return new Response(
    `<!doctype html><meta charset="utf-8"><title>Allnighter</title>${body}`,
    { headers: { "content-type": "text/html; charset=utf-8" } }
  );
}
