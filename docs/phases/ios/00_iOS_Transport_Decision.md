# 00 — iOS Transport Decision (read first)

Status: **Locked for iOS.** Every iOS doc obeys this one.
Milestone: iOS (Remote Floor Manager)
Depends on: `../../mvp/00_MVP_Architecture.md` §5/§6/§10, `../../mvp/RB6_Council_As_Tool.md`
Owner: Founder
Created: 2026-06-15

> This fixes *how* the phone reaches the Mac so no later iOS phase re-decides it.
> It supersedes the LAN-first transport of `../ON HOLD/08_Transport_And_Pairing.md`
> and the custom relay of `../ON HOLD/20_Relay_And_Push.md`.

---

## 1. The goal that forces this decision

The killer advantage of the iOS app is **controlling the Mac from anywhere** —
not on the same wifi. A vibe coder on a walk checks in, reviews finished lanes,
sends new work requests, and can hit the kill switch. So:

- **LAN-only is dead.** A same-network remote is not the product.
- The connection must be **easy** (the audience installs ChatGPT/Codex — a
  one-time setup is fine, fragile per-network config is not),
- **secure enough to trust with code execution on your Mac from the open
  internet**, and
- **cheap to operate** (solo founder, pre-users — ideally zero infra we run).

---

## 2. The decision: Tailscale (P2P WireGuard)

The phone and Mac join the **user's own private tailnet**. The phone reaches the
Mac over WireGuard — encrypted end to end, NAT traversal handled, reachable from
anywhere. We run **zero servers**.

> **Honesty note (product copy):** say "a **private Tailscale connection** to your
> Mac," not "direct peer-to-peer." Tailscale prefers a direct path but falls back
> to its own **encrypted DERP relays** when NAT/firewalls block one. Traffic stays
> end-to-end encrypted and unreadable by Tailscale or us in both cases — but the
> word "direct" is not always literally true, and our honesty rule forbids
> implying a guarantee we don't control.

### Why Tailscale wins (and why it is the *more* secure choice, not a shortcut)

1. **It is the trust story.** WireGuard is the audited, modern VPN protocol. The
   pitch to a user is "we use the zero-trust networking tech companies trust,"
   not "trust the little server I wrote." Rolling our own encrypted relay would
   mean hand-building key exchange, identity, and replay protection for a path
   that *executes code on the user's Mac* — exactly the thing easy to get subtly
   wrong. Tailscale already solved and audited it.
2. **The Mac is never on the public internet.** The app's server binds to the
   **tailnet interface only** — invisible to everyone except the user's own
   devices, even on the same coffee-shop wifi. No port forwarding, no exposed
   ports, no certificates to manage.
3. **End-to-end encrypted, device-to-device.** Tailscale's coordination server
   brokers keys but **cannot read traffic** (direct when possible, encrypted DERP
   relay as fallback — never readable by Tailscale or us).
4. **Not our infrastructure.** Each user connects *their own* devices on *their
   own* tailnet. Zero servers for us, zero user data held by us, no scaling cost,
   strong privacy pitch.
5. **Not boxed into Apple.** Unlike CloudKit, the same Tailscale + WebSocket spine
   serves a future Android/web client.

### The honest cost (accepted — and bigger than "install an app")

The friction is real and the onboarding must treat it as a guided flow, not a
toggle. Spelled out so nobody under-scopes it:

- **It's an account, not just an install.** A first-time user must create a
  Tailscale account (Google/GitHub/Apple OAuth — they already have one), and join
  a tailnet, on **both** devices. The wizard guides this with deep links, not prose.
- **Same identity on both devices is the #1 silent failure.** Phone signed into a
  personal account, Mac into a work account = different tailnets = endless hangs
  with no error. Onboarding must say, loudly, "sign in with the **same** account on
  both," and pairing should verify the tailnet matches before it proceeds
  (`01` § Connectivity ladder). This single nudge prevents most setup failures.
- **iOS cannot truly "detect Tailscale."** There is no iOS Tailscale CLI and no
  `tailscale://` URL scheme to query or control the VPN. On iOS the only honest
  signal is **reachability**: can the app reach `/health` at the Mac's address?
  (Plus a `getifaddrs` check for a `utun*` interface in the `100.64.0.0/10` CGNAT
  range as a weak hint.) The Mac side *can* introspect via `tailscale status
  --json`. Do not design a phantom "is Tailscale on?" iOS API. (`01` § Connectivity)
- The friction is acceptable for this audience (they run multiple AI CLIs), but
  "acceptable" is the floor — the wizard + a connectivity *diagnostic ladder*
  (`01`) are what make it feel easy.

### 2.5 Transport binding + TLS: prefer `tailscale serve`, plain HTTP fallback

How the Mac's loopback server (RB6, see `01`) reaches the tailnet — decided from
first principles because three mentors flagged the naive "bind to the `100.x`
interface" path as operationally fragile (the IP can change across Tailscale
restarts, the interface may not exist at startup, and it carries no TLS):

- **Default (recommended): `tailscale serve`.** Tailscale proxies the tailnet onto
  the server **while it stays on `127.0.0.1`** — so RB6's "no reshape" becomes
  *literally* true (no interface enumeration, no rebind-on-change), it adds an
  automatic valid `*.ts.net` **HTTPS/WSS** cert (real defense-in-depth above
  WireGuard, cleaner for the "executes code on your Mac" trust story), and
  off-tailnet unreachability is enforced by Tailscale. `serve` is tailnet-only;
  `funnel` (public) is **never** used.
- **Fallback: bind to the discovered tailnet IP, plain HTTP** (WireGuard already
  encrypts). Used when `tailscale serve` is unavailable. Requires the IP-discovery
  + wait-for-interface + rebind logic in `01`.
- **Caveat to verify on the founder's machine** (like Phase 02 verifies CLI flags
  before locking): `serve` needs the standalone Tailscale client (the Mac App Store
  build's CLI is limited) and a one-time "HTTPS certificates" enable in the tailnet
  admin console. If that proves too heavy in practice, the fallback is the default.

---

## 3. What this deletes (do not build)

| Killed | Was in | Replaced by |
| --- | --- | --- |
| Bonjour `_allnighter._tcp` discovery | `ON HOLD/08` | Tailscale MagicDNS name, exchanged at pairing |
| Pinned self-signed TLS + signed-challenge transport auth | `ON HOLD/08` | WireGuard encryption (Tailscale) |
| Custom VPS relay + remote command queue | `ON HOLD/20` | P2P over the tailnet (works away from LAN natively) |
| LAN-only assumption | `ON HOLD/08`/`09` | From-anywhere by default |

Ed25519 device **pairing/authorization** survives — but as an *app-level*
authorization layer on top of Tailscale (§4), not as the transport's crypto.

## 4. Two security layers, never one

Tailscale secures the *transport*; the app still authorizes the *device*. Being
on the tailnet is necessary but not sufficient (a tailnet may be shared, or a
device compromised). Defense in depth:

1. **Tailscale** — encrypted transport + network isolation (the Mac is only
   reachable from the user's tailnet).
2. **App-level device approval** — at pairing the Mac explicitly approves each
   phone (device pubkey + an approval step shown on the Mac); every request is
   bound to an approved device. Pairing tokens are short-lived; device identity
   is explicit (carried from `WORKING_RULES.md` § Security Boundary).

Secrets (any worker CLI auth) **never leave the Mac**. iOS sends commands; the
Mac executes (`WORKING_RULES.md`). The MVP holds no model API keys at all
(`../../mvp/00_MVP_Architecture.md` §9).

## 5. Push (deferred seam — not v1)

Background "your lane finished — come review" pings need Apple's push service
(APNs), which requires a provider to hold the signing key. We will **not build
that** — same philosophy as Tailscale: use a specialist.

- **Vendor:** a push SaaS behind a thin **`PushNotifier`** abstraction so it
  stays swappable. **OneSignal is the likely default** (push-specialist, generous
  free tier) — but the seam is the commitment, not the vendor: Ably or FCM drop
  in with no other change. Nothing is baked into the foundation.
- **v1 ships without push.** Live updates flow over the Tailscale connection while
  the app is open. Background pings are a later additive layer.
- **The push path carries no secrets.** A notification is a content-light
  doorbell ("a lane finished — open to review"); the real data is fetched over
  Tailscale when the app opens. The push vendor never sees sensitive content, so
  it sits outside the security-critical path entirely.

---

## 6. Decision log

| Date | Decision | Note |
| --- | --- | --- |
| 2026-06-15 | **Tailscale (P2P WireGuard) is the iOS transport.** LAN-only is dead; from-anywhere is the product. | Strongest trust story, zero infra, not Apple-locked. The advice to "use Tailscale, they solved it" is endorsed. |
| 2026-06-15 | **CloudKit rejected.** | Buggy, Apple-lock (Android/web later), non-App-Store Mac entitlement risk. |
| 2026-06-15 | **Old `08` bespoke transport + `20` relay deleted.** Bonjour, pinned TLS, VPS relay all gone. | Tailscale subsumes them; less code, stronger security. |
| 2026-06-15 | **Two layers: Tailscale transport + app-level device approval.** | Tailnet membership is not authorization. |
| 2026-06-15 | **Push is a deferred seam behind `PushNotifier`; vendor chosen at build time; not in v1.** | Use a specialist; carry no secrets through it; live updates over Tailscale meanwhile. |
| 2026-06-15 | **Transport binding: prefer `tailscale serve` (server stays on `127.0.0.1`, auto TLS, no interface logic); plain-HTTP bind to the tailnet IP is the fallback.** (§2.5) | Mentor-converged: naive `100.x` interface bind is fragile (changing IP, startup race, no TLS). Verify `serve` prerequisites on-device before locking. |
| 2026-06-15 | **Embedded Tailscale (`tsnet`/`libtailscale`/NetworkExtension) evaluated and deferred.** | Would remove the second app install, but means a separate node identity, auth-key provisioning (implies infra/secrets we said we'd never run), and App Store VPN-entitlement review. Crosses from "use their tailnet" to "manage Tailscale for them." Revisit post-v1 only. |
| 2026-06-15 | **Product copy says "private Tailscale connection," not "direct P2P."** | Tailscale may use encrypted DERP relays; traffic stays E2E-encrypted but "direct" isn't guaranteed. Honesty rule. |
| 2026-06-15 | **Same-tailnet/same-SSO on both devices is a first-class onboarding requirement; pairing verifies tailnet match.** | The #1 silent failure mode; cheap to prevent, expensive to debug. |
| 2026-06-15 | **"Mac asleep / unreachable / server-off" are first-class states, not generic errors; Mac stays awake (power assertion) while serving an active run.** | Users blame setup when the Mac merely slept. (`01` § Connectivity, § Caffeination) |

> Append a row whenever a phase changes a locked decision here.
