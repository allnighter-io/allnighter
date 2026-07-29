import XCTest
import AgentOSTeam
@testable import AllnighterCore

final class LiveArtifactProjectorTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_750_000_000)
  private let context = ArtifactProjector.Context(
    modelDisplayName: { id in id == "model_grok" ? "Grok" : "Opus" },
    sourceId: { _ in "grok" }
  )

  private func teamRun() -> TeamRun {
    let workers = [
      Agent(id: "model_grok#0", modelId: "model_grok", instanceIndex: 0,
             skillId: "reader", skillName: "Reader", purpose: .answer),
      Agent(id: "model_opus#0", modelId: "model_opus", instanceIndex: 0,
             skillId: "lead", skillName: "Lead", purpose: .plan),
    ]
    let answers = workers.map {
      TeamAnswer(memberId: $0.id, modelId: $0.modelId, role: $0.purpose?.rawValue ?? "answer",
                 result: WorkerRunResult(status: .queued))
    }
    return TeamRun(
      id: "run_live1", prompt: "Should we ship live paint?", status: .fanningOut,
      presetId: "code_spec_review", workers: workers, answers: answers,
      createdAt: now, teamDisplayName: "Spec Review"
    )
  }

  func testSeedUsesSeatSetOrderAndQueuedStatus() {
    let state = LiveArtifactProjector.seed(run: teamRun(), context: context)
    XCTAssertEqual(state.seatList.map(\.workerId), ["model_grok#0", "model_opus#0"])
    XCTAssertEqual(state.seatList.map(\.status), ["queued", "queued"])
    XCTAssertNil(state.seatList[0].oneLiner)
  }

  func testWorkerStatusChangedUpdatesStatusAndDuration() {
    var state = LiveArtifactProjector.seed(run: teamRun(), context: context)
    let running = RunEvent(
      id: "e1", seq: 1, ts: now.addingTimeInterval(1),
      kind: RunEventKind.workerStatusChanged,
      payload: [
        "workerId": .string("model_grok#0"),
        "to": .string(WorkerAnswerStatus.running.rawValue),
      ]
    )
    XCTAssertTrue(LiveArtifactProjector.apply(running, to: &state))
    XCTAssertEqual(state.seatList[0].status, WorkerAnswerStatus.running.rawValue)
    XCTAssertEqual(state.seatList[0].startedAt, running.ts)

    let done = RunEvent(
      id: "e2", seq: 2, ts: now.addingTimeInterval(5),
      kind: RunEventKind.workerStatusChanged,
      payload: [
        "workerId": .string("model_grok#0"),
        "to": .string(WorkerAnswerStatus.done.rawValue),
        "durationMs": .int(3200),
      ]
    )
    XCTAssertTrue(LiveArtifactProjector.apply(done, to: &state))
    XCTAssertEqual(state.seatList[0].status, WorkerAnswerStatus.done.rawValue)
    XCTAssertEqual(state.seatList[0].durationMs, 3200)
  }

  func testWorkerAnswerDeltaSetsOneLinerWithoutInventingOthers() {
    var state = LiveArtifactProjector.seed(run: teamRun(), context: context)
    let delta = RunEvent(
      id: "e3", seq: 3, ts: now.addingTimeInterval(2),
      kind: RunEventKind.workerAnswerDelta,
      payload: [
        "workerId": .string("model_grok#0"),
        "text": .string("First visible line\nsecond line"),
      ]
    )
    XCTAssertTrue(LiveArtifactProjector.apply(delta, to: &state))
    XCTAssertEqual(state.seatList[0].oneLiner, "First visible line")
    XCTAssertNil(state.seatList[1].oneLiner)
  }

  func testIgnoresUnknownEventKinds() {
    var state = LiveArtifactProjector.seed(run: teamRun(), context: context)
    let ignored = RunEvent(
      id: "e4", seq: 4, ts: now, kind: RunEventKind.runStatusChanged,
      payload: ["to": .string(RunStatus.running.rawValue)]
    )
    XCTAssertFalse(LiveArtifactProjector.apply(ignored, to: &state))
  }
}
