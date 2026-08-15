import Foundation

/// LR-S02 — mint a seated local row from a live overlay candidate.
///
/// `--body opencode` also merges live `/api/tags` into `opencode.json` and
/// reclaims a leftover `opencode serve`. `--body claude_code` never touches
/// `opencode.json`. Tests must pass `opencodeConfigURL` — production resolves
/// the real path; XCTest refuses it.
public enum LocalRuntimeSeatMint {
    /// Resolve `candidateID` from the live overlay (`candidateID(tag:)` +
    /// `/api/tags` snapshot). `get()` will not find it. `--body` on an
    /// already-seated id refuses. Prints belong to the caller — this returns
    /// `Assessment.disclosures` as the policy already writes them.
    public static func enable(
        candidateID: ModelID,
        bodyDriverId: String,
        snapshot: OllamaLocalRuntimeObserver.Snapshot?,
        now: Date = Date(),
        opencodeConfigURL: URL? = nil,
        fileManager: FileManager = .default,
        serveReclaimTable: OpenCodeLeftoverServeReclaim.Table? = nil,
        isTestHost: Bool = AllnighterSupportRoot.isRunningUnderTestHost
    ) throws -> OllamaLocalSeatEnablePolicy.Assessment {
        if ModelCatalog.get(candidateID) != nil {
            throw ModelCatalogError.invalid(
                "\(candidateID) is already seated — omit --body and run: alln models enable \(candidateID)"
            )
        }
        let overlay = ModelListProjector.overlayDefinitions(
            from: snapshot,
            seated: ModelCatalog.list(),
            now: now
        )
        guard let candidate = overlay.first(where: { $0.id == candidateID }) else {
            throw ModelCatalogError.notFound(candidateID)
        }
        let tag = OpenCodeLocalSeatReadiness.ollamaTag(from: candidate.modelLabel)
        let served = tag.flatMap { name in
            snapshot?.residentModels.first { $0.name == name }?.servedContextWindow
        }
        // No G1 store in this packet. Nil discloses the existing "has not passed G1" line.
        let assessment = OllamaLocalSeatEnablePolicy.assessExplicitEnable(
            candidate: candidate,
            bodyDriverId: bodyDriverId,
            g1Passed: nil,
            servedContextWindow: served
        )
        if let refusal = assessment.refusal {
            throw ModelCatalogError.invalid(refusal)
        }
        guard assessment.permitsEnable, var seat = assessment.boundSeat else {
            throw ModelCatalogError.invalid("Allnighter could not enable this model.")
        }
        if ModelCatalog.get(seat.id) != nil {
            throw ModelCatalogError.invalid(
                "\(seat.id) is already seated — omit --body and run: alln models enable \(seat.id)"
            )
        }
        var disclosures = assessment.disclosures
        if bodyDriverId == "opencode" {
            let sync = try syncOpenCodeConfig(
                snapshot: snapshot,
                configURLOverride: opencodeConfigURL,
                fileManager: fileManager,
                serveReclaimTable: serveReclaimTable,
                isTestHost: isTestHost
            )
            disclosures.append(contentsOf: sync.disclosures)
            if !sync.addedModelIds.isEmpty {
                seat.addedOpenCodeModelIds = sync.addedModelIds
            }
        }
        seat.origin = .discovered
        try ModelCatalog.saveDiscovered(seat)
        try ModelCatalog.setEnabled(seat.id, true)
        return OllamaLocalSeatEnablePolicy.Assessment(
            disclosures: disclosures,
            permitsEnable: assessment.permitsEnable,
            automaticCodeOffer: assessment.automaticCodeOffer,
            boundSeat: assessment.boundSeat,
            refusal: assessment.refusal
        )
    }

    // MARK: - OpenCode body (LR-S02b)

    private struct OpenCodeSync: Equatable, Sendable {
        var disclosures: [String]
        var addedModelIds: [String]
    }

    private static func syncOpenCodeConfig(
        snapshot: OllamaLocalRuntimeObserver.Snapshot?,
        configURLOverride: URL?,
        fileManager: FileManager,
        serveReclaimTable: OpenCodeLeftoverServeReclaim.Table?,
        isTestHost: Bool
    ) throws -> OpenCodeSync {
        let configURL = try OpenCodeOllamaSetup.resolveConfigURL(
            override: configURLOverride,
            isTestHost: isTestHost
        )
        var root = try readOpenCodeRoot(at: configURL, fileManager: fileManager)
        let tagNames = liveTagNames(from: snapshot)
        let merge = try OpenCodeOllamaProviderMerge.merge(
            into: &root,
            localTags: tagNames
        )
        if merge.didChange {
            let encoded = try OpenCodeOllamaProviderMerge.encodeRoot(root)
            do {
                try fileManager.createDirectory(
                    at: configURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try encoded.write(to: configURL, options: [.atomic])
            } catch {
                throw ModelCatalogError.invalid(
                    "could not write \(configURL.path): \(error.localizedDescription)"
                )
            }
        }
        let leftover = OpenCodeLeftoverServeReclaim.reclaim(
            table: OpenCodeLeftoverServeReclaim.resolvedTable(
                override: serveReclaimTable,
                isTestHost: isTestHost
            )
        )
        return OpenCodeSync(
            disclosures: opencodeSyncDisclosures(merge: merge, leftover: leftover),
            addedModelIds: merge.addedModelIds
        )
    }

    /// Observed `/api/tags` names only — never guess when Ollama is unreachable.
    private static func liveTagNames(
        from snapshot: OllamaLocalRuntimeObserver.Snapshot?
    ) -> [String] {
        guard let snapshot else { return [] }
        switch snapshot.observeFailure {
        case .version, .tags, .unparseableVersion, .unparseableTags:
            return []
        case .ps, .unparseablePs, .none:
            return snapshot.localTags.map(\.name)
        }
    }

    private static func readOpenCodeRoot(
        at url: URL,
        fileManager: FileManager
    ) throws -> [String: Any] {
        guard fileManager.fileExists(atPath: url.path) else { return [:] }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ModelCatalogError.invalid(
                "could not read \(url.path): \(error.localizedDescription)"
            )
        }
        do {
            return try OpenCodeOllamaProviderMerge.parseRoot(data)
        } catch let error as OpenCodeOllamaProviderMerge.Error {
            throw ModelCatalogError.invalid(error.description)
        } catch {
            throw ModelCatalogError.invalid(
                "opencode.json is not valid JSON (\(error.localizedDescription)) — refusing to clobber it"
            )
        }
    }

    private static func opencodeSyncDisclosures(
        merge: OpenCodeOllamaProviderMerge.Result,
        leftover: OpenCodeLeftoverServeReclaim.Outcome
    ) -> [String] {
        var lines: [String] = []
        if !merge.addedModelIds.isEmpty {
            lines.append(
                "OpenCode can now use these models: \(merge.addedModelIds.joined(separator: ", "))."
            )
        }
        switch leftover {
        case .notAttempted, .idle:
            break
        case .reclaimed(let pid, _):
            lines.append(
                "Allnighter restarted a leftover OpenCode serve (process \(pid)) so new models are visible to alln run."
            )
        case .refusedAllnServe(let pid, _):
            lines.append(
                "Port \(OpenCodeLeftoverServeReclaim.defaultPort) is already used by Allnighter serve (process \(pid)). Allnighter left it running."
            )
        case .skippedForeign, .skippedUnreadableCommand:
            lines.append(
                "Something else is already using port \(OpenCodeLeftoverServeReclaim.defaultPort). Allnighter left it running."
            )
        }
        return lines
    }
}
