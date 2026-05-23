import SwiftUI
import HealthyMonitorCore

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if appState.activeFocusSession != nil {
                activeSessionContent
            } else {
                idleContent
            }
            Divider()
            footerSection
        }
        .frame(width: 300)
        .task { await appState.refreshStats() }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "heart.fill")
                .foregroundStyle(.red)
            Text("HealthyMonitor")
                .font(.headline)
            Spacer()
            complianceBadge
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    /// Badge shows: current session compliance when active; last ended session when idle; "–" otherwise.
    private var complianceBadge: some View {
        let sessionStats = appState.activeFocusSession != nil
            ? appState.currentSessionStats
            : appState.lastEndedSession?.stats
        let total = sessionStats?.totalReminders ?? 0
        let hasData = total > 0
        let rate = sessionStats?.overallComplianceRate ?? 0
        let label = hasData ? "\(Int(rate * 100))%" : "–"
        let badgeColor = hasData ? color(for: rate) : Color.secondary
        return Text(label)
            .font(.caption.bold())
            .foregroundStyle(badgeColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(badgeColor.opacity(0.15), in: Capsule())
    }

    // MARK: - Idle state (no focus session)

    private var idleContent: some View {
        VStack(spacing: 12) {
            VStack(spacing: 4) {
                Image(systemName: "timer")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("No active focus session")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let lastLabel = lastSessionLabel {
                    Text(lastLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 16)

            Button {
                Task { await appState.startFocusSession() }
            } label: {
                Label("Start Focus Session", systemImage: "play.fill")
                    .font(.callout.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    /// "Last session · 75% · 2h ago" — or auto-ended note when the prior session was
    /// closed by the inactivity safety net. nil when no prior session exists.
    private var lastSessionLabel: String? {
        guard let session = appState.lastEndedSession,
              let endedAt = session.endedAt else { return nil }
        let elapsed = Date.now.timeIntervalSince(endedAt)
        let hours = Int(elapsed) / 3600
        let minutes = (Int(elapsed) % 3600) / 60
        let ago: String
        if hours > 0 { ago = "\(hours)h ago" }
        else if minutes > 0 { ago = "\(minutes)m ago" }
        else { ago = "just now" }
        if session.endReason == .autoEndedDueToInactivity {
            return "Auto-ended \(ago) — no reminders confirmed"
        }
        guard let stats = session.stats, stats.totalReminders > 0 else { return nil }
        let percent = Int(stats.overallComplianceRate * 100)
        return "Last session · \(percent)% · \(ago)"
    }

    // MARK: - Active session state

    private var activeSessionContent: some View {
        VStack(spacing: 0) {
            sessionTimerRow
            Divider()
            complianceSection
            Divider()
            sessionActionSection
        }
    }

    private var sessionTimerRow: some View {
        TimelineView(.everyMinute) { _ in
            HStack {
                Image(systemName: "target")
                    .foregroundStyle(.green)
                Text("Focusing")
                    .font(.callout.bold())
                Spacer()
                Text(elapsedString)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private var elapsedString: String {
        guard let session = appState.activeFocusSession else { return "" }
        let elapsed = Date.now.timeIntervalSince(session.startedAt)
        let h = Int(elapsed) / 3600
        let m = (Int(elapsed) % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    private var complianceSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("This session")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 10)

            HStack(spacing: 16) {
                ForEach(ReminderType.allCases, id: \.self) { type in
                    ReminderTypeCard(
                        type: type,
                        stats: appState.currentSessionStats?.stats(for: type) ?? .zero
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }

    private var sessionActionSection: some View {
        VStack(spacing: 2) {
            if case .paused = appState.engineState {
                QuickActionRow(icon: "play.fill", label: "Resume reminders", color: .green) {
                    Task { await appState.resumeEngine() }
                }
            } else {
                QuickActionRow(icon: "pause.fill", label: "Pause reminders", color: .orange) {
                    Task { await appState.pauseEngine() }
                }
            }
            QuickActionRow(icon: "stop.fill", label: "End Focus Session", color: .red) {
                Task { await appState.endFocusSession() }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack {
            Button("Settings") {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func color(for rate: Double) -> Color {
        switch rate {
        case 0.7...: return .green
        case 0.4..<0.7: return .orange
        default: return .red
        }
    }
}

// MARK: - Sub-views

private struct ReminderTypeCard: View {
    let type: ReminderType
    let stats: DailyStats.TypeStats

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: stats.complianceRate)
                    .stroke(ringColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.5), value: stats.complianceRate)
                Text(type.emoji)
                    .font(.title3)
            }
            .frame(width: 52, height: 52)

            Text(type.displayName)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if stats.total > 0 {
                Text("\(stats.completed)/\(stats.total)")
                    .font(.caption2.bold())
            } else {
                Text("–")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var ringColor: Color {
        switch stats.complianceRate {
        case 0.7...: return .green
        case 0.4..<0.7: return .orange
        default: return stats.total == 0 ? .secondary : .red
        }
    }
}

private struct QuickActionRow: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .frame(width: 20)
                Text(label)
                    .font(.callout)
                Spacer()
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
    }
}
