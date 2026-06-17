# 03 - iOS Thread Read State And Push

Status: Deferred iOS-only phase; does not gate Mac app delivery
Milestone: iOS (Remote Floor Manager)
Owner: iOS + remote spine
Updated: 2026-06-17

## Purpose

This doc owns the iOS-only follow-up for thread unread state and mobile push.

Mac unread state and Mac local notifications must ship without this work:

- Mac read cursor and unread derivation:
  [`../threads/06_Unread_Message_Light.md`](../threads/06_Unread_Message_Light.md)
- Mac local notifications 1.0:
  [`../threads/02_Notifications.md`](../threads/02_Notifications.md)

iOS consumes those contracts later. It is not a prerequisite, blocker, proof
requirement, or acceptance criterion for the macOS app.

## Product Rule

```text
iOS is a remote floor manager after the Mac app is done. The Mac owns execution,
thread truth, read truth, and notification truth for Mac v1.
```

Do not put iOS-only protocol fields, mobile push, or phone-side reconciliation
requirements back into Mac thread docs.

## Scope

Build this only after the Mac app is ready for the iOS companion.

This doc owns:

- iOS rendering of unread state from Mac-provided thread payloads.
- Phone-side `markRead(threadId, throughTurnId)` intent after a target turn is
  visible on the phone.
- Monotonic read-cursor reconciliation with the Mac as final truth.
- Mobile push doorbells for thread events.
- Content-light push payloads and fetch-on-open validation.
- Per-device mobile push settings after trusted pairing exists.

This doc does not own:

- Mac local notifications.
- Mac menu-bar badges.
- Mac read-cursor derivation.
- Thread timeline visibility on macOS.
- Any cloud-owned read truth.
- Any remote shell, generic MCP bridge, or free-form command channel.

## Required Mac Contracts

The iOS phase may start only after these Mac contracts are built and stable:

- Durable `ThreadReadCursor` in `WorkThread`.
- Core unread derivation from cursor + turns.
- `ThreadStore.markRead` / `markReadToLatestVisible`.
- Mac timeline clear-on-visible behavior.
- Mac local notification policy for meaningful thread/turn transitions.

The iOS work must consume these contracts; it must not invent parallel phone
truth.

## Future Remote Thread Payload

When the remote spine exposes thread lists, include:

```text
Thread payload
- readCursor?
- hasUnread              # derived convenience only; source fields must also be present
- firstUnreadTurnId?
- latestUnreadTurnId?
```

Rules:

- `hasUnread` is a convenience field from the Mac, not iOS-owned truth.
- iOS must not derive unread from local timestamps.
- If payload fields disagree, the Mac cursor + turn truth wins.

## Future Read Intent

```text
Intent
- thread.mark_read(threadId, throughTurnId)

Event
- thread.read_state_changed(threadId, readCursor, firstUnreadTurnId?)
```

Rules:

- iOS sends `markRead` only after the target turn is visible on the phone.
- The Mac accepts a phone cursor only if it advances the cursor under the same
  store rules as Mac visibility clearing.
- If iOS is offline, it may clear locally for feel, but must reconcile with Mac
  truth on reconnect.
- Reconciliation is monotonic: never move `lastReadTurnId` backward.
- Notification delivery or tap state is never a read receipt.

## Future Mobile Push

Mobile push is a doorbell, not storage and not read truth.

Likely provider:

```text
PushNotifier seam -> OneSignal likely default, swappable
```

Payload shape:

```text
threadId
turnId
eventKind
displayTitle      # content-light
macId
seq
```

Rules:

- Push payload contains no prompt, reply, code, artifact text, secret, or
  credential.
- Sensitive content is fetched after open through the trusted remote spine.
- The Mac remains thread truth and final authorizer.
- A cloud breach must not reveal thread content or control the Mac.
- Opening a push fetches current thread truth; it does not trust payload state.

## Ordered Slices

- [ ] iOS03-S01 - Add remote thread payload read-state fields after the thread
  remote spine exists.
- [ ] iOS03-S02 - Add phone `markRead` intent and Mac-side monotonic acceptance.
- [ ] iOS03-S03 - Add iOS unread rendering from Mac payloads.
- [ ] iOS03-S04 - Add `PushNotifier` seam for mobile push.
- [ ] iOS03-S05 - Add content-light mobile push payloads for thread events.
- [ ] iOS03-S06 - Add fetch-on-open validation and paired-device push settings.

## Works Test

With a paired phone and push enabled, a completed worker/team/dispatch event
sends a content-light mobile notification. Opening it fetches encrypted thread
content through the remote spine. The payload contains no prompt, reply, code, or
artifact text.

After the target turn is visible on the phone, iOS sends `markRead`. The Mac
advances the cursor only if the requested turn is a valid forward move. Relaunch
on both devices preserves the Mac truth.

## Done When

- Mac app docs have no iOS dependency for Mac unread or Mac local notifications.
- iOS renders unread from Mac truth, not phone-only state.
- Phone `markRead` is monotonic and accepted by the Mac store path.
- Mobile push is content-light and fetches truth after open.
- Push delivery, push tap, and notification receipt are never read receipts.
