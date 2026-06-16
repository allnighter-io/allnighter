import SwiftUI

// The clean conversation-workspace home (docs/phases/wiring compose-routing,
// reference FirstRun). What the app launches into: a left rail of work orders +
// a "You already pay for the team" empty state with the bench, the three modes,
// and the routing composer. Conversation list + live wiring come in CR3/CR4;
// this is the launch shell so the app never opens into setup/clutter.

struct HomeView: View {
    var body: some View {
        HStack(spacing: 0) {
            HomeSidebar()
                .frame(width: 300)
            Rectangle().fill(ALColor.borderSubtle).frame(width: 1)
            HomeEmptyState()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Left rail

private struct HomeSidebar: View {
    @State private var search = ""
    @State private var filter = "all"
    private let filters = [("all", "All"), ("design", "Design"), ("build", "Build"), ("running", "Running")]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 10) {
                Button {} label: {
                    Label("New work order", systemImage: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.alPrimary)

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 13)).foregroundStyle(ALColor.textFaint)
                    TextField("Search conversations", text: $search)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5))
                        .foregroundStyle(ALColor.textPrimary)
                }
                .padding(.horizontal, 10).frame(height: 32)
                .background(ALColor.input, in: RoundedRectangle(cornerRadius: ALRadius.md))
                .overlay { RoundedRectangle(cornerRadius: ALRadius.md).strokeBorder(ALColor.borderSubtle, lineWidth: 1) }

                HStack(spacing: 7) {
                    ForEach(filters, id: \.0) { key, label in
                        Button { filter = key } label: {
                            Text(label).font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(filter == key ? ALColor.textPrimary : ALColor.textMuted)
                                .padding(.horizontal, 11).frame(height: 26)
                                .background(filter == key ? ALColor.active : ALColor.subtle, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 12)

            Spacer(minLength: 0)
            emptyHint
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(ALColor.subtle)
    }

    private var emptyHint: some View {
        VStack(spacing: 8) {
            Image(systemName: "moon.stars.fill").font(.system(size: 26)).foregroundStyle(ALColor.accent)
            Text("No conversations yet")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(ALColor.textSecondary)
            Text("Your work orders will live here — newest on top.")
                .font(.system(size: 11.5)).foregroundStyle(ALColor.textFaint)
                .multilineTextAlignment(.center).frame(maxWidth: 210).lineSpacing(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14)
    }
}

// MARK: - Empty state ("You already pay for the team")

private struct HomeEmptyState: View {
    private let bench = ComposeRoutingData.bench
    private let modes: [(ComposeMode, String)] = [
        (.chat, "Ask the bench a question — “token bucket or sliding window for rate limiting?”"),
        (.fanout, "Drop a screenshot — “make this profile feel premium and clean” → a board of options."),
        (.exec, "Point an agent at your repo — “add the 429 + Retry-After path to the limiter.”"),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "moon.stars.fill").font(.system(size: 40)).foregroundStyle(ALColor.accent)
                    .padding(.top, 40)
                Text("You already pay for the team.")
                    .font(.system(size: 26, weight: .heavy)).tracking(-0.4)
                    .foregroundStyle(ALColor.textPrimary)
                Text("Allnighter puts the AI tools you already subscribe to on one bench. Ask one, ask them all, or hand the work to an agent — and route any turn to anyone.")
                    .font(.system(size: 13.5)).foregroundStyle(ALColor.textMuted)
                    .multilineTextAlignment(.center).lineSpacing(3).frame(maxWidth: 600)

                benchChips
                modeCards
                RoutingComposer(big: true)
                    .padding(.top, 4)
                hint
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 28).padding(.bottom, 40)
        }
        .background(ALColor.base)
    }

    private var benchChips: some View {
        let rows = [Array(bench.prefix(3)), Array(bench.suffix(from: min(3, bench.count)))]
        return VStack(spacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 8) {
                    ForEach(row) { m in benchChip(m) }
                }
            }
        }
        .padding(.top, 6)
    }

    private func benchChip(_ m: ComposeBenchModel) -> some View {
        HStack(spacing: 8) {
            DriverBrandGlyph(driverId: m.driverId, boxSize: 18, iconSize: 11, cornerRadius: 5)
            Text(m.name).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(ALColor.textPrimary)
            Text(m.cli).font(ALFont.monoSm).foregroundStyle(ALColor.textFaint)
            Circle().fill(m.ready ? ALPalette.green500 : ALColor.textFaint).frame(width: 6, height: 6)
        }
        .padding(.horizontal, 11).frame(height: 34)
        .background(ALColor.raised, in: Capsule())
        .overlay { Capsule().strokeBorder(ALColor.borderDefault, lineWidth: 1) }
    }

    private var modeCards: some View {
        HStack(spacing: 12) {
            ForEach(Array(modes.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: item.0.icon).font(.system(size: 15)).foregroundStyle(ALColor.accentText)
                        Text(item.0.label).font(.system(size: 13, weight: .semibold)).foregroundStyle(ALColor.textPrimary)
                    }
                    Text(item.1).font(.system(size: 11.5)).foregroundStyle(ALColor.textMuted)
                        .lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(13)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ALColor.surface, in: RoundedRectangle(cornerRadius: ALRadius.lg))
                .overlay { RoundedRectangle(cornerRadius: ALRadius.lg).strokeBorder(ALColor.borderSubtle, lineWidth: 1) }
            }
        }
        .padding(.top, 4)
    }

    private var hint: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.turn.down.right").font(.system(size: 11)).foregroundStyle(ALColor.textFaint)
            Text("One model answers — route the turn to anyone.")
                .font(.system(size: 11)).foregroundStyle(ALColor.textFaint)
        }
    }
}
