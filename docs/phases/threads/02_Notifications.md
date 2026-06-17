# 02 - Thread Notifications

Status: Fast follow after Work Threads MLP; coordinates with `05_Unread_Message_Light.md`
Owner: Mac app backend + iOS remote spine
Updated: 2026-06-17

## Goal

Notify the user when work lands or needs attention, so they can keep the bench
busy without staring at Allnighter.

This is high value because Allnighter is a floor manager. The user should know
when a worker replied, a team run completed, a dispatch returned, or a lane is
blocked.

## Product Claim

```text
Allnighter tells you when a thread is ready for your next decision.
```

## Sequence

Ship in two layers:

1. **Mac local notifications** immediately after Work Threads MLP, or in
   parallel with rich-turn attachment if the thread state-change hooks are ready.
2. **Mobile push via OneSignal** after the iOS remote spine and E2E content rules
   are in place.

Mac notifications do not require cloud or iOS.

Unread/read truth is owned separately by
[`05_Unread_Message_Light.md`](05_Unread_Message_Light.md). Notification
delivery, click-through, and push receipt must not be treated as read receipts.
The notification policy may suppress delivery when the target turn is already
visible and read, but visibility/read state remains the cursor's job.

## Notification Events

Notify by derived thread/turn state:

```text
turn.completed
turn.failed
turn.timedOut
turn.awaitingManualPaste
turn.authRequired
thread.needsAttention
dispatch.returned
returnReview.completed
```

Do not notify for every low-level stream chunk or every status poll.

## Mac Local Notifications

Rules:

- Local only.
- User opt-in via macOS notification permission.
- No secrets in notification body by default.
- Respect quiet hours / focus setting if present.
- Debounce noisy threads.
- Clicking opens the thread and scrolls/focuses the relevant turn.
- A notification is emitted only after a meaningful state transition, not merely
  because the app restarted and re-read persisted state.

Default copy examples:

```text
Claude replied in "Notifications strategy"
Team run complete: "Should sync be push or pull?"
Codex returned from dispatch
Grok needs sign-in
```

## Menu Bar Presence

The Mac menu bar item should become a lightweight floor-manager indicator:

```text
any thread running       -> subtle live dot
N threads need attention -> badge/count
click                    -> highest-priority thread by Home triage order
```

This gives some walk-away value even before notification permission is granted.
Do not include ordinary unread threads in the numeric badge; that count is for
needs-attention only. If unread is later reflected in the menu bar, use a quiet
amber dot and source it from `05_Unread_Message_Light.md`.

## Mobile Push With OneSignal

Use OneSignal as the likely default push provider behind a `PushNotifier` seam,
consistent with the iOS remote spine.

Rules:

- Push payload is content-light.
- Sensitive content stays E2E encrypted and fetched after open.
- The Mac remains thread truth and final authorizer.
- A cloud breach must not reveal thread content or control the Mac.
- Push is a doorbell, not durable storage.

Payload shape:

```text
threadId
turnId
eventKind
displayTitle      # content-light
macId
seq
```

## User Controls

- Global notifications on/off.
- Per-thread mute.
- Notify on: replies, team run complete, dispatch returned, failures/blocked.
- Quiet hours.
- Mobile push on/off per paired device.
- Reset notification permission guidance if macOS permission was denied.

## Ordered Slices

- [ ] NOTIF-S01 - Add notification policy model and settings.
- [ ] NOTIF-S02 - Emit notification candidates from turn/thread state changes.
- [ ] NOTIF-S03 - Mac local notification delivery and click-to-thread.
- [ ] NOTIF-S04 - Debounce and per-thread mute.
- [ ] NOTIF-S05 - Menu bar live/needs-attention indicator.
- [ ] NOTIF-S06 - Add push seam (`PushNotifier`) but keep implementation off.
- [ ] NOTIF-S07 - OneSignal mobile push after remote spine exists.
- [ ] NOTIF-S08 - E2E fetch-on-open validation for pushed thread events.

## Works Test

Mac:

```text
Send a chat turn and leave the thread. When the worker reply completes,
Allnighter posts one local notification. Clicking it opens the thread at the
reply turn. A failed worker posts a needs-attention notification. Muting the
thread suppresses both.
```

Mobile:

```text
With a paired phone and push enabled, a completed worker/team/dispatch event
sends a content-light OneSignal notification. Opening it fetches encrypted
thread content through the remote spine. The push payload contains no prompt,
reply, code, or artifact text.
```

## Proof Command

```text
swift test
scripts/check.sh
```

Mobile push also needs an end-to-end manual Works Test on a paired device before
product copy claims remote notifications.
