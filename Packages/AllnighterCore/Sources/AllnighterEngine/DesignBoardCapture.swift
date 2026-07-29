import Foundation
import AllnighterCore
import AgentOSTeam
#if canImport(WebKit)
import WebKit
#endif
#if canImport(AppKit)
import AppKit
#endif

/// Thin Design-lane host camera: local HTML/SVG → PNG via WebKit.
/// Product default for `outputKind == designBoard` (`docs/operations/Design_Lane.md`).
/// Never calls `imageGen`. Fail closed on missing file / render error / no WebKit.
public enum DesignBoardCapture: Sendable {

    public struct Viewport: Sendable, Equatable {
        public var width: Double
        public var height: Double

        public init(width: Double, height: Double) {
            self.width = width
            self.height = height
        }

        public static let desktop = Viewport(width: 1280, height: 800)
        public static let mobile = Viewport(width: 390, height: 844)

        public static func forShape(_ shape: TargetShape) -> Viewport {
            shape == .mobile ? .mobile : .desktop
        }
    }

    public enum CaptureError: Error, Equatable, Sendable {
        case fileMissing
        case unsupportedType
        case renderFailed(String)
        case unavailable
        case timedOut
    }

    /// Captureable extensions the host camera understands (v1).
    public static let captureableExtensions: Set<String> = ["html", "htm", "svg"]

    /// Sanitize a worker id for a run-folder filename (`model_x#0` → `model_x-0`).
    public static func sanitizeFileToken(_ agentId: String) -> String {
        agentId
            .replacingOccurrences(of: "#", with: "-")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
    }

    /// Relative PNG name written into the run folder for a seat.
    public static func optionImageRelativeName(agentId: String) -> String {
        "option_\(sanitizeFileToken(agentId)).png"
    }

    /// Locate a captureable HTML/SVG for one seat.
    /// Prefer a machine-readable path declaration in seat output, else
    /// `runDir/option_<id>.html|.svg` (sanitized id).
    public static func locateArtifact(
        agentId: String,
        runDirectory: URL,
        seatOutput: String?,
        fileManager: FileManager = .default
    ) -> URL? {
        if let declared = declaredArtifactPath(in: seatOutput),
           let resolved = resolveArtifactPath(declared, runDirectory: runDirectory, fileManager: fileManager) {
            return resolved
        }
        let token = sanitizeFileToken(agentId)
        for name in ["option_\(token).html", "option_\(token).htm", "option_\(token).svg"] {
            let url = runDirectory.appendingPathComponent(name)
            if fileManager.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    /// Capture one local HTML/SVG file into a PNG. Sandbox: file:// only; no network.
    public static func capture(
        sourceFile: URL,
        destinationPNG: URL,
        viewport: Viewport = .desktop,
        timeoutSeconds: TimeInterval = 15
    ) async throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: sourceFile.path) else { throw CaptureError.fileMissing }
        let ext = sourceFile.pathExtension.lowercased()
        guard captureableExtensions.contains(ext) else { throw CaptureError.unsupportedType }

        #if canImport(WebKit) && canImport(AppKit)
        await MainActor.run {
            _ = NSApplication.shared
        }
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await renderWithWebKit(
                    sourceFile: sourceFile,
                    destinationPNG: destinationPNG,
                    viewport: viewport
                )
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                throw CaptureError.timedOut
            }
            try await group.next()
            group.cancelAll()
        }
        #else
        throw CaptureError.unavailable
        #endif
    }

    /// Capture every answer seat into a `BoardPayload`. Failed / missing artifacts
    /// become gray tiles — never diffusion fallback.
    public static func captureBoard(
        answerWorkers: [Agent],
        answers: [TeamAnswer],
        runDirectory: URL,
        targetShape: TargetShape = .desktop
    ) async -> BoardPayload {
        let answerById = Dictionary(answers.map { ($0.memberId, $0) }, uniquingKeysWith: { a, _ in a })
        let viewport = Viewport.forShape(targetShape)
        var options: [DesignOption] = []
        options.reserveCapacity(answerWorkers.count)

        for agent in answerWorkers {
            let persona = agent.skillId ?? "design"
            let answer = answerById[agent.id]
            guard let source = locateArtifact(
                agentId: agent.id,
                runDirectory: runDirectory,
                seatOutput: answer?.output
            ) else {
                options.append(DesignOption(
                    agentId: agent.id,
                    modelId: agent.modelId,
                    persona: persona,
                    status: .failed,
                    failureReason: "no captureable HTML/SVG for seat (expected option_\(sanitizeFileToken(agent.id)).html|.svg or a declared path)"
                ))
                continue
            }

            let relative = optionImageRelativeName(agentId: agent.id)
            let dest = runDirectory.appendingPathComponent(relative)
            try? FileManager.default.removeItem(at: dest)

            do {
                try await capture(sourceFile: source, destinationPNG: dest, viewport: viewport)
                guard WorkerImageCapture.isValidImage(at: dest) else {
                    options.append(DesignOption(
                        agentId: agent.id,
                        modelId: agent.modelId,
                        persona: persona,
                        status: .failed,
                        failureReason: "WebKit capture produced no valid PNG"
                    ))
                    continue
                }
                options.append(DesignOption(
                    agentId: agent.id,
                    modelId: agent.modelId,
                    persona: persona,
                    imagePath: relative,
                    status: .done
                ))
            } catch let error as CaptureError {
                options.append(DesignOption(
                    agentId: agent.id,
                    modelId: agent.modelId,
                    persona: persona,
                    status: .failed,
                    failureReason: captureFailureReason(error)
                ))
            } catch {
                options.append(DesignOption(
                    agentId: agent.id,
                    modelId: agent.modelId,
                    persona: persona,
                    status: .failed,
                    failureReason: "WebKit capture failed: \(error.localizedDescription)"
                ))
            }
        }

        return BoardPayload(targetShape: targetShape, options: options)
    }

    // MARK: - Path declaration

    /// Machine-readable path line from seat Evidence / answer text, e.g.
    /// `capture: html option_foo.html` or `path: svg ./mock.svg`.
    public static func declaredArtifactPath(in text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        let pattern = #"(?im)^\s*(?:#\s*)?(?:capture|path)\s*[:=]\s*(html|htm|svg|native|concept)\s+(\S+)\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges >= 3,
              let kindRange = Range(match.range(at: 1), in: text),
              let pathRange = Range(match.range(at: 2), in: text) else { return nil }
        let kind = text[kindRange].lowercased()
        // native / concept are not this camera — fail closed at locate time.
        guard kind == "html" || kind == "htm" || kind == "svg" else { return nil }
        return String(text[pathRange])
    }

    private static func resolveArtifactPath(
        _ raw: String,
        runDirectory: URL,
        fileManager: FileManager
    ) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let candidates: [URL]
        if trimmed.hasPrefix("/") {
            candidates = [URL(fileURLWithPath: trimmed)]
        } else if trimmed.hasPrefix("~/") {
            let home = fileManager.homeDirectoryForCurrentUser
            candidates = [home.appendingPathComponent(String(trimmed.dropFirst(2)))]
        } else {
            candidates = [
                runDirectory.appendingPathComponent(trimmed),
                URL(fileURLWithPath: trimmed)
            ]
        }
        for url in candidates {
            let ext = url.pathExtension.lowercased()
            guard captureableExtensions.contains(ext) else { continue }
            guard fileManager.fileExists(atPath: url.path) else { continue }
            return url.standardizedFileURL
        }
        return nil
    }

    private static func captureFailureReason(_ error: CaptureError) -> String {
        switch error {
        case .fileMissing: return "captureable file missing"
        case .unsupportedType: return "unsupported capture type (need .html/.svg)"
        case .renderFailed(let detail): return "WebKit render failed: \(detail)"
        case .unavailable: return "WebKit capture unavailable on this host"
        case .timedOut: return "WebKit capture timed out"
        }
    }

    // MARK: - WebKit

    #if canImport(WebKit) && canImport(AppKit)
    @MainActor
    private static func renderWithWebKit(
        sourceFile: URL,
        destinationPNG: URL,
        viewport: Viewport
    ) async throws {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.suppressesIncrementalRendering = true
        if #available(macOS 11.0, *) {
            config.defaultWebpagePreferences.allowsContentJavaScript = true
        }

        let frame = NSRect(x: 0, y: 0, width: viewport.width, height: viewport.height)
        let webView = WKWebView(frame: frame, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")

        let bridge = NavigationBridge()
        webView.navigationDelegate = bridge

        let fileURL = sourceFile.standardizedFileURL
        let readRoot = fileURL.deletingLastPathComponent()
        webView.loadFileURL(fileURL, allowingReadAccessTo: readRoot)

        try await bridge.waitUntilFinished()

        let snapshotConfig = WKSnapshotConfiguration()
        snapshotConfig.rect = CGRect(origin: .zero, size: CGSize(width: viewport.width, height: viewport.height))
        if #available(macOS 10.15, *) {
            snapshotConfig.afterScreenUpdates = true
        }

        let image: NSImage = try await withCheckedThrowingContinuation { cont in
            webView.takeSnapshot(with: snapshotConfig) { image, error in
                if let image {
                    cont.resume(returning: image)
                } else {
                    cont.resume(throwing: CaptureError.renderFailed(error?.localizedDescription ?? "nil snapshot"))
                }
            }
        }

        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            throw CaptureError.renderFailed("PNG encode failed")
        }
        try png.write(to: destinationPNG, options: .atomic)
    }

    /// Navigation delegate that finishes on load and rejects non-file navigation (no network).
    @MainActor
    private final class NavigationBridge: NSObject, WKNavigationDelegate {
        private var continuation: CheckedContinuation<Void, Error>?
        private var pending: Result<Void, Error>?
        private var settled = false

        func waitUntilFinished() async throws {
            if let pending {
                switch pending {
                case .success: return
                case .failure(let error): throw error
                }
            }
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                if let pending = self.pending {
                    switch pending {
                    case .success: cont.resume()
                    case .failure(let error): cont.resume(throwing: error)
                    }
                } else {
                    self.continuation = cont
                }
            }
        }

        private func settle(_ result: Result<Void, Error>) {
            guard !settled else { return }
            settled = true
            if let continuation {
                self.continuation = nil
                continuation.resume(with: result)
            } else {
                pending = result
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            if let url = navigationAction.request.url, url.isFileURL {
                decisionHandler(.allow)
            } else if navigationAction.request.url == nil {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            settle(.success(()))
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            settle(.failure(CaptureError.renderFailed(error.localizedDescription)))
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            settle(.failure(CaptureError.renderFailed(error.localizedDescription)))
        }
    }
    #endif
}
