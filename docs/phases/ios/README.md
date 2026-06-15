# Allnighter iOS — Remote Floor Manager (control your Mac from anywhere)

> **This folder is the design spine for the iOS companion app.** It is a
> deferred, *designed-for* follow-on to the MVP — not the next thing built. The
> MVP execution truth lives in `docs/mvp/`; this folder records the transport
> decision and the connection spine so iOS lands without reshaping anything.

Status: **Spine finalized (post 6-mentor review).** The **connection spine (`01`)
is buildable in parallel** with the Mac MVP once its dependencies land; the **GUI
(`02`) is deferred.** Mac MVP ships first.
Updated: 2026-06-15

---

## 0. The product, in one line

> **Control your Mac's council and lanes from your phone — from anywhere,
> securely, with almost no setup.**

A vibe coder out for a walk should be able to open Allnighter on their phone,
see what their Mac is doing, review finished lanes, fire off new work requests,
and hit the kill switch — without being on the same wifi, without exposing their
Mac to the internet, and without trusting a server we run.

**LAN-only is explicitly dead.** The killer advantage is *from anywhere*. The old
roadmap's LAN-first transport (`../ON HOLD/08_Transport_And_Pairing.md`) and
custom VPS relay (`../ON HOLD/20_Relay_And_Push.md`) are superseded by this
folder — see `00_iOS_Transport_Decision.md` for exactly what is deleted.

---

## 1. The locked decisions (read `00` for the why)

| Concern | Decision |
| --- | --- |
| **Connection** | **Tailscale** over the user's own private tailnet, encrypted end-to-end, from anywhere. Zero infra for us. (Say "private Tailscale connection," not "direct P2P" — `00` §2.) |
| **Binding** | **Prefer `tailscale serve`** (server stays on `127.0.0.1`, auto TLS, no interface logic); plain-HTTP bind to the tailnet IP is the fallback. (`00` §2.5) |
| **CloudKit** | **Dropped.** Buggy, Apple-locked (we may want Android/web later), entitlement risk on a non-App-Store Mac app. |
| **Bespoke transport** | **Deleted.** Bonjour discovery, hand-rolled pinned-TLS, the custom VPS relay (old `08`/`20`) — all replaced by Tailscale. |
| **Authorization** | **App-level device pairing on top of Tailscale.** Tailnet membership is not enough; the Mac approves each device, and every request carries a hardened Ed25519 assertion (signed body + requestId dedup + ±60s skew). |
| **Server** | **Must be built — RB6-S08 was never completed** (verified: no `serve`/HTTP/WS in-tree). `01` lands the loopback server + an **event journal for resume**, then exposes it on the tailnet. Not "reuse what exists." |
| **Contract** | The `RunEvent` envelope from `../../mvp/00_MVP_Architecture.md` §6 is unchanged — but the legacy `synthesis.*` constants must be **frozen to `stage.*`** before the wire locks. |
| **Push** | Specialist SaaS behind a thin `PushNotifier` seam — **OneSignal likely default, fully swappable** (Ably/FCM drop in). **Not in v1** — live updates flow over Tailscale while the app is open. Content-light "doorbell" only; data fetched over Tailscale. |

---

## 2. Build order (docs)

```text
00  iOS Transport Decision   (locks Tailscale; binding+TLS; what we delete; security posture)  <- read first
01  Connection Spine         (build the server + event journal -> tailnet + pairing + RemoteClient)
02  iOS App Shell            (onboarding + Home / Active / Review / new-work / kill switch)  [deferred GUI]
```

`03_Push.md` is intentionally not written yet — push is a deferred seam noted in
`00` § Push. Write it when background notifications are actually built.

### Known pre-reqs surfaced by the mentor review (do not skip)

1. **The server doesn't exist.** Finish RB6-S08 (loopback HTTP/WS) as part of `01`
   — the "reuse RB6's server" framing was wrong; it was never built.
2. **Events aren't durable.** `RunEvent` is in-memory; resume needs an event
   journal + persisted monotonic `seq` (`01` § Event durability).
3. **Freeze the event vocabulary** (`synthesis.*` → `stage.*`) before the wire locks.
4. **Delete the SwiftData template** at `Allnighter/Allnighter.xcodeproj`; stand up
   `Apps/AllnighteriOS/` via XcodeGen (`02` pre-req).

---

## 3. Why this is not a box

- **The contract is transport-agnostic.** The event stream is the durable spine;
  Tailscale, a relay, or a mesh VPN are swappable pipes under it. We are choosing
  the pipe, not rewriting the contract.
- **Not boxed into Apple.** Dropping CloudKit keeps an Android/web client possible
  later; the same Tailscale + WebSocket spine serves any client.
- **No infra, no liability.** Each user's own tailnet carries the traffic; we run
  no servers and hold no user data. The push doorbell (later) carries no secrets.

---

## 4. How to execute (rules — inherits `docs/mvp/README.md` §7)

1. **The Mac stays the source of truth.** The phone is a resilient client; no
   durable run truth lives on the device (carried from `WORKING_RULES.md`).
2. **Contract-first.** Any new wire shape starts in `AllnighterCore` with
   round-trip tests + fixtures, never only in view code.
3. **Reuse the contract, build the server.** The `00` event *envelope* is fixed —
   if a change would alter the event shapes, stop (that breaks the seam). But the
   server itself must be built (RB6-S08) with a durable event journal; don't
   assume it exists.
4. **Two security layers, always.** Tailscale (encrypted transport + network
   isolation) *and* app-level device approval (authorization). Never one alone.
5. **Honesty.** A dropped connection shows as disconnected; on reconnect the
   client resumes with `?since=<seq>` and loses no events — never fakes liveness.
