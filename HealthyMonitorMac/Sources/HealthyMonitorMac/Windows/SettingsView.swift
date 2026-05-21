import SwiftUI
import HealthyMonitorCore

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var standInterval: Double = 45
    @State private var waterInterval: Double = 90
    @State private var stretchInterval: Double = 60
    @State private var workStart: Int = 9
    @State private var workEnd: Int = 18
    @State private var hasQuietHours: Bool = false
    @State private var quietStart: Int = 22
    @State private var quietEnd: Int = 7
    @State private var apiKey: String = ""

    var body: some View {
        TabView {
            remindersTab
                .tabItem { Label("Reminders", systemImage: "bell") }

            scheduleTab
                .tabItem { Label("Schedule", systemImage: "calendar") }

            llmTab
                .tabItem { Label("AI Coach", systemImage: "bubble.left.and.bubble.right") }
        }
        .frame(width: 420, height: 320)
        .padding()
        .onAppear { loadFromProfile() }
    }

    // MARK: - Reminders tab

    private var remindersTab: some View {
        Form {
            Section("Reminder Intervals") {
                IntervalSlider(label: "🧍 Stand up", value: $standInterval, unit: "min")
                IntervalSlider(label: "💧 Drink water", value: $waterInterval, unit: "min")
                IntervalSlider(label: "🤸 Stretch", value: $stretchInterval, unit: "min")
            }
            Button("Save Intervals") { saveIntervals() }
                .buttonStyle(.borderedProminent)
        }
        .formStyle(.grouped)
    }

    // MARK: - Schedule tab

    private var scheduleTab: some View {
        Form {
            Section("Work Hours") {
                Picker("Start", selection: $workStart) {
                    ForEach(0..<24, id: \.self) { h in
                        Text(formatHour(h)).tag(h)
                    }
                }
                Picker("End", selection: $workEnd) {
                    ForEach(0..<24, id: \.self) { h in
                        Text(formatHour(h)).tag(h)
                    }
                }
            }
            Section("Quiet Hours (no reminders)") {
                Toggle("Enable quiet hours", isOn: $hasQuietHours)
                if hasQuietHours {
                    Picker("From", selection: $quietStart) {
                        ForEach(0..<24, id: \.self) { h in Text(formatHour(h)).tag(h) }
                    }
                    Picker("Until", selection: $quietEnd) {
                        ForEach(0..<24, id: \.self) { h in Text(formatHour(h)).tag(h) }
                    }
                }
            }
            Button("Save Schedule") { saveSchedule() }
                .buttonStyle(.borderedProminent)
        }
        .formStyle(.grouped)
    }

    // MARK: - AI Coach tab

    private var llmTab: some View {
        Form {
            Section("DeepSeek API Key") {
                SecureField("sk-...", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                Text("Get your key at platform.deepseek.com. Stored securely in Keychain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Save API Key") { saveAPIKey() }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Helpers

    private func loadFromProfile() {
        let p = appState.profile
        workStart = p.workScheduleStartHour
        workEnd = p.workScheduleEndHour
        hasQuietHours = p.quietHoursStartHour != nil
        quietStart = p.quietHoursStartHour ?? 22
        quietEnd = p.quietHoursEndHour ?? 7
        standInterval = Double(p.reminderIntervalMinutes[ReminderType.stand.rawValue] ?? ReminderType.stand.defaultIntervalMinutes)
        waterInterval = Double(p.reminderIntervalMinutes[ReminderType.water.rawValue] ?? ReminderType.water.defaultIntervalMinutes)
        stretchInterval = Double(p.reminderIntervalMinutes[ReminderType.stretch.rawValue] ?? ReminderType.stretch.defaultIntervalMinutes)
        apiKey = KeychainHelper.loadAPIKey() ?? ""
    }

    private func saveIntervals() {
        Task {
            await appState.updateIntervals(
                stand: Int(standInterval),
                water: Int(waterInterval),
                stretch: Int(stretchInterval)
            )
        }
    }

    private func saveSchedule() {
        var profile = appState.profile
        profile.workScheduleStartHour = workStart
        profile.workScheduleEndHour = workEnd
        profile.quietHoursStartHour = hasQuietHours ? quietStart : nil
        profile.quietHoursEndHour = hasQuietHours ? quietEnd : nil
        Task { await appState.updateProfile(profile) }
    }

    private func saveAPIKey() {
        KeychainHelper.saveAPIKey(apiKey)
    }

    private func formatHour(_ h: Int) -> String {
        let suffix = h < 12 ? "AM" : "PM"
        let display = h == 0 ? 12 : (h > 12 ? h - 12 : h)
        return "\(display):00 \(suffix)"
    }
}

private struct IntervalSlider: View {
    let label: String
    @Binding var value: Double
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                Spacer()
                Text("\(Int(value)) \(unit)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: $value, in: 15...120, step: 5)
        }
    }
}
