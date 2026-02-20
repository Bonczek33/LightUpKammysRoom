//
//  GeneralSettingsTab.swift
//  LIFXBTMacApp
//
//  Created by Tomasz Bak on 2/20/26.
//


//
//  Settings+General.swift
//  LIFXBTMacApp
//
//  General Settings tab — user profile (DOB, FTP, weight), HR and power
//  intensity modulation, and power smoothing. Uses a read-modify-write
//  pattern so changes here never clobber fields owned by other tabs.
//
//  Owned config fields:
//    dateOfBirth, ftp, weightKg, powerMovingAverageSeconds,
//    modulateIntensityWithHR, minIntensityPercent, maxIntensityPercent,
//    modulateIntensityWithPower, minPowerIntensityPercent, maxPowerIntensityPercent
//

import SwiftUI

// MARK: - General Settings Tab

struct GeneralSettingsTab: View {
    @AppStorage("lifx_bt_tacx_user_config_v10") private var configData: Data?
    @State private var showingResetAlert = false

    // Load from UserDefaults
    @State private var dateOfBirth: Date = UserConfigStore.defaultsDOB
    @State private var ftp: Int = UserConfigStore.defaultsFTP
    @State private var weightKg: Double = 50.0
    @State private var modulateIntensityWithHR: Bool = UserConfigStore.defaultsModulateIntensityWithHR
    @State private var minIntensityPercent: Double = UserConfigStore.defaultsMinIntensityPercent
    @State private var maxIntensityPercent: Double = UserConfigStore.defaultsMaxIntensityPercent
    @State private var modulateIntensityWithPower: Bool = UserConfigStore.defaultsModulateIntensityWithPower
    @State private var minPowerIntensityPercent: Double = UserConfigStore.defaultsMinPowerIntensityPercent
    @State private var maxPowerIntensityPercent: Double = UserConfigStore.defaultsMaxPowerIntensityPercent
    @State private var powerMovingAverageSeconds: Double = UserConfigStore.defaultsPowerMovingAverageSeconds

    let intFormatter: NumberFormatter = {
        let f = NumberFormatter(); f.numberStyle = .none; return f
    }()

    let doubleFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 1
        f.maximumFractionDigits = 1
        return f
    }()

    var ageYears: Int {
        let comps = Calendar.current.dateComponents([.year], from: dateOfBirth, to: Date())
        return max(0, comps.year ?? 0)
    }

    var maxHR: Int { max(80, 220 - ageYears) }

    // MARK: Persistence

    private func loadSettings() {
        guard let data = configData,
              let decoded = try? JSONDecoder().decode(PersistedUserConfig.self, from: data) else { return }
        dateOfBirth = decoded.dateOfBirth
        ftp = decoded.ftp
        weightKg = decoded.weightKg
        modulateIntensityWithHR = decoded.modulateIntensityWithHR
        minIntensityPercent = decoded.minIntensityPercent
        maxIntensityPercent = decoded.maxIntensityPercent
        modulateIntensityWithPower = decoded.modulateIntensityWithPower ?? UserConfigStore.defaultsModulateIntensityWithPower
        minPowerIntensityPercent = decoded.minPowerIntensityPercent ?? UserConfigStore.defaultsMinPowerIntensityPercent
        maxPowerIntensityPercent = decoded.maxPowerIntensityPercent ?? UserConfigStore.defaultsMaxPowerIntensityPercent
        powerMovingAverageSeconds = decoded.powerMovingAverageSeconds
    }

    private func saveSettings() {
        // Read-modify-write: preserve fields owned by other tabs (BT, LIFX, auto source, aliases)
        var config: PersistedUserConfig
        if let data = configData,
           let existing = try? JSONDecoder().decode(PersistedUserConfig.self, from: data) {
            config = existing
        } else {
            config = PersistedUserConfig(
                dateOfBirth: dateOfBirth, ftp: ftp, weightKg: weightKg,
                autoSourceRaw: "Off",
                powerMovingAverageSeconds: powerMovingAverageSeconds,
                aliasesByID: [:],
                modulateIntensityWithHR: modulateIntensityWithHR,
                minIntensityPercent: minIntensityPercent,
                maxIntensityPercent: maxIntensityPercent,
                modulateIntensityWithPower: modulateIntensityWithPower,
                minPowerIntensityPercent: minPowerIntensityPercent,
                maxPowerIntensityPercent: maxPowerIntensityPercent
            )
        }
        config.dateOfBirth = dateOfBirth
        config.ftp = max(50, min(500, ftp))
        config.weightKg = max(30.0, min(200.0, weightKg))
        config.powerMovingAverageSeconds = max(0.0, min(10.0, powerMovingAverageSeconds))
        config.modulateIntensityWithHR = modulateIntensityWithHR
        config.minIntensityPercent = max(0.0, min(100.0, minIntensityPercent))
        config.maxIntensityPercent = max(0.0, min(100.0, maxIntensityPercent))
        config.modulateIntensityWithPower = modulateIntensityWithPower
        config.minPowerIntensityPercent = max(0.0, min(100.0, minPowerIntensityPercent))
        config.maxPowerIntensityPercent = max(0.0, min(100.0, maxPowerIntensityPercent))
        if let encoded = try? JSONEncoder().encode(config) { configData = encoded }
        NotificationCenter.default.post(name: .settingsDidChange, object: nil)
    }

    private func resetToDefaults() {
        dateOfBirth = UserConfigStore.defaultsDOB
        ftp = UserConfigStore.defaultsFTP
        weightKg = UserConfigStore.defaultsWeightKg
        modulateIntensityWithHR = UserConfigStore.defaultsModulateIntensityWithHR
        minIntensityPercent = UserConfigStore.defaultsMinIntensityPercent
        maxIntensityPercent = UserConfigStore.defaultsMaxIntensityPercent
        modulateIntensityWithPower = UserConfigStore.defaultsModulateIntensityWithPower
        minPowerIntensityPercent = UserConfigStore.defaultsMinPowerIntensityPercent
        maxPowerIntensityPercent = UserConfigStore.defaultsMaxPowerIntensityPercent
        powerMovingAverageSeconds = UserConfigStore.defaultsPowerMovingAverageSeconds

        // Read-modify-write: preserve BT and LIFX fields
        var config: PersistedUserConfig
        if let data = configData,
           let existing = try? JSONDecoder().decode(PersistedUserConfig.self, from: data) {
            config = existing
        } else {
            config = PersistedUserConfig(
                dateOfBirth: UserConfigStore.defaultsDOB, ftp: UserConfigStore.defaultsFTP,
                weightKg: UserConfigStore.defaultsWeightKg, autoSourceRaw: "Off",
                powerMovingAverageSeconds: UserConfigStore.defaultsPowerMovingAverageSeconds,
                aliasesByID: [:],
                modulateIntensityWithHR: UserConfigStore.defaultsModulateIntensityWithHR,
                minIntensityPercent: UserConfigStore.defaultsMinIntensityPercent,
                maxIntensityPercent: UserConfigStore.defaultsMaxIntensityPercent,
                modulateIntensityWithPower: UserConfigStore.defaultsModulateIntensityWithPower,
                minPowerIntensityPercent: UserConfigStore.defaultsMinPowerIntensityPercent,
                maxPowerIntensityPercent: UserConfigStore.defaultsMaxPowerIntensityPercent
            )
        }
        config.dateOfBirth = UserConfigStore.defaultsDOB
        config.ftp = UserConfigStore.defaultsFTP
        config.weightKg = UserConfigStore.defaultsWeightKg
        config.powerMovingAverageSeconds = UserConfigStore.defaultsPowerMovingAverageSeconds
        config.modulateIntensityWithHR = UserConfigStore.defaultsModulateIntensityWithHR
        config.minIntensityPercent = UserConfigStore.defaultsMinIntensityPercent
        config.maxIntensityPercent = UserConfigStore.defaultsMaxIntensityPercent
        config.modulateIntensityWithPower = UserConfigStore.defaultsModulateIntensityWithPower
        config.minPowerIntensityPercent = UserConfigStore.defaultsMinPowerIntensityPercent
        config.maxPowerIntensityPercent = UserConfigStore.defaultsMaxPowerIntensityPercent
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

                        // Profile
                        GroupBox(label: Text("Profile").font(.subheadline)) {
                            VStack(spacing: 12) {
                                HStack {
                                    Text("Date of Birth:").frame(width: 120, alignment: .trailing)
                                    DatePicker("", selection: $dateOfBirth, in: ...Date(),
                                               displayedComponents: [.date])
                                        .labelsHidden().datePickerStyle(.field).frame(width: 140)
                                        .help("Used to calculate your age-predicted maximum heart rate (220 - age).")
                                    Spacer()
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Age: \(ageYears)").font(.caption).foregroundColor(.secondary)
                                        Text("Max HR: \(maxHR) bpm").font(.caption).foregroundColor(.secondary)
                                    }
                                }
                                HStack {
                                    Text("FTP:").frame(width: 120, alignment: .trailing)
                                    TextField("", value: $ftp, formatter: intFormatter)
                                        .textFieldStyle(.roundedBorder).frame(width: 80)
                                        .help("Functional Threshold Power. Used to calculate power training zones.")
                                    Text("watts").font(.caption).foregroundColor(.secondary)
                                    Spacer()
                                }
                                HStack {
                                    Text("Weight:").frame(width: 120, alignment: .trailing)
                                    TextField("", value: $weightKg, formatter: doubleFormatter)
                                        .textFieldStyle(.roundedBorder).frame(width: 80)
                                        .help("Your body weight, used to calculate Power-to-Weight ratio (W/kg).")
                                    Text("kg").font(.caption).foregroundColor(.secondary)
                                    Spacer()
                                    Text("\(String(format: "%.1f", weightKg * 2.20462)) lbs")
                                        .font(.caption).foregroundColor(.secondary)
                                }
                            }
                            .padding(8)
                        }

                        Divider()

                        // Intensity modulation — HR
                        GroupBox(label: Text("Intensity Modulation (Heart Rate)").font(.subheadline)) {
                            VStack(alignment: .leading, spacing: 12) {
                                Toggle("Modulate intensity with heart rate", isOn: $modulateIntensityWithHR)
                                    .toggleStyle(.switch)
                                    .help("Adjusts light brightness based on HR position within the current training zone.")
                                Text("When enabled, brightness changes based on heart rate position within the zone.")
                                    .font(.caption).foregroundColor(.secondary)
                                if modulateIntensityWithHR {
                                    Divider()
                                    intensitySliders(min: $minIntensityPercent, max: $maxIntensityPercent,
                                                     label: "heart rate")
                                }
                            }
                            .padding(8)
                        }

                        // Intensity modulation — Power
                        GroupBox(label: Text("Intensity Modulation (Power)").font(.subheadline)) {
                            VStack(alignment: .leading, spacing: 12) {
                                Toggle("Modulate intensity with power", isOn: $modulateIntensityWithPower)
                                    .toggleStyle(.switch)
                                    .help("Adjusts light brightness based on power position within the current training zone.")
                                Text("When enabled, brightness changes based on power position within the zone.")
                                    .font(.caption).foregroundColor(.secondary)
                                if modulateIntensityWithPower {
                                    Divider()
                                    intensitySliders(min: $minPowerIntensityPercent, max: $maxPowerIntensityPercent,
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
                                        Text("Smoothing Window:").frame(width: 120, alignment: .trailing)
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
                            Button("Reset All Settings to Defaults") { showingResetAlert = true }
                                .foregroundColor(.red)
                            Text("This will reset your FTP, DOB, weight, power smoothing, and intensity settings to defaults.")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                    .padding()
                }
            }
            .onAppear { loadSettings() }
            .onChange(of: dateOfBirth)              { _, _ in saveSettings() }
            .onChange(of: ftp)                      { _, _ in saveSettings() }
            .onChange(of: weightKg)                 { _, _ in saveSettings() }
            .onChange(of: modulateIntensityWithHR)  { _, _ in saveSettings() }
            .onChange(of: minIntensityPercent)       { _, _ in saveSettings() }
            .onChange(of: maxIntensityPercent)       { _, _ in saveSettings() }
            .onChange(of: modulateIntensityWithPower){ _, _ in saveSettings() }
            .onChange(of: minPowerIntensityPercent)  { _, _ in saveSettings() }
            .onChange(of: maxPowerIntensityPercent)  { _, _ in saveSettings() }
            .onChange(of: powerMovingAverageSeconds) { _, _ in saveSettings() }
            .alert("Reset All Settings?", isPresented: $showingResetAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) { resetToDefaults() }
            } message: {
                Text("All settings will be reset to defaults. Changes will take effect immediately.")
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