# 02 - Thread Notifications

Status: **BUILT** (NOTIF-S01–S05 + UNR-S06, 2026-06-17)
Owner: Mac app backend
Updated: 2026-06-17

## Goal

Notify the user when work lands or needs attention, so they can keep the bench
busy without staring at Allnighter.

This is high value because Allnighter is the Project Manager. The user should
know when a worker replied, a team run completed, a dispatch returned, or a lane
is blocked.

## Product Claim

```text
Allnighter tells you when a thread is ready for your next decision.
```

## Scope

Ship **Mac local notifications only** in this phase.

Notifications 1.0 does not require cloud, iOS, OneSignal, Supabase, R2, or a
remote spine. iOS push is deferred to
[`../ios/03_iOS_Thread_Read_State_And_Push.md`](../ios/03_iOS_Thread_Read_State_And_Push.md)
and must not block Mac shipping.

This doc also owns UNR-S06 from
[`06_Unread_Message_Light.md`](06_Unread_Message_Light.md): the notification
policy must suppress local notification delivery when the landed turn is already
visible/read. It must not treat notification delivery or click-through as read
truth.

Unread/read truth is owned separately by
[`06_Unread_Message_Light.md`](06_Unread_Message_Light.md). Notification
delivery and click-through must not be treated as read receipts. The notification
policy may suppress delivery when the target turn is already visible and read,
but visibility/read state remains the cursor's job.

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
amber dot and source it from `06_Unread_Message_Light.md`.

## User Controls

- Global notifications on/off.
- Per-thread mute.
- Notify on: replies, team run complete, dispatch returned, failures/blocked.
- Quiet hours.
- Reset notification permission guidance if macOS permission was denied.

## Ordered Slices

- [x] NOTIF-S01 - Add notification policy model and settings.
- [x] NOTIF-S02 - Emit notification candidates from turn/thread state changes.
- [x] NOTIF-S03 - Mac local notification delivery and click-to-thread.
- [x] NOTIF-S04 - Debounce and per-thread mute.
- [x] NOTIF-S05 - Menu bar live/needs-attention indicator.

## Works Test

```text
Send a chat turn and leave the thread. When the worker reply completes,
Allnighter posts one local notification. Clicking it opens the thread at the
reply turn. A failed worker posts a needs-attention notification. Muting the
thread suppresses both.
```

## Proof Command

```text
swift test
scripts/check.sh
```
