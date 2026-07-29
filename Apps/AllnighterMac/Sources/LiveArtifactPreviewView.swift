import SwiftUI
import AllnighterCore

/// TRR-S01c — compact live seat preview fed by `RunEvent`s (Mac-only).
struct LiveArtifactPreviewView: View {
  let state: LiveArtifactProjector.State
  var isLive: Bool = true

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      header
      ForEach(state.seatList, id: \.agentId) { seat in
        LiveArtifactSeatRow(seat: seat, isLive: isLive)
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(ALColor.raised, in: RoundedRectangle(cornerRadius: ALRadius.lg))
    .overlay {
      RoundedRectangle(cornerRadius: ALRadius.lg)
        .strokeBorder(isLive ? ALColor.accentBorder : ALColor.borderSubtle, lineWidth: 1)
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 6) {
        Text(isLive ? "TEAM ARTIFACT · LIVE" : "TEAM ARTIFACT")
          .font(.system(size: 9, weight: .semibold)).tracking(0.6)
          .foregroundStyle(isLive ? ALColor.accentText : ALColor.textFaint)
        if isLive {
          Circle().fill(ALColor.accent).frame(width: 6, height: 6)
            .symbolEffect(.pulse, options: .repeating)
        }
      }
      Text(state.teamLabel).font(ALFont.monoSm).foregroundStyle(ALColor.textMuted)
      Text(state.question).font(.system(size: 13, weight: .medium))
        .foregroundStyle(ALColor.textPrimary).lineLimit(2)
    }
  }
}

private struct LiveArtifactSeatRow: View {
  let seat: LiveArtifactProjector.SeatState
  var isLive: Bool

  private var dot: FloorWorkerStatePresenter.Dot {
    FloorWorkerStatePresenter.dot(status: seat.status)
  }

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      if seat.sourceId.isEmpty {
        Text(String(seat.displayName.prefix(1)).uppercased())
          .font(.system(size: 11, weight: .semibold))
          .frame(width: 26, height: 26)
          .background(ALColor.surface, in: RoundedRectangle(cornerRadius: 6))
      } else {
        DriverBrandGlyph(
          driverId: seat.sourceId, boxSize: 26, iconSize: 13, cornerRadius: 6,
          muted: seat.status == WorkerAnswerStatus.queued.rawValue
        )
      }
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 5) {
          Text(seat.displayName)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(ALColor.textSecondary).lineLimit(1)
          if seat.isLead {
            Text("Lead").font(.system(size: 8.5, weight: .semibold))
              .foregroundStyle(ALColor.textMuted)
          }
          Spacer(minLength: 4)
          durationBadge
          statusDot(dot)
        }
        if let oneLiner = seat.oneLiner {
          Text(oneLiner).font(.system(size: 11.5))
            .foregroundStyle(ALColor.textMuted).lineLimit(2)
        } else if seat.status == WorkerAnswerStatus.running.rawValue {
          Text("No live text yet").font(.system(size: 11.5))
            .foregroundStyle(ALColor.textFaint)
        }
      }
    }
    .padding(8)
    .background(
      isLive && dot == .running ? ALColor.active.opacity(0.35) : ALColor.surface,
      in: RoundedRectangle(cornerRadius: 8)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 8).strokeBorder(ALColor.borderSubtle, lineWidth: 1)
    }
  }

  @ViewBuilder private var durationBadge: some View {
    if dot == .running {
      TimelineView(.periodic(from: .now, by: 1)) { ctx in
        if let label = FloorWorkerStatePresenter.durationLabel(
          status: seat.status, startedAt: seat.startedAt,
          finishedAt: nil, durationMs: seat.durationMs, now: ctx.date
        ) {
          Text(label).font(.system(size: 9.5, design: .monospaced))
            .foregroundStyle(ALColor.textFaint)
        }
      }
    } else if let label = FloorWorkerStatePresenter.durationLabel(
      status: seat.status, startedAt: seat.startedAt,
      finishedAt: nil, durationMs: seat.durationMs, now: Date()
    ) {
      Text(label).font(.system(size: 9.5, design: .monospaced))
        .foregroundStyle(ALColor.textFaint)
    }
  }

  @ViewBuilder private func statusDot(_ dot: FloorWorkerStatePresenter.Dot) -> some View {
    if isLive && dot == .running {
      Circle().fill(dot.color).frame(width: 7, height: 7)
        .symbolEffect(.pulse, options: .repeating)
    } else {
      Circle().fill(dot.color).frame(width: 7, height: 7)
    }
  }
}
