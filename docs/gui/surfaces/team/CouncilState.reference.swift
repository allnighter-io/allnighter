// ============================================================
//  CouncilState.swift
//  Legacy visual reference only. Product vocabulary is now
//  Team/Model/Skill/Worker/Plan; do not copy Council/panel/
//  plan writer labels into new UI.
//  The Council screen's state machine, as a SwiftUI-ready model.
//  Mirrors the prototype in ui_kits/council/index.html (CouncilApp).
//
//  This is a SKELETON to implement against — wire the timers to real
//  CLI subprocess events, not the simulated delays from the prototype.
// ============================================================

import SwiftUI
import Observation

// MARK: - Domain

struct Model: Identifiable, Hashable {
    let id: String
    let name: String      // "Opus 4.8"
    let model: String     // "via claude-code"
    let brandSlug: String? // Simple Icons slug, e.g. "anthropic" — nil → fall back to SF Symbol
    let glyphHex: UInt32?  // brand tint for the glyph
    var isPlanWriter: Bool = false
}

enum RunStatus: String {
    case queued, running, done, failed, timedOut
    // Pill colors live in ALColor.status*; running uses ALMotion.pulse on the dot.
}

struct WorkerRun {
    var status: RunStatus = .queued
    var meta: String? = nil   // "2,140 · 00:04"  or  "auth expired"
}

/// The three top-level screens, plus the plan writer sub-state of `.run`.
enum CouncilView: Equatable { case compose, run, plan }
enum SynthPhase: Equatable { case waiting, planning, ready }

// MARK: - The founder's six-worker panel (MVP)

enum CouncilData {
    static let models: [Model] = [
        Model(id: "opus",     name: "Opus 4.8",     model: "via claude-code", brandSlug: "anthropic",    glyphHex: 0xFFA630, isPlanWriter: true),
        Model(id: "gpt",      name: "ChatGPT 5.5",  model: "via codex-cli",   brandSlug: nil,            glyphHex: nil),   // SF Symbol "terminal"
        Model(id: "sonnet",   name: "Sonnet 4.6",   model: "via claude-code", brandSlug: "anthropic",    glyphHex: 0xAEB5C9),
        Model(id: "composer", name: "Composer 2.5", model: "via cursor",      brandSlug: nil,            glyphHex: nil),   // SF Symbol "square"
        Model(id: "gemini",   name: "Gemini Flash", model: "via gemini-cli",  brandSlug: "googlegemini", glyphHex: 0xE1E5F0),
        Model(id: "grok",     name: "Grok Build",   model: "via grok-cli",    brandSlug: "x",            glyphHex: 0xE1E5F0),
    ]
}

// MARK: - Observable view model

@Observable
final class CouncilModel {
    var prompt: String = "Give me three different directions for making this dashboard feel premium."
    var selected: Set<String> = Set(CouncilData.workers.map(\.id))
    var view: CouncilView = .compose
    var states: [String: WorkerRun] = [:]
    var elapsed: String = "00:00"
    var synth: SynthPhase = .waiting

    var selectedWorkers: [Model] { CouncilData.workers.filter { selected.contains($0.id) } }
    var canRun: Bool { !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !selected.isEmpty }

    // Panel selection — never allow zero (keep at least one seat).
    func toggle(_ id: String) {
        if selected.contains(id) {
            if selected.count > 1 { selected.remove(id) }
        } else {
            selected.insert(id)
        }
    }

    // compose → run.  Each worker: queued → running → done/failed.
    // When the slowest finishes: synth waiting → planning (+450ms) → ready (+2.7s).
    // Replace the simulated scheduling below with real CLI process callbacks.
    func startRun() {
        states = Dictionary(uniqueKeysWithValues: selectedWorkers.map { ($0.id, WorkerRun(status: .queued)) })
        synth = .waiting; elapsed = "00:00"; view = .run
        // TODO: spawn one async task per selected worker; update states[id] on
        //       process start (.running) and exit (.done with token+time meta, or
        //       .failed with the surfaced reason). Drive `elapsed` from a 100ms ticker.
        //       When all have terminated, set synth = .planning, run Opus on the
        //       collected answers, then synth = .ready.
    }

    func stop()  { view = .compose }                 // discards the in-flight run
    func reset() { states = [:]; synth = .waiting; elapsed = "00:00"; view = .compose }
    func openPlan() { view = .plan }
}

/*
 STATE TRANSITION TABLE
 ──────────────────────────────────────────────────────────────────────
 from .compose
   Run team (canRun)         → .run, synth .waiting, all seats .queued
 within .run
   per worker (stagger ~170ms)  → .running           (live dot pulses)
   per worker (on CLI exit)     → .done | .failed | .timedOut (+ meta)
   all workers terminated       → synth .planning (live mark blinks)
   synthesis complete           → synth .ready        ("View plan")
   Stop                         → .compose            (clear timers/tasks)
   View plan (.ready)    → .plan
 within .plan
   New run                      → .compose (reset)
   Tabs                         → segmented "Plan" / "Worker answers"
 ──────────────────────────────────────────────────────────────────────
 HONESTY RULE: a worker that did not return is shown .failed with its real
 reason ("auth expired"), never hidden or faked. Surface it in Doctor too.
*/
