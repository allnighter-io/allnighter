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

The backend is not starting from zero:

- `ThreadContextPacket` already has `includedFiles: [String]`, defaulting to `[]`
  for legacy packets, and `text` stores the exact rendered context body.
- `ThreadContextBuilder.Options.attachedFiles` already resolves absolute or
  `workingDir`-relative paths, reads UTF-8 file contents, applies byte caps,
  renders an "Attached files:" block, records `includedFiles`, and marks
  truncation.
- `ThreadSendCoordinator.Request` and `WorkerChatCoordinator` already accept
  `contextOptions`, so chat has a canonical send-transaction path that can carry
  attached files.
- `GitObserver` already shells out to git safely for Project/root metadata.
- The Mac gap is the product surface: `RoutingComposer` / `ALTextEditor` do not
  detect `@`, do not show a picker, do not persist file chips, and do not pass
  attached files into the send options.

## Truth Owner

| Layer | Owns |
| --- | --- |
| `ProjectFileCatalog` | Searchable, Project-scoped path list and ranking; no file-body index |
| `ProjectFileReferenceResolver` | Path normalization, safety, metadata, hashing, line-range validation |
| `ThreadDraftContext.fileReferences` | Draft refs visible in the composer before send |
| `ThreadTurn.fileReferenceRefs` | Committed ordered refs on the sent turn |
| `ThreadContextBuilder.Options.attachedFiles` | Existing Core input used to deliver referenced file bodies |
| `ThreadContextPacket.includedFiles` | Compatibility path list of files included in the packet body |
| `ThreadContextPacket.includedFileReferences` | Additive detailed audit: order, hash, range, delivery mode |
| `ThreadContextPacket.text` | Exact referenced-file text delivered to the worker |
| Worker prompt renderer | Protected referenced-files block from the saved packet |
| Mac composer | Presents Core truth; does not invent durable refs |

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
6. docs entrypoints and files in the current proposal/work order scope;
7. shallow/common entrypoints as a final tiebreaker.

Typed-query ranking:

1. exact basename prefix;
2. path-segment prefix;
3. basename contains;
4. path contains;
5. fuzzy abbreviation;
6. the empty-query recency score as a tiebreaker.

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
4. resolve every selected ref against the current Project root or dispatch lane
   root through `ProjectExecutionResolver`;
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
max referenced-file body budget: 256 KB total
text only
line ranges optional through CLI/MCP and future editor integration
directory refs: not supported
```

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
`deliveredByteCount`, `truncated`, and `deliveryMode`.

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
| `FILE_REFERENCE_CATALOG_STALE` | Search catalog cannot guarantee freshness |
| `FILE_REFERENCE_WORKER_UNSUPPORTED` | Selected worker cannot read Project files |

Each error needs `agentAction`, `fixCommand` when applicable, `retryable`, and
`requiresManual` where a human must choose a safer file or refresh refs.

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

Missing proof / waiver:

```text
Until Mac GUI test fixtures exist for the composer palette, backend CLI/Core
proof can land first, but the Mac v1 slice is not done without a GUI proof seal.
```

## Ordered Slices

| Slice | Delivers | Status |
| --- | --- | --- |
| **FR-S00** | Contract hardening: reuse `ThreadContextBuilder.Options.attachedFiles`, add file-ref models, policy defaults, resolver, error codes, legacy decode defaults | Draft |
| **FR-S01** | `ProjectFileCatalog`: git/rg path source, no content index, recency/lane ranking, safety filters, recents | Draft |
| **FR-S02** | Send transaction: parse `@` tokens before mode branch, draft refs, `includedFiles` + `includedFileReferences`, bounded content delivery, hash recheck, fake worker proof | Draft |
| **FR-S03** | CLI/MCP: `alln project files`, `--ref`, registry schemas, MCP `fileReferences[]` | Draft |
| **FR-S04** | Mac `@` palette: keyboard search, chips, preview, paste path, DnD Project-local files | Draft |
| **FR-S05** | Work Order/Pending revalidation: stored hashes, refresh action, changed/missing blockers | Draft |
| **FR-S06** | Context reveal + history: ordered refs, delivered content/truncation, current hash status, delivery mode | Draft |
| **FR-S07** | GUI proof seal + dogfood pass for Project Manager chat and Send to team | Draft |

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
| Delayed dispatch -> current file | Work Order revalidation | Same path means same approved input | Hash must match or refresh approval | Change file after approval; dispatch blocks |
| Search result -> safe file | `ProjectFileCatalog` + resolver | Catalogued means sendable | Resolver is final authority at send | Catalog stale with deleted file; send fails before turn commit |

## Open Questions

- Should v1 allow explicit sensitive-file override, or keep sensitive files fully
  blocked until a permission UX exists?
- Should line ranges ship in Mac v1 through a path suffix parser, or wait for
  editor/open-file integration?
- Should path-only delivery remain available as an advanced worker strategy for
  high-context CLI agents, or should v1 always include bounded text?
- Should FSEvents refresh land in FR-S01, or is Project activation + explicit
  refresh enough for v1 because resolver truth is send-time?

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
