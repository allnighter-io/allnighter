# OC-S01a — OpenCode extractor tests + fixture

Status: **ready**
SSOT: `docs/phases/setup/OpenCode_CLI_Support.md` (Output Contract section only)

## Goal

Add offline proof that `TextUtil.extractOpenCodeVisibleText` strips OpenCode
metadata footers and leaves the assistant answer.

## Copy-paste prompt

```text
You are implementing sprint work order OC-S01a ONLY.

Read ONLY:
- docs/phases/sprint/opencode/OC-S01a-extractor-tests.md
- Packages/AllnighterCore/Sources/AllnighterEngine/TextUtil.swift

Touch ONLY:
- Packages/AllnighterCore/Tests/AllnighterEngineTests/OpenCodeVisibleTextTests.swift (new)
- Packages/AllnighterCore/Sources/AllnighterCore/Resources/Fixtures/opencode_stdout_smoke.txt (new)

Do NOT read Package.swift, Fixtures.swift, WorkerRunner, or any other file.
Do NOT research Bundle.module. Do NOT add helpers.

Use INLINE strings in tests (copy fixture content into the test). No bundle loading.

Create opencode_stdout_smoke.txt:
ALLNIGHTER_READY
> Build · Qwen/Qwen3-Coder-Next · 1.8s

Create OpenCodeVisibleTextTests.swift — copy this skeleton and run tests:

import XCTest
@testable import AllnighterEngine

final class OpenCodeVisibleTextTests: XCTestCase {
    func testSmokeFixtureShape() throws {
        let raw = """
        ALLNIGHTER_READY
        > Build · Qwen/Qwen3-Coder-Next · 1.8s
        """
        XCTAssertEqual(TextUtil.extractOpenCodeVisibleText(raw), "ALLNIGHTER_READY")
    }

    func testMultiLineAnswer() {
        let raw = """
        Line one
        Line two
        > Build · zai-org/GLM-5.2 · 2.2s
        """
        XCTAssertEqual(TextUtil.extractOpenCodeVisibleText(raw), "Line one\nLine two")
    }
}

Run: swift test --package-path Packages/AllnighterCore --filter OpenCodeVisibleText

If you have written zero files after 2 minutes, STOP thinking and WRITE the files.
```

## Stall nudge (supervisor sends if GLM stops without writing)

See [Pair Programming Team](../../Pair_Programming_Team.md) §Stall detection.

```text
NUDGE — same slice OC-S01a. Do not research bundle loading.
Write the two files from the skeleton in OC-S01a-extractor-tests.md now.
Run swift test --filter OpenCodeVisibleText. Nothing else.
```

## Read only

- `Packages/AllnighterCore/Sources/AllnighterEngine/TextUtil.swift`

## Touch only

- `Packages/AllnighterCore/Tests/AllnighterEngineTests/OpenCodeVisibleTextTests.swift` **(new)**
- `Packages/AllnighterCore/Sources/AllnighterCore/Resources/Fixtures/opencode_stdout_smoke.txt` **(new)**

## Do not read / do not touch

- `Fixtures.swift`, `Package.swift`, `WorkerRunner.swift`, anything else

## Steps

1. Write `.txt` fixture (reference copy for humans/CI).
2. Write test file with **inline** multiline strings (no `Bundle.module`).
3. Run proof command.

## Works Test

```bash
swift test --package-path Packages/AllnighterCore --filter OpenCodeVisibleText
```

## Done when

- [ ] `opencode_stdout_smoke.txt` exists
- [ ] `OpenCodeVisibleTextTests` passes
- [ ] No other files changed
