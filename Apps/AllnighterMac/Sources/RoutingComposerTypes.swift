import SwiftUI
import AppKit
import AllnighterCore
import AllnighterEngine

// Shared composer routing types — extracted from RoutingComposer.swift (Structure batch).

enum ComposeEffort: String, CaseIterable { case low, med, high }
enum ComposeLane: String, CaseIterable { case code, design, copy, signal }

/// Everything the composer arms when the user clicks Send.
struct ComposeRouting: Equatable {
    /// `nil` ⇒ the Default Team (`TeamCatalog.defaultRunTeam`).
    var team: String?
    var to: String
    var effort: ComposeEffort
    var lane: ComposeLane
    var text: String
    var fileReferences: [FileReferenceInput] = []
    /// Pasted/picked images, frozen to temp files. Staged into the thread's attachment
    /// store on send and DELIVERED to every worker (single OR team) by the run path.
    var attachments: [ComposeAttachment] = []
}

/// A composer-captured attachment, frozen to a temp file on disk. The send path stages
/// it into the thread's canonical attachment store and hands the worker(s) its path.
struct ComposeAttachment: Identifiable, Equatable {
    let id: String
    /// Frozen temp file (PNG for images, .txt for captured long pastes).
    let fileURL: URL
    let displayName: String
    let kind: Kind
    enum Kind: Equatable { case image, text }
}

/// A bench model as the composer sees it (maps from AppModel).
struct ComposeBenchModel: Identifiable, Equatable {
    let id: String
    let name: String
    let driverId: String
    let cli: String
    let sub: String
    let ready: Bool
    var notReadyReason: String?
    /// Whether this worker exposes a reasoning-effort axis in the composer.
    let supportsEffort: Bool
}

/// A saved team for a lane (maps from TeamCatalog).
struct ComposeTeam: Identifiable, Equatable {
    let id: String
    let name: String
    let summary: String
    let isFavorite: Bool
    /// The craft this team belongs to — drives the row icon (the picker no longer
    /// filters by lane, so each row carries its own).
    var lane: ComposeLane = .code
    /// Curated starter team (built-in). Ranks above the plain A–Z tail so the picker is
    /// never blank on cold-start. (Until a real curation flag exists, built-in = featured.)
    var isFeatured: Bool = false
}

struct ComposeFileReference: Identifiable, Equatable {
    var path: String
    var id: String { path }
}

enum PopoverKeyAction { case up, down, enter, escape, tab }

/// Forwards ↑/↓/⏎/esc inside an NSPopover via a local NSEvent monitor — reliable where
/// SwiftUI `.onKeyPress` doesn't fire, and (unlike a first-responder catcher) it does NOT
/// steal focus, so a search field in the same popover keeps working. The handler returns
/// true to consume the event; other keys pass through (so typing still reaches the field).
struct PopoverKeyCatcher: NSViewRepresentable {
    var handle: (PopoverKeyAction) -> Bool

    func makeNSView(context: Context) -> NSView {
        context.coordinator.handle = handle
        context.coordinator.install()
        let view = NSView()
        view.setFrameSize(.zero)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.handle = handle
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.remove()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var handle: ((PopoverKeyAction) -> Bool)?
        private var monitor: Any?

        func install() {
            remove()
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                let action: PopoverKeyAction?
                switch event.keyCode {
                case 126: action = .up
                case 125: action = .down
                case 36, 76: action = .enter
                case 53: action = .escape
                case 48: action = .tab
                default: action = nil
                }
                if let action, self.handle?(action) == true { return nil }
                return event
            }
        }

        func remove() {
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        }

        deinit { remove() }
    }
}

extension ComposeEffort { var label: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() } }
extension ComposeLane {
    var label: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
    var icon: String { switch self { case .code: "hammer"; case .design: "photo"; case .copy: "doc.text"; case .signal: "antenna.radiowaves.left.and.right" } }
    var workLane: WorkLane { switch self { case .code: .code; case .design: .design; case .copy: .copy; case .signal: .signal } }
}
