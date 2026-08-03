# CM-S10 — Extract ThreadsViewModel notifications

Status: done (`95a68cc7`, Gemini via `alln run`)
Owner: code-maintainer Structure lens
Updated: 2026-08-03

## Goal

Move `MARK: - Notifications` out of `ThreadsViewModel.swift` into
`ThreadsViewModel+Notifications.swift`. **Move only — no behavior change.**

## Copy-paste prompt

```text
Implement CM-S10 only. Read docs/operations/code-maintainer/plans/ThreadsViewModel-split.md.

Touch ONLY:
- Apps/AllnighterMac/Sources/ThreadsViewModel.swift (remove moved code)
- Apps/AllnighterMac/Sources/ThreadsViewModel+Notifications.swift (NEW extension)

Move the entire `// MARK: - Notifications (02 + UNR-S06)` section:
- isThreadNotificationsMuted, setThreadNotificationsMuted
- shouldSuppressNotification, notificationVisibilityContext
- openFromNotification, openPriorityThreadFromMenuBar
- processNotificationTransitions

Use `extension ThreadsViewModel { }` in the new file. Widen `private` → `internal` on
any stored properties/helpers the extension needs (notificationPolicy, notificationPolicyStore,
notificationDelivery, serveDaemonProbe, floorStatus, previousRunNotificationSnapshots, etc.).
Keep @MainActor on the extension.

Proof:
cd Apps/AllnighterMac && xcodegen generate && xcodebuild build -scheme AllnighterMac -destination 'platform=macOS'

Commit only the two Swift files above.
Message: refactor(mac): extract ThreadsViewModel notifications (CM-S10)
```

## Works Test

```text
xcodebuild build -scheme AllnighterMac -destination 'platform=macOS'
```
