import Foundation

public enum AIReadinessFingerprint: String, Codable, Sendable, CaseIterable {
    case typeScriptAppOrMonorepo
    case swiftAppleApp
    case cliTool
    case unclear
}

public enum AIReadinessShape {
    /// Deterministic shape fingerprint. Checks the repo root and one level of
    /// nested markers (`Packages/*/Package.swift`, `Apps/*/*.xcodeproj`) so
    /// Allnighter-style monorepos are not reported as unclear.
    public static func detect(
        at root: URL,
        fileExists: ((String) -> Bool)? = nil,
        fileContents: ((String) throws -> String)? = nil,
        entryNames: (() throws -> [String])? = nil
    ) -> AIReadinessFingerprint {
        let usingDefaults = fileExists == nil && entryNames == nil
        let fileExists = fileExists ?? { name in
            FileManager.default.fileExists(atPath: root.appendingPathComponent(name).path)
        }
        let fileContents = fileContents ?? { name in
            try String(contentsOf: root.appendingPathComponent(name), encoding: .utf8)
        }
        let entryNames = entryNames ?? {
            try FileManager.default.contentsOfDirectory(atPath: root.path)
        }

        var hasSwiftApp = false
        var hasTS = false
        var hasCLI = false

        let entries = (try? entryNames()) ?? []
        for entry in entries {
            let lower = entry.lowercased()
            if lower.hasSuffix(".xcodeproj") || lower.hasSuffix(".xcworkspace") {
                hasSwiftApp = true
            }
        }

        if usingDefaults {
            scanNestedSwiftMarkers(root: root, hasSwiftApp: &hasSwiftApp, hasCLI: &hasCLI)
        } else {
            // Injectable probes — tests supply relative paths via fileExists.
            for probe in entries where probe.contains("/") {
                let lower = probe.lowercased()
                if lower.hasSuffix("package.swift") {
                    hasSwiftApp = true
                    if let contents = try? fileContents(probe),
                       contents.contains("executableTarget") {
                        hasCLI = true
                    }
                }
                if lower.hasSuffix(".xcodeproj") || lower.hasSuffix(".xcworkspace") {
                    hasSwiftApp = true
                }
            }
            for probe in [
                "Packages/AllnighterCore/Package.swift",
                "Packages/Core/Package.swift",
                "Packages/App/Package.swift",
                "Apps/AllnighterMac/AllnighterMac.xcodeproj",
                "Apps/MacApp/MacApp.xcodeproj"
            ] where fileExists(probe) {
                hasSwiftApp = true
                if probe.hasSuffix("Package.swift"),
                   let contents = try? fileContents(probe),
                   contents.contains("executableTarget") {
                    hasCLI = true
                }
            }
        }

        if fileExists("Package.swift") {
            hasSwiftApp = true
            if let contents = try? fileContents("Package.swift"),
               contents.contains("executableTarget") {
                hasCLI = true
            }
        }

        if fileExists("package.json") {
            let hasTSConfig = fileExists("tsconfig.json")
            if hasTSConfig {
                hasTS = true
            } else if let contents = try? fileContents("package.json"),
                      contents.contains("\"typescript\"") {
                hasTS = true
            }
            if !hasTSConfig,
               let contents = try? fileContents("package.json"),
               contents.contains("\"bin\"") {
                hasCLI = true
            }
        }

        if fileExists("go.mod") { hasCLI = true }
        if fileExists("Cargo.toml"),
           let contents = try? fileContents("Cargo.toml"),
           contents.contains("[[bin]]") {
            hasCLI = true
        }
        if fileExists("main.go") || fileExists("main.swift") { hasCLI = true }

        if hasSwiftApp && hasTS { return .unclear }
        if hasSwiftApp { return .swiftAppleApp }
        if hasTS { return .typeScriptAppOrMonorepo }
        if hasCLI { return .cliTool }
        return .unclear
    }

    private static func scanNestedSwiftMarkers(
        root: URL, hasSwiftApp: inout Bool, hasCLI: inout Bool
    ) {
        let fm = FileManager.default
        let packages = root.appendingPathComponent("Packages")
        if let kids = try? fm.contentsOfDirectory(
            at: packages, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) {
            for kid in kids {
                let manifest = kid.appendingPathComponent("Package.swift")
                if fm.fileExists(atPath: manifest.path) {
                    hasSwiftApp = true
                    if let contents = try? String(contentsOf: manifest, encoding: .utf8),
                       contents.contains("executableTarget") {
                        hasCLI = true
                    }
                }
            }
        }
        let apps = root.appendingPathComponent("Apps")
        if let kids = try? fm.contentsOfDirectory(
            at: apps, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) {
            for kid in kids {
                guard let nested = try? fm.contentsOfDirectory(atPath: kid.path) else { continue }
                if nested.contains(where: {
                    let lower = $0.lowercased()
                    return lower.hasSuffix(".xcodeproj") || lower.hasSuffix(".xcworkspace")
                }) {
                    hasSwiftApp = true
                }
            }
        }
    }

    public static func brief(for fingerprint: AIReadinessFingerprint) -> String {
        switch fingerprint {
        case .typeScriptAppOrMonorepo:
            return """
            ## Shape: TypeScript app or monorepo

            When examining this repo, also consider:
            - Which script is *the* test command? If multiple test scripts exist, note which one is the primary and whether `npm test` or equivalent works reliably.
            - Package manager truth: is the lockfile committed? Does `npm ci` / `yarn --frozen-lockfile` reproduce cleanly?
            - Workspace graph: in a monorepo, which package should an agent open first? Are boundaries documented?
            """
        case .swiftAppleApp:
            return """
            ## Shape: Swift Apple app (including nested Packages/ + Apps/ monorepos)

            When examining this repo, also consider:
            - Simulator bootstrap determinism: can a clean-clone agent open and run in the simulator without manual steps?
            - Scheme discoverability: are schemes shared or user-specific? Does `xcodebuild -list` find the right target?
            - SPM vs CocoaPods clarity: if both package managers are present, which is authoritative? Is resolution deterministic?
            - Sibling path dependencies: does Package.swift point at undeclared local packages that hang resolve?
            - Build log noise: are warnings so common that an agent cannot find the actual error in build output?
            """
        case .cliTool:
            return """
            ## Shape: CLI / agent-facing tool

            When examining this repo, also consider:
            - Machine-readable output: is there a `--json` flag for programmatic consumption? Do scripts depend on human-readable parsing?
            - Teach-at-failure: when a command fails, does the output tell the user what to do next, or just the error?
            - Cold PATH: can an agent install and run this tool from a clean environment without manual PATH configuration?
            - Invented-flag risk: are help text and actual behavior guaranteed to stay in sync, or could an agent hallucinate valid-looking flags that silently do the wrong thing?
            """
        case .unclear:
            return """
            ## Shape: unclear

            The repo shape could not be determined with confidence after checking the root and \
            common nested markers (`Packages/*/Package.swift`, `Apps/*/*.xcodeproj`). Ask \
            universal questions only — do not assume a specific technology stack.
            """
        }
    }
}
