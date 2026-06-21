# 00 — iOS Architecture & Trust Decision (read first)

Status: **Locked architecture; foundation prep may start; iOS product UI remains
deferred.** Every iOS doc obeys this one.
Milestone: iOS (Remote Project Manager)
Owner: Founder
Created: 2026-06-15
Updated: 2026-06-19 (Foundation Slice 0 reset)
Depends on: `../../mvp/00_MVP_Architecture.md` §4/§6/§9, `../../mvp/RB6_Team_As_Tool.md`

> This fixes *how* the phone reaches the Mac and *how trust works*, so no later iOS
> phase re-decides it. **Major revision:** the default path is now a **cloud relay
> (Supabase + Cloudflare R2)**, not Tailscale. Tailscale survives as an **optional
> premium "Direct Mode."** The earlier Tailscale-first drafts are superseded by this
> file; the trust model they established is **transport-agnostic and carries over
> unchanged** — that is exactly why the pivot is additive, not a rewrite.

> **2026-06-19 reset:** start with `00a_iOS_Foundation_Slice_0.md`, not app UI.
> The shared foundation can be prepared now because the `alln`/Core contract is
> stable enough to harden locally. The phone product shell still waits for the Mac
> Project Manager surface and `01` remote spine to settle.

---

## 1. The goal that forces this decision

The killer feature is **controlling the Mac from anywhere, with almost no setup.**
The ICP is **a non-developer "vibe coder."** Their bar is set by the tools they
already love:

> They sign into ChatGPT + Codex, it works with their Mac, and **nobody ever asked
> them about VPNs, IPs, or networking.** That is the bar.

So the connection must be:
- **Easy** — "sign in, pair, walk away," not "configure a remote server." If setup
  is hard, this ICP drops off before seeing value.
- **Secure enough to trust with remote control of a Mac** from the open internet.
- **Cheap to operate** for a solo founder pre-users.

---

## 2. The decision: cloud-first (Supabase + R2) default; Tailscale = premium Direct Mode

### 2.1 Why cloud-first (the connection direction is the whole trick)

Every consumer app that "just works from anywhere" (Slack, ChatGPT, your
thermostat) works because the device **dials out** to a cloud. Outbound
connections traverse NAT/firewalls with **zero user config**. Requiring the phone
to reach *into* the Mac (the Tailscale model) creates a networking problem the user
must solve — and Tailscale, even at its best, still needs an **install + account +
same-account-on-both**, which we could never reduce to a tap. That irreducible
friction was the signal the *architecture*, not the onboarding, was wrong for this
ICP.

```text
iPhone app  ─────────────┐                         ┌──► Anthropic / OpenAI / xAI /
                         Supabase (control plane)   │    Gemini / Aider / Cursor / …
Mac agent  ──dials OUT──► command inbox + events ───┘    (where the AI actually runs)
   holds the subscription CLI logins (the reason a Mac must exist)
   subscribes to its inbox, VERIFIES every command, executes locally, SIGNS events back
                         Cloudflare R2 (media plane)
                         encrypted, transient board images
```

### 2.2 The Mac's real role: it is the *router/subscription-proxy*, not the executor

The AI does **not** run on the Mac. `claude -p`, `codex`, `grok` are thin local
clients that send prompts to the **vendor clouds** and stream answers back. The
Mac's irreplaceable job is to hold your **interactive subscription logins**, so you
invoke those clouds at **flat-rate (subscription) instead of metered (API key)** —
the whole zero-marginal-cost arbitrage. You cannot run those logged-in CLIs from a
server; that is why a Mac must be in the loop at all.

Consequence: a "nothing ever leaves your Mac" purity stance was always fiction —
your work already crosses the internet to three vendor clouds on every run. So
adding **one blind, end-to-end-encrypted Allnighter relay is on-brand**, not a
privacy betrayal. **The Mac stays the source of truth; the cloud is a blind
relay/cache.**

### 2.3 The two planes

| Plane | Carrier | Carries | Why |
| --- | --- | --- | --- |
| **Control** | **Supabase** (Auth, Postgres, RLS, Realtime) | signed/encrypted command envelopes + light event metadata | Turnkey Apple/Google auth, RLS, realtime subscriptions, dashboard/debuggability — the hard product substrate, ready now. |
| **Media** | **Cloudflare R2** (Standard class) | encrypted, transient design-board images; presigned URLs; lifecycle-deleted after hours | **Free egress** is the cost lever for image delivery; the Mac is truth so the cloud copy is a short-lived cache, not storage. |

We are **not** Cloudflare-only for v1: that means hand-rolling consumer auth, the
device/account model, realtime semantics, admin/debug, and abuse handling — i.e.
becoming an infra company. Supabase gives that immediately. (Revisit Cloudflare-only
only at real scale, with a team — never as a solo founder shipping v1.)

### 2.4 Connection modes (one trust spine, swappable carrier)

```text
cloudRelay     (DEFAULT)  Mac dials out to Supabase; phone <-> Supabase; media via R2
tailscaleDirect (PREMIUM) phone <-> Mac P2P over the user's tailnet; NO relay, NO R2
loopback        (dev/local) RB6 bearer on 127.0.0.1
```

The `RemoteClient` (`01`) abstracts the mode. **The trust model, the `RunEvent`
contract, the registry, the command set, revocation, and audit are identical across
modes** — only the carrier differs. The old Tailscale "serve/loopback exposure"
design is not wasted; it **becomes the implementation of `tailscaleDirect`**.

### 2.5 Tailscale Direct Mode — kept as premium, not killed

Tailscale is no longer the default, but it earns its place as an **opt-in premium
path for users who deeply care about privacy/security** — and there are real
*functional* reasons, not just ideological ones:

1. **Local AI (the cleanest future-proof).** Within 1–2 years many devs run local
   models on Mac Studios. When inference is **local**, the work never leaves the
   machine — routing it through *our* cloud relay would **reintroduce egress they
   deliberately eliminated**. Direct Mode preserves "nothing leaves my Mac" for that
   cohort. Cloud-relay is fine *because* today the work already goes to vendor
   clouds; the moment that stops (local models), the relay's free pass expires.
2. **Media bandwidth.** Design-board images (and any future heavy artifacts) flow
   P2P in Direct Mode — cheaper, faster, never touching our infra or R2.
3. **Privacy/security maximalists** who want zero third-party relay at all.

Convenience usually wins, so **cloud is the default for everyone; Direct Mode is the
premium opt-in.** The carrier abstraction (§2.4) makes shipping it later additive.

---

## 3. Trust model — the network is just a cable; Allnighter owns the trust

This survives the pivot unchanged (it was always transport-agnostic). The cloud is
**dumb, blind, and never trusted to invent commands.** The Mac is the **final
authorizer.**

1. **Account ≠ authorization.** Sign-in (§5) does identity/discovery/routing only.
2. **Device keys are the truth — two per device** (signing ≠ sealing). At pairing the
   phone generates an **Ed25519 signing key** (`Curve25519.Signing`, for command auth)
   **and an X25519 sealing key** (`Curve25519.KeyAgreement`, to *receive* sealed
   content) — private keys in iOS Keychain. The Mac pins both pubkeys and explicitly
   **approves** the device. The Mac agent likewise has its own signing + sealing
   keys. `deviceId` is only a hint; the verifying key is resolved from the Mac's own
   registry. (You cannot seal/encrypt to a signing key — hence two keys. Crypto
   contract in `01`.)
3. **Every command is signed** by the device signing key over `deviceId|method|
   requestId|timestamp|protocolMajor|kind|sha256(payload)`. The Mac verifies:
   *approved & unrevoked? signature matches the pinned key? fresh (non-replayed)
   requestId? allowed kind? valid payload?* — then executes. ±60s skew window;
   distinct `clockSkew` error returns the Mac's `serverTime` so the phone re-syncs.
4. **The Mac also SIGNS what it sends back** (events/acks, `agentSigningPubkey`), so a
   cloud row-injection can't *fabricate* run state — only be dropped, not forged.
5. **Cloud breach cannot control *or* deceive a Mac.** Commands need a device key the
   cloud never holds; events are Mac-signed; the Mac re-verifies everything. A breached
   Supabase/R2 yields **minimized routing metadata + ciphertext — never control,
   never readable work.**
6. Plus: requestId dedupe (window = the ±60s skew window), per-device rate limits +
   size caps, surgical per-device revocation teardown, metadata-only audit, and
   protocol-version negotiation (all in `01`).

### 3.1 Typed commands only — never a remote shell (load-bearing invariant)

The phone sends a **closed enum** (`startRun`, `stopRun`, `stopAll`). **There is no generic
"run this on my Mac" pathway, and there never will be.** This is the security floor
*and* the reason a non-developer feels safe enabling remote control. (Also: do not
expose a generic MCP server to iOS — iOS sends typed Allnighter commands; the Mac
translates locally to MCP/tool calls. A remote MCP god-token is "remote shell by
another name.")

### 3.2 End-to-end encryption — both directions, all sensitive content

Not just images: **every sensitive payload is sealed**, inbound and outbound, via
one primitive — **HPKE (RFC 9180) in `CryptoKit`** (DHKEM-X25519 · HKDF-SHA256 ·
AES-GCM-256), sealed to the recipient's **sealing** (X25519) key.

- **Outbound (Mac → phone):** outputs, plans, board images, stage markdown are
  sealed to each approved device's `deviceSealingPubkey`. Large blobs go to R2 as
  **ciphertext** (per-blob content key, presigned PUT, R2 Standard, TTL-deleted); the
  content key is sealed **per device** (one ciphertext, N sealed keys). The phone
  unseals, fetches ciphertext (R2 free egress), decrypts locally. **Direct Mode
  bypasses R2** (P2P).
- **Inbound (phone → Mac):** the highest-sensitivity item is the **`startRun` prompt**
  — it is sealed to the Mac's `agentSealingPubkey` **before** it touches
  `command_inbox`. The Mac decrypts only after verifying the signature. Without this,
  Supabase would see the union of everything the user types — the honeypot on the
  inbound side.
- **The control plane is content-light:** Supabase carries metadata only; sensitive
  fields are sealed by reference. A full breach of Supabase **and** R2 yields
  ciphertext + sealed keys the attacker can't open.

> **Why this matters *most*:** each vendor sees only its slice of your work; an
> Allnighter relay could otherwise see the **union** across all vendors — the most
> sensitive vantage in the system. Route everything; read nothing.

### 3.3 Mac reachability posture (resolving "fire off work from a walk" vs. sleep)

A sleeping Mac won't wake from a Supabase Realtime push, so a queued `startRun` would
just wait. We resolve this honestly, with consent:

- A user-consented **"Keep my Mac available for remote work"** setting. **On**
  (default for desktops; an explicit, battery-caveated opt-in for laptops) holds a
  power assertion while the agent is connected/running so queued work runs promptly —
  this is what makes "fire off work from a walk" real.
- **Off / laptop on battery:** the Mac may sleep; commands queue and **drain on next
  wake** (the agent polls — delivery is **at-least-once**, `01`). The phone shows
  honest **"your Mac is asleep — work starts when it wakes" / "asleep, last seen X"**
  states; nothing is lost, nothing is faked.
- Either way the **kill switch** is reliable via the poll backstop (`01`).

---

## 4. Honesty & secrets posture

- **Secrets never leave the Mac.** Subscription CLI auth lives only on the Mac; the
  MVP holds no model API keys (`../../mvp/00_MVP_Architecture.md` §9). iOS sends
  typed commands; the Mac executes.
- **The cloud is a blind relay/cache, never product storage.** R2 objects are
  transient (TTL); the Mac is truth. The moment we keep user data durably "to be
  helpful," we've become a different, less-private company — hold that line.
- **Never fake liveness.** "Mac asleep / unreachable / server-off" are distinct,
  honest states (`01`), not a generic "offline."
- **Precise privacy claims (brand is trust → be exact).** Say **"we can't read your
  work — we see minimized, TTL'd routing metadata"**, not "we never see anything."
  Content is E2E-sealed; but Supabase still sees behavioral metadata (run cadence,
  counts, kinds, timing, how many Macs). The precise claim is the stronger one.
- **Revocation is forward-only.** It stops *future* access; content a device already
  unsealed cannot be recalled (inherent to E2E). Say so.

---

## 5. Sign-in: Apple primary, Google fallback

- **Sign in with Apple, out of the box.** Zero new credentials (no email/password),
  "Hide My Email" matches our privacy posture, and the App Store effectively
  **requires** Sign in with Apple if we also offer a social login (Google). Make it
  the primary button.
- **Google as fallback** — for the Mac side, non-Apple users, and a future
  Android/web client. Supabase Auth supports both natively (configuration, not
  custom auth).
- **Layering:** account (Apple/Google) = identity + discovery + routing (sign into
  the same account on both → the phone *sees* your Macs). **Device key + one-tap Mac
  approval = authorization** (a leaked password still can't control a Mac). This
  also **eliminates the old #1 failure mode** — "same Apple ID" replaces "same
  tailnet," which every non-developer already understands.

---

## 6. What this changes / deletes

| Killed or demoted | Replaced by |
| --- | --- |
| Tailscale as the **required** path | **cloud relay default**; Tailscale = optional premium Direct Mode (§2.5) |
| "Server bound to the tailnet" as the only model | Mac **dials out** to Supabase (cloud mode); the loopback server + `tailscale serve` is now the **Direct Mode** implementation |
| "We run zero infra / nothing leaves your Mac" | We run a **blind, E2E relay** (Supabase + R2); honest framing: the Mac already routes to vendor clouds (§2.2) |
| CloudKit (earlier round) | still dropped — Apple-locked, entitlement risk; Supabase is cross-platform and turnkey |
| Bonjour / pinned-TLS / bespoke LAN relay (earlier rounds) | still deleted |

---

## 7. Push (deferred seam — not v1)

Background "your lane finished — come review" pings need a push specialist behind a
thin **`PushNotifier`** seam — **OneSignal likely default, swappable** (Ably/FCM).
**Not in v1**: live updates flow over the active connection (Supabase Realtime in
cloud mode) while the app is open. Push is a content-light doorbell carrying no
secrets (data fetched over the encrypted path).

---

## 8. Decision log

| Date | Decision | Note |
| --- | --- | --- |
| 2026-06-15 | **Cloud-first default: Supabase (control + auth + realtime) + Cloudflare R2 (encrypted transient media). Mac dials OUT.** | The ChatGPT/Codex bar for a non-developer ICP; outbound dial removes NAT; the Mac already routes to vendor clouds so a blind E2E relay is on-brand. |
| 2026-06-15 | **Tailscale demoted from default to optional premium "Direct Mode."** Not killed. | Earns its keep for local-AI (avoids re-introducing egress), media bandwidth, and privacy maximalists. Carrier abstraction makes it additive. |
| 2026-06-15 | **The Mac is the router/subscription-proxy, not the executor; cloud is a blind relay/cache; Mac is truth.** | The AI runs in vendor clouds; the Mac holds the flat-rate subscription logins. |
| 2026-06-15 | **Trust spine is transport-agnostic and carries over unchanged:** typed commands only (no remote shell), device-key-signed, Mac as final authorizer, requestId dedupe, rate limits, revocation teardown, metadata-only audit. | A cloud breach yields metadata + ciphertext — never control, never readable work. |
| 2026-06-15 | **E2E media: per-image content key → R2 ciphertext; key sealed to the device pubkey via the control plane; DB stores `sealedKeyForDevice`, never the raw key. R2 Standard (not IA).** | Breach of Supabase+R2 = unopenable blobs. R2 free egress + TTL ≈ $0. |
| 2026-06-15 | **Sign in with Apple (primary, Hide-My-Email; App-Store-required if Google offered) + Google (fallback).** Account = identity/discovery; device key + approval = authorization. | Eliminates the old "same tailnet" failure mode → "same Apple ID." Supabase Auth supports both. |
| 2026-06-15 | **Not Cloudflare-only for v1.** | All-Cloudflare means hand-rolling auth/device-model/realtime/admin — becoming an infra company. Revisit only at real scale with a team. |
| 2026-06-15 | **Cloud is a transient, blind cache — never durable product storage.** | The discipline that keeps the pivot a pure friction-win and not an identity change. |
| 2026-06-15 (hardening) | **Two keys per device + per Mac (Ed25519 signing + X25519 sealing); HPKE for all sealing; sealing both directions (incl. the `startRun` prompt → Mac); Mac signs events.** | Round-4 review: can't seal to a signing key; the inbound prompt is the most sensitive payload; signed events stop cloud forgery. |
| 2026-06-15 (hardening) | **Mac reachability is a consented "Keep available for remote work" setting; otherwise sleep + queue + at-least-once drain on wake.** (§3.3) | Reconciles "fire work from a walk" with physics + laptop battery, honestly. |
| 2026-06-15 (hardening) | **Same-account-different-provider is a first-class diagnosed failure** (`01` RemoteDoctor); **`validUntil` is long-lived (~1yr) with explicit re-approval**; **`stopAll` is never capability-gated**; **iOS min 17.2**; **kill-switch + all commands at-least-once (poll + push)**; **snapshot includes recently-completed runs**. | Top real-world drop-offs / safety floors surfaced by 4 mentors. |
| 2026-06-15 (hardening) | **Honesty: "can't read your work *but* see minimized TTL'd metadata"; revocation is forward-only.** Drop "AirDrop-class" framing (proximity ≠ our model). | Trust brand demands the precise claim. |

> Append a row whenever a phase changes a locked decision here.
