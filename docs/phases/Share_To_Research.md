# Share to Research — send a link from your phone, get the read back

Status: **Draft feature packet — not started.** Worth building pre-launch; not urgent.
Owner: AllnighterCore + iOS app + Mac (`alln serve`)
Updated: 2026-07-24

## Founder intent

> "If I am on an X post I no longer have to press share → email. Instead I share it
> to alln, and if we are really clever, the moment it sees a link from X it
> recognizes this is a Research request."

Today the founder does this **3+ times a day**: sees a post, shares it to email,
then later opens a terminal, finds the link, pastes it, and runs the Research
team — five manual steps per link, every link. The run itself is now one
command. This packet removes the last gap: the phone.

## Product value

Share sheet → the read comes back. No copy, no paste, no terminal, no context
switch, on the surface where you actually find links.

It is also the iOS app's first genuinely defensible feature. A vendor cannot
copy it: the value comes from *several different frontier CLIs the user already
pays for, on the user's own Mac, reasoning over the same distilled source*. No
single vendor has a competitor's model on their bench, and no cloud service has
the user's subscriptions. "Share a link, get a triangulated project-aware read"
is only buildable by the thing that already orchestrates the user's own tools.

## Trusted workflow slice

```text
iOS share sheet (X post / YouTube / article)
  -> Allnighter share extension pre-fills a Research request
  -> ONE tap to confirm
  -> typed `startRun` command over the existing cloud relay
  -> the Mac resolves the route and runs the Research team (RunService.run)
  -> the insight lands in the thread, readable on the phone
```

## What already exists — this is mostly wiring

Verified in code, not assumed:

| Piece | Where | State |
| --- | --- | --- |
| Typed remote commands (`startRun`, `stopRun`, `stopAll`, `markThreadRead`, pending verbs) | `RemoteCommandRouter.swift` | Built |
| iOS run execution | `AsyncTeamRemoteCommandExecutor.startRun` → `AsyncTeamService.start(origin: .ios)` → `RunService.run` | Built |
| Cloud relay drain loop | `RemoteMacAgentCoordinator`, hosted by `ServeDaemon` (`alln serve`) | Built |
| Thread mirroring for iOS | `RemoteIOSThreadMirrorExecutor` | Built |
| The Research team | `signal_outside` (display "Research"), scout + 3 triangulating interpreters + skeptic + writer | Built, proven live |
| URL routing (X vs video vs pasted text) | `SignalSourceRouter` | Built, 8 tests |

**New work is therefore small and mostly iOS-side:** a Share Extension target, a
one-tap confirm sheet, and the mapping from a shared URL to an
`AsyncTeamStartRequest` carrying `teamPresetId: "signal_outside"`.

## New/changed semantic rules

1. **Auto-recognize, never auto-run.** The share extension pre-fills and waits
   for one tap. A silent auto-run means a mis-share spends real vendor quota and
   the user finds out afterwards. The tap costs nothing and keeps spend
   user-authorized — consistent with "never silently spend".
2. **The classifier is shared, never re-implemented.** iOS must not decide what
   an X link is. `SignalSourceRouter` is the one owner: X → the Mac's Grok reads
   it, anything else → `vvx`, no link → pasted text. A second copy of that rule
   on the phone is how the X-safety rule would eventually drift.
3. **No fetching on the phone, ever.** The phone sends a URL string. It does not
   resolve it, does not call `vvx`, does not read X. The Mac does the work with
   the user's own tools.
4. **Typed command only.** This reuses the existing `startRun` command. It does
   not add a protocol operation and never becomes a remote shell — the locked
   iOS trust model (`ios/00`) already forbids that.

## Truth owner

`RunService.run` — unchanged. This packet adds an origin, not an execution path.
`SignalSourceRouter` owns source routing. The run journal remains the durable
record; the phone reads a projection, never a second truth.

## Lie-prone layers

- **"Shared" looking like "ran."** A share that never reached the Mac must not
  read as queued-forever. It must say the Mac is unreachable.
- **A stale thread projection** presented as live run state.
- **Auto-run** framed as convenience while quietly spending quota.

## Non-goals

- Auto-running on share.
- Any fetching, transcript extraction, or X reading on the phone.
- A new protocol operation, a second run owner, or a remote shell.
- An email/inbox intake path — founder ruled this out: pasting the URL is enough,
  and the share sheet replaces the email habit entirely.
- Making the Mac reachable when it is not (no wake-on-demand in v1).

## Implementation impact

| Surface | Impact |
| --- | --- |
| Core | Map a shared URL → `AsyncTeamStartRequest` (team `signal_outside`). Reuse `SignalSourceRouter`. No new run semantics. |
| iOS app | New Share Extension target; one-tap confirm sheet; result view reads the existing thread projection. |
| Mac app / `alln serve` | None beyond running: the relay drain loop already exists. |
| Driver/protocol | None. Reuses `startRun`. |
| Auth/privacy | No new credentials. No X login on the phone. The relay stays blind — it carries a URL and a team id, not the user's work. |

## Honest boundary

Something outside the phone has to run the user's tools. If the Mac is asleep,
offline, or `alln serve` is not running, the share fails with that stated
plainly — the same honesty the sandbox hand-off uses when Allnighter is not
open. It must never look queued when nothing will pick it up.

## Works Test

```text
1. On iPhone, share a real X post to Allnighter -> confirm once
   -> an insight returns citing the post, with source receipts and a skeptic pass;
      the Mac's Grok read it and `vvx` was never invoked on the X URL.
2. Share a YouTube link -> confirm once
   -> the scout runs `vvx sense "<url>"`, the transcript reaches the interpreters,
      and the insight quotes it.
3. Share with the Mac unreachable
   -> the phone says the Mac cannot be reached, and NO run appears queued.
```

Proof command (Mac side): `alln team result <run-id> --json` shows the run with
`origin: ios` and the real worker roster.

Missing proof / waiver: none claimed until the three gestures above pass on a
real device against a real Mac.

## Done when

- Sharing a link from iOS starts a Research run after exactly one confirm tap.
- The insight is readable on the phone without opening a terminal.
- X links are never sent to `vvx` — enforced by the shared `SignalSourceRouter`,
  not by iOS-side prose.
- An unreachable Mac fails visibly and queues nothing.
- No new run owner, protocol operation, or second copy of the routing rule.

## Open questions

1. **Result delivery.** Does the phone poll the thread projection, or does the
   relay push a completion? Polling is simpler and already possible; a push is
   nicer and may already fall out of the event-sync spine.
2. **Which team.** v1 hard-codes Research. Worth deciding whether the confirm
   sheet later offers a team picker, or whether that reintroduces the selection
   ceremony this product deliberately deleted.
