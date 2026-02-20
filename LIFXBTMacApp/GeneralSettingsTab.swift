//
//  Settings+General.swift
//  LIFXBTMacApp
//
//  General Settings tab — HR and power intensity modulation, power smoothing,
//  and a reset button. DOB / FTP / weight have moved to Settings+Profile.swift.
//
//  Uses a read-modify-write pattern (mutateConfig) so changes here never
//  clobber fields owned by other tabs.
//
//  Owned config fields:
//    powerMovingAverageSeconds,
//    modulateIntensityWithHR, minIntensityPercent, maxIntensityPercent,
//    modulateIntensityWithPower, minPowerIntensityPercent, maxPowerIntensityPercent
//

import SwiftUI

// MARK: - General Settings Tab

struct GeneralSettingsTab: View {
    @AppStorage("lifx_bt_tacx_user_config_v10") private var configData: Data?
    @State private var showingResetAlert = false

    @State private var modulateIntensityWithHR:   Bool   = UserConfigStore.defaultsModulateIntensityWithHR
    @State private var minIntensityPercent:        Double = UserConfigStore.defaultsMinIntensityPercent
    @State private var maxIntensityPercent:        Double = UserConfigStore.defaultsMaxIntensityPercent
    @State private var modulateIntensityWithPower: Bool   = UserConfigStore.defaultsModulateIntensityWithPower
    @State private var minPowerIntensityPercent:   Double = UserConfigStore.defaultsMinPowerIntensityPercent
    @State private var maxPowerIntensityPercent:   Double = UserConfigStore.defaultsMaxPowerIntensityPercent
    @State private var powerMovingAverageSeconds:  Double = UserConfigStore.defaultsPowerMovingAverageSeconds

    // MARK: Persistence

    private func loadSettings() {
        guard let data = configData,
              let d = try? JSONDecoder().decode(PersistedUserConfig.self, from: data) else { return }
        modulateIntensityWithHR   = d.modulateIntensityWithHR
        minIntensityPercent        = d.minIntensityPercent
        maxIntensityPercent        = d.maxIntensityPercent
        modulateIntensityWithPower = d.modulateIntensityWithPower  ?? UserConfigStore.defaultsModulateIntensityWithPower
        minPowerIntensityPercent   = d.minPowerIntensityPercent    ?? UserConfigStore.defaultsMinPowerIntensityPercent
        maxPowerIntensityPercent   = d.maxPowerIntensityPercent    ?? UserConfigStore.defaultsMaxPowerIntensityPercent
        powerMovingAverageSeconds  = d.powerMovingAverageSeconds
    }

    private func saveSettings() {
        mutateConfig { c in
            c.modulateIntensityWithHR   = modulateIntensityWithHR
            c.minIntensityPercent        = max(0, min(100, minIntensityPercent))
            c.maxIntensityPercent        = max(0, min(100, maxIntensityPercent))
            c.modulateIntensityWithPower = modulateIntensityWithPower
            c.minPowerIntensityPercent   = max(0, min(100, minPowerIntensityPercent))
            c.maxPowerIntensityPercent   = max(0, min(100, maxPowerIntensityPercent))
            c.powerMovingAverageSeconds  = max(0, min(10, powerMovingAverageSeconds))
        }
    }

    private func resetToDefaults() {
        modulateIntensityWithHR   = UserConfigStore.defaultsModulateIntensityWithHR
        minIntensityPercent        = UserConfigStore.defaultsMinIntensityPercent
        maxIntensityPercent        = UserConfigStore.defaultsMaxIntensityPercent
        modulateIntensityWithPower = UserConfigStore.defaultsModulateIntensityWithPower
        minPowerIntensityPercent   = UserConfigStore.defaultsMinPowerIntensityPercent
        maxPowerIntensityPercent   = UserConfigStore.defaultsMaxPowerIntensityPercent
        powerMovingAverageSeconds  = UserConfigStore.defaultsPowerMovingAverageSeconds
        saveSettings()
    }

    /// Read-modify-write helper — decodes, applies mutation, re-encodes, posts notification.
    /// Only touches the fields passed to the closure; all other tab fields are preserved.
    private func mutateConfig(_ block: (inout PersistedUserConfig) -> Void) {
        guard let data = configData,
              var config = try? JSONDecoder().decode(PersistedUserConfig.self, from: data) else { return }
        block(&config)
        if let encoded = try? JSONEncoder().encode(config) { configData = encoded }
        NotificationCenter.default.post(name: .settingsDidChange, object: nil)
    }

    // MARK: Body

    var body: some View {
        ScrollView {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("General Settings").font(.headline)
                        Divider()

                        // Intensity modulation — HR
                        GroupBox(label: Text("Intensity Modulation (Heart Rate)").font(.subheadline)) {
                            VStack(alignment: .leading, spacing: 12) {
                                Toggle("Modulate intensity with heart rate",
                                       isOn: $modulateIntensityWithHR)
                                    .toggleStyle(.switch)
                                    .help("Adjusts light brightness based on HR position within the current training zone.")
                                Text("When enabled, brightness changes based on heart rate position within the zone.")
                                    .font(.caption).foregroundColor(.secondary)
                                if modulateIntensityWithHR {
                                    Divider()
                                    intensitySliders(min: $minIntensityPercent,
                                                     max: $maxIntensityPercent,
                                                     label: "heart rate")
                                }
                            }
                            .padding(8)
                        }

                        // Intensity modulation — Power
                        GroupBox(label: Text("Intensity Modulation (Power)").font(.subheadline)) {
                            VStack(alignment: .leading, spacing: 12) {
                                Toggle("Modulate intensity with power",
                                       isOn: $modulateIntensityWithPower)
                                    .toggleStyle(.switch)
                                    .help("Adjusts light brightness based on power position within the current training zone.")
                                Text("When enabled, brightness changes based on power position within the zone.")
                                    .font(.caption).foregroundColor(.secondary)
                                if modulateIntensityWithPower {
                                    Divider()
                                    intensitySliders(min: $minPowerIntensityPercent,
                                                     max: $maxPowerIntensityPercent,
                                                     label: "power")
                                }
                                if modulateIntensityWithHR && modulateIntensityWithPower {
                                    Divider()
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

                        // Power smoothing
                        GroupBox(label: Text("Power Smoothing").font(.subheadline)) {
                            VStack(alignment: .leading, spacing: 12) {
                                Toggle("Smooth power data with moving average",
                                       isOn: Binding(
                                           get: { powerMovingAverageSeconds > 0 },
                                           set: { powerMovingAverageSeconds = $0 ? 2.0 : 0.0 }
                                       ))
                                    .toggleStyle(.switch)
                                    .help("Reduces light flickering from power spikes.")
                                Text("Raw power values are always shown in the UI; smoothing only affects zone and brightness calculations.")
                                    .font(.caption).foregroundColor(.secondary)
                                if powerMovingAverageSeconds > 0 {
                                    Divider()
                                    HStack {
                                        Text("Smoothing Window:")
                                            .frame(width: 120, alignment: .trailing)
                                        Slider(value: $powerMovingAverageSeconds, in: 0.25...5, step: 0.25)
                                            .frame(width: 200)
                                            .help("Higher values smooth more aggressively.")
                                        Text(String(format: "%.2fs", powerMovingAverageSeconds))
                                            .font(.caption).monospacedDigit().foregroundColor(.secondary)
                                            .frame(width: 50, alignment: .trailing)
                                    }
                                    Text("Smoothing window of \(String(format: "%.1f", powerMovingAverageSeconds))s applied before zone and brightness calculations.")
                                        .font(.caption).foregroundColor(.secondary).italic()
                                }
                            }
                            .padding(8)
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            Button("Reset Modulation & Smoothing to Defaults") {
                                showingResetAlert = true
                            }
                            .foregroundColor(.red)
                            Text("Resets HR/power intensity modulation and power smoothing. Profile data (DOB, FTP, weight) is managed in the Profile tab.")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                    .padding()
                }
            }
            .onAppear { loadSettings() }
            .onChange(of: modulateIntensityWithHR)   { _, _ in saveSettings() }
            .onChange(of: minIntensityPercent)        { _, _ in saveSettings() }
            .onChange(of: maxIntensityPercent)        { _, _ in saveSettings() }
            .onChange(of: modulateIntensityWithPower) { _, _ in saveSettings() }
            .onChange(of: minPowerIntensityPercent)   { _, _ in saveSettings() }
            .onChange(of: maxPowerIntensityPercent)   { _, _ in saveSettings() }
            .onChange(of: powerMovingAverageSeconds)  { _, _ in saveSettings() }
            .alert("Reset Settings?", isPresented: $showingResetAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) { resetToDefaults() }
            } message: {
                Text("HR/power intensity modulation and power smoothing will be reset to defaults.")
            }
        }
    }

    // MARK: Helpers

    @ViewBuilder
    private func intensitySliders(min: Binding<Double>, max: Binding<Double>, label: String) -> some View {
        VStack(spacing: 12) {
            HStack {
                Text("Min Intensity:").frame(width: 120, alignment: .trailing)
                Slider(value: min, in: 0...100, step: 5).frame(width: 200)
                    .help("Light brightness at the bottom of a zone.")
                Text("\(Int(min.wrappedValue))%")
                    .font(.caption).foregroundColor(.secondary).frame(width: 40, alignment: .trailing)
            }
            HStack {
                Text("Max Intensity:").frame(width: 120, alignment: .trailing)
                Slider(value: max, in: 0...100, step: 5).frame(width: 200)
                    .help("Light brightness at the top of a zone.")
                Text("\(Int(max.wrappedValue))%")
                    .font(.caption).foregroundColor(.secondary).frame(width: 40, alignment: .trailing)
            }
            Text("Brightness varies between \(Int(min.wrappedValue))% and \(Int(max.wrappedValue))% based on your \(label) within each zone.")
                .font(.caption).foregroundColor(.secondary).italic()
        }
    }
}
