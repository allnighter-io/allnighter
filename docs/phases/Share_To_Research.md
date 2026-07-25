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

## Review — two independent models, 2026-07-24

Reviewed by **Gemini 3.6 Flash** (agy) and **Composer 2.5** (cursor) via `alln run`,
read-only. Both were told to disprove the packet against the repo. They agreed on
the central finding, and every claim below was verified by hand before being
accepted. The corrections are folded into the sections that follow; the draft this
replaces was wrong in three load-bearing ways.

| Finding | Verdict |
| --- | --- |
| `WorkRequestDraft` takes `prompt:`, not `message:` — the draft's snippet would not compile | **Confirmed**, `WorkRequestSender.swift:12` |
| "Exactly one thing is missing" was false — a Share Extension cannot read the host app's credentials | **Confirmed.** `RemoteCredentialPaths.directory` writes to the app container's Application Support; `.appex` has a different container, and `AllnighteriOS.entitlements` declares no App Group |
| "X links never reach `vvx` — enforced by `SignalSourceRouter`" was an overclaim | **Confirmed.** `allowsVideoTool` is never called in production; enforcement is the generated scout prompt |
| Link shorteners bypassed the X rule — `bit.ly` → x.com routed to the downloader | **Confirmed and FIXED** in the same pass: new `.unresolvedRedirect` route, 13 shortener hosts, `forbidsVideoTool`, 4 new tests |
| The relay QUEUES commands when the Mac is offline, contradicting the packet's "never look queued" | **Confirmed.** `CloudRemoteClient.send` always `submitCommand`s; `SupabaseRemoteMacRelay` persists to `command_inbox` |
| `sendWorkRequest` ignores `ack.accepted`, so a revoked device can get a silent success | **Confirmed** — unlike `stopAllWork`/`stopActiveRun`, which do check |

## What already exists — and what the reviews corrected

Verified in code, not assumed:

| Piece | Where | State |
| --- | --- | --- |
| Typed remote commands (`startRun`, `stopRun`, `stopAll`, `markThreadRead`, pending verbs) | `RemoteCommandRouter.swift` | Built |
| iOS run execution | `AsyncTeamRemoteCommandExecutor.startRun` → `AsyncTeamService.start(origin: .ios)` → `RunService.run` | Built |
| Cloud relay drain loop | `RemoteMacAgentCoordinator`, hosted by `ServeDaemon` (`alln serve`) | Built |
| Thread mirroring for iOS | `RemoteIOSThreadMirrorExecutor` | Built |
| iOS app sending a run with a chosen team | `WorkRequestSender.send(draft)` — `WorkRequestDraft.teamPresetId` → `.startRun` | Built |
| iOS app receiving + displaying results | `ConversationHomeStore` (loads the Mac-owned thread snapshot) → `ConversationThreadView` | Built |
| The Research team | `signal_outside` (display "Research"), scout + 3 triangulating interpreters + skeptic + writer | Built, proven live |
| URL routing (X vs video vs pasted text) | `SignalSourceRouter` | Built, 8 tests |

**An earlier draft said "exactly one thing is missing." That was wrong.** The send
and display paths do exist, but a Share Extension is a separate process with its
own container, so the slice is:

1. **A Share Extension target** — none exists (`Apps/AllnighteriOS` has no `*Share*` file).
2. **An App Group + shared credential/session storage.** `RemoteCredentialPaths`
   and the Supabase session store write to the host app's Application Support.
   The extension cannot read them, and no App Group entitlement exists. Without
   this the extension cannot sign a `startRun` at all. **This is the real P0.**
3. **A one-tap confirm sheet** building
   `WorkRequestDraft(prompt: <shared URL>, teamPresetId: "signal_outside")` —
   note `prompt:`, not `message:`.
4. **`NSExtensionItem` extraction** — X may hand over a URL attachment, plain
   text, both, or neither.
5. **A return path to the host app** — no URL scheme, no `onOpenURL`, no
   `NSUserActivity` today, so after confirm the user is left in X with no thread.

Recommended shape (both reviewers converged on it independently): the extension
should **stage the request into the App Group and hand off to the host app**
rather than build a relay client inside a ~30 MB, cold-started extension process.

## New/changed semantic rules

1. **Auto-recognize, never auto-run.** The share extension pre-fills and waits
   for one tap. A silent auto-run means a mis-share spends real vendor quota and
   the user finds out afterwards. The tap costs nothing and keeps spend
   user-authorized — consistent with "never silently spend".
2. **The classifier is shared, never re-implemented.** iOS must not decide what
   an X link is. `SignalSourceRouter` is the one owner of the RULE: X → the Mac's
   Grok reads it; a shortener → the model resolves it by reading (never the
   downloader, since it may land on X); anything else → `vvx`; no link → pasted
   text. A second copy on the phone is how the X-safety rule would drift.
   **Honest limit:** the scout is a vendor CLI that shells out on its own, so
   nothing can physically block a `vvx` call. The rule is enforced by the
   generated scout instructions, not by an interceptor — `allowsVideoTool` exists
   for callers that CAN gate (this confirm sheet is the first real one) and is
   currently used only by tests. Do not describe this as code-enforced end to end.
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
| Core | None expected. `WorkRequestSender` already carries `teamPresetId`; `SignalSourceRouter` already routes. |
| iOS app | The whole slice: a new Share Extension target + a one-tap confirm sheet that builds a `WorkRequestDraft`. Results need no new view — the existing thread surface shows them. |
| Mac app / `alln serve` | None beyond running: the relay drain loop already exists. |
| Driver/protocol | None. Reuses `startRun`. |
| Auth/privacy | No new credentials. No X login on the phone. The relay stays blind — it carries a URL and a team id, not the user's work. |

## Honest boundary

Something outside the phone has to run the user's tools.

**Corrected by review:** the relay does NOT reject when the Mac is down — it
persists the command to `command_inbox` and the Mac drains it on next wake. So
"never look queued" was the wrong requirement; work genuinely IS queued. The
honest requirement is to **say so**: the confirm sheet must distinguish "sent —
your Mac is offline, this will run when it wakes" from "running now", and must
never imply a result is imminent when the Mac is asleep.

Two related honesty bugs to fix in the same slice:
- `sendWorkRequest` ignores `ack.accepted`, so a revoked or expired device gets a
  silent success. `stopAllWork` and `stopActiveRun` already check it; this path
  must too.
- Send must be idempotent per share. The request id is non-deterministic today,
  so a double-tap can bill two full six-model runs.

## Works Test

```text
1. On iPhone, share a real X post to Allnighter -> confirm once
   -> an insight returns citing the post, with source receipts and a skeptic pass;
      the Mac's Grok read it and `vvx` was never invoked on the X URL.
2. Share a YouTube link -> confirm once
   -> the scout runs `vvx sense "<url>"`, the transcript reaches the interpreters,
      and the insight quotes it.
3. Share with the Mac asleep/offline
   -> the phone says "queued until your Mac wakes" (NOT "running"), the command
      is in `command_inbox`, and it runs on next drain with no duplicate.
4. Double-tap confirm
   -> exactly ONE run. Same share, same request id, one billed fan-out.
5. Share a bit.ly that redirects to an X post
   -> the scout resolves it by reading; `vvx` is never invoked on it.
6. Share plain text with no URL, and a share with two URLs
   -> handled explicitly, never a crash or a silent no-op.
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
- An offline Mac is reported as queued-until-wake, never as running.
- A double-tap bills one run, not two.
- No new run owner, protocol operation, or second copy of the routing rule.

## Settled — do not re-open as questions

**Result delivery is not a special problem.** A Research run returns exactly like
any other run: the Mac writes the run journal, the thread snapshot mirrors, and
`ConversationHomeStore` → `ConversationThreadView` already loads and shows it.
There is nothing to design here — an earlier draft of this packet raised it as an
open question, which was wrong.

**The team is always Research.** A shared link is a Research request by
definition; the confirm sheet does not offer a team picker. Founder ruling
2026-07-24. A picker would reintroduce exactly the selection ceremony this
product deleted, in the one place where the intent is already unambiguous.
