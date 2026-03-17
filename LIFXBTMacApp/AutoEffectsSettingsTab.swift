//
//  AutoEffectsSettingsTab.swift
//  LIFXBTMacApp
//
//  Settings for automatic light effects:
//   1. Inactivity — random effect after 15 min idle (HR + power both 0)
//   2. Reminder   — random effect at a scheduled time on selected days
//

import SwiftUI

struct AutoEffectsSettingsTab: View {
    @EnvironmentObject var store: UserConfigStore

    private let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    private func persist() {
        store.save()
        NotificationCenter.default.post(name: .settingsDidChange, object: nil)
    }

    var body: some View {
        ScrollView {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Automatic Light Effects")
                            .font(.headline)
                        Text("These effects activate automatically when lights are on and no HR or power data is detected (rider is idle).")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Divider()

                        // ── Inactivity effect ────────────────────────────────
                        GroupBox(label: Text("Inactivity Effect").font(.subheadline)) {
                            VStack(alignment: .leading, spacing: 12) {
                                Toggle("Enable inactivity effect", isOn: $store.inactivityEffectEnabled)
                                    .toggleStyle(.switch)
                                    .onChange(of: store.inactivityEffectEnabled) { _, _ in persist() }
                                    .help("Activates a random light effect after 15 minutes of no HR or power data, while lights are on.")

                                Text("After 15 minutes of inactivity (HR and power both zero), a random effect plays for 15 minutes. Repeats every 30 minutes while idle.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Divider()

                                HStack(spacing: 6) {
                                    Image(systemName: "info.circle")
                                        .foregroundColor(.blue)
                                    Text("Eligible effects: Breathe, Pulse, Comet, Rainbow, Lava, Move → / Move ←")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(8)
                        }

                        // ── Reminder effect ──────────────────────────────────
                        GroupBox(label: Text("Reminder Effect").font(.subheadline)) {
                            VStack(alignment: .leading, spacing: 12) {
                                Toggle("Enable reminder effect", isOn: $store.reminderEffectEnabled)
                                    .toggleStyle(.switch)
                                    .onChange(of: store.reminderEffectEnabled) { _, _ in persist() }
                                    .help("Activates a random light effect at the scheduled time on selected days, if HR and power are zero.")

                                Text("Plays a random effect for 15 minutes at the selected time. Only activates when lights are on and no sensor data is active.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Divider()

                                if store.reminderEffectEnabled {

                                    // Day picker
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Active days:")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        HStack(spacing: 6) {
                                            ForEach(0..<7) { day in
                                                let isOn = store.reminderDays.contains(day)
                                                Button(action: {
                                                    if isOn {
                                                        store.reminderDays.removeAll { $0 == day }
                                                    } else {
                                                        store.reminderDays.append(day)
                                                        store.reminderDays.sort()
                                                    }
                                                    persist()
                                                }) {
                                                    Text(dayNames[day])
                                                        .font(.caption)
                                                        .fontWeight(isOn ? .semibold : .regular)
                                                        .frame(width: 34, height: 26)
                                                        .background(isOn ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                                                        .foregroundColor(isOn ? .white : .primary)
                                                        .cornerRadius(6)
                                                        .overlay(
                                                            RoundedRectangle(cornerRadius: 6)
                                                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                                                        )
                                                }
                                                .buttonStyle(.plain)
                                                .help(isOn ? "Click to disable \(dayNames[day])" : "Click to enable \(dayNames[day])")
                                            }

                                            Spacer()

                                            // Quick day-group buttons
                                            Button("Daily") {
                                                store.reminderDays = [0,1,2,3,4,5,6]; persist()
                                            }
                                            .buttonStyle(.borderless)
                                            .font(.caption)
                                            .help("Enable all days")

                                            Button("Weekdays") {
                                                store.reminderDays = [1,2,3,4,5]; persist()
                                            }
                                            .buttonStyle(.borderless)
                                            .font(.caption)
                                            .help("Mon–Fri only")

                                            Button("Weekends") {
                                                store.reminderDays = [0,6]; persist()
                                            }
                                            .buttonStyle(.borderless)
                                            .font(.caption)
                                            .help("Sat–Sun only")
                                        }
                                    }

                                    Divider()

                                    // Time picker
                                    HStack(spacing: 12) {
                                        Text("Time:")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .frame(width: 40, alignment: .trailing)

                                        Picker("", selection: $store.reminderHour) {
                                            ForEach(0..<24) { h in
                                                Text(String(format: "%02d", h)).tag(h)
                                            }
                                        }
                                        .frame(width: 60)
                                        .onChange(of: store.reminderHour) { _, _ in persist() }
                                        .help("Hour (24h)")

                                        Text(":")
                                            .foregroundColor(.secondary)

                                        Picker("", selection: $store.reminderMinute) {
                                            ForEach(0..<60) { m in
                                                Text(String(format: "%02d", m)).tag(m)
                                            }
                                        }
                                        .frame(width: 60)
                                        .onChange(of: store.reminderMinute) { _, _ in persist() }
                                        .help("Minute (00–59)")

                                        Text(reminderSummary)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .italic()
                                    }
                                }
                            }
                            .padding(8)
                        }
                    }
                    .padding()
                }
            }
        }
    }

    private var reminderSummary: String {
        let h = store.reminderHour
        let m = store.reminderMinute
        let ampm = h < 12 ? "AM" : "PM"
        let h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h)
        let timeStr = String(format: "%d:%02d %@", h12, m, ampm)

        if store.reminderDays.count == 7 {
            return "Daily at \(timeStr)"
        } else if store.reminderDays.sorted() == [1,2,3,4,5] {
            return "Weekdays at \(timeStr)"
        } else if store.reminderDays.sorted() == [0,6] {
            return "Weekends at \(timeStr)"
        } else if store.reminderDays.isEmpty {
            return "No days selected"
        } else {
            let names = store.reminderDays.sorted().map { dayNames[$0] }.joined(separator: ", ")
            return "\(names) at \(timeStr)"
        }
    }
}
