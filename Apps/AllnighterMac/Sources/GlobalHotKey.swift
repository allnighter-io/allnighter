import AppKit
import Carbon.HIToolbox

extension Notification.Name {
    /// Posted when the global quick-capture hotkey fires. The app's root view
    /// observes it on the main actor and brings the composer forward.
    static let allnighterQuickCapture = Notification.Name("AllnighterQuickCapture")
}

/// A system-wide hotkey via Carbon `RegisterEventHotKey`. Carbon is the reliable
/// no-entitlement path for a global shortcut in an unsandboxed Mac app: unlike
/// `NSEvent` global monitors it needs no Accessibility permission. On fire it
/// posts `.allnighterQuickCapture` rather than calling UI directly, so no
/// main-actor state is captured into the C callback. (Carbon delivers hotkey
/// events on the main run loop.)
enum GlobalHotKey {
    /// Default: Option–Command–Space. `keyCode` is a Carbon virtual key.
    struct Combo {
        var keyCode: UInt32
        var modifiers: UInt32
        static let optionCommandSpace = Combo(
            keyCode: UInt32(kVK_Space),
            modifiers: UInt32(optionKey | cmdKey)
        )
    }

    nonisolated(unsafe) private static var hotKeyRef: EventHotKeyRef?
    nonisolated(unsafe) private static var eventHandler: EventHandlerRef?

    /// Four-char Carbon signature ('ALNT').
    private static let signature: OSType = {
        let chars: [Character] = ["A", "L", "N", "T"]
        return chars.reduce(OSType(0)) { ($0 << 8) + OSType($1.asciiValue ?? 0) }
    }()

    /// Registers the hotkey once. Silently no-ops on failure (e.g. the combo is
    /// already claimed system-wide) — quick capture is a convenience, never a
    /// hard dependency.
    static func enable(_ combo: Combo = .optionCommandSpace) {
        guard hotKeyRef == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ -> OSStatus in
                var hkID = EventHotKeyID()
                GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                    nil, MemoryLayout<EventHotKeyID>.size, nil, &hkID
                )
                if hkID.signature == GlobalHotKey.signature {
                    NotificationCenter.default.post(name: .allnighterQuickCapture, object: nil)
                }
                return noErr
            },
            1, &eventType, nil, &eventHandler
        )

        let hotKeyID = EventHotKeyID(signature: signature, id: 1)
        RegisterEventHotKey(
            combo.keyCode, combo.modifiers,
            hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef
        )
    }
}
