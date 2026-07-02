import Foundation
import AllnighterCore

/// The neutral result of invoking one worker's CLI once — shared by workers
/// (wrapped into a `TeamAnswer`) and reduce stages (wrapped into a `StageOutput`).
/// Pure of orchestration concerns.
///
/// This is AgentOSCLI's `WorkerRunResult` (F2_B.1+.2 cutover, then F2_B.3c's
/// `WorkerRunner` deletion): the telemetry fields this type used to carry inline
/// (`startedAt`, `ttftMs`, `rawStdoutChunkCount`, etc.) live under `.timing` (a
/// `RunTiming`). Kept as a local alias so the many `WorkerRunOutcome` call sites
/// keep resolving by name — this file is its sole surviving home now that
/// `WorkerRunner.swift` (which used to declare it) is deleted.
public typealias WorkerRunOutcome = WorkerRunResult
