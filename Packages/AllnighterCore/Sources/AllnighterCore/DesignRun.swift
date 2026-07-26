import Foundation

/// The design lane (Lane 2). Default Design means **built surface → host
/// screenshot** on the board (`BoardPayload` / artifact hero) — not Midjourney.
/// Law: `docs/phases/Design_Lane.md`. Historical Design0 diffusion/OCR contract
/// is superseded for the Design default; concept/`imageGen` seats remain
/// explicit opt-in only.
///
/// Each UI-design seat builds a bounded renderable surface (native fixture or
/// HTML). A **host capture step** in the team-run pipeline writes
/// `options[].imagePath`. Dead and not coming back: OCR / pHash as the design
/// gate, and silent diffusion as the Design default.

/// The render target a board is judged at. Inferred from an attached screenshot's
/// pixel dimensions, or chosen once for greenfield. Light — not the dead render
/// contract.
public enum TargetShape: String, Codable, Sendable, CaseIterable {
    case mobile
    case desktop
}

/// The reproducible input of a design run, persisted as `design_request.json`
/// alongside `run.json`. The personas also live on the workers' `stance`; this
/// is the honest, self-contained record of what was asked.
public struct DesignRequest: Codable, Sendable, Equatable {
    /// The user's instruction ("make this feel premium and clean").
    public var prompt: String
    /// The design personas spread across seats (e.g. `minimal`, `bold`, `editorial`,
    /// `on_brand`) — the source of range.
    public var personaIds: [String]
    /// Local path (relative to the run folder) of the attached "before" screenshot,
    /// if any. Shown to the user and read by the image engines; never OCR'd.
    public var screenshotPath: String?
    public var targetShape: TargetShape

    public init(
        prompt: String,
        personaIds: [String],
        screenshotPath: String? = nil,
        targetShape: TargetShape
    ) {
        self.prompt = prompt
        self.personaIds = personaIds
        self.screenshotPath = screenshotPath
        self.targetShape = targetShape
    }
}

/// One tile on the board: the generated design image for one seat. `imagePath` is
/// relative to the run folder (a normalized local PNG/JPEG); `nil` when the seat
/// failed (a gray tile + reason). `sessionId` is the engine's session handle, used
/// by "more like this" (resume + image edit).
public struct DesignOption: Codable, Sendable, Equatable, Identifiable {
    public var workerId: String
    public var modelId: String
    /// The design skill this worker wore (e.g. `bold`).
    public var persona: String
    public var imagePath: String?
    public var sessionId: String?
    public var status: StageStatus
    public var failureReason: String?

    public var id: String { workerId }
    public var hasImage: Bool { status == .done && (imagePath?.isEmpty == false) }

    public init(
        workerId: String,
        modelId: String,
        persona: String,
        imagePath: String? = nil,
        sessionId: String? = nil,
        status: StageStatus,
        failureReason: String? = nil
    ) {
        self.workerId = workerId
        self.modelId = modelId
        self.persona = persona
        self.imagePath = imagePath
        self.sessionId = sessionId
        self.status = status
        self.failureReason = failureReason
    }
}

/// The human's pick — a real decision artifact (adopted + rejected, with reasons),
/// logged for future taste memory. Persisted inside the latest `board` stage and as
/// `chosen_option.json`.
public struct ChosenOption: Codable, Sendable, Equatable {
    public var workerId: String
    public var persona: String
    /// User-authored ("why I picked this"); the best taste-ledger signal.
    public var rationale: String?
    /// Seats the user passed over (provenance for taste memory).
    public var rejectedWorkerIds: [String]
    public var chosenAt: Date?

    public init(
        workerId: String,
        persona: String,
        rationale: String? = nil,
        rejectedWorkerIds: [String] = [],
        chosenAt: Date? = nil
    ) {
        self.workerId = workerId
        self.persona = persona
        self.rationale = rationale
        self.rejectedWorkerIds = rejectedWorkerIds
        self.chosenAt = chosenAt
    }
}

/// The board: an ordered gallery of generated options at one render target, plus
/// the human's pick once made. The structured truth of the `board` stage; the UI
/// renders it as the first surface (no AI verdict precedes it).
public struct BoardPayload: Codable, Sendable, Equatable {
    public var targetShape: TargetShape
    /// The attached "before" screenshot (relative path), for the before/after toggle.
    public var screenshotPath: String?
    public var options: [DesignOption]
    /// Set when the human picks; `nil` while the board is still being judged.
    public var chosen: ChosenOption?

    public init(
        targetShape: TargetShape,
        screenshotPath: String? = nil,
        options: [DesignOption],
        chosen: ChosenOption? = nil
    ) {
        self.targetShape = targetShape
        self.screenshotPath = screenshotPath
        self.options = options
        self.chosen = chosen
    }

    /// Options that rendered successfully, in board order.
    public var rendered: [DesignOption] { options.filter(\.hasImage) }
}
