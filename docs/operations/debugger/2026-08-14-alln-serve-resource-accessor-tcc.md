# 2026-08-14 — `alln serve` resource-accessor Documents TCC

```text
Tier: T3 (repeated; 1.1.10 did not kill the mechanism)
Symptom / repro: Documents TCC prompt before typing `alln`. Trigger is the
  LaunchAgent `com.allnighter.resident-coordinator` (`alln serve`, RunAtLoad +
  KeepAlive), not the foreground CLI.
Bug fingerprint: ToolRuntime() → CatalogLoader.bundled() → SwiftPM
  resource-bundle accessor. Bundle(path: sibling) is nil because the sidecar
  has catalog.json and no Info.plist. Fallback Bundle(path: compile-time
  absolute) stats ~/Documents (1.1.9 bake: mike's dist/.build-universal).
  KeepAlive crash-loop: each fatalError re-stats Documents.
  1.1.10 binary was clean (Library scratch) but relocate-proof ran `version`,
  which never builds ToolRuntime — false green. Stale 1.1.9 daemon kept
  crashing until bootout.
Truth owner: ExecutableResource (sidecar file reads; never the accessor).
  OpenCodePermissionPolicy.defaultExternalDirectoryAllowRoots = [].
  relocate-cli-proof.sh runs `menu --json` + strings gate.
Lie-prone layer: “chdir / Library scratch is enough”; “version after hide
  bundles proves catalog load”; Bundle(path:) on an SPM resource directory.
Fix: CatalogLoader / CatalogOverlayLoader / RecipeCatalog / Fixtures read
  sidecar files. Serve createSession allow-roots = run directory + held
  write locks. CLI 1.1.11.
Proof: scripts/swift-test.sh --filter CatalogLoaderTests
  --filter CatalogAuthorityTests --filter RecipeCatalogTests
  --filter OpenCodePermissionPolicyTests
  --filter OpenCodePermissionPolicyLockGatingTests
  --filter VersionIdentityTests
  check-fast.sh greps Bundle.module out of production Sources.
  strings "$BIN" must not contain Documents/GitHub.
  Empirical: alln serve disable && alln serve enable; launchctl print
  gui/$UID/com.allnighter.resident-coordinator; serve log has no fatalError.
```
