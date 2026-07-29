import Foundation
import AllnighterCore

/// Scans durable relay folders for unreadable or WTA-retired `relay.json` rows.
public enum RelayPersistenceDoctorCheck {
    public struct Finding: Sendable, Equatable {
        public var relayId: String
        public var path: String
        public var issue: Issue

        public enum Issue: Sendable, Equatable {
            case retiredWorkerKeys
            case decodeFailed
        }
    }

    public static func scan(relaysRoot: URL) -> [Finding] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: relaysRoot, includingPropertiesForKeys: nil
        ) else { return [] }

        let store = RelayStateStore(rootDirectory: relaysRoot)
        var findings: [Finding] = []
        for directory in entries where directory.lastPathComponent.hasPrefix("relay_") {
            let relayId = directory.lastPathComponent
            let path = directory.appendingPathComponent("relay.json").path
            switch store.loadResult(id: relayId) {
            case .success:
                continue
            case .failure(.notFound):
                continue
            case .failure(.decodeFailed(let detail)):
                findings.append(.init(
                    relayId: relayId,
                    path: detail.path,
                    issue: detail.retiredWorkerKeys ? .retiredWorkerKeys : .decodeFailed
                ))
            }
        }
        return findings.sorted { $0.relayId < $1.relayId }
    }

    public static func doctorCheck(relaysRoot: URL) -> DoctorResult.Check {
        let findings = scan(relaysRoot: relaysRoot)
        guard !findings.isEmpty else {
            return .init(
                name: "relayPersistence",
                status: .ok,
                detail: "all relay.json files decode with current seat keys (devModelId/pmModelId)"
            )
        }
        let retired = findings.filter { $0.issue == .retiredWorkerKeys }.count
        let corrupt = findings.filter { $0.issue == .decodeFailed }.count
        var parts: [String] = []
        if retired > 0 { parts.append("\(retired) relay\(retired == 1 ? "" : "s") with retired devWorkerId/pmWorkerId keys") }
        if corrupt > 0 { parts.append("\(corrupt) relay\(corrupt == 1 ? "" : "s") with unreadable relay.json") }
        let sample = findings.prefix(3).map(\.relayId).joined(separator: ", ")
        let detail = parts.joined(separator: "; ") + " (e.g. \(sample))"
        return .init(
            name: "relayPersistence",
            status: .critical,
            detail: detail,
            fixCommand: "swift build --package-path Packages/AllnighterCore && alln install-cli",
            requiresManual: false
        )
    }
}
