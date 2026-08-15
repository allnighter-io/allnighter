import SwiftUI
import AllnighterCore

// LR-S05 — Settings › CLIs LOCAL RUNTIME section. Own class — never a READY body row.
struct LocalRuntimeSectionView: View {
  @Environment(AppModel.self) private var model
  var forceBodySelectorOpen: Bool = false

  @State private var bodySelectorOpen = false

  private var surface: LocalRuntimeSurfacePresenter.Snapshot { model.localRuntimeSurface }

  var body: some View {
    let surface = model.localRuntimeSurface
    VStack(alignment: .leading, spacing: 10) {
      header(surface)
      runtimeSummary(surface)
      stateCopy(surface)
      if !surface.tags.isEmpty {
        tagList(surface)
      }
      if let error = model.localRuntimeEnableError {
        Text(error)
          .font(.system(size: 11.5, design: .monospaced))
          .foregroundStyle(ALColor.statusFailed)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(16)
    .background(ALColor.surface, in: RoundedRectangle(cornerRadius: ALRadius.lg))
    .overlay {
      RoundedRectangle(cornerRadius: ALRadius.lg)
        .strokeBorder(ALColor.borderSubtle, lineWidth: 1)
    }
    .onAppear {
      if forceBodySelectorOpen { bodySelectorOpen = true }
    }
  }

  // MARK: - Header

  private func header(_ surface: LocalRuntimeSurfacePresenter.Snapshot) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
      Text(surface.sectionTitle)
        .font(.system(size: 10, weight: .semibold))
        .tracking(0.9)
        .textCase(.uppercase)
        .foregroundStyle(ALColor.textFaint)
      Spacer(minLength: 0)
      if surface.showsBodySelector {
        bodySelector(surface)
      }
    }
  }

  private func bodySelector(_ surface: LocalRuntimeSurfacePresenter.Snapshot) -> some View {
    HStack(spacing: 6) {
      Text(ChromeCopy.localRuntimeViaSelector)
        .font(.system(size: 11.5))
        .foregroundStyle(ALColor.textMuted)
      Button {
        bodySelectorOpen.toggle()
      } label: {
        HStack(spacing: 4) {
          Text(surface.defaultBodyLabel)
            .font(.system(size: 11.5, weight: .semibold))
          Image(systemName: "chevron.down")
            .font(.system(size: 9, weight: .semibold))
        }
        .foregroundStyle(ALColor.textPrimary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(ALColor.raised, in: RoundedRectangle(cornerRadius: ALRadius.md))
        .overlay {
          RoundedRectangle(cornerRadius: ALRadius.md)
            .strokeBorder(ALColor.borderDefault, lineWidth: 1)
        }
      }
      .buttonStyle(.plain)
      .alPopover(isPresented: $bodySelectorOpen, arrowEdge: .bottom) {
        VStack(alignment: .leading, spacing: 0) {
          bodyOption("opencode", label: "OpenCode", selected: surface.defaultBody == "opencode")
          bodyOption("claude_code", label: "Claude Code", selected: surface.defaultBody == "claude_code")
        }
        .padding(.vertical, 4)
        .frame(minWidth: 168)
      }
    }
  }

  private func bodyOption(_ driverId: String, label: String, selected: Bool) -> some View {
    Button {
      model.setLocalRuntimeSessionDefaultBody(driverId)
      bodySelectorOpen = false
    } label: {
      HStack {
        Text(label)
          .font(.system(size: 12.5, weight: selected ? .semibold : .regular))
          .foregroundStyle(selected ? ALColor.textPrimary : ALColor.textSecondary)
        Spacer(minLength: 0)
        if selected {
          Image(systemName: "checkmark")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(ALColor.accent)
        }
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(selected ? ALColor.active : Color.clear)
    }
    .buttonStyle(.plain)
  }

  // MARK: - Summary

  private func runtimeSummary(_ surface: LocalRuntimeSurfacePresenter.Snapshot) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text(surface.harnessLine)
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(ALColor.textPrimary)
      Spacer(minLength: 0)
      if surface.showsInstallAction, let driverId = surface.installDriverId {
        installButton(driverId: driverId)
      } else if surface.showsReadyDot {
        RuntimeReachableDot()
      }
    }
  }

  private func installButton(driverId: String) -> some View {
    Button {
      installMissingBody(driverId: driverId)
    } label: {
      Text("Copy install")
        .font(.system(size: 11.5, weight: .semibold))
    }
    .buttonStyle(.alSecondary(small: true))
  }

  private func installMissingBody(driverId: String) {
    guard let card = model.setupCards.first(where: { $0.driverId == driverId }) else { return }
    let payload = SetupRecoveryCopy.installShellCommand(fromInstallHint: card.installHint)
      ?? card.installHint
      ?? card.docsURL
      ?? ""
    guard !payload.isEmpty else { return }
    SetupActions.copyToPasteboard(payload)
  }

  @ViewBuilder
  private func stateCopy(_ surface: LocalRuntimeSurfacePresenter.Snapshot) -> some View {
    if surface.loading {
      Text("Checking local runtime…")
        .font(.system(size: 12))
        .foregroundStyle(ALColor.textMuted)
    } else if surface.unobserved {
      Text(ChromeCopy.localRuntimeUnobserved)
        .font(.system(size: 12))
        .foregroundStyle(ALColor.textMuted)
        .fixedSize(horizontal: false, vertical: true)
    } else if let detail = surface.detailLine {
      Text(detail)
        .font(.system(size: 11.5, design: .monospaced))
        .foregroundStyle(ALColor.textFaint)
    } else if surface.emptyObserved {
      Text("No local tags on this machine.")
        .font(.system(size: 12))
        .foregroundStyle(ALColor.textMuted)
    }
  }

  // MARK: - Tags

  private func tagList(_ surface: LocalRuntimeSurfacePresenter.Snapshot) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(surface.tags) { tag in
        tagRow(tag)
        if tag.id != surface.tags.last?.id {
          Rectangle().fill(ALColor.borderSubtle).frame(height: 1).padding(.vertical, 2)
        }
      }
    }
    .padding(.top, 4)
  }

  private func tagRow(_ tag: LocalRuntimeSurfacePresenter.TagRow) -> some View {
    let inFlight = model.localRuntimeEnablingTagId == tag.id
    return HStack(alignment: .center, spacing: 10) {
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 6) {
          Text(tag.displayName)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(ALColor.textPrimary)
            .lineLimit(1)
          if tag.capabilityUnknown {
            Text("capability unknown")
              .font(.system(size: 9, weight: .semibold))
              .foregroundStyle(ALColor.textFaint)
              .padding(.horizontal, 5)
              .padding(.vertical, 1.5)
              .background(ALColor.active, in: Capsule())
          }
          if tag.seated, tag.readiness == "Unavailable" {
            Text("Unavailable")
              .font(.system(size: 9, weight: .semibold))
              .foregroundStyle(ALColor.textFaint)
          }
        }
        HStack(spacing: 8) {
          Text(tag.modelLabel)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(ALColor.textFaint)
            .lineLimit(1)
          if let advisory = tag.advisory {
            Text(advisory)
              .font(.system(size: 11))
              .foregroundStyle(ALColor.textMuted)
              .lineLimit(2)
          }
        }
      }
      Spacer(minLength: 8)
      if inFlight {
        ProgressView().controlSize(.small)
      } else {
        Toggle("", isOn: Binding(
          get: { tag.enabled },
          set: { model.setLocalRuntimeTagEnabled(id: tag.id, enabled: $0) }
        ))
        .labelsHidden()
        .toggleStyle(.switch)
        .tint(ALColor.accent)
      }
    }
    .padding(.vertical, 8)
  }
}

/// Ollama reachable — visually distinct from body READY green dots.
struct RuntimeReachableDot: View {
  var body: some View {
    Circle()
      .fill(ALPalette.blue500)
      .frame(width: 7, height: 7)
      .shadow(color: ALPalette.blue500.opacity(0.35), radius: 3, x: 0, y: 0)
      .accessibilityLabel("Ollama reachable")
  }
}

#if DEBUG
#Preview("LOCAL RUNTIME") {
  LocalRuntimeSectionView()
    .padding()
    .background(ALColor.base)
    .environment(AppModel())
}
#endif
