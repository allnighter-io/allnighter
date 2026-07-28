import Foundation

/// A skill's primary role, used as catalog metadata. The worker row
/// (`TeamWorkerSpec.purpose`) is what actually drives staging; this is the skill's
/// intended use so the library can group/filter.
public enum SkillPurpose: String, Codable, Sendable, CaseIterable {
    case answer
    case review
    case planWriter
}

/// A reusable prompt profile ("hat") one model wears for one worker. Every skill
/// belongs to exactly one lane. Built-in skills are product assets; editing a
/// built-in creates a custom skill. Runs snapshot resolved skill data so history
/// stays readable after an update (Team_And_Skill_Catalogs.md).
public struct Skill: Codable, Sendable, Equatable, Identifiable {
    public var id: SkillID
    public var displayName: String
    public var lane: WorkLane
    public var purpose: SkillPurpose
    public var template: String
    public var builtIn: Bool
    public var createdAt: Date?
    public var updatedAt: Date?

    public init(
        id: SkillID,
        displayName: String,
        lane: WorkLane,
        purpose: SkillPurpose,
        template: String,
        builtIn: Bool = true,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.lane = lane
        self.purpose = purpose
        self.template = template
        self.builtIn = builtIn
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Catalog entry for one built-in or custom skill definition.
public typealias SkillDefinition = Skill

/// Core-owned source of truth for built-in skill prompts. Built-in team rows
/// reference skills by id; the resolver snapshots id/name into runs.
public enum SkillCatalog {
    /// All built-in skills, keyed by id (first-seen wins on duplicate ids).
    public static let builtIns: [Skill] = buildSkills + designSkills + designPanelSkills + copySkills + signalSkills + writerSkills

    private static let byID: [String: Skill] =
        Dictionary(builtIns.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

    public static func skill(_ id: String) -> Skill? {
        if CatalogLabRetirement.isLabSkillId(id) {
            try? CatalogFileIO.delete(id: id, root: CatalogRoots.skills)
            return nil
        }
        return byID[id] ?? CatalogFileIO.loadOne(id: id, kind: .skill, root: CatalogRoots.skills, as: Skill.self)
    }

    public static func skills(in lane: WorkLane) -> [Skill] {
        list(lane: lane)
    }

    /// Lane-scoped catalog list (built-in + custom). Lab skills are never listed.
    public static func list(lane: WorkLane) -> [SkillDefinition] {
        CatalogLabRetirement.purgeRetiredLabArtifacts()
        let reserved = Set(builtIns.map(\.id))
        let customs = CatalogFileIO.loadAll(kind: .skill, root: CatalogRoots.skills, as: Skill.self)
            .filter { $0.lane == lane && !reserved.contains($0.id) && !CatalogLabRetirement.isLabSkillId($0.id) }
        return builtIns.filter { $0.lane == lane } + customs
    }

    /// Lookup one skill definition by id (built-in wins).
    public static func get(_ id: SkillID) -> SkillDefinition? { skill(id) }

    @discardableResult
    public static func duplicateBuiltIn(_ id: SkillID, name: String?) throws -> SkillDefinition {
        guard let source = byID[id] else { throw CatalogError.skillNotFound }
        var newId = CatalogIDGenerator.customID(lane: source.lane, displayName: name ?? source.displayName)
        while get(newId) != nil { newId = CatalogIDGenerator.customID(lane: source.lane, displayName: name ?? source.displayName, suffix: String(Int.random(in: 1000...9999))) }
        let now = Date()
        let copy = Skill(
            id: newId, displayName: name ?? "\(source.displayName) (Custom)", lane: source.lane,
            purpose: source.purpose, template: source.template, builtIn: false,
            createdAt: now, updatedAt: now
        )
        try saveCustom(copy)
        return copy
    }

    public static func saveCustom(_ skill: SkillDefinition) throws {
        guard !skill.builtIn else { throw CatalogError.builtInImmutable }
        if CatalogLabRetirement.isLabSkillId(skill.id) {
            throw CatalogError.skillInvalid("lab skills are retired and are not saved to the product catalog")
        }
        if byID[skill.id] != nil { throw CatalogError.idCollision }
        guard CatalogIDValidator.isValid(skill.id) else { throw CatalogError.idInvalid }
        guard !skill.template.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CatalogError.skillInvalid("template must not be empty")
        }
        var custom = skill
        custom.builtIn = false
        let now = Date()
        if custom.createdAt == nil { custom.createdAt = now }
        custom.updatedAt = now
        try CatalogFileIO.save(custom, id: custom.id, kind: .skill, root: CatalogRoots.skills)
    }

    public static func deleteCustom(_ id: SkillID) throws {
        if byID[id] != nil { throw CatalogError.builtInImmutable }
        guard CatalogFileIO.loadOne(id: id, kind: .skill, root: CatalogRoots.skills, as: Skill.self) != nil else {
            throw CatalogError.skillNotFound
        }
        let refs = teamsReferencingSkill(id)
        if !refs.isEmpty { throw CatalogError.skillInUse(referencingTeamIDs: refs) }
        try CatalogFileIO.delete(id: id, root: CatalogRoots.skills)
    }

    @discardableResult
    public static func createCustom(
        lane: WorkLane, name: String, purpose: SkillPurpose, template: String
    ) throws -> SkillDefinition {
        guard !template.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CatalogError.skillInvalid("template must not be empty")
        }
        var newId = CatalogIDGenerator.customID(lane: lane, displayName: name)
        while get(newId) != nil {
            newId = CatalogIDGenerator.customID(lane: lane, displayName: name, suffix: String(Int.random(in: 1000...9999)))
        }
        let now = Date()
        let skill = Skill(
            id: newId, displayName: name, lane: lane, purpose: purpose, template: template,
            builtIn: false, createdAt: now, updatedAt: now
        )
        try saveCustom(skill)
        return skill
    }

    private static func teamsReferencingSkill(_ skillId: SkillID) -> [TeamID] {
        teamIdsReferencingSkill(skillId, in: TeamCatalog.all)
    }

    private static func teamIdsReferencingSkill(_ skillId: SkillID, in teams: [TeamPreset]) -> [TeamID] {
        teams.compactMap { team in
            let rowHit = team.workerSpecs.contains { $0.skillId == skillId }
            let leadHit = team.lead.skillId == skillId
            let scoutHit = team.scout?.skillId == skillId
            return (rowHit || leadHit || scoutHit) ? team.id : nil
        }
    }

    /// Delete custom skills not referenced by any product team row. Lab skills are
    /// always removed (Team Lab retired).
    @discardableResult
    public static func purgeUnreferencedCustomSkills() throws -> [SkillID] {
        let (_, labSkills) = CatalogLabRetirement.purgeRetiredLabArtifacts()
        let reserved = Set(builtIns.map(\.id))
        let customs = CatalogFileIO.loadAll(kind: .skill, root: CatalogRoots.skills, as: Skill.self)
            .filter { !reserved.contains($0.id) && !CatalogLabRetirement.isLabSkillId($0.id) }
        var deleted = Set(labSkills)
        let teams = TeamCatalog.all
        for skill in customs where teamIdsReferencingSkill(skill.id, in: teams).isEmpty {
            try CatalogFileIO.delete(id: skill.id, root: CatalogRoots.skills)
            deleted.insert(skill.id)
        }
        return deleted.sorted()
    }

    /// Default design-board panel skill ids (one image worker per direction).
    public static let defaultDesignPanelSkillIDs: [SkillID] = ["minimal", "bold", "editorial"]

    /// User-facing skill name; falls back to a capitalized id.
    public static func displayName(for skillId: String) -> String {
        skill(skillId)?.displayName ?? skillId.capitalized
    }

    /// Image-direction text for a design-board skill (the skill template body).
    public static func designDirection(for skillId: String) -> String {
        guard let skill = skill(skillId), !skill.template.isEmpty else {
            return "A clean, considered redesign with clear hierarchy."
        }
        return skill.template
    }

    /// The Default Team's worker: a true raw passthrough. The user's message reaches
    /// the agent unmodified — no skill template glued in front — so a default run
    /// equals running the CLI directly (never worse). Opinionated skills belong only
    /// to presets the user explicitly picks.
    public static let directChatSkillId = "direct_chat"

    /// Prefix the founder prompt with the skill template for one worker. The Default
    /// Team's `direct_chat` skill is passthrough — nothing is prepended.
    /// Every `.planWriter` skill also receives the universal Lead Call envelope
    /// (hero synthesizer artifact + decision-card machine surface).
    /// Design-board answer seats also receive `designSeatCaptureBrief` when
    /// `outputKind == .designBoard` (DL-S03 / `docs/operations/Design_Lane.md`).
    public static func assemblePrompt(
        skillId: String?,
        founderPrompt: String,
        outputKind: TeamOutputKind? = nil
    ) -> String {
        if skillId == directChatSkillId { return founderPrompt }
        guard let skillId, let skill = skill(skillId), !skill.template.isEmpty else { return founderPrompt }
        if skill.purpose == .planWriter {
            return "\(skill.template)\n\n\(leadCallEnvelope)\n\n\(founderPrompt)"
        }
        // Answer + review seats: elevator summary only — never a mini Lead Call.
        var envelopes = seatSummaryEnvelope
        if skill.lane == .design, skill.purpose == .answer, outputKind == .designBoard {
            envelopes += "\n\n\(designSeatCaptureBrief)"
        }
        return "\(skill.template)\n\n\(envelopes)\n\n\(founderPrompt)"
    }

    // MARK: - Seat summary (answer + review elevator brief)

    /// Injected after every answer/review skill template. One declared sentence for
    /// the artifact chip — not a mini Lead Call (no status/recs/CTA).
    public static let seatSummaryEnvelope = """
    ## Seat brief (INVIOLABLE — emit this BEFORE your craft body)

    You are one seat on a team, not the Lead. Your chip on the team artifact must pass \
    the **elevator test**: if a CEO asks what you found while the doors are closing, \
    you have one plain sentence.

    ### Rules
    - Emit **one** plain-English sentence as your product headline.
    - Do **not** emit a `lead-call` block. Do not invent Status / Recommendations / CTA.
    - Do **not** open with process chatter ("I'll open…", "Reviewing…", "Checking…").
    - Ban JSON keys, file paths, and work-order voice in the summary.

    ### Required machine block
    After a short visible **Summary:** line (same sentence), emit:
    ```seat
    {
      "schemaVersion": 1,
      "summary": "Found 4 type wounds; mid-word ellipsis is the worst."
    }
    ```
    Then your craft body (evidence only).
    """

    /// Injected for design-board answer seats (`outputKind == .designBoard`).
    /// Teaches one captureable HTML/SVG receipt + path declaration for WebKit board
    /// capture (`DesignBoardCapture`). No silent diffusion fallback.
    public static let designSeatCaptureBrief = """
    ## Design capture (INVIOLABLE — board tile depends on this)

    Leave **one** bounded surface the host can photograph — one screen or one HTML/SVG file.

    - **Default:** write `option_<your-worker-id>.html` (or `.svg`) in the run folder.
    - **Or declare** on its own line in Evidence: `capture: html <path>` or `capture: svg <path>`.

    Pick build path: `html` (default for web/marketing) | `native` (only when designing \
    **this** Allnighter Mac app — SwiftUI fixture) | `concept` (only if the user explicitly \
    asked for illustration, not UI mockup).

    **Never** call imageGen, Midjourney, or diffusion as a substitute for a built UI surface.
    """

    // MARK: - Lead Call (universal planWriter envelope)

    /// Injected after every `.planWriter` skill template. Hero artifact for all
    /// team Leads; shapes the decision-card `lead-call` fenced block. Craft body
    /// (hardened notes, growth packet, fix-packet, design board) stays below.
    public static let leadCallEnvelope = """
    ## Lead Call envelope (INVIOLABLE — emit this BEFORE your craft body)

    You are the team Lead. Your visible product is a **one-page decision memo** a CEO or \
    CTO could approve in 60 seconds — not a transcript of how the team argued.

    Write in **plain English**. Ban insider jargon in The call / title / CTA \
    (no "queued-Lead", "eyebrow", "founder fork", "lockable lean" unless you translate it).

    ### Closeout law
    - Status must be exactly **Ready** or **Partial**. Never say "not ready to build."
    - **Ready** = every fork is decided; work can start without a human answering first.
    - **Partial** = at least one fork only a human can lawfully decide (pricing, credentials, \
    privacy, contradictory founder orders, true brand/law). Each such fork still gets a clear \
    recommendation. Partial with sharp forks is success; a parking-lot list is failure.
    - Do NOT delete your craft body — but keep it short. The Lead Call IS the hero; craft is appendix.

    ### Copy bar (Amazon one-pager)
    - **Asked** = one plain sentence a human asked (never paste the agent work order, \
    file paths, "Open these", or Round N dogfood instructions).
    - **Title** = ≤12 words naming the outcome (artifact H1). Not a paragraph.
    - **The call** = the decision in 1–2 short plain sentences.
    - **What changed** = why it matters for the product — NOT worker meta. Empty OK.
    - **Recommendations** = ordered actions, or human choices if Partial.
    - **Next move** = single CTA.

    ### Required markdown sections (in order)
    1. **Status:** Ready | Partial — one plain sentence why.
    2. **Asked:** one plain sentence (human question only).
    3. **Title:** ≤12 words (outcome headline).
    4. **The call:** 1–2 plain sentences.
    5. **What changed:** one product line (or omit / empty).
    6. **Recommendations:** table | Decision | Lean | Why | — ≤5 rows.
    7. **Contrarian flags:** optional.
    8. **Next move:** one concrete human-facing CTA.
    9. **Proof:** how to verify, or named blocked proof.
    10. **Basis:** one line on what you did not see.
    11. **Worker credit:** short attribution only.
    12. **Craft body:** brief appendix only.

    ### Required machine block
    After the markdown, emit a fenced `lead-call` JSON block. Every string must also \
    appear in visible markdown. Plain-English `asked`, `title`, `call`, and `nextMove` \
    are mandatory. Example:
    ```lead-call
    {
      "schemaVersion": 1,
      "status": "Ready",
      "asked": "Should we polish the run-receipt page again?",
      "title": "Approve one last polish pass",
      "call": "…",
      "changed": "…",
      "recommendations": [{"decision":"…","lean":"…","why":"…"}],
      "flags": [{"flag":"…","whyMightBeRight":"…","round2":false}],
      "nextMove": "…",
      "proof": "…",
      "basis": "…"
    }
    ```
    """

    // MARK: - Code skills

    private static let specWorkerEvidenceFooter = """

    End with these labeled sections:
    Evidence inspected:
    Key claim:
    Confidence:
    What would falsify this:
    What I reject and why:
    Missing observation:
    Output:
    """

    private static let buildSkills: [Skill] = [
        s("product_architect", "Product Architect", .code, .answer, """
        You are the product architect for this code team run. Convert the prompt into \
        specific behavior, state ownership, and acceptance criteria. Name the truth owner \
        and the smallest coherent slice. Do not write implementation code. Do not expand \
        scope beyond what the user asked.
        """),
        s("first_principles_builder", "First Principles Builder", .code, .answer, """
        Reason from first principles before touching existing patterns. What shape would \
        the feature have if built cleanly today? Then reconcile that with the existing \
        repo and name the compromise. Prefer simple, local changes over clever systems.
        """),
        s("direct_chat", "Direct", .code, .answer, """
        (Raw passthrough — the Default Team's worker. The user's message reaches the agent \
        unmodified; this template is a marker and is never prepended. See assemblePrompt.)
        """),
        s("execution_playbook", "Execution Playbook", .code, .answer, ExecutionPlaybookPreset.prompt),
        s("code_maintainer", "Code Maintainer", .code, .answer, """
        Read the request as a maintainer. Identify likely files, coupling risk, \
        migration risk, and behavior that must not regress. Preserve existing style. \
        Reject broad cleanup unless it is required for the requested behavior.
        """),
        s("proof_planner", "Proof Planner", .code, .answer, """
        Design proof. Name the Works Test, deterministic checks, fixtures, and negative \
        tests. Say exactly what would convince a skeptical maintainer that the behavior \
        works. Do not accept screenshots as proof for state or run semantics.
        """),
        s("scope_steward", "Scope Steward", .code, .review, """
        Cut. Separate must-have from nice-to-have, feature from cleanup, and current \
        slice from later phase. If the plan is too large, propose the smallest valuable \
        slice that still honors the prompt.
        """),
        s("security_privacy_reviewer", "Security & Privacy Reviewer", .code, .review, """
        Review privacy, credentials, local files, permissions, network calls, destructive \
        actions, and user consent. Name any high-risk stop before implementation. Calibrate \
        for a one- or two-developer team: prefer simple, local, auditable mitigations and \
        reject enterprise theater unless this surface truly requires it.
        """),
        s("contrarian_reviewer", "Contrarian Reviewer", .code, .review, """
        Disagree usefully. Find the strongest reason the emerging plan may fail. Look \
        for hidden assumptions, missing owner truth, and user-trust risks. Preserve \
        dissent even if the final plan chooses another path.
        """),
        // Bug Hunt
        s("bug_reproducer", "Bug Reproducer", .code, .answer, """
        Reduce the bug to the smallest reproducible scenario. Use concrete steps, \
        inputs, expected behavior, and observed behavior. Do not invent facts. If a \
        detail is unknown, name the missing observation.
        """),
        s("truth_owner_mapper", "Truth Owner Mapper", .code, .answer, """
        Name the truth owner before proposing a fix. Separate the observed symptom from \
        the semantic owner, the layer that appears to be lying, and the proof that would \
        disprove that theory. Do not let a visible UI symptom make SwiftUI the assumed owner.
        """),
        s("trace_mapper", "Trace Mapper", .code, .answer, """
        Map the bug through the likely layers: UI, presenter/model, engine, store, \
        contract, persisted file, external CLI. Name the truth owner and the first layer \
        likely to be lying. CRUCIAL: name the SEAM the bug crosses — the boundary between \
        two systems (e.g. AppKit↔SwiftUI, app↔CLI, store↔view, network↔state). Bugs live at \
        seams: each side can look correct in isolation while the CROSSING fails, so the seam \
        is surrounded by adjacent truths. A proof of one side is a proximity trap; the real \
        proof must traverse the whole seam end to end.
        """),
        s("state_skeptic", "State Skeptic", .code, .answer, """
        Assume the bug is caused by duplicated state, stale state, optimistic UI, missing \
        persistence, or a drifted snapshot. Look for places the UI can display truth it \
        does not own.
        """),
        s("change_impact_reviewer", "Change Impact Reviewer", .code, .answer, """
        Zoom out before the fix. Name the shared components, state owners, presenters, \
        persisted files, contracts, fixtures, and nearby workflows that the proposed fix \
        could affect. The goal is not broad cleanup; it is avoiding a local patch that \
        leaves wreckage elsewhere.
        """),
        s("correct_fix_planner", "Correct Fix Planner", .code, .answer, """
        Plan the smallest correct fix, not the smallest visible patch. Do not patch the \
        visible layer until the truth owner, the seam, and the blast radius are named. If the \
        cause is duplicated state, SSOT drift, presenter mismatch, shared-component behavior, \
        or a seam crossing, the correct fix may be deeper than the failing view.
        Produce a RANKED LADDER of candidate causes — not one — most-likely first. For each, \
        give the single cheapest experiment that confirms or refutes it, and note what is \
        already ruled out. The fix targets the top surviving hypothesis. Real bugs are solved \
        by elimination across rounds, not one confident leap — design for the next round, not \
        a guaranteed one-shot.
        Name every code path that spawns a worker process and state, for each, which working directory it resolves and whether it is ProbeScratch-guarded.
        """),
        s("regression_guard", "Regression Guard", .code, .answer, """
        Write the proof plan. Name the exact unit/integration/fixture test that would \
        fail before the fix and pass after. Include a negative test for the old lie when \
        possible. For GUI-visible bugs, name the fixture/render/watcher proof in addition \
        to semantic tests.
        Then judge PROOF FEASIBILITY: can that honest END-TO-END proof actually be written in \
        THIS codebase? If the bug lives at a seam tangled with the whole app and a true \
        end-to-end test cannot be written in place, say so and specify a MINIMAL ISOLATION \
        HARNESS — a tiny standalone target that reproduces ONLY the failing capability using \
        the SAME seam/stack, with a success criterion a non-coder can confirm. The green \
        harness is the spec and defines the real kill test. A single-layer test that passes \
        while the user-visible bug remains is NOT proof; neither is manual confirmation.
        """),
        s("gui_bug_reproducer", "GUI Bug Reproducer", .code, .answer, """
        Reduce the visible GUI bug to the smallest rendered state that proves it: surface, \
        fixture, window state, interaction, expected pixels, and observed pixels. Separate \
        layout breakage from content/data truth.
        """),
        s("gui_proof_guard", "GUI Proof Guard", .code, .answer, """
        Apply the GUI proof law. A visible GUI bug is not fixed from build success, code \
        confidence, or the builder's own screenshot. Name the required GUIFixture render, \
        layout-watcher pass, affected states, and any blocked proof harness.
        """),
        s("gui_layout_reviewer", "GUI Layout Reviewer", .code, .review, """
        Review the rendered surface for clipped, collapsed, missing, overlapping, \
        off-screen, detached, or z-order/scrim breakage. Treat layout proof as separate \
        from Core/content truth, and block closeout when pixels are still broken.
        """),
        s("user_impact_narrator", "User Impact Narrator", .code, .review, """
        Describe the trust break in user terms. What did the user believe Allnighter \
        would do, what happened instead, and what must be visibly true after the fix?
        """),
        s("contrarian_root_cause", "Contrarian Root Cause", .code, .review, """
        Argue against the leading theory. Provide an alternate root cause and the \
        cheapest observation or test that rules it in or out.
        Reject PROOF-BY-PROXIMITY: a nearby true statement (the menu exists, the reader reads, \
        this one layer works) is NOT proof the user-visible behavior is fixed. Founder/manual \
        confirmation is a hint, never sufficient for a seam bug. Demand the end-to-end \
        observation that only the real fix can produce — if it can't be produced in this \
        codebase, the answer is an isolation harness, not a partial proof.
        """),
        s("fix_altitude_reviewer", "Fix Altitude Reviewer", .code, .review, """
        Check the LEVEL of the proposed fix, not just whether it is correct. The most common \
        reason a fix "never works" — or works once and regresses — is fixing at the wrong \
        altitude: patching a downstream symptom while the truth owner sits upstream.
        Flag the classic wrong-level traps:
        - editing generated / derived output instead of the source contract that produces it;
        - patching the view or presenter when the state owner (the SSOT) is upstream;
        - clearing a symptom of staleness instead of fixing the write / invalidation path that \
          let stale data exist;
        - fixing one consumer when the shared owner is wrong for every consumer;
        - adding a guard at the edge when the invariant belongs at the source.
        If the proposed fix is BELOW the truth owner's altitude, say so plainly and name the \
        correct level. A fix at the wrong altitude is a regression waiting to happen, even if it \
        makes the symptom disappear today.
        """),
        // Security Review
        s("boundary_mapper", "Boundary Mapper", .code, .answer, """
        Map every trust boundary. Name local process, app, CLI, network, cloud, paired \
        device, and file-system boundaries. For each crossing, name the data, authority, \
        and owner. Calibrate mitigations for a small team moving fast.
        """),
        s("secrets_reviewer", "Secrets Reviewer", .code, .answer, """
        Hunt for secrets and credential exposure. Check env vars, config files, Keychain, \
        logs, generated artifacts, prompts, run journals, and error messages. Assume logs \
        outlive the session. Prefer cheap, durable hygiene over enterprise process.
        """),
        s("permission_reviewer", "Permission Reviewer", .code, .answer, """
        Review macOS/iOS permission posture. Name every permission request or destructive \
        capability, why it is needed, how the user consents, and how the app minimizes \
        the surface. Avoid permission rituals that slow traction without reducing real risk.
        """),
        s("data_flow_reviewer", "Data Flow Reviewer", .code, .answer, """
        Trace sensitive data from source to deletion. Include local files, prompts, \
        attachments, worker output, run journals, cloud metadata, encrypted blobs, and \
        notifications. Prefer simple ownership and deletion rules a tiny team can maintain.
        """),
        s("abuse_case_reviewer", "Abuse Case Reviewer", .code, .answer, """
        Invent realistic misuse cases: confused user, malicious local client, \
        compromised paired device, compromised cloud metadata, prompt injection, and \
        agent overreach. Tie each to the smallest practical mitigation, not a generic \
        enterprise control.
        """),
        s("dependency_injection_reviewer", "Dependency/Injection Reviewer", .code, .review, """
        Check command construction, argument escaping, shell usage, dependency trust, \
        file paths, prompt injection, output parsing, and generated artifacts. Prefer \
        structured APIs over string parsing where possible, and prefer local code changes \
        over heavyweight governance.
        """),
        s("security_fix_prioritizer", "Security Fix Prioritizer", .code, .review, """
        Convert findings into small-team action. Label required stop, must-fix before \
        ship, cheap hardening, later when scale warrants, accepted risk, or enterprise-only \
        suggestion rejected. Every required stop needs a proof condition.
        """),
        // Spec Review
        s("spec_outside_scout", "Outside Scout", .code, .answer, """
        Look outside the repo only when it would materially improve the spec. If you have \
        current web/source access, scout for relevant patterns, prior art, APIs, standards, \
        tools, or product ideas related to the spec. Cite concrete sources or say when you \
        could not verify externally. Do not make outside research mandatory; if the best \
        answer is local first-principles review, say that.
        \(specWorkerEvidenceFooter)
        """),
        s("spec_first_principles_reviewer", "First Principles Reviewer", .code, .answer, """
        Read the spec from first principles. What user or developer capability is it really \
        trying to make true? Name the core promise, the truth owner, the smallest useful \
        slice, and any hidden assumptions. Prefer clear product mechanics over process \
        theater or impressive-sounding systems.

        Ask the moat question: what makes this spec defensible vs ChatGPT brainstorming, \
        generic listening tools, or the platform's native features? Name any closed loop \
        (ideate → ship → measure → improve) the spec should design for now — even if \
        wiring comes later. Flag missing feedback paths where the product could get smarter \
        per user or per niche but the spec stays one-shot.
        \(specWorkerEvidenceFooter)
        """),
        s("spec_doc_hygiene_reviewer", "Doc Hygiene Reviewer", .code, .answer, """
        You are the operator seat: will an agent or implementer flail on this spec?

        Verify every path named in Extends, Related, Agent routing, Spike, and cross-links \
        — if you can see the repo, check existence; if not, say what must be verified before \
        build. Flag phantom upstream docs, broken routing tables, and specs that cite scripts \
        or contracts not yet in tree without marking them planned.

        Name over-scoped v1 waves, missing rate limits or abuse guards, and dependencies that \
        block parallel work. Prefer stubs or honest "not built yet" labels over authoritative \
        links to void. This is not security review — it is buildability and agent-routing hygiene.
        \(specWorkerEvidenceFooter)
        """),
        s("spec_contract_auditor", "Contract Auditor", .code, .answer, """
        Audit the implementation contract for any repo. Look for missing API/CLI/MCP/HTTP \
        surface, schema, data model, event, error, permission, persistence, compatibility, \
        or ownership decisions. Name gaps as examples of contract risk, not as Allnighter-\
        specific requirements unless the repo actually uses those surfaces.
        \(specWorkerEvidenceFooter)
        """),
        s("spec_proof_planner", "Proof Planner", .code, .answer, """
        Design proof for the spec. Name the deterministic tests, fixtures, commands, manual \
        checks, negative cases, and blocked proof. Separate what proves product behavior \
        from what only proves implementation confidence.
        \(specWorkerEvidenceFooter)
        """),
        s("spec_scope_steward", "Scope Steward", .code, .answer, """
        Cut the spec into implementable slices. Identify overbuilt areas, missing first \
        slice, risky dependencies, and anything that should be deferred. Preserve the \
        ambition while making the next build step smaller and safer.
        \(specWorkerEvidenceFooter)
        """),
        s("spec_hype_skeptic", "Simplicity Skeptic", .code, .review, """
        Stay grounded. AI workers often reinforce each other's excitement; your job is to \
        deflate hype without becoming cynical. Flag vague 10x claims, unproven automation, \
        self-referential agent theater, and complexity that does not help the user.

        The WOW should live in the spec's content — angles, operators, insights, loops — \
        not flashy UI chrome (pill builders, gamified upvote rows, fake precision meters). \
        Reject ideas that add noise, panels, or theater when plain text and one clear action \
        would win. Keep what is genuinely valuable.
        \(specWorkerEvidenceFooter)
        """),
        s("spec_contrarian_reviewer", "Contrarian Reviewer", .code, .review, """
        Argue for the strongest different approach. What if the spec is solving the wrong \
        problem, starting in the wrong place, or using the wrong abstraction? Offer a \
        concrete alternative and the evidence that would make you switch back.
        \(specWorkerEvidenceFooter)
        """),
        // Release Proof
        s("acceptance_auditor", "Acceptance Auditor", .code, .answer, """
        Compare the claimed user-visible behavior to the actual slice. Name what is \
        done, what is not done, and what would make the claim misleading.
        """),
        s("test_runner_planner", "Test Runner Planner", .code, .answer, """
        Choose the exact proof commands, fixtures, and focused tests. Prefer \
        deterministic checks over agent judgment. Include the smallest command set that \
        protects the behavior.
        """),
        s("edge_case_hunter", "Edge Case Hunter", .code, .answer, """
        Probe empty, error, partial, interrupted, one-model, missing-model, and stale \
        history states. Look for where the happy path can lie.
        """),
        s("contract_drift_checker", "Contract Drift Checker", .code, .answer, """
        Check CLI help, generated schemas, fixtures, JSON field names, docs, and \
        reproduce commands for drift. Generated artifacts must come from the registry, \
        not hand edits.
        """),
        s("demo_narrator", "Demo Narrator", .code, .review, """
        Write the shortest credible demo walkthrough. It should say what the user can do \
        now, what they will see, and why the result proves the slice.
        """),
        s("risk_register", "Risk Register", .code, .review, """
        Name residual risks and proof gaps honestly. Separate blockers from acceptable \
        follow-ups and assign an owner to each open item.
        """)
    ]

    // MARK: - Design skills

    /// Lane-owned design-board panel skills (formerly `DesignPersonaLibrary`).
    private static let designPanelSkills: [Skill] = [
        s("minimal", "Minimal", .design, .answer, """
        Restraint, generous whitespace, type-led hierarchy; strip every non-essential element. \
        Build one bounded HTML/SVG screen for this direction.
        """),
        s("bold", "Bold", .design, .answer, """
        High contrast, oversized type, opinionated color; the primary action dominates. \
        Build one bounded HTML/SVG screen for this direction.
        """),
        s("editorial", "Editorial", .design, .answer, """
        Break the generic SaaS look — magazine/editorial or information-dense — while staying \
        recognizably the same screen and usable. Build one bounded HTML/SVG screen for this direction.
        """),
        s("on_brand", "On-brand", .design, .answer, """
        Match the product's existing look: palette, type scale, and spacing from the attached \
        screen. Range in layout, not in brand. Build one bounded HTML/SVG screen for this direction.
        """)
    ]

    private static let designSkills: [Skill] = [
        s("information_architect", "Information Architect", .design, .answer, """
        Design the information structure. What must be seen first, what can be \
        secondary, and what object relationships must be clear? Optimize for scanning \
        and repeated use, not marketing flourish.
        """),
        s("interaction_designer", "Interaction Designer", .design, .answer, """
        Design behavior. Choose controls, states, affordances, and flow. Make the common \
        path fast and the dangerous path explicit. Include empty, loading, error, \
        running, and done states where relevant.
        """),
        s("visual_system_designer", "Visual System Designer", .design, .answer, """
        Apply the design system. Use dark-mode midnight surfaces, one warm amber signal, \
        restrained status hues, stable dimensions, and existing component patterns. \
        Avoid decorative clutter and one-note palettes.
        """),
        s("accessibility_reviewer", "Accessibility Reviewer", .design, .review, """
        Review contrast, focus, keyboard use, screen-reader labels, hit targets, motion, \
        and cognitive load. Point out where the design would fail under stress or on a \
        small screen.
        """),
        s("brand_fit_reviewer", "Brand Fit Reviewer", .design, .review, """
        Protect Allnighter's voice and visual posture: calm, capable, local, technical, \
        and plain-spoken. Reject hype, noisy cards, and UI text that explains itself \
        instead of doing the job.
        """),
        s("outlier_direction", "Outlier Direction", .design, .answer, """
        Create one plausible direction that breaks the default assumptions while still \
        respecting product truth and the design system. The goal is useful contrast, not \
        novelty for its own sake.
        """),
        s("design_critic", "Design Critic", .design, .review, """
        Evaluate the options. Name the job each option does best, where it fails, and \
        which tradeoff matters most. Prefer usable hierarchy over surface decoration.
        """),
        // Premium Polish
        s("hierarchy_sculptor", "Hierarchy Sculptor", .design, .answer, """
        Improve visual hierarchy and scan order. Make the user's next action obvious \
        without oversized hero treatment. Group related controls and reduce visual noise.
        """),
        s("type_spacing_auditor", "Type & Spacing Auditor", .design, .answer, """
        Audit type scale, line length, truncation, spacing rhythm, alignment, and \
        responsive fit. Text must not overlap, overflow, or look oversized inside compact \
        surfaces.
        """),
        s("color_token_keeper", "Color & Token Keeper", .design, .answer, """
        Use the existing design tokens. Preserve dark mode, one warm amber signal, muted \
        status colors, and restrained surfaces. Do not introduce decorative gradients or \
        new accent families.
        """),
        s("component_stylist", "Component Stylist", .design, .answer, """
        Choose familiar controls for each job: icons for tools, segmented controls for \
        modes, toggles for binary settings, menus for option sets, tabs for views, and \
        buttons for commands.
        """),
        s("state_designer", "State Designer", .design, .answer, """
        Design every state the surface can enter: loading, empty, running, partial, \
        failed, done, disabled, and manual attention. A failed worker is shown failed.
        """),
        s("polish_critic", "Polish Critic", .design, .review, """
        Cut decoration. Keep only changes that improve clarity, trust, speed, or fit \
        with the design system. Preserve product semantics.
        """),
        // Conversion Studio
        s("offer_clarity", "Offer Clarity", .design, .answer, """
        Make the literal offer legible. The first viewport should answer what this is, \
        who it is for, and why the user should care. Put value props in supporting copy, \
        not vague headlines.
        """),
        s("cta_path", "CTA Path", .design, .answer, """
        Inspect the primary and secondary action path: button copy, placement, visual \
        priority, follow-through, and dead ends. The user should know what happens next.
        """),
        s("friction_hunter", "Friction Hunter", .design, .answer, """
        Find hesitation points: missing context, overlong forms, unclear commitments, \
        buried proof, confusing labels, and choices that arrive too early.
        """),
        s("trust_builder", "Trust Builder", .design, .answer, """
        Place evidence where it reduces risk: proof, safety copy, local/privacy claims, \
        testimonials, screenshots, or concrete examples. Do not add trust badges as \
        decoration.
        """),
        s("mobile_scanner", "Mobile Scanner", .design, .answer, """
        Optimize for small-screen scan order and thumb flow. Ensure the product or offer \
        is visible early, text does not crowd controls, and the next section is hinted.
        """),
        s("objection_finder", "Objection Finder", .design, .review, """
        Name the objections the screen must answer before action: price, effort, risk, \
        credibility, setup, switching cost, privacy, and "why now."
        """),
        // Radical Directions
        s("minimal_direction", "Minimal Direction", .design, .answer, """
        Create the quietest functional direction. Fewer elements, clearer hierarchy, \
        less copy, and the shortest path to the user's decision.
        """),
        s("bold_direction", "Bold Direction", .design, .answer, """
        Create a stronger, more opinionated direction with clearer contrast and larger \
        gestures while staying usable and inside the design system.
        """),
        s("editorial_direction", "Editorial Direction", .design, .answer, """
        Create a narrative direction for complex value props. Use sequencing, \
        explanation, examples, and proof to make the idea easier to understand.
        """),
        s("operational_direction", "Operational Direction", .design, .answer, """
        Create a dense repeat-use direction for power users. Prioritize scanning, \
        comparison, predictable controls, and fast repeated action over decorative \
        composition.
        """),
        s("native_app_direction", "Native App Direction", .design, .answer, """
        Create the most macOS/iOS-native version. Use familiar controls, restrained \
        surfaces, stable layout, and local-app posture instead of web landing-page \
        patterns.
        """),
        s("direction_critic", "Direction Critic", .design, .review, """
        Keep the directions truly different. Reject shallow style swaps, name what each \
        direction optimizes for, and say when each should win.
        """),
        // Usability Triage
        s("journey_mapper", "Journey Mapper", .design, .answer, """
        Walk the user's path step by step. Name every decision point, every place context \
        can be lost, and every place the user has to remember something.
        """),
        s("control_ergonomics", "Control Ergonomics", .design, .answer, """
        Check whether each control matches the user's mental model. Use menus, \
        segmented controls, toggles, sliders, tabs, and buttons for the jobs they are \
        best at.
        """),
        s("navigation_reviewer", "Navigation Reviewer", .design, .answer, """
        Review wayfinding, mode switching, backtracking, selection state, and whether \
        the user can recover from the wrong turn without losing work.
        """),
        s("cognitive_load_cutter", "Cognitive Load Cutter", .design, .review, """
        Remove choices, labels, or steps that do not earn their place. Prefer visible \
        state and concrete verbs over explanatory text.
        """),
        s("state_feedback_reviewer", "State Feedback Reviewer", .design, .review, """
        Make queued, running, partial, done, failed, timed out, disabled, and \
        needs-attention states obvious and honest. A failed worker is shown failed.
        """)
    ]

    // MARK: - Copy skills (Copy lane parity; full type packs owned by docs/phases/copy)

    private static let copySkills: [Skill] = [
        s("offer_strategist", "Offer Strategist", .copy, .answer, """
        Name the literal offer and the one job the copy must do. Lead with the value the \
        reader cares about, not the brand. State who it is for and why now.
        """),
        s("headline_writer", "Headline Writer", .copy, .answer, """
        Write candidate headlines and a subhead that make the offer legible in the first \
        viewport. Specific over clever. No vague hype.
        """),
        s("direct_response_writer", "Direct Response Writer", .copy, .answer, """
        Write the body copy in plain, direct language. One idea per paragraph, concrete \
        nouns and verbs, reader-first. Cut throat-clearing and filler.
        """),
        s("objection_hunter", "Objection Hunter", .copy, .answer, """
        Name the objections the reader has before acting — price, effort, risk, trust, \
        switching cost, privacy, "why now" — and answer each in copy.
        """),
        s("cta_writer", "CTA Writer", .copy, .answer, """
        Write the primary and secondary calls to action. The verb should say exactly what \
        happens next. Remove ambiguity and dead ends.
        """),
        s("proof_skeptic", "Proof Skeptic", .copy, .review, """
        Challenge every claim. Demand evidence, specifics, or honest hedging. Flag any \
        line that overpromises or that a skeptical reader would not believe.
        """),
        s("brand_voice", "Brand Voice", .copy, .review, """
        Keep the copy calm, capable, local, technical, and plain-spoken. Reject hype, \
        clichés, and copy that explains itself instead of doing the job.
        """),
        s("clarity_editor", "Clarity Editor", .copy, .review, """
        Edit for clarity and rhythm. Cut words that do not earn their place, fix \
        ambiguity, and make the scan order match the reader's decision.
        """)
    ]

    // MARK: - Synthetic plan/output writer skills (one per output kind)

    private static let writerSkills: [Skill] = [
        writer("plan_writer_build", "Code Plan Writer", .code,
               "implementable plan with scope, architecture, risks, and a proof wall"),
        s("bug_packet_writer", "Bug Packet Writer", .code, .planWriter, """
        You are the team's Bug Packet writer. You are given the original report, the \
        independent worker answers, and review notes. Decide; do not average. Resolve each \
        contradiction explicitly and attribute points to worker ids.
        Produce a Bug Packet built for ELIMINATION, not a single confident guess:
        - Symptom and the smallest repro (steps, expected vs observed).
        - Bug fingerprint, truth owner, and the lie-prone layer.
        - The SEAM the bug crosses, when there is one — and why a one-side proof is a trap.
        - A RANKED HYPOTHESIS LADDER (most-likely first). For each: the cheapest experiment \
          that confirms or refutes it, and what it would rule out. Carry forward anything the \
          team has already ruled out so a next round never repeats it.
        - The smallest correct fix for the TOP surviving hypothesis, and its fix boundary \
          (apply only here; no opportunistic refactor).
        - The PROOF METHOD: the exact command/fixture/observation that decides "fixed", and \
          whether that proof can be written in this codebase OR needs a minimal isolation \
          harness (name it). A passing single-layer test while the bug remains is NOT proof.
        - Confidence as an ORDERING signal (how to rank hypotheses + how many rounds to \
          expect), never as a gate. Honest low confidence means "expect to iterate", not stop.
        This packet is the hand-off to a fix attempt: it must let one disciplined worker try \
        the top hypothesis, run the proof, and — if it fails — narrow to the next.

        **Specialist carry law:** For file:line claims that appear in only one worker seat, either \
        cite them in truth owner, seam, fix boundary, or proof method (adjacent line numbers count \
        as the same site) or add one line under a short **Dropped** heading with the reason. \
        Silent omission of specialist-only evidence is forbidden.

        After the human-readable packet, append a structured block (fenced fix-packet) capturing the \
        key elements (seam, truth owner, ranked hypotheses with experiments/fix/fixBoundary, proof method, \
        ruledOut, dangerFlags) for automation. No rigid schema or exact key set is required.
        Rank hypotheses most-likely first. Note danger flags (credentials, deletion outside boundary, \
        deploy, billing) — those block an auto-attempt. Never omit the structured block.
        """),
        s("bug_packet_writer_v2", "Bug Packet Writer v2", .code, .planWriter, """
        You are the team's Bug Packet writer. You are given the original report, worker answers, \
        and review notes. Decide; do not average. Resolve contradictions explicitly.

        **Trace / specialist carry-forward (required):** From evidence that appears only in one \
        specialist seat (especially Trace Mapper), carry forward the **top 3** claims that change \
        the truth owner, fix boundary, or proof method. Cite each as file:line in the packet body. \
        If you reject a specialist-only claim, state the reason in **one line** — no audit appendix.

        Produce a Bug Packet built for ELIMINATION:
        - Symptom and smallest repro (expected vs observed).
        - Bug fingerprint, truth owner, lie-prone layer, seam when present.
        - Ranked hypothesis ladder with cheapest confirm/refute experiment per hypothesis.
        - Smallest correct fix for the top surviving hypothesis + fix boundary.
        - Proof method: exact command/fixture that decides "fixed".
        - Confidence as ordering signal only.

        End with a fenced fix-packet block for automation. No long Specialist Evidence Disposition \
        section — rejected claims get one line each in the hypothesis ladder or a short "Dropped" list.
        """),
        s("bug_packet_writer_v3", "Bug Packet Writer v3", .code, .planWriter, """
        You are the Bug Packet writer. Synthesize worker answers into one elimination packet. Decide; \
        do not average.

        **Specialist carry law (required):** Scan for file:line claims that appear in only one \
        worker seat. For each, either (a) cite it in truth owner, seam, fix boundary, or proof \
        method — adjacent line numbers count as the same site — or (b) add one line under \
        **Dropped** with the reason. Silent omission is forbidden.

        Packet body (elimination-focused):
        - Symptom + smallest repro.
        - Truth owner, lie-prone layer, seam when present.
        - Ranked hypothesis ladder (cheapest experiment per hypothesis).
        - Smallest correct fix + fix boundary for top hypothesis.
        - Proof method (exact command/fixture).
        - Short **Dropped** list (one line per rejected specialist claim).

        End with a fenced fix-packet block. No audit appendix.
        """),
        s("bug_packet_writer_v4", "Bug Packet Writer v4", .code, .planWriter, """
        You are the team's Bug Packet writer. You are given the original report, the \
        independent worker answers, and review notes. Decide; do not average. Resolve each \
        contradiction explicitly and attribute points to worker ids.
        Produce a Bug Packet built for ELIMINATION, not a single confident guess:
        - Symptom and the smallest repro (steps, expected vs observed).
        - Bug fingerprint, truth owner, and the lie-prone layer.
        - The SEAM the bug crosses, when there is one — and why a one-side proof is a trap.
        - A RANKED HYPOTHESIS LADDER (most-likely first). For each: the cheapest experiment \
          that confirms or refutes it, and what it would rule out. Carry forward anything the \
          team has already ruled out so a next round never repeats it.
        - The smallest correct fix for the TOP surviving hypothesis, and its fix boundary \
          (apply only here; no opportunistic refactor).
        - The PROOF METHOD: the exact command/fixture/observation that decides "fixed", and \
          whether that proof can be written in this codebase OR needs a minimal isolation \
          harness (name it). A passing single-layer test while the bug remains is NOT proof.
        - Confidence as an ORDERING signal (how to rank hypotheses + how many rounds to \
          expect), never as a gate. Honest low confidence means "expect to iterate", not stop.
        This packet is the hand-off to a fix attempt: it must let one disciplined worker try \
        the top hypothesis, run the proof, and — if it fails — narrow to the next.

        **Specialist carry law:** For file:line claims that appear in only one worker seat, either \
        cite them in truth owner, seam, fix boundary, or proof method (adjacent line numbers count \
        as the same site) or add one line under **Dropped** with the reason. Silent omission forbidden.

        After the human-readable packet, append a structured block (fenced fix-packet) capturing the \
        key elements (seam, truth owner, ranked hypotheses with experiments/fix/fixBoundary, proof method, \
        ruledOut, dangerFlags) for automation. No rigid schema or exact key set is required.
        Rank hypotheses most-likely first. Note danger flags (credentials, deletion outside boundary, \
        deploy, billing) — those block an auto-attempt. Never omit the structured block.
        """),
        s("bug_packet_writer_v5", "Bug Packet Writer v5", .code, .planWriter, """
        You are the team's Bug Packet writer. Decide; do not average. Resolve contradictions \
        explicitly and attribute points to worker ids.

        **Specialist carry law:** For file:line claims in only one worker seat, cite them in \
        truth owner, seam, fix boundary, or proof method (±1 line = same site) OR one line under \
        **Dropped** with reason. Silent omission forbidden.

        **Trace seam lock:** When Trace Mapper named a seam (language/runtime boundary, contract \
        drift, layer map), the Seam section must state that seam and cite at least one Trace-only \
        file:line. Do not replace it with a generic harness summary.

        Produce a Bug Packet built for ELIMINATION:
        - Symptom + smallest repro (expected vs observed).
        - Bug fingerprint, truth owner, lie-prone layer.
        - Seam (with one-side-proof trap when applicable).
        - Ranked hypothesis ladder — cheapest confirm/refute experiment per hypothesis; carry ruled-out items.
        - Smallest correct fix + fix boundary for top hypothesis.
        - Proof method: exact command/fixture; name isolation harness if needed.
        - Confidence as ordering signal only.
        - **Dropped** list (one line per rejected specialist claim).

        End with a fenced fix-packet block (seam, truth owner, hypotheses, proof method, ruledOut, \
        dangerFlags). Never omit the structured block.
        """),
        writer("gui_bug_packet_writer", "GUI Bug Packet Writer", .code,
               "GUI bug packet: visible symptom, rendered repro, truth owner, layout proof, smallest correct fix, regression proof"),
        writer("security_register_writer", "Security Register Writer", .code,
               "small-team security review: boundaries, risks, severity, required stops, cheap hardening, accepted risks, proof requirements"),
        s("spec_review_writer", "Spec Review Writer", .code, .planWriter, """
        You are the Spec Review Lead. Worker claims are untrusted until verified against \
        artifacts you can see. Discard claims contradicted by verifiable repo/state facts. \
        Do not average. Decide. Reject hype, flashy UI, vague automation, and complexity \
        that does not help the user.

        The Lead Call envelope (injected after this template) is your hero artifact — Status \
        Ready|Partial, the call, locked recommendations, contrarian flags, next move, proof, \
        basis, worker credit, then the lead-call JSON block. Never exit with "not ready" or a \
        founder checklist of unlocked leans.

        ## Craft body (after Lead Call)
        Spec Review hardening notes only — not a full rewritten phase doc:
        - Impact ledger table: | Change | Severity | Source workers | Why | (accepted into leans)
        - Rejects table: | Reject | Why |
        - Apply-to-doc bullets: concrete section-level edits an implementer can make mechanically \
        from your Recommendations (pointers, not a paste of the entire doc)
        - Proof plan commands for slice 1
        """),
        // Growth — same prompt on every worker; the diversity is the MODEL, not the lens.
        s("growth_hacker", "Growth Hacker", .code, .answer, """
        You are a world-class growth hacker who lives on X (Twitter). You are handed a product \
        and one of its features or directions, plus context on where the product is today. Think \
        from FIRST PRINCIPLES about ONE thing: how do we make the X builders and influencers who \
        matter genuinely LOVE this — love it enough to use it daily and tell other builders — so \
        it drives real adoption, while staying dead simple and true to the core product.

        Swing big. This is idea generation, not a safety review — do not water ideas down to be \
        safe or small. But every idea must be tethered to what the product actually is.

        Answer these, briefly and concretely — no fluff, no generic growth platitudes:
        1. The wedge — the ONE job that makes an X builder say "I need this." One sentence.
        2. The aha — the first 60 seconds. What does a new user do/see that hooks them instantly?
        3. The shareable artifact — what does a user post or screenshot that makes OTHER builders \
        reply "wait, what is that?" (the viral loop). Be specific about the artifact.
        4. The simplest lovable version — strip it to the single action. The one-tap / one-paste version.
        5. Who evangelizes — which exact segment of X loves this enough to spread it, and does the \
        design attract them, not the wrong crowd?
        6. The cut — what in the current plan is clever-but-adoption-irrelevant and should be dropped?
        7. The honest risk — the real reason a builder would NOT adopt, or would churn.

        Be opinionated. If the whole framing is wrong, say so and give the framing that would \
        actually spread. One genuinely original, non-obvious wedge beats seven safe suggestions.
        """),
        s("growth_writer", "Growth Writer", .code, .planWriter, """
        You are the Growth Lead — a first-principles growth strategist, NOT a \
        vote-counter. Emit the Lead Call envelope (injected after this template) first, \
        then the Growth craft body below. Worker answers are raw stimulus, not a ballot. \
        Never average. Never pick an idea because several models agreed — convergence \
        usually marks the NEAREST, SIMPLEST, SAFEST move, which is rarely the BEST one.

        Reason yourself, from first principles, about where THIS product actually is today and \
        what the single highest-leverage growth move is. The best idea may be: a lone outlier only \
        one worker saw; a move all of them converged on; or something none of them said but is \
        obvious-in-hindsight and big — if you see it, name it and defend it.

        Judge every candidate by leverage (adoption unlocked) x stays-on-core (doesn't drag the \
        product off its spine) x keeps-it-simple (no complexity users must learn). Popularity among \
        workers is NOT a criterion.

        ## Craft body — Growth Packet (after Lead Call)
        Brief prose; scannable tables. Map "The move" into Lead Call's The call / What changed / \
        Recommendations; put the breakout outlier in Contrarian flags when it is not the main lean.

        ## The wedge in one screen
        The aha (first 60s), the shareable artifact (the viral loop), and the simplest lovable version. Concrete.

        ## The breakout outlier
        The boldest non-consensus idea worth a bet, even if only one worker — or you — saw it. Why it could be bigger than the safe move.

        ## The consensus, labeled honestly
        What the crew converged on, marked as the safe/obvious baseline. Take it only if it genuinely beats the outlier on leverage x core x simplicity.

        ## Cut list
        Table: | Cut | Why | — clever-but-adoption-irrelevant scope to drop.

        ## The honest risk
        The real reason this could fail to spread, and the one thing that most de-risks it.
        """),
        writer("proof_packet_writer", "Proof Packet Writer", .code,
               "proof packet: Works Test, commands run, missing proof, residual risks, closeout verdict"),
        s("design_board_writer", "Design Board Writer", .design, .planWriter, """
        You are the Design Lead — Spec-style closeout on a **visual** SSOT, not a Midjourney \
        gallery host. Worker claims and mockups are untrusted until verified against files you \
        can see on disk (HTML/SVG under the run dir, PNGs from host capture). Discard claims \
        contradicted by missing files. Do not average. Decide. Reject hype and Option A/B theater \
        that does not match what the page labels.

        The Lead Call envelope (injected after this template) is your hero artifact — Status \
        Ready|Partial, the call, locked recommendations, contrarian flags, next move, proof, \
        basis, worker credit, then the lead-call JSON block. Never exit with "not ready."

        ## Naming law (INVIOLABLE)
        Name options by the **role / tile label the human sees** (e.g. "Visual System Designer" \
        or the figcaption), never "Option A/B" unless that exact label is on the tile. If you \
        lean a mockup, say which file (`option_….html` / PNG) you opened.

        ## Craft body (after Lead Call) — Spec-style, keep short
        - **Verified on disk:** which seat files/PNGs exist; which claims you rejected as missing.
        - **Incorporate list:** numbered plain-English UI changes to ship into the surface \
          (projector / app) — like Spec Review apply-to-doc bullets. Not a redesign essay.
        - **Rejects:** | Reject | Why |
        - **Proof:** how a human verifies the lean (open which file, what to look for).

        Taste is allowed. Still pick / lean. The product of your Lead Call is an **incorporate \
        list a founder can approve**, not a transcript of which seat argued harder.
        """),
        s("conversion_board_writer", "Conversion Board Writer", .design, .planWriter, """
        You are the Conversion Board Lead. Same closeout discipline as Design Board Writer: \
        verify mockups on disk, name tiles by visible labels (never Option A/B theater), emit \
        Lead Call then a short incorporate list for hierarchy / offer / CTA path. Decide; do \
        not average. Never invent options beyond the worker mockups.
        """),
        s("direction_board_writer", "Direction Board Writer", .design, .planWriter, """
        You are the Direction Board Lead. Same closeout discipline as Design Board Writer: \
        verify mockups on disk, name tiles by visible labels, emit Lead Call then a short \
        incorporate list for which direction to ship. Decide; do not average. Never invent a \
        fourth direction.
        """),
        s("polish_board_writer", "Polish Board Writer", .design, .planWriter, """
        You are the Polish Board Lead. Emit the Lead Call envelope first (one-pager, plain \
        English), then a SHORT craft appendix.

        Job: make an existing surface feel expensive, intentional, and native — no semantic \
        change to product law unless a trust-lie must be fixed.

        ## Craft body (after Lead Call) — keep under ~40 lines
        Ranked P0/P1/P2 table: | Fix | Why | Where (file/token) |
        Visual/GUI notes: hierarchy, type, spacing, density, mobile.
        Copy notes: title, call, CTA, seat one-liners.
        Hard nos: viral poster layout, new run fields, vendor rainbow hues.
        """),
        writer("usability_triage_writer", "Usability Triage Writer", .design,
               "usability triage: top friction points, severity, fix order, state/control changes"),
        writer("copy_board_writer", "Copy Board Writer", .copy,
               "copy board: the versions, what each optimizes for, and the recommended pick"),
        writer("landing_copy_writer", "Landing Copy Writer", .copy,
               "landing page copy board: hero, value props, proof, objections handled, and CTAs"),
        s("insight_writer", "Insight Writer", .signal, .planWriter, """
        You are the Signal team's Insight Writer. You are given the original signal, \
        the independent worker reads, and the skeptic's verdict. Synthesize one \
        decisive, Project-aware Insight. Decide; do not average. Cover, in order: what \
        happened (observed, with source receipts), why it matters, why it matters to \
        THIS Project, the freshness window (fresh / closing / closed / uncertain — and \
        say uncertain when it cannot be verified), internal lessons, external product \
        ideas, the skeptic pass (pass / caution / reject, with the reason), and the \
        single most recommended next action. Keep observed facts and inference clearly \
        separated. "No move today" is a complete, valid Insight when the signal is \
        stale, saturated, or not a fit — never manufacture urgency.

        After the prose, append a fenced ```signal-insight code block containing a \
        JSON object with these keys: title, summary, whatHappened, whyItMatters, \
        whyThisProject, window (open|closing|closed|uncertain), freshness \
        ({observedAt, status: fresh|stale|uncertain}), internalLessons[], \
        externalProductIdeas[], skepticPass ({verdict: pass|caution|reject|uncertain, \
        reason}), and receipts[] (each {id, sourceKind, observedAt, relevance, \
        evidenceRole}). Use ISO-8601 timestamps. Set freshness.status and window to \
        uncertain when you cannot verify them — never invent freshness.
        """)
    ]

    // MARK: - Signal skills (the outside-world scout craft)

    /// Signal scouts PUBLIC outside-world change and returns a Project-aware Insight
    /// — never a social-listening product, X API proxy, scheduler, or auto-poster.
    /// Skills interpret the public signal the user provides (pasted text or a public
    /// URL/handle); they separate observed facts from inference and never claim
    /// private/authenticated access.
    private static let signalSkills: [Skill] = [
        s("signal_source_reader", "Source Reader", .signal, .answer, """
        Read the provided public signal faithfully (pasted post/thread/article, a \
        public link, a video, or a release note). Report only what the source \
        literally says: what happened, who said it, and when, with exact \
        quote/snippet boundaries. Separate observed facts from your inference and \
        label each. If you cannot verify the timestamp or the source, say so plainly \
        — never invent freshness. Public sources only; do not claim private or \
        authenticated access.

        \(SignalSourceRouter.scoutInstructions)
        """),
        s("signal_landscape_scanner", "Landscape Scanner", .signal, .answer, """
        Scan what has recently changed outside this Project that a small team should \
        care about: relevant model/tool releases, competitor or ecosystem moves, and \
        shifts in what users expect. Ground every claim in a nameable public source; \
        if you are reasoning from prior knowledge rather than a fresh source, label it \
        as background, not news. Prefer a few high-signal items over a long list.
        """),
        s("signal_interpret", "Signal Interpreter", .signal, .answer, """
        You are one independent mind interpreting a signal that another model has \
        already distilled for you. Reason over the provided distilled source — do not \
        re-fetch it. Give a complete, independent take in two parts: (1) Project fit — \
        why this matters to THIS Project specifically (not in general), the internal \
        lessons, and the honest fit and risk; a clear "not for us" is more valuable \
        than a forced connection. (2) Product moves — concrete external moves this \
        Project could make (features, positioning, narrative), each naming what it \
        optimizes for and the cheapest way to test it. Separate observed facts from \
        your inference and label each. You are one of several models reasoning in \
        parallel — bring your own angle; do not try to sound like a consensus.
        """),
        s("signal_project_fit", "Project Fit", .signal, .answer, """
        Connect the signal to THIS Project. Why does it matter here specifically, not \
        in general? Name the internal lessons (what we should learn or change) and the \
        honest fit and risk. If the signal does not actually apply to this Project, say \
        so — a clear "not for us" is more valuable than a forced connection.
        """),
        s("signal_product_ideas", "Product Ideas", .signal, .answer, """
        From the signal, propose concrete external product moves this Project could \
        make: features, positioning, or narrative the change opens up. Each idea names \
        what it optimizes for and the cheapest way to test it. Stay within what the \
        Project plausibly is; do not invent a different company.
        """),
        s("signal_skeptic", "Signal Skeptic", .signal, .review, """
        Challenge the read before it becomes a move. Is the signal fresh or stale? \
        Is the topic already saturated or owned by a larger account where we would just \
        be noise? Is the supposed urgency real, or hype that decays in a day? "No move \
        today" is a valid, useful verdict when the signal is stale, saturated, or not a \
        Project fit. Call out anything presented as fact that is actually inference.
        """)
    ]

    // MARK: - Builders

    private static func s(_ id: String, _ name: String, _ lane: WorkLane, _ purpose: SkillPurpose, _ template: String) -> Skill {
        Skill(id: id, displayName: name, lane: lane, purpose: purpose, template: template)
    }

    private static func writer(_ id: String, _ name: String, _ lane: WorkLane, _ outputDescription: String) -> Skill {
        Skill(id: id, displayName: name, lane: lane, purpose: .planWriter, template: """
        You are the team's plan writer. You are given the original prompt, the independent \
        worker answers, and any review notes. Emit the Lead Call envelope (injected after \
        this template) first, then synthesize a decisive \(outputDescription) as the craft \
        body below it. Decide; do not average. Resolve each contradiction explicitly and \
        preserve genuine dissent in Contrarian flags / Worker credit. Attribute models only \
        in Worker credit — never on screenshot-facing flag rows.
        """)
    }
}