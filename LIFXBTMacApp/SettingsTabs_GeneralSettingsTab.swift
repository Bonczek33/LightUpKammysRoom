//
//  SettingsTabs_GeneralSettingsTab.swift
//  LIFXBTMacApp
//
//  General Settings tab — HR and power intensity modulation, power smoothing.
//  Binds directly to UserConfigStore @Published properties — no local @State
//  mirrors, so values are always in sync regardless of load timing.
//

import SwiftUI

// MARK: - General Settings Tab

struct GeneralSettingsTab: View {
    @EnvironmentObject var store: UserConfigStore
    @State private var showingResetAlert = false

    private func persist() {
        store.save()
        NotificationCenter.default.post(name: .settingsDidChange, object: nil)
    }

    private func resetToDefaults() {
        store.modulateIntensityWithHR   = UserConfigStore.defaultsModulateIntensityWithHR
        store.minIntensityPercent        = UserConfigStore.defaultsMinIntensityPercent
        store.maxIntensityPercent        = UserConfigStore.defaultsMaxIntensityPercent
        store.modulateIntensityWithPower = UserConfigStore.defaultsModulateIntensityWithPower
        store.minPowerIntensityPercent   = UserConfigStore.defaultsMinPowerIntensityPercent
        store.maxPowerIntensityPercent   = UserConfigStore.defaultsMaxPowerIntensityPercent
        store.powerMovingAverageSeconds  = UserConfigStore.defaultsPowerMovingAverageSeconds
        persist()
    }

    var body: some View {
        ScrollView {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("General Settings").font(.headline)
                        Divider()

                        GroupBox(label: Text("Intensity Modulation (Heart Rate)").font(.subheadline)) {
                            VStack(alignment: .leading, spacing: 12) {
                                Toggle("Modulate intensity with heart rate", isOn: $store.modulateIntensityWithHR)
                                    .toggleStyle(.switch)
                                    .onChange(of: store.modulateIntensityWithHR) { _, _ in persist() }
                                    .help("Adjusts light brightness based on HR position within the current training zone.")
                                Text("When enabled, brightness changes based on heart rate position within the zone.")
                                    .font(.caption).foregroundColor(.secondary)
                                Divider()
                                if store.modulateIntensityWithHR {
                                    intensitySliders(min: $store.minIntensityPercent,
                                                     max: $store.maxIntensityPercent,
                                                     label: "heart rate")
                                }
                            }
                            .padding(8)
                        }

                        GroupBox(label: Text("Intensity Modulation (Power)").font(.subheadline)) {
                            VStack(alignment: .leading, spacing: 12) {
                                Toggle("Modulate intensity with power", isOn: $store.modulateIntensityWithPower)
                                    .toggleStyle(.switch)
                                    .onChange(of: store.modulateIntensityWithPower) { _, _ in persist() }
                                    .help("Adjusts light brightness based on power position within the current training zone.")
                                Text("When enabled, brightness changes based on power position within the zone.")
                                    .font(.caption).foregroundColor(.secondary)
                                Divider()
                                if store.modulateIntensityWithPower {
                                    intensitySliders(min: $store.minPowerIntensityPercent,
                                                     max: $store.maxPowerIntensityPercent,
                                                     label: "power")
                                }
                                if store.modulateIntensityWithHR && store.modulateIntensityWithPower {
                                    HStack(spacing: 6) {
                                        Image(systemName: "info.circle").foregroundColor(.blue)
                                        Text("Both modulations enabled. HR takes priority with Power source; Power takes priority with HR source.")
                                            .font(.caption).foregroundColor(.secondary)
                                    }
                                }
                            }
                            .padding(8)
                        }

                        Divider()

                        GroupBox(label: Text("Power Smoothing").font(.subheadline)) {
                            VStack(alignment: .leading, spacing: 12) {
                                Toggle("Smooth power data with moving average",
                                       isOn: Binding(
                                           get: { store.powerMovingAverageSeconds > 0 },
                                           set: { store.powerMovingAverageSeconds = $0 ? 2.0 : 0.0; persist() }
                                       ))
                                    .toggleStyle(.switch)
                                    .help("Reduces light flickering from power spikes.")
                                Text("Raw power values are always shown in the UI; smoothing only affects zone and brightness calculations.")
                                    .font(.caption).foregroundColor(.secondary)
                                Divider()
                                if store.powerMovingAverageSeconds > 0 {
                                    HStack {
                                        Text("Smoothing Window:").frame(width: 120, alignment: .trailing)
                                        Slider(value: $store.powerMovingAverageSeconds, in: 0.25...5, step: 0.25)
                                            .frame(width: 200)
                                            .onChange(of: store.powerMovingAverageSeconds) { _, _ in persist() }
                                            .help("Higher values smooth more aggressively.")
                                        Text(String(format: "%.2fs", store.powerMovingAverageSeconds))
                                            .font(.caption).monospacedDigit().foregroundColor(.secondary)
                                            .frame(width: 50, alignment: .trailing)
                                    }
                                    Text("Smoothing window of \(String(format: "%.1f", store.powerMovingAverageSeconds))s applied before zone and brightness calculations.")
                                        .font(.caption).foregroundColor(.secondary).italic()
                                }
                            }
                            .padding(8)
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            Button("Reset Modulation & Smoothing to Defaults") { showingResetAlert = true }
                                .foregroundColor(.red)
                            Text("Resets HR/power intensity modulation and power smoothing. Profile data (DOB, FTP, weight) is managed in the Profile tab.")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                    .padding()
                }
            }
            .alert("Reset Settings?", isPresented: $showingResetAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) { resetToDefaults() }
            } message: {
                Text("HR/power intensity modulation and power smoothing will be reset to defaults.")
            }
        }
    }

    @ViewBuilder
    private func intensitySliders(min: Binding<Double>, max: Binding<Double>, label: String) -> some View {
        VStack(spacing: 12) {
            HStack {
                Text("Min Intensity:").frame(width: 120, alignment: .trailing)
                Slider(value: min, in: 0...100, step: 5).frame(width: 200)
                    .onChange(of: min.wrappedValue) { _, _ in persist() }
                    .help("Light brightness at the bottom of a zone.")
                Text("\(Int(min.wrappedValue))%")
                    .font(.caption).foregroundColor(.secondary).frame(width: 40, alignment: .trailing)
            }
            HStack {
                Text("Max Intensity:").frame(width: 120, alignment: .trailing)
                Slider(value: max, in: 0...100, step: 5).frame(width: 200)
                    .onChange(of: max.wrappedValue) { _, _ in persist() }
                    .help("Light brightness at the top of a zone.")
                Text("\(Int(max.wrappedValue))%")
                    .font(.caption).foregroundColor(.secondary).frame(width: 40, alignment: .trailing)
            }
            Text("Brightness varies between \(Int(min.wrappedValue))% and \(Int(max.wrappedValue))% based on your \(label) within each zone.")
                .font(.caption).foregroundColor(.secondary).italic()
        }
    }
}
