# Composer File References

Status: Backend/Core/CLI integrated; first Mac composer bridge landed; ranking/polish + GUI proof pending
Owner: AllnighterCore + Mac app + CLI/MCP contracts
Created: 2026-06-19
Updated: 2026-06-20
Process: `docs/workflows/SSOT_Founder_Input_Workflow.md` ->
`docs/workflows/SSOT_Feature_Workflow.md`
Depends on: code SSOT `RunService.swift` (run resolution/execution),
[`Persistent_Work_Threads.md`](Persistent_Work_Threads.md),
[`Composer_Image_Attachments.md`](../archive/phases/Composer_Image_Attachments.md),
[`CLI_Implementation_Contract.md`](CLI_Implementation_Contract.md)

## Founder Intent

Raw request:

```text
Add File References to Allnighter so a user can press @ in the composer and
quickly tell agents which files to read. V1 is Mac only. Telling agents about
files is key and this is a critical missing feature. Make it insanely fast and
insanely great.
```

Product value:

```text
The user can point the Project Manager or a team at exact Project files without
explaining paths in prose, copy-pasting code, or hoping the agent guesses the
right context.
```

Trusted workflow slice:

```text
open Project
-> press @ in the composer
-> fuzzy-pick one or more Project files
-> see stable file chips before send
-> send chat or Send to team
-> saved context packet records the exact referenced paths, hashes, and delivered text
-> worker receives the selected file contents in an explicit referenced-files block
-> history can reveal what was referenced and whether files changed later
```

Non-goals for Mac v1:

- arbitrary out-of-Project file upload;
- directory references as a durable object;
- PDF/document ingestion;
- automatic codebase-wide retrieval;
- code indexing, embeddings, semantic retrieval, or "related file" guessing;
- token, quota, time, or cost estimates;
- iOS composer UI;
- editing files from the reference palette;
- using file references to bypass Project root, worker readiness, or dispatch
  gates.

## Product Bar

The composer should feel like a native command palette for context:

```text
@Proje...
Project_Spine_And_Project_Manager.md
```

Enter adds a chip. Send gives the agent the referenced files:

```text
Referenced files:
1. docs/phases/Project_Spine_And_Project_Manager.md
2. Packages/AllnighterCore/Sources/AllnighterCore/ProjectSpine.swift
```

The feature fails if users still type "look at the project spine doc" and hope
the worker finds it. The feature also fails if the Mac UI feels good while CLI,
MCP, context packets, and worker prompts disagree about what was sent.

## First Principle

A file reference is not prose. It is a Project-scoped, ordered, auditable input
to the user's current turn.

If Allnighter shows a file chip in the composer and the user presses Send, then
thread history, the context packet, the worker prompt, CLI JSON, MCP output, and
context reveal all agree on the same ordered reference set.

## Mentor Feedback Decisions

Accepted:

- The picker is a path picker, not a code intelligence system. Use Git and local
  file metadata; do not add embeddings, parsing, or semantic retrieval.
- Empty-query results should be recency-ranked: recently changed, recently
  referenced, and files this lane already touched should appear before generic
  alphabetical results.
- The visible chip should have a stable backing token such as
  `@docs/phases/Composer_File_References.md`; attributed styling is presentation,
  not state.
- At send/dispatch time, resolve and read the file in the correct Project/lane
  root. Capture the delivered text in the saved context packet and make reveal
  honest.
- The resolver must be shared across composer surfaces: chat, Send to team,
  direct dispatch, "Go build that" notes, and voice-note interpretation.

Rejected or deferred:

- No token footprint badges. The existing context code explicitly bans estimated
  token counts and the product should not introduce usage theater.
- No semantic-neighbor boosting in v1. A string/path heuristic can be useful;
  inferred "related files" are retrieval, not an explicit user reference.
- No iOS filesystem picker in v1. A later iOS picker can be a best-effort
  mentioned-files list, clearly distinct from the Mac's authoritative Project
  file list.

## Current State

The backend is no longer starting from zero. The anchors below were verified
against the tree on 2026-06-20; treat them as the load-bearing reuse surface,
not as prose. The first backend pass landed the Core/Engine/CLI/MCP foundation.
Commit `b1604881` landed the first Mac composer bridge: `@` detection, an inline
Project-file picker, selected chips, and file-reference delivery into both
project-scoped team runs and worker chat. The Mac surface still needs ranking
polish, matched-text highlighting, draft/paste/DnD finish, context reveal, and a
native GUI proof seal before the feature can be called fixed.

- `ThreadContextPacket` now keeps `includedFiles: [String]` for compatibility
  and adds `includedFileReferences: [IncludedFileReferenceDelivery]` for
  ordered audit rows. Legacy packets decode both new arrays as `[]`.
- `ThreadTurn` now carries `fileReferenceRefs: [TurnFileReferenceRef]` beside
  image `attachmentRefs`, so committed user turns record exactly which file
  refs were selected.
- `ThreadContextBuilder.Options.attachedFiles` now accepts richer
  `AttachedFileInput` values with optional line ranges and preloaded resolver
  text, while preserving the legacy `attachedFiles: ["path"]` call pattern.
  File references render as a `Referenced files:` block in
  `ThreadContextPacket.text`.
- `ProjectFileReferenceResolver` resolves Mac Project-root paths, rejects
  root escapes, missing/unreadable files, binary content, suspicious secret
  paths, invalid ranges, oversize sources, and too many references. It returns
  frozen text, hashes, byte counts, line-range metadata, and builder inputs.
- `ProjectFileCatalog` provides the non-GUI path catalog: `git ls-files`
  tracked + untracked paths first, then a filesystem fallback, ranked by query,
  modified time, recently referenced paths, and lane-touched paths. It is a path
  catalog only: no embeddings, parsing, semantic retrieval, or file contents.
- `ThreadSendCoordinator.Request.contextOptions` and `WorkerChatCoordinator`
  send/`beginSend` (`AllnighterEngine/ThreadSendCoordinator.swift:25-45`,
  `WorkerChatCoordinator.swift:106-139`) already accept
  `contextOptions: ThreadContextBuilder.Options`; `ThreadSendCoordinator.Request`
  now also accepts `fileReferences: [FileReferenceInput]` and parses manual
  `@path` tokens from message text at send time.
- `alln thread send` now accepts repeatable `--ref path[:start-end]`; MCP
  `thread_send` accepts `fileReferences[]` as strings or `{path,startLine,endLine}`
  objects. `alln project files` remains deferred until the Project CLI group
  exists.
- Thread send JSON/MCP responses now include `fileReferenceIds` and
  `fileReferences[]` delivery audit rows.
- Reserved file-reference error codes live in
  `ContractRegistry+Milestone1.swift`; surfaced send-time resolver errors are
  registry-owned, not ad hoc strings.
- Focused backend proofs exist in `ProjectFileReferenceResolverTests`,
  `ThreadContextBuilderTests`, `ThreadSendFileReferenceTests`, and legacy decode
  tests.
- Delayed Work Order/Pending hash revalidation is not implemented yet; that is
  FR-S05 and must block changed files with `FILE_REFERENCE_CHANGED_BEFORE_INVOKE`
  before delayed dispatch.
- The Mac first bridge now lives in `RoutingComposer`
  (`Apps/AllnighterMac/Sources/RoutingComposer.swift`) and `ALTextEditor`
  (`Apps/AllnighterMac/Sources/AllnighterTextEditor.swift`). It should be treated
  as implemented but visually unverified: `xcodebuild`/native proof was blocked
  by local `sandbox-exec` package-resolution failure, and
  `scripts/check_gui_proof.sh` correctly requires a fresh proof packet for the
  changed composer views.
- `GitObserver` (`AllnighterEngine/GitObserver.swift`) exposes
  `repoTopLevel(forPath:)`, `dirtyFiles(rootPath:)`, and `recentCommits(...)` —
  enough to seed the catalog's git path source and dirty/recency ranking without
  new shell-outs.
- `ProjectExecutionResolver` (`AllnighterEngine/ProjectExecutionResolver.swift`)
  `resolve(project:) -> ProjectExecutionScope` yields `workerCwd` / `proofCwd` /
  `attachmentMirrorRoot`; send-time ref resolution roots against this scope.
- `ALTextEditor` is an `NSViewRepresentable` over a plain-text `NSTextView` that
  exposes only `text`/`contentHeight`/`isFocused` — it exposes **no caret rect
  or selection today**, and nothing uses `NSTextAttachment`. FR-S04 must extend
  the editor Coordinator to surface `selectedRange`/caret rect before a
  caret-anchored palette is possible.

## Truth Owner

| Layer | Owns |
| --- | --- |
| `ProjectFileCatalog` | Searchable, Project-scoped path list and ranking; no file-body index |
| `ProjectFileReferenceResolver` | Path normalization, safety, metadata, hashing, line-range validation |
| `ThreadDraftContext.fileReferences` | Draft refs visible in the composer before send |
| `ThreadTurn.fileReferenceRefs` | Committed ordered refs on the sent turn |
| `ThreadContextBuilder.Options.attachedFiles` | Existing Core input used to deliver referenced file bodies; FR-S00 extends its element to carry an optional line range and lifts its byte caps for references |
| `ThreadContextPacket.includedFiles` | Compatibility path list of files included in the packet body |
| `ThreadContextPacket.includedFileReferences` | Additive detailed audit: order, hash, range, delivery mode |
| `ThreadContextPacket.text` | Exact referenced-file text delivered to the worker |
| Worker prompt renderer | Protected referenced-files block from the saved packet |
| Mac composer | Presents Core truth; does not invent durable refs |

Mirror, do not reuse, the image attachment trio: `ThreadAttachmentStore`,
`IncludedAttachmentDelivery`, and `AttachmentDeliveryRenderer.pathBlock()`
(which renders "Attached images (use these paths):") are the shape precedent.
Note the deliberate divergence: images deliver **paths** to a mirrored blob;
file references deliver **bounded content** inline in the packet `text`. The CLI
`thread_send` JSON `AttachmentRow` (`attachmentId` / `canonicalPath` /
`deliveredPathUsed` / `storedSha256`) is the row precedent for `fileReferences[]`.

Do not use image attachments for Project file references. Do not put absolute
paths in user-facing chips when a root-relative path is available. Do not let
SwiftUI own selected-file truth. Do not replace the existing `includedFiles` /
`attachedFiles` path with a parallel GUI-only schema.

## Implementation Law

### 1. Project-scoped only

Mac v1 catalogs and references files under the selected Project root. A mutating
route is already blocked without a Project; file references follow the same
floor.

Rules:

- store root-relative paths as the public identity;
- resolve absolute paths only through the selected Project root;
- reject `..`, symlink escapes, missing roots, and duplicate active Project
  roots;
- never infer a Project from a pasted path when a Project is already selected.

### 2. Search is a warmed path catalog, not code retrieval

The `@` palette must not shell out on every keystroke.

V1 catalog warm-up:

```text
Project selected
-> warm ProjectFileCatalog in Core
-> git repo: git ls-files -z --cached --others --exclude-standard
-> folder Project: rg --files with default ignore semantics
-> filter generated/cache/vendor directories
-> classify text/binary/large/sensitive
-> refresh on Project activation and cheap file-system events when available
```

The catalog stores path metadata only: root-relative path, basename, extension,
directory depth, mtime, git dirty/untracked flags, last referenced time, and
lane-touched markers. It never stores file contents, embeddings, ASTs, semantic
summaries, or inferred related-file sets.

Empty-query ranking:

1. files already modified or returned by the current lane/thread;
2. recently referenced in this Project/thread;
3. dirty, staged, or untracked files from git;
4. recently modified files;
5. lazy last-commit-touch recency, when cheap/cached;
6. human-readable document formats as a gentle tie-breaker (`.md`, `.mdx`,
   `.txt`, `.rst`, `.adoc`) without repo-specific filename assumptions;
7. files in the current proposal/work-order scope, when that scope exists;
8. shallow/common entrypoints as a final tiebreaker.

Typed-query ranking:

1. exact basename prefix;
2. path-segment prefix;
3. basename contains;
4. path contains;
5. fuzzy abbreviation;
6. freshness/recency as a strong tiebreaker, especially among similar matches;
7. human-readable document formats as a gentle tiebreaker only after match
   quality and freshness.

Do not encode Allnighter-specific vocabulary such as SSOT, PRD, Workflow,
Decision, Plan, or Brief as privileged terms. Those words may rank naturally
because the user typed them, because the file is fresh, or because the path is a
human-readable document; they are not global product assumptions about how other
users organize work.

Palette open target: instant with recents and warm candidates; search update
target: under 50 ms for the warmed catalog on ordinary repos. If the catalog is
warming, the palette stays usable with recents plus exact-path validation.
Staleness is acceptable only for search results; the send resolver is the final
authority.

### 3. Safety filtering is default-on

Default search hides:

- ignored files;
- `.git/`, `.allnighter/`, build/cache/vendor folders;
- binary files;
- files over the v1 size cap;
- obvious secret material such as `.env`, private keys, tokens, certificates,
  and credential stores.

Manual exact-path references still pass through the same resolver. Sensitive
files are blocked in v1 rather than added with a tiny warning.

### 4. Selection is ordered and durable before send

Each selected file receives a `sequence` when added. Chips, turn refs, context
packet refs, and prompt blocks all sort by `sequence`. Never sort by filename,
catalog completion order, modified time, or worker capability.

Draft refs persist with the thread draft. If the app quits before send, reopening
the thread restores the chips or shows exact resolver failures.

### 5. Send resolves, reads, and audits references

The send transaction must:

1. lock the thread;
2. parse any stable `@path` backing tokens from the final composer text;
3. merge parsed tokens with draft refs, dedupe, and preserve appearance order;
4. resolve every selected ref against the scope from
   `ProjectExecutionResolver.resolve(project:)` — root refs at `workerCwd`, the
   same root the worker is invoked from, so chip path and delivered path cannot
   diverge;
5. reject missing, escaped, binary, sensitive, oversized, or invalid line-range
   refs;
6. hash the referenced file at send time;
7. feed the ordered root-relative paths into
   `ThreadContextBuilder.Options.attachedFiles`;
8. append the user turn with ordered `fileReferenceRefs`;
9. save `context/<packetId>.json` with `includedFiles`,
   `includedFileReferences`, and packet `text`;
10. invoke the worker from the selected Project/lane root.

If a file changes between send resolution and worker invocation, fail before the
worker starts with `FILE_REFERENCE_CHANGED_BEFORE_INVOKE`. Do not silently send
the agent to a different file than the user selected.

### 6. References deliver bounded text, not a hidden file blob

Mac v1 reads referenced text files at send/dispatch time and delivers bounded
file contents through the saved context packet. The durable user-facing token is
still a path reference; Allnighter does not create a separate file upload,
workspace mirror, or hidden attachment store for Project files.

Prompt block shape is renderer-owned, but it must be explicit and deterministic:

```text
Referenced files selected by the user. Use these contents before answering.

--- docs/phases/Project_Spine_And_Project_Manager.md
sha256: ...
<bounded file contents>

--- Packages/AllnighterCore/Sources/AllnighterCore/ProjectSpine.swift lines 1-120
sha256: ...
<bounded file contents>
```

If a file exceeds the cap, include a visible truncation note in the packet and
context reveal. Do not estimate token cost. Workers may also receive the
root-relative path and hash so project-aware CLIs can reopen the source, but a
path-only instruction does not satisfy Mac v1 unless a specific worker delivery
strategy declares it.

Two builder changes are load-bearing here and belong to FR-S00, because the
existing `attachedFiles: [String]` path cannot satisfy this section as-is:

- **Line ranges.** `attachedFiles` is a flat path list. To deliver
  `path lines 1-120`, FR-S00 extends the builder input element to an
  `(path, lineRange?)` shape (a new `AttachedFileInput` carried by
  `ThreadContextBuilder.Options`, keeping the bare-`String` element decoding for
  back-compat), and the renderer slices to the validated range. If FR-S00 ships
  whole-file only, line ranges must be removed from the v1 schema, CLI, and
  prompt block in lockstep — not left as dead promises.
- **Byte budget.** The reference path must use this spec's budget (below), not
  the legacy 16 KB/4 KB chat-attachment caps. FR-S00 either raises
  `Options.maxBytes`/`maxFileBytes` for the reference send or threads explicit
  per-send caps. The Works Test asserts the *delivered* byte count at the new
  budget so a silent fallback to 4 KB fails the test.

### 7. Pending and work orders revalidate

File refs in Draft, Pending, proposal, and Work Order flows store the selected
path and hash. Before delayed dispatch, Allnighter re-resolves every reference:

- same path + same hash: proceed;
- missing or unreadable: block with a visible resolver error;
- changed hash: block and offer a refresh action that updates the Work Order
  before dispatch.

Do not let delayed work read changed files under an old approval hash.

### 8. Context reveal is honest

After send, reveal shows:

- ordered root-relative paths;
- line range, if any;
- hash captured at send;
- the delivered text block or truncation note from `ThreadContextPacket.text`;
- whether the current file still matches that hash;
- worker delivery mode: `attachedFileBlock` for v1.

History never hides a missing or changed reference. It shows the old reference
and current status.

## Schema

Draft/turn refs:

```swift
public struct DraftFileReference: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var projectId: String
    public var sequence: Int
    public var rootRelativePath: String
    public var lineRange: FileLineRange?
    public var addedAt: Date
}

public struct TurnFileReferenceRef: Codable, Sendable, Equatable {
    public var referenceId: String
    public var sequence: Int
}

public struct IncludedFileReferenceDelivery: Codable, Sendable, Equatable {
    public var referenceId: String
    public var sequence: Int
    public var projectId: String
    public var rootRelativePath: String
    public var lineRange: FileLineRange?
    public var resolvedAbsolutePath: String
    public var deliveredPathUsed: String
    public var storedSha256: String
    public var byteSize: Int
    public var deliveredByteCount: Int
    public var truncated: Bool
    public var languageHint: String?
    public var deliveryMode: FileReferenceDeliveryMode
}

public struct FileLineRange: Codable, Sendable, Equatable {
    public var startLine: Int
    public var endLine: Int
}

public enum FileReferenceDeliveryMode: String, Codable, Sendable {
    case attachedFileBlock
    case projectPathBlock
}
```

Additive fields:

```swift
// ThreadTurn - default [] for legacy decode
public var fileReferenceRefs: [TurnFileReferenceRef] = []

// ThreadContextPacket - keep existing includedFiles as the compatibility path list.
// Add default [] for detailed reveal/revalidation metadata.
public var includedFileReferences: [IncludedFileReferenceDelivery] = []
```

`ThreadContextPacket.text` remains the exact body delivered to the worker,
including the bounded referenced-file contents. `includedFiles` remains the
simple path list for existing context-reveal and fixture compatibility.

V1 policy defaults:

```text
max references per turn: 12
max referenced file delivery: 64 KB per file
max referenced-file body budget: 256 KB total (total wins: e.g. 12 x 64 KB is
  capped by the 256 KB body budget, dropping/truncating lowest-sequence-last)
text only
line ranges optional through CLI/MCP and future editor integration
directory refs: not supported
```

These supersede the legacy `ThreadContextBuilder.Options` defaults (16 KB total /
4 KB per file) **on the reference delivery path only**. They are a deliberate,
larger budget for user-selected files and must be encoded as file-reference
policy constants in Core, not hard-coded at call sites. Plain chat attachments
keep their existing caps unless a separate decision changes them.

## Mac Surface Contract

Composer behavior:

- pressing `@` opens the File References palette at the caret;
- typing filters Project files immediately;
- path fragments work (`@Sources/Project` narrows by path, not just basename);
- `Enter` adds the highlighted file chip;
- `Shift+Enter` or multi-select keeps the palette open;
- `Esc` closes without changing the draft;
- manual `@relative/path.swift` text is parsed defensively at send time;
- pasted Project-local paths become file chips after resolver confirmation;
- dragging Project-local text files into the composer creates file chips;
- duplicate refs collapse to one chip unless the line range differs;
- removing a chip updates draft truth immediately.

Chip behavior:

- display root-relative path with basename emphasis;
- keep backing text copy-paste friendly as `@root/relative/path`;
- use attributed styling / token deletion for polish, but never make the
  `NSTextAttachment` the only durable state;
- show compact badges for modified, large-blocked, unreadable, or changed-since-
  selected states;
- hover or keyboard focus previews a small matched excerpt and metadata such as
  bytes and line count;
- secondary actions: Open File, Reveal in Finder, Copy Relative Path, Remove.

Do not show estimated tokens, cost, quota burn, or runtime. File size and line
count are observed facts; token impact is a forecast.

Picker presentation:

- keep one compact list in v1; no groups for Docs / Code / Chats;
- do not mix prior chats into `@` in v1 — files are durable Project context,
  prior chats are a separate future memory/history primitive;
- show root-relative path rows, not cards or previews by default;
- highlight the exact matched characters/words in the filename/path so the eye
  can verify the hit quickly;
- keep metadata muted and secondary; the row's job is fast selection, not
  explanation.

Palette copy is plain and operational:

```text
Search Project files
No matching files
Indexing Project files...
File is ignored
File is outside this Project
File is too large for v1
Sensitive file blocked
```

Do not add visible instruction text explaining how `@` works after the user is in
the flow. The control should behave like a familiar mention/file picker.

Anchoring should prefer the actual caret rect from the AppKit text view. If that
is unstable during early implementation, a polished list pinned under the
composer is acceptable for the first GUI proof; do not ship a jumpy popover just
because it is caret-anchored in theory.

## CLI Contract

Search:

```bash
alln project files <project-id|current> [--query <text>] [--limit <n>] [--json]
```

Search output includes root-relative paths and ranking metadata only. It never
returns file contents.

`alln project files` lands under the `project` command group, which does not
exist yet — it arrives with Project Spine CLI (`PRJ-S07+`), and the README
execution order already places that before File References (step 4 before
step 5). FR-S03 must not invent a parallel `project` group: if the group is not
yet present, FR-S03 is blocked on PRJ-S07, and `current` resolves through the
active Project the same way other Project-scoped commands will.

Send:

```bash
alln thread send <thread-id|latest> [<message>] \
  [--ref <root-relative-path>[:<start>-<end>]]... \
  [--worker <model-id>] \
  [--idempotency-key <key>] \
  [--json]
```

Team/project sends that accept Project context also accept `--ref` after their
Project-scoped command forms exist. `--ref` is a new flag and does not collide
with anything today: `thread send` currently exposes `--image` (image input),
`--worker`, `--idempotency-key`, and `--json` — there is no `--file` flag.
`--image` stays image-only; `--ref` is the file-reference flag.

JSON send output includes `fileReferences[]` with `referenceId`,
`rootRelativePath`, `lineRange`, `storedSha256`, `byteSize`, `deliveredPathUsed`,
`deliveredByteCount`, `truncated`, and `deliveryMode`.

## MCP Contract

Add registry-derived support only. No hand-written MCP-only descriptor. Params
are added to the `MCPToolSpec` entries in
`ContractRegistry+Milestone1.swift`; `fileReferences[]` mirrors the existing
`images` param shape there (`type: "array"` with `arrayItems.oneOf` of a string
and an object), so CLI flag, MCP schema, and `mcp-tools.json` stay one
projection. `alln dev export-contracts --check` is the drift gate that must stay
green after the registry edit.

Tools:

```text
project_files_search(projectId, query, limit) -> candidates[]
thread_send(..., fileReferences[])
project_chat(..., fileReferences[])
team_ask(..., fileReferences[]) where Project-scoped
```

`fileReferences[]` accepts either:

```json
"docs/phases/Project_Spine_And_Project_Manager.md"
```

or:

```json
{ "path": "Packages/AllnighterCore/Sources/AllnighterCore/ProjectSpine.swift",
  "startLine": 1,
  "endLine": 120 }
```

MCP callers cannot reference files outside the Project and cannot self-approve a
changed reference in delayed dispatch.

## Errors

Registry-owned errors only:

| Code | When |
| --- | --- |
| `FILE_REFERENCE_PROJECT_ROOT_MISSING` | Thread has no usable Project/working directory root |
| `FILE_REFERENCE_OUTSIDE_PROJECT` | Path escapes selected Project root |
| `FILE_REFERENCE_NOT_FOUND` | File missing at resolution |
| `FILE_REFERENCE_UNREADABLE` | File exists but cannot be read |
| `FILE_REFERENCE_BINARY_UNSUPPORTED` | Resolver classifies file as binary |
| `FILE_REFERENCE_TOO_LARGE` | File exceeds v1 cap |
| `FILE_REFERENCE_TOO_MANY` | Turn exceeds max refs |
| `FILE_REFERENCE_SENSITIVE_BLOCKED` | Secret-like path/content is blocked |
| `FILE_REFERENCE_LINE_RANGE_INVALID` | Line range is empty or outside file |
| `FILE_REFERENCE_CHANGED_BEFORE_INVOKE` | Hash changed after send resolution; reserved for FR-S05 delayed dispatch |
| `FILE_REFERENCE_CATALOG_STALE` | Search catalog cannot guarantee freshness; reserved for GUI/catalog refresh |
| `FILE_REFERENCE_WORKER_UNSUPPORTED` | Selected worker cannot read Project files; reserved for route gating |

Each entry is an `ErrorSpec` in `ContractRegistry+Milestone1.swift` and must
carry the real required fields: `code` (UPPER_SNAKE, as above), `ruleId`
(dot-form, e.g. `file.reference.outside_project`), `agentAction`, `requiresManual`,
`retryable`, `explain`, and `exitClass` (`usage` for caller-fixable input like
outside-project / too-large / too-many / line-range-invalid / sensitive-blocked;
`operational` for state races like `FILE_REFERENCE_CHANGED_BEFORE_INVOKE` and
`FILE_REFERENCE_CATALOG_STALE`). There is no `fixCommand` field on `ErrorSpec`;
put any recovery command inline in `agentAction`. Set `requiresManual` true where
a human must choose a safer file or refresh refs (changed-before-invoke,
sensitive-blocked, work-order hash mismatch); `retryable` true only where an
unmodified retry can succeed (catalog-stale).

## Privacy And Permissions

Mac v1 is local-first. File refs do not add a cloud surface and do not require
new Full Disk Access posture beyond the selected Project root behavior already
owned by Project setup.

Rules:

- search only the selected Project root;
- never catalog the whole home folder;
- never build embeddings, semantic summaries, or a code intelligence index;
- never include secret-looking files by default;
- never show absolute paths in model prompts unless the worker cannot resolve a
  root-relative path;
- never send file references to iOS as content in v1;
- make worker delivery visible in context reveal.

## Later iOS

iOS is parked and not part of Mac v1. When revived, it must not pretend to have
the Mac filesystem.

Later iOS rules:

- The default iPhone `@` picker is populated from mentioned files in local thread
  history: paths, chips, context packets, returns, and work orders.
- Mentioned-files results are best-effort and visibly distinct from the Mac's
  authoritative Project file list.
- Recently mentioned files rank highest.
- If the Mac runner is reachable, iOS may request a path-only, recency-ranked
  file list: paths and timestamps only, never file contents.
- Dispatch still resolves on the Mac. A missing file becomes a gentle visible
  blocker, never a silent miss.

## Works Test

Primary Works Test:

```text
Create a temporary Project with three text files, one ignored file, one binary
file, and one .env file. Open the Mac composer, press @, fuzzy-pick two allowed
files, send to a fake Project-file-reading worker, and assert the saved context
packet, thread turn, CLI JSON projection, and fake worker transcript all contain
the same ordered paths, hashes, and delivered file contents. Then mutate one
referenced file before a delayed dispatch and assert dispatch blocks with
FILE_REFERENCE_CHANGED_BEFORE_INVOKE.
```

Proof command:

```text
swift test --package-path Packages/AllnighterCore --filter 'ProjectFileReference|ThreadSendFileReference|ProjectFileCatalog|ThreadContextBuilder'
bash scripts/check.sh
```

GUI proof:

```text
Mac fixture: compose-file-reference
Assertions: @ palette opens, fuzzy search returns Project files, selecting creates
chips, blocked files show blocked state, send creates the expected context reveal.
```

Register `compose-file-reference` in `GUIFixture.benchScenarios`
(`Apps/AllnighterMac/Sources/GUIFixture.swift`) alongside the existing
`compose-*` ids (e.g. `compose-mode-menu`, `compose-target-chat`), and add the
matching deep-link detection. The proof seal runs through
`scripts/check_gui_proof.sh`; layout truth is the watcher's, content truth is the
CLI's (`GUI_Visual_Proof_Gate.md`).

Missing proof / waiver:

```text
Until Mac GUI test fixtures exist for the composer palette, backend CLI/Core
proof can land first, but the Mac v1 slice is not done without a GUI proof seal.
```

## Ordered Slices

| Slice | Delivers | Status |
| --- | --- | --- |
| **FR-S00** | Contract hardening: extend `ThreadContextBuilder.Options` input element to `(path, lineRange?)` + file-reference byte budget (supersede 16 KB/4 KB on the ref path), add file-ref models, policy defaults, resolver, error codes (real `ErrorSpec` fields), legacy `[String]` + decode defaults | Backend landed |
| **FR-S01** | `ProjectFileCatalog`: git/rg path source, no content index, recency/lane ranking, safety filters, recents | Backend catalog landed; GUI consumption pending |
| **FR-S02** | Send transaction: parse `@` tokens before mode branch, draft refs, `includedFiles` + `includedFileReferences`, bounded content delivery, hash recheck, fake worker proof | Thread send + fake worker proof landed; delayed-dispatch hash recheck moves to FR-S05 |
| **FR-S03** | CLI/MCP: `alln project files`, `--ref`, registry schemas, MCP `fileReferences[]`. **Depends on the `project` command group (PRJ-S07+)**; the `--ref`/`fileReferences[]` half on `thread send` can land first | `thread send --ref` + MCP `fileReferences[]` landed; `alln project files` deferred |
| **FR-S04** | Mac `@` palette: keyboard search, chips, preview, paste path, DnD Project-local files | First bridge landed in `b1604881`; ranking/highlight/paste/DnD/persistence + GUI proof pending |
| **FR-S05** | Work Order/Pending revalidation: stored hashes, refresh action, changed/missing blockers | Draft |
| **FR-S06** | Context reveal + history: ordered refs, delivered content/truncation, current hash status, delivery mode | Draft |
| **FR-S07** | GUI proof seal + dogfood pass for Project Manager chat and Send to team | Draft |
| **FR-S08** | Picker ranking and compact scan polish: match highlighting, freshness-weighted ranking, gentle document-format boost, no groups, no prior chats | **BUILT** (2026-06-20; `composer/file-reference-picker` sealed). Tiered match-quality ranking (exact / prefix / segment-prefix / contains / fuzzy-abbrev) dominates; freshness (recent ≫ dirty/staged/untracked > modified > touched) breaks ties; gentle readable-doc tiebreak (.md/.mdx/.txt/.rst/.adoc); generated/build/vendor/cache/archive sink unless very exact; no repo-specific vocab boosts. GUI: one compact ungrouped list, root-relative full paths, amber match highlighting, no prior chats. Core ranking tests + GUI proof green. |

Backend/Core/CLI slices FR-S00 through FR-S03 should land before the Mac surface.
FR-S04 through FR-S07 are the Mac v1 product finish. iOS presentation is deferred.

## Inference Bans

| Junction | Owner | Possible bad inference | Ban | Negative test |
| --- | --- | --- | --- | --- |
| Composer chip -> durable truth | `ThreadDraftContext` | SwiftUI chip state is enough | Chips render draft refs; send reads draft truth | Kill/reopen app before send; chips restore or show resolver errors |
| File path -> Project | `ProjectStore` + resolver | Absolute path can pick a Project | Selected Project owns resolution | Paste path from another Project while Project A selected; reject |
| Ref -> delivery | `ThreadContextBuilder` + packet | Path-only mention is enough | V1 delivers bounded file text and records the receipt | Fake worker receives only `@foo.swift`; test fails |
| Picker -> retrieval | `ProjectFileCatalog` | File picker should infer related files | Catalog is path/recency only; no semantic retrieval | Referencing `UserStore.swift` does not auto-add `UserStoreTests.swift` |
| File size -> usage | Context policy | Show token/cost impact | Show observed bytes/lines only; no token estimates | UI fixture containing "+1.2k tokens" fails copy check |
| Delayed mutating run -> current file | File-reference revalidation | Same path means same referenced input | Hash must match or the reference refreshes before send | Change file after the reference was taken; delayed send blocks |
| Search result -> safe file | `ProjectFileCatalog` + resolver | Catalogued means sendable | Resolver is final authority at send | Catalog stale with deleted file; send fails before turn commit |

## Open Questions

Each carries a recommended default so FR-S00 is not blocked on a meeting; the
founder can overturn any of them, but implementation should assume the default.

- **Sensitive-file override.** *Recommended: keep fully blocked in v1.* No
  override path until a real permission UX exists; the error stays
  `requiresManual`. Cheap to relax later, expensive to walk back a leak.
- **Line ranges in Mac v1.** *Recommended: build the Core/CLI/MCP plumbing now
  (foundation-first), expose whole-file only in the Mac `@` palette.* FR-S00
  carries `lineRange?` end-to-end and the resolver validates it; CLI `--ref
  path:start-end` and MCP `{path,startLine,endLine}` work immediately; the Mac
  chip exposes ranges only once open-file/editor integration lands. This avoids
  the dead-promise failure mode without gating the GUI on a range-picker.
- **Path-only delivery.** *Recommended: bounded text is the only v1 delivery
  mode; keep `projectPathBlock` in the enum but unused.* A worker may
  additionally receive path+hash, but path-only never satisfies v1 (Inference
  Ban: "path-only mention is enough"). Revisit only when a concrete high-context
  CLI worker declares a path-read strategy.
- **FSEvents refresh.** *Recommended: defer to a later slice; FR-S01 ships
  Project-activation + explicit refresh only.* The send resolver is the
  authority, so a stale catalog can only mislead search, never delivery
  (`FILE_REFERENCE_CATALOG_STALE` covers the race). FSEvents is a search-latency
  nicety, not a correctness requirement.

## Done When

- `@` in the Mac composer finds Project files instantly on ordinary repos.
- File chips survive draft reload and always resolve through the selected Project.
- Send creates one ordered reference truth across thread, packet, prompt, CLI,
  MCP, and reveal.
- Workers receive bounded referenced-file contents from the saved packet.
- Missing, changed, ignored, binary, oversized, sensitive, or out-of-root files
  fail visibly before the worker can guess.
- Delayed work revalidates file hashes before dispatch.
- Backend tests, contract drift checks, and the Mac GUI proof seal pass.

## Final Cleanup Directive: No Legacy Path

Implementation is already under way, and this feature must finish cleanly. There
are no external users to migrate, so do not preserve legacy file-reference or
attachment compatibility paths for their own sake.

Rules:

- zero legacy code after the slice lands;
- no migration layer, fallback mode, dual schema, or compatibility adapter;
- remove old `[String]`-only file attachment/reference plumbing once the new
  Project-scoped reference model is in place;
- keep only additive decode defaults that are required for existing repo
  fixtures/tests while the slice is being completed, then delete or update those
  fixtures/tests to the new model before marking the feature done;
- treat lingering legacy branches as cleanup blockers, not technical debt for a
  later milestone.

The final state is one Project-scoped implementation: root-relative references,
Project-root resolution, bounded text delivery, audited packet metadata, and no
parallel legacy path.
