# Composer File References

Status: Draft Mac v1 feature packet
Owner: AllnighterCore + Mac app + CLI/MCP contracts
Created: 2026-06-19
Updated: 2026-06-19
Process: `docs/workflows/SSOT_Founder_Input_Workflow.md` ->
`docs/workflows/SSOT_Feature_Workflow.md`
Depends on: [`Project_Spine_And_Project_Manager.md`](Project_Spine_And_Project_Manager.md),
[`Persistent_Work_Threads.md`](Persistent_Work_Threads.md),
[`Composer_Image_Attachments.md`](Composer_Image_Attachments.md),
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
-> saved context packet records the exact referenced paths and hashes
-> worker receives an explicit "read these files first" block
-> history can reveal what was referenced and whether files changed later
```

Non-goals for Mac v1:

- arbitrary out-of-Project file upload;
- directory references as a durable object;
- PDF/document ingestion;
- automatic codebase-wide retrieval;
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

Enter adds a chip. Send tells the agent:

```text
Read these files before answering:
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

## Truth Owner

| Layer | Owns |
| --- | --- |
| `ProjectFileIndex` | Searchable, Project-scoped candidate list and ranking |
| `ProjectFileReferenceResolver` | Path normalization, safety, metadata, hashing, line-range validation |
| `ThreadDraftContext.fileReferences` | Draft refs visible in the composer before send |
| `ThreadTurn.fileReferenceRefs` | Committed ordered refs on the sent turn |
| `ThreadContextPacket.includedFileReferences` | Audit record used to render the worker prompt |
| Worker prompt renderer | Protected "read these files first" block from the saved packet |
| Mac composer | Presents Core truth; does not invent durable refs |

Do not use image attachments for Project file references. Do not put absolute
paths in user-facing chips when a root-relative path is available. Do not let
SwiftUI own selected-file truth.

## Implementation Law

### 1. Project-scoped only

Mac v1 indexes and references files under the selected Project root. A mutating
route is already blocked without a Project; file references follow the same
floor.

Rules:

- store root-relative paths as the public identity;
- resolve absolute paths only through the selected Project root;
- reject `..`, symlink escapes, missing roots, and duplicate active Project
  roots;
- never infer a Project from a pasted path when a Project is already selected.

### 2. Search is warmed, local, and fast

The `@` palette must not shell out on every keystroke.

V1 indexing:

```text
Project selected
-> warm ProjectFileIndex in Core
-> git repo: git ls-files -co --exclude-standard
-> folder Project: rg --files with default ignore semantics
-> filter generated/cache/vendor directories
-> classify text/binary/large/sensitive
-> update with FSEvents debounce while Project is open
```

Ranking:

1. exact basename prefix;
2. path-segment prefix;
3. fuzzy abbreviation;
4. recently referenced in this Project;
5. dirty or recently changed files;
6. docs entrypoints and files in the current proposal/work order scope.

Palette open target: instant with recents and warm candidates; search update
target: under 50 ms for the warmed index on ordinary repos. If the index is
warming, the palette stays usable with recents plus exact-path validation.

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
index completion order, modified time, or worker capability.

Draft refs persist with the thread draft. If the app quits before send, reopening
the thread restores the chips or shows exact resolver failures.

### 5. Send resolves and audits references

The send transaction must:

1. lock the thread;
2. resolve every selected ref against the current Project root;
3. reject missing, escaped, binary, sensitive, oversized, or invalid line-range
   refs;
4. hash the referenced file at send time;
5. append the user turn with ordered `fileReferenceRefs`;
6. save `context/<packetId>.json` with `includedFileReferences`;
7. render the worker prompt from the saved packet;
8. invoke the worker from the selected Project root.

If a file changes between send resolution and worker invocation, fail before the
worker starts with `FILE_REFERENCE_CHANGED_BEFORE_INVOKE`. Do not silently send
the agent to a different file than the user selected.

### 6. References are read instructions, not content snapshots

Mac v1 tells project-aware workers which files to read. It does not copy file
contents into thread history as a hidden attachment.

Prompt block shape:

```text
Referenced files selected by the user. Read them before answering. If a file is
missing, unreadable, or different from the hash below, say so instead of
guessing.

1. docs/phases/Project_Spine_And_Project_Manager.md
   sha256: ...
2. Packages/AllnighterCore/Sources/AllnighterCore/ProjectSpine.swift
   lines: 1-120
   sha256: ...
```

Non-project-aware workers receive a visible warning and do not claim to have read
files. The Project Manager and Send to team routes should prefer workers whose
driver manifests declare Project file reading support when file refs are present.

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
- whether the current file still matches that hash;
- worker delivery mode: `projectPathBlock` for v1.

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
    public var languageHint: String?
    public var deliveryMode: FileReferenceDeliveryMode
}

public struct FileLineRange: Codable, Sendable, Equatable {
    public var startLine: Int
    public var endLine: Int
}

public enum FileReferenceDeliveryMode: String, Codable, Sendable {
    case projectPathBlock
}
```

Additive fields:

```swift
// ThreadTurn - default [] for legacy decode
public var fileReferenceRefs: [TurnFileReferenceRef] = []

// ThreadContextPacket - default [] for legacy decode
public var includedFileReferences: [IncludedFileReferenceDelivery] = []
```

V1 policy defaults:

```text
max references per turn: 12
max referenced file size: 1 MB
text only
line ranges optional through CLI/MCP and future editor integration
directory refs: not supported
```

## Mac Surface Contract

Composer behavior:

- pressing `@` opens the File References palette at the caret;
- typing filters Project files immediately;
- `Enter` adds the highlighted file chip;
- `Shift+Enter` or multi-select keeps the palette open;
- `Esc` closes without changing the draft;
- pasted Project-local paths become file chips after resolver confirmation;
- dragging Project-local text files into the composer creates file chips;
- duplicate refs collapse to one chip unless the line range differs;
- removing a chip updates draft truth immediately.

Chip behavior:

- display root-relative path with basename emphasis;
- show compact badges for modified, large-blocked, unreadable, or changed-since-
  selected states;
- hover or keyboard focus previews a small matched excerpt and metadata;
- secondary actions: Open File, Reveal in Finder, Copy Relative Path, Remove.

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

## CLI Contract

Search:

```bash
alln project files <project-id|current> [--query <text>] [--limit <n>] [--json]
```

Send:

```bash
alln thread send <thread-id|latest> [<message>] \
  [--ref <root-relative-path>[:<start>-<end>]]... \
  [--worker <model-id>] \
  [--idempotency-key <key>] \
  [--json]
```

Team/project sends that accept Project context also accept `--ref` after their
Project-scoped command forms exist. `--file` remains prompt-body input; it is not
a file reference flag.

JSON send output includes `fileReferences[]` with `referenceId`,
`rootRelativePath`, `lineRange`, `storedSha256`, `byteSize`, `deliveredPathUsed`,
and `deliveryMode`.

## MCP Contract

Add registry-derived support only. No hand-written MCP-only descriptor.

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
| `FILE_REFERENCE_OUTSIDE_PROJECT` | Path escapes selected Project root |
| `FILE_REFERENCE_NOT_FOUND` | File missing at resolution |
| `FILE_REFERENCE_UNREADABLE` | File exists but cannot be read |
| `FILE_REFERENCE_BINARY_UNSUPPORTED` | Resolver classifies file as binary |
| `FILE_REFERENCE_TOO_LARGE` | File exceeds v1 cap |
| `FILE_REFERENCE_TOO_MANY` | Turn exceeds max refs |
| `FILE_REFERENCE_SENSITIVE_BLOCKED` | Secret-like path/content is blocked |
| `FILE_REFERENCE_LINE_RANGE_INVALID` | Line range is empty or outside file |
| `FILE_REFERENCE_CHANGED_BEFORE_INVOKE` | Hash changed after send resolution |
| `FILE_REFERENCE_INDEX_STALE` | Search index cannot guarantee freshness |
| `FILE_REFERENCE_WORKER_UNSUPPORTED` | Selected worker cannot read Project files |

Each error needs `agentAction`, `fixCommand` when applicable, `retryable`, and
`requiresManual` where a human must choose a safer file or refresh refs.

## Privacy And Permissions

Mac v1 is local-first. File refs do not add a cloud surface and do not require
new Full Disk Access posture beyond the selected Project root behavior already
owned by Project setup.

Rules:

- search only the selected Project root;
- never index the whole home folder;
- never include secret-looking files by default;
- never show absolute paths in model prompts unless the worker cannot resolve a
  root-relative path;
- never send file references to iOS as content in v1;
- make worker delivery visible in context reveal.

## Works Test

Primary Works Test:

```text
Create a temporary Project with three text files, one ignored file, one binary
file, and one .env file. Open the Mac composer, press @, fuzzy-pick two allowed
files, send to a fake Project-file-reading worker, and assert the saved context
packet, thread turn, CLI JSON projection, and fake worker transcript all contain
the same ordered paths and hashes. Then mutate one referenced file before a
delayed dispatch and assert dispatch blocks with FILE_REFERENCE_CHANGED_BEFORE_INVOKE.
```

Proof command:

```text
swift test --package-path Packages/AllnighterCore --filter 'ProjectFileReference|ThreadSendFileReference|ProjectFileIndex|FileReferencePromptRenderer'
bash scripts/check.sh
```

GUI proof:

```text
Mac fixture: compose-file-reference
Assertions: @ palette opens, fuzzy search returns Project files, selecting creates
chips, blocked files show blocked state, send creates the expected context reveal.
```

Missing proof / waiver:

```text
Until Mac GUI test fixtures exist for the composer palette, backend CLI/Core
proof can land first, but the Mac v1 slice is not done without a GUI proof seal.
```

## Ordered Slices

| Slice | Delivers | Status |
| --- | --- | --- |
| **FR-S00** | Contract packet: Core models, policy defaults, resolver, error codes, legacy decode defaults | Draft |
| **FR-S01** | `ProjectFileIndex`: git/rg source, FSEvents refresh, ranking, safety filters, recents | Draft |
| **FR-S02** | Send transaction: draft refs, `includedFileReferences`, prompt renderer, hash recheck, fake worker proof | Draft |
| **FR-S03** | CLI/MCP: `alln project files`, `--ref`, registry schemas, MCP `fileReferences[]` | Draft |
| **FR-S04** | Mac `@` palette: keyboard search, chips, preview, paste path, DnD Project-local files | Draft |
| **FR-S05** | Work Order/Pending revalidation: stored hashes, refresh action, changed/missing blockers | Draft |
| **FR-S06** | Context reveal + history: ordered refs, current hash status, delivery mode, unsupported-worker warnings | Draft |
| **FR-S07** | GUI proof seal + dogfood pass for Project Manager chat and Send to team | Draft |

Backend/Core/CLI slices FR-S00 through FR-S03 should land before the Mac surface.
FR-S04 through FR-S07 are the Mac v1 product finish. iOS presentation is deferred.

## Inference Bans

| Junction | Owner | Possible bad inference | Ban | Negative test |
| --- | --- | --- | --- | --- |
| Composer chip -> durable truth | `ThreadDraftContext` | SwiftUI chip state is enough | Chips render draft refs; send reads draft truth | Kill/reopen app before send; chips restore or show resolver errors |
| File path -> Project | `ProjectStore` + resolver | Absolute path can pick a Project | Selected Project owns resolution | Paste path from another Project while Project A selected; reject |
| Ref -> content | Worker prompt renderer | Referenced means content copied into prompt | V1 sends read instructions and hash, not hidden content | Context packet has delivery metadata but no file body |
| Delayed dispatch -> current file | Work Order revalidation | Same path means same approved input | Hash must match or refresh approval | Change file after approval; dispatch blocks |
| Search result -> safe file | `ProjectFileIndex` + resolver | Indexed means sendable | Resolver is final authority at send | Index stale with deleted file; send fails before turn commit |

## Open Questions

- Should v1 allow explicit sensitive-file override, or keep sensitive files fully
  blocked until a permission UX exists?
- Should line ranges ship in Mac v1 through a path suffix parser, or wait for
  editor/open-file integration?
- Should small text snippets be optionally included for non-project-aware chat
  workers, or should file refs require Project-file-reading worker capability?

## Done When

- `@` in the Mac composer finds Project files instantly on ordinary repos.
- File chips survive draft reload and always resolve through the selected Project.
- Send creates one ordered reference truth across thread, packet, prompt, CLI,
  MCP, and reveal.
- Workers receive a protected "read these files first" block from the saved
  packet.
- Missing, changed, ignored, binary, oversized, sensitive, or out-of-root files
  fail visibly before the worker can guess.
- Delayed work revalidates file hashes before dispatch.
- Backend tests, contract drift checks, and the Mac GUI proof seal pass.
