# Allnighter iOS — Remote Project Manager (control your Mac from anywhere)

> **This folder is the parked spine for the future iOS companion app.** The MVP
> execution truth lives in `docs/mvp/`; this folder records the architecture, the
> trust model, and the connection spine so iOS can land later without reshaping
> the Mac product.

Status: **Foundation prep may start; iOS product UI remains deferred.** Architecture
decisions are preserved here, but iOS work must not block Mac feature delivery, Mac
proofs, or Mac phase closeout.
Updated: 2026-06-19 (Foundation Slice 0 reset)

---

## 0. The product, in one line

> **Control your Mac's team runs and design boards from your phone — from anywhere,
> securely, with almost no setup.**

A non-developer "vibe coder" on a walk should **sign in, pick their Mac, and go** —
check what it's doing, review design boards, fire off new work, hit the kill switch —
without VPNs, IPs, ports, or networking. The bar is ChatGPT/Codex: *you sign in and it
just works.*

> **The trust promise (the magic):** *Your iPhone can control only the Allnighter
> actions you explicitly allow, only for Macs you pair, with one-tap revoke — and we
> can't read your work (we route only minimized, auto-deleting metadata).* The cloud is
> a **blind relay**; **the Mac is truth and the final authorizer**; typed commands
> only, never a remote shell (`00` §3).

---

## 1. The locked decisions (read `00` for the why)

| Concern | Decision |
| --- | --- |
| **Default connection** | **Cloud-first.** The Mac **dials out** to **Supabase** (control plane); the phone talks to Supabase; the Mac verifies + executes locally. Outbound dial removes NAT/firewall setup — the ChatGPT-bar onboarding. |
| **Media** | **Cloudflare R2** (Standard) — encrypted, transient design-board images; presigned URLs; lifecycle-deleted after hours; **free egress**. The Mac is truth, so R2 is a blind cache, never storage. |
| **Premium path** | **Tailscale "Direct Mode"** — optional, opt-in: phone↔Mac P2P, no relay, no R2. For privacy maximalists, **local-AI users** (avoids re-introducing egress), and media bandwidth. Same trust spine; carrier-swappable. |
| **The Mac's role** | **Router / subscription-proxy, not executor.** The AI runs in vendor clouds; the Mac holds your flat-rate subscription logins. Cloud = blind relay/cache; **Mac = truth.** |
| **Trust model** | **Network is just a cable; Allnighter owns the trust** (`00` §3): **two keys per device/Mac** (Ed25519 signing + X25519 sealing), device-key-signed **typed commands** (no remote shell), **Mac is final authorizer + signs its own events** (a cloud breach can't control *or* deceive a Mac), registry + capabilities, surgical revocation, metadata-only audit. Transport-agnostic. |
| **E2E content (both directions)** | **HPKE** (CryptoKit) seals all sensitive content: outputs/plans/board-images **and the inbound `startRun` prompt** (sealed to the Mac). Large blobs → R2 ciphertext + **per-device** sealed keys. Supabase carries **content-light metadata only**. Breach ⇒ metadata + unopenable blobs. |
| **Sign-in** | **Apple primary** (no new password; Hide-My-Email; App-Store-required if Google offered) + **Google fallback**. Account = identity/discovery; device key + Mac approval = authorization. |
| **CloudKit** | Still **dropped** (Apple-locked, entitlement risk). Supabase is cross-platform + turnkey. **Not Cloudflare-only** for v1 (would mean building auth/realtime/admin ourselves). |
| **Contract** | The `RunEvent` envelope (`../../mvp/00_MVP_Architecture.md` §6) is unchanged — but legacy `synthesis.*` constants must be **frozen to `stage.*`** before the wire locks. |
| **Push** | Deferred iOS-only follow-up in `03`. Specialist SaaS behind a `PushNotifier` seam — **OneSignal likely default, swappable**. Content-light doorbell, no secrets. |

---

## 2. Build order (docs)

```text
00   iOS Architecture & Trust Decision  (cloud-first; trust model; sign-in; E2E)  <- read first
00a  Foundation Slice 0                 (sync, cleanup, hardening before remote code)
01   Connection Spine                   (Supabase control + R2 media + Mac agent + trust + RemoteClient)
01a  Pairing Ceremony                   (sign in -> tap your Mac -> approve once)
02   iOS App Shell                      (onboarding / Home / Active / Design board / kill switch)  [deferred GUI]
03   iOS Thread Read State And Push     (remote unread + mobile push; deferred)
```

> iOS **product/UI** execution starts after the macOS app is done. Foundation-only
> work may start with `00a` when it is limited to shared Core/Engine contracts,
> mock clients, journal/replay hardening, and docs. Pairing (`01a`) is still the
> first trust moment, but it is not a Mac blocker.

[`03_iOS_Thread_Read_State_And_Push.md`](03_iOS_Thread_Read_State_And_Push.md)
owns remote unread state and mobile push. Do not put that acceptance burden back
on Mac thread docs.

### Known pre-reqs (do not skip)

1. **The remote agent/server doesn't exist.** `alln serve` now exists as a resident
   coordinator/health/wake skeleton, but `01` still must build the **outbound Mac
   agent** (cloud) and the command/event HTTP/WS surface used by Direct Mode.
2. **Run durability is partial.** `RunStore` now writes non-terminal snapshots and
   owner markers with orphan recovery, but resume still needs an append-only event
   journal + persisted monotonic `seq` (`01` § Event durability) — Mac journal =
   truth, cloud mirror = transient.
3. **Freeze the event vocabulary** (`synthesis.*` → `stage.*`) before the wire locks.
4. **Do not build on the SwiftData template.** The current
   `Apps/AllnighteriOS/` project is still the starter scaffold (`Item.swift`,
   persistent `ModelContainer`, hand-managed `.xcodeproj`). `00a` quarantines it;
   `02` deletes/replaces it when UI work starts.
5. **Do not depend on unfinished Project Manager UX.** PRJ-S00-S06 are built, but
   PRJ-S07-S13 are still moving. Foundation can expose typed team-run commands and
   snapshots; phone-as-Project-Manager surfaces wait.

---

## 3. Why this is not a box

- **Transport-agnostic trust spine.** The `RunEvent` contract + the trust model are
  the durable core; cloud relay and Tailscale Direct are swappable carriers under it.
  We're choosing the pipe, not rewriting the contract.
- **Not boxed into Apple.** Supabase + R2 keep Android/web possible later; Sign in
  with Apple is the primary button, not the only door.
- **Blind by design.** A breach of Supabase + R2 yields routing metadata + ciphertext
  — never control of a Mac (commands need a device key the cloud never holds) and
  never readable work (E2E sealed keys).

---

## 4. How to execute (rules — inherits `docs/mvp/README.md` §7)

1. **The Mac is truth and the final authorizer.** The cloud is a blind, transient
   relay/cache; the Mac re-verifies every command regardless of what the cloud passes.
2. **Contract-first.** Any new wire/DB shape starts in `AllnighterCore` with
   round-trip tests + fixtures, never only in view code.
3. **Reuse the contract, build the agent.** The `00`/§6 event *envelope* is fixed; the
   outbound Mac agent + cloud schema + journal must be built (`01`).
4. **Two layers, always.** Account (sign-in) for identity/discovery **and** device
   key + one-tap Mac approval for authorization. Never one alone.
5. **Content-light cloud + E2E content.** Supabase carries metadata only; sensitive
   content (outputs, plans, board images) is end-to-end encrypted by reference. The
   cloud must never see plaintext work.
6. **Honesty.** "Mac asleep / agent-off / signed-out" are distinct states; on
   reconnect the client resumes by `seq` and loses no events — never fakes liveness.
7. **Cloud is never durable product storage.** TTL everything; the Mac stays truth.
   The moment we keep user data "to be helpful," we've become a different company.
