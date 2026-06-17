# 01a — Pairing Ceremony (the WOW — sign in, tap your Mac, approve once)

Status: Draft — **first iOS trust foundation when iOS starts**, but deferred until
the macOS app is done. Not a Mac blocker.
Milestone: iOS (Remote Project Manager)
Owner: Mac + Shared Core (engine) / iOS (presenter)
Created: 2026-06-15
Updated: 2026-06-17 (Mac-first reset)
Depends on: `01_Connection_Spine.md` (`TrustedRemoteStore`, device assertion, the Mac
agent), `00` (§3 trust model, §5 sign-in, §2.4 connection modes)

## Why this is its own doc, and why it is not "later"

Pairing is the **first trust moment** — the emotional proof the whole system is safe
and simple. The ICP is **a non-developer vibe coder.** Two outcomes only:

- **Hard** → "configure a remote server" → they drop before seeing value.
- **Easy** → "I signed in and now I run my Mac from my phone — this is insane" → the
  WOW that sells everything else.

The cloud-first pivot (`00`) makes the default ceremony **even simpler** than the
earlier QR plan: no install of a VPN, no scanning — **sign in, tap your Mac, approve
once.** (We dropped the "AirDrop-class" framing: AirDrop's magic is *proximity*; ours
is *no networking, from anywhere* — don't invite a "why must I be near my Mac?"
expectation.) We foundation-build the ceremony now as a tested engine; the GUI just
makes it look as good as it feels.

> The bar: **"Sign in, pick your Mac, approve once."** Never "configure a remote
> server."

## The simplicity bar (measurable, non-negotiable)

The happy path must clear all of these or it isn't done:

- The user **never sees or types**: an IP, port, hostname, UUID/`deviceId`, token, or
  config. (Those live inside opaque payloads.)
- **Cloud-mode happy path = sign in → tap your Mac → approve on the Mac → done.**
- **Pair once.** Every later launch reconnects automatically (`01` registry). No
  re-onboarding.
- **Every failure → one plain-language reason + one button** (`01` `RemoteDoctor`).
  Never a stack trace, never "tailnet interface," never a dead-end.
- The security gate is always the same and always honest: **a human approves the new
  device on the Mac** (one tap). A leaked password alone can't add a controller.

These are Exit Gates (below).

## The two ceremonies, one trust gate

Same security in both (`00` §3): the phone generates an **Ed25519 device key**
(CryptoKit; private key in iOS Keychain), the Mac stores the **public key** and a
human **approves** the device once. `deviceId` is a hint; the signature is the truth.
Only **discovery + carrier** differ by connection mode.

### A. Cloud mode (DEFAULT) — account-based, no QR

The everyday path, and the simplest possible:

```text
1. User signs into Allnighter on the Mac (Apple/Google) -> Mac registers as a mac_agent.
2. User signs into Allnighter on the phone with the SAME account.
3. Phone lists "Your Macs" (account-based discovery, 01 RemoteClient.macs()).
4. Tap a Mac -> phone generates its device key, sends a pair request (device pubkey)
   via the control plane.
5. Mac shows "Trust Mike's iPhone?" -> ONE-TAP APPROVE (or `allnighter pair approve`
   / a notification if the Mac is headless).
6. Phone lands directly on live runs. Thereafter it signs commands; the Mac verifies.
```

No scanning, no codes. "Same account" replaces the old "same tailnet" failure mode —
and everyone understands "use the same Apple ID."

**v1 approval is Mac-only** (the human at the Mac taps Approve, or runs
`allnighter pair approve`, or taps a Mac notification). **Adding a device while away
from the Mac is v1.1** — but the `approveRequest` command is **reserved in the closed
enum now** (`01`) so v1.1 is wiring, not a wire-contract change. (Reconciles the
earlier "approve from an already-trusted device" wording: that is v1.1, not v1.)

> **Same-account-different-provider is the #1 silent dead end:** Apple on the phone +
> Google on the Mac = two distinct accounts = the phone sees no Mac, with no error.
> `RemoteDoctor` (`01`) detects and explains this ("you used Apple here, Google on
> your Mac — sign in with the same one"). Do not leave it as a mystery hang.

> **First-device bootstrap on a truly headless Mac** (closet mini, no display): the
> *first* pairing **requires a monitor/keyboard once, or SSH** to run
> `allnighter pair approve` — nothing trusted exists yet to delegate to. This is an
> unavoidable, one-time floor; device #2+ gets the ergonomic remote-approve in v1.1.

### B. Direct Mode / headless / Mac→Mac — the carrier ceremony (QR + link + code)

Used to enable **Tailscale Direct Mode** (premium) and for **headless/closet-Mac** or
**Mac→Mac** pairing, where the phone must learn the Mac's P2P endpoint + pin its
identity. **One ceremony, three carriers**, same payload/token/approval:

| Carrier | For | How |
| --- | --- | --- |
| **QR (deep-link)** | enabling Direct Mode on a phone | Mac shows a QR encoding `allnighter://pair?...`; Camera opens Allnighter **mid-ceremony** — zero typing |
| **Pairing link** | Mac → Mac (MacBook → headless mini) | "Copy pairing link" → open on the other Mac → it connects + requests approval |
| **Manual 6-digit code** | terminal / QR won't scan | short code, short TTL, backoff — the only typed path |

`PairingPayload` (Direct Mode): `{ endpoints:[{url, transportMode}], agentSigningPubkey,
agentSealingPubkey, tailnetName(display), protocolVersion, pairingToken(single-use),
expiresAt }`. The user never sees an IP/UUID.

- **Use a universal link, not a custom URL scheme.** Any app can register
  `allnighter://`, so a custom scheme is interceptable; a **universal `https://` link**
  (AASA-validated, domain-exclusive) can't be hijacked, and falls back to the App
  Store if Allnighter isn't installed. The QR encodes the universal link.
- **`agentSigningPubkey` is the trust anchor (TOFU)** — pinned at first contact, so
  even if a ceremony were misrouted, a fake Mac fails signature verification. The
  payload is unauthenticated until that check runs; the pin is what makes it safe.
- **Switching a cloud-paired device to Direct Mode needs no second human approval** —
  same `trusted_devices` row + same device keys; this ceremony only teaches the phone
  the P2P endpoint and pins the Mac's keys.

## Temporary, single-use, no standing surface

In both modes the pairing token / request is **single-use, short-TTL**, with
failed-attempt **lockout** (`01` registry). No permanent discovery beacon; after
pairing the phone uses the stored connection (account routing in cloud mode, pinned
endpoint in Direct Mode). Pairing is an *armed moment*, not an open door.

## Resumable — never lose the user

- **Cloud mode:** the only external step is sign-in. If the Mac isn't visible yet
  ("open Allnighter on your Mac, same account"), the phone holds state and the Mac
  appears the moment it signs in — no restart.
- **Direct Mode:** if Tailscale isn't installed/on, the app holds the pending payload,
  deep-links to Tailscale (App Store smart link — no `tailscale://` scheme exists),
  and **resumes automatically** on return; an expired token re-arms in one tap.
- Guidance is always **reason + button + resume**, in plain language.

## Headless carrier = foundation + test surface (when iOS starts)

The CLI is how the whole ceremony will be built and proven **before any SwiftUI**
when the deferred iOS phase starts, and it doubles as the Mac->Mac/headless
approver:

```text
allnighter pair list                       # pending + trusted devices
allnighter pair approve <deviceId>         # the human gate (cloud-mode approval too)
allnighter pair revoke  <deviceId>
allnighter pair begin                      # Direct Mode: arms a window; prints deep-link + ASCII QR + 6-digit code
```

The full ceremony (both modes, device-key gen, approval, dedupe, expiry, lockout,
resume) is exercised via `swift test` + `MockiOSClient` with **zero GUI**. The `02`
GUI is a thin presenter over exactly this.

## What is buildable now vs. needs the iOS target

| Now (foundation, `01`/`01a`) | Early `02` (thin, but first) |
| --- | --- |
| Account-based pairing engine (discover → request → approve) in Core + Mac agent | The SwiftUI "Your Macs → tap → waiting for approval" screen |
| `TrustedRemoteStore`, device-key gen, signed assertion | The Mac one-tap "Trust this device?" sheet |
| CLI approval + Direct-Mode carriers (QR/link/code) | iOS `allnighter://pair` URL-scheme + Camera handoff (Direct Mode) |
| `MockiOSClient` proof of the whole ceremony | Universal-link / App-Store-fallback wiring |

**Sequencing:** because pairing is the trust foundation, its SwiftUI screen is **one
of the first `02` screens**, presenting an already-magical, already-tested ceremony.

## What the user NEVER does (drop-off killers — explicit non-goals)

- Type/copy an IP, port, hostname, UUID, `deviceId`, or token. (Manual 6-digit code is
  the only typed path, Direct Mode only, as a fallback.)
- Read networking docs, configure a server, set up SSH, edit a config.
- In cloud mode: install anything beyond the Allnighter apps + sign in.
- Re-pair on every launch (pair once; reconnect is silent).

## Works Test (ceremony-specific)

```text
Cloud mode (default):
  - Two devices signed into the same account: the phone lists the Mac, taps it, the
    Mac shows "Trust this iPhone?", one tap approves, the phone lands on live runs
    -- WITHOUT typing or scanning anything -- in under ~20s.
  - Headless Mac: approval works via `allnighter pair approve` / notification.
  - Pair once, force-quit, relaunch -> reconnects automatically.
Direct Mode / Mac->Mac:
  - Camera at the deep-link QR opens the app mid-ceremony, approve on the Mac, P2P
    connection established (no relay); manual code + pairing-link carriers also work;
    resumes across a Tailscale install.
Both:
  - single-use token/request + expiry + failed-attempt lockout enforced;
  - the entire ceremony passes headless (CLI + MockiOSClient), no SwiftUI.
```

## Exit Gates

- [ ] Cloud-mode happy path = sign in → tap → approve, **nothing typed or scanned**;
  no IP/UUID/port/token ever shown (UX checklist + Works Test).
- [ ] Same trust gate (device key + one-tap Mac approval) in both modes.
- [ ] Direct-Mode carriers (QR-deep-link / pairing-link / manual code) share one
  payload/token/approval; QR opens the app mid-ceremony.
- [ ] Ceremony resumable (across sign-in in cloud mode; across Tailscale install in
  Direct Mode).
- [ ] Whole ceremony proven **headless** before any GUI; `swift test` green; Audit CLEAN.

## Closeout

The first thing a new user does is also the moment they decide to trust (and keep)
Allnighter. Cloud-mode pairing — sign in, tap your Mac, approve once — is the
sign-in-simple default; Direct Mode reuses the same trust gate over a QR carrier. The
`02` GUI's only job is to make a magical, already-tested ritual look as good as it
feels: "wait, that's it? I can run my Mac from my phone now?"
