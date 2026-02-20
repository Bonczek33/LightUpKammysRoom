//
//  LIFXBTMacApp.swift
//  LIFXBTMacApp
//
//  Created by Tomasz Bak on 2/16/26.
//

import SwiftUI
import AppKit

extension Notification.Name {
    static let settingsDidChange = Notification.Name("settingsDidChange")
}

@main
struct LIFXBTMacApp: App {
    @StateObject private var bt = BluetoothSensorsViewModel()
    @StateObject private var antPlus = ANTPlusSensorViewModel()
    @StateObject private var lifx = LIFXDiscoveryViewModel()
    @StateObject private var store = UserConfigStore()
    @StateObject private var auto = AutoColorController()
    @StateObject private var charts = ChartsViewModel()

var body: some Scene {
     //   WindowGroup("Light Up Kammy's Room") {
       //     ContentView(bt: bt, lifx: lifx, auto: auto, store: store, charts: charts)
       // }
        WindowGroup("Light Up Kammy's Room") {
            ContentView(
                bt: bt,
                antPlus: antPlus,
                lifx: lifx,
                auto: auto,
                store: store,
                charts: charts
            )
            .onAppear {
                bringMainWindowToFront()
            }
        }
    .defaultSize(width: 1000, height: 1000)
    .defaultPosition(.center)
        // REMOVED: Duplicate Settings menu command
        // macOS automatically creates Settings menu when Settings scene exists
        
        #if swift(>=5.9)
        Settings {
            SettingsView()
                .frame(width: 1000, height: 600, alignment: .center)
                .environmentObject(bt)
                .environmentObject(antPlus)
                .environmentObject(lifx)
                .environmentObject(store)
                .environmentObject(auto)
                .environmentObject(charts)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 1000, height: 600)
        .defaultPosition(.center)
        .windowResizability(.contentSize)
        #else
        Settings {
            SettingsView()
                .environmentObject(bt)
        }
        #endif

    }
}

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
            
            BluetoothSettingsTab()
                .tabItem {
                    Label("Sensors", systemImage: "antenna.radiowaves.left.and.right")
                }
            
            LightsSettingsTab()
                .tabItem {
                    Label("Lights", systemImage: "lightbulb")
                }
            
            ZonesSettingsTab()
                .tabItem {
                    Label("Zones", systemImage: "chart.bar.fill")
                }
            
            AboutSettingsTab()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .padding(20)
    }
}

private func bringMainWindowToFront() {
    DispatchQueue.main.async {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }
}

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
        let f = NumberFormatter()
        f.numberStyle = .none
        return f
    }()
    
    let doubleFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 1
        f.maximumFractionDigits = 1
        return f
    }()
    
    var ageYears: Int {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year], from: dateOfBirth, to: Date())
        return max(0, comps.year ?? 0)
    }
    
    var maxHR: Int { max(80, 220 - ageYears) }
    
    private func loadSettings() {
        guard let data = configData,
              let decoded = try? JSONDecoder().decode(PersistedUserConfig.self, from: data) else {
            return
        }
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
            // No existing config — create a fresh one with safe defaults for non-General fields
            config = PersistedUserConfig(
                dateOfBirth: dateOfBirth,
                ftp: ftp,
                weightKg: weightKg,
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
        
        // Only update the fields owned by General Settings
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
        
        if let encoded = try? JSONEncoder().encode(config) {
            configData = encoded
        }
        
        // Notify main app to reload settings
        NotificationCenter.default.post(name: .settingsDidChange, object: nil)
    }
    
    // FIXED: Proper reset implementation — preserves BT and LIFX fields
    private func resetToDefaults() {
        // Reset all state variables to defaults
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
                dateOfBirth: UserConfigStore.defaultsDOB,
                ftp: UserConfigStore.defaultsFTP,
                weightKg: UserConfigStore.defaultsWeightKg,
                autoSourceRaw: "Off",
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
        
        // Only reset General Settings fields
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
        
        if let encoded = try? JSONEncoder().encode(config) {
            configData = encoded
        }
        
        // Notify main app
        NotificationCenter.default.post(name: .settingsDidChange, object: nil)
    }
    
    var body: some View {
        ScrollView {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("General Settings")
                            .font(.headline)
                        
                        Divider()
                        
                        // Profile Settings
                        GroupBox(label: Text("Profile").font(.subheadline)) {
                            VStack(spacing: 12) {
                                HStack {
                                    Text("Date of Birth:")
                                        .frame(width: 120, alignment: .trailing)
                                    
                                    DatePicker(
                                        "",
                                        selection: $dateOfBirth,
                                        in: ...Date(),
                                        displayedComponents: [.date]
                                    )
                                    .labelsHidden()
                                    .datePickerStyle(.field)
                                    .frame(width: 140)
                                    .help("Used to calculate your age-predicted maximum heart rate (220 - age).")
                                    
                                    Spacer()
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Age: \(ageYears)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text("Max HR: \(maxHR) bpm")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                
                                HStack {
                                    Text("FTP:")
                                        .frame(width: 120, alignment: .trailing)
                                    
                                    TextField("", value: $ftp, formatter: intFormatter)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 80)
                                        .help("Functional Threshold Power — the max power you can sustain for ~1 hour. Used to calculate power training zones.")
                                    
                                    Text("watts")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    Spacer()
                                }
                                
                                HStack {
                                    Text("Weight:")
                                        .frame(width: 120, alignment: .trailing)
                                    

                                    TextField("", value: $weightKg, formatter: doubleFormatter)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 80)
                                        .help("Your body weight, used to calculate Power-to-Weight ratio (W/kg) in the performance charts.")
                                    
                                    Text("kg")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    Spacer()
                                    
                                    Text("\(String(format: "%.1f", weightKg * 2.20462)) lbs")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(8)
                        }
                        
                        Divider()
                        
                        // Intensity Modulation Settings (HR-based)
                        GroupBox(label: Text("Intensity Modulation (Heart Rate)").font(.subheadline)) {
                            VStack(alignment: .leading, spacing: 12) {
                                Toggle("Modulate intensity with heart rate", isOn: $modulateIntensityWithHR)
                                    .toggleStyle(.switch)
                                    .help("Adjusts light brightness based on where your heart rate falls within the current training zone. Lower HR in the zone = dimmer, higher = brighter.")
                                
                                Text("When enabled, light brightness changes based on your heart rate position within the current zone. Works with both Power and Heart Rate source modes.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                if modulateIntensityWithHR {
                                    VStack(spacing: 12) {
                                        Divider()
                                        
                                        HStack {
                                            Text("Min Intensity:")
                                                .frame(width: 120, alignment: .trailing)
                                            
                                            Slider(value: $minIntensityPercent, in: 0...100, step: 5)
                                                .frame(width: 200)
                                                .help("Light brightness at the bottom of a zone. Lower values create more dramatic contrast between zone entry and zone peak.")
                                            
                                            Text("\(Int(minIntensityPercent))%")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .frame(width: 40, alignment: .trailing)
                                        }
                                        
                                        HStack {
                                            Text("Max Intensity:")
                                                .frame(width: 120, alignment: .trailing)
                                            
                                            Slider(value: $maxIntensityPercent, in: 0...100, step: 5)
                                                .frame(width: 200)
                                                .help("Light brightness at the top of a zone. Set below 100% to avoid overly bright lights at peak effort.")
                                            
                                            Text("\(Int(maxIntensityPercent))%")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .frame(width: 40, alignment: .trailing)
                                        }
                                        
                                        Text("Light brightness will vary between \(Int(minIntensityPercent))% and \(Int(maxIntensityPercent))% based on your heart rate within each zone.")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .italic()
                                    }
                                }
                            }
                            .padding(8)
                        }
                        
                        // Intensity Modulation Settings (Power-based)
                        GroupBox(label: Text("Intensity Modulation (Power)").font(.subheadline)) {
                            VStack(alignment: .leading, spacing: 12) {
                                Toggle("Modulate intensity with power", isOn: $modulateIntensityWithPower)
                                    .toggleStyle(.switch)
                                    .help("Adjusts light brightness based on where your power falls within the current training zone. Power smoothing is applied before modulation.")
                                
                                Text("When enabled, light brightness changes based on your power position within the current zone. Works with both Heart Rate and Power source modes.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                if modulateIntensityWithPower {
                                    VStack(spacing: 12) {
                                        Divider()
                                        
                                        HStack {
                                            Text("Min Intensity:")
                                                .frame(width: 120, alignment: .trailing)
                                            
                                            Slider(value: $minPowerIntensityPercent, in: 0...100, step: 5)
                                                .frame(width: 200)
                                                .help("Light brightness at the bottom of a zone. Lower values create more dramatic contrast between zone entry and zone peak.")
                                            
                                            Text("\(Int(minPowerIntensityPercent))%")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .frame(width: 40, alignment: .trailing)
                                        }
                                        
                                        HStack {
                                            Text("Max Intensity:")
                                                .frame(width: 120, alignment: .trailing)
                                            
                                            Slider(value: $maxPowerIntensityPercent, in: 0...100, step: 5)
                                                .frame(width: 200)
                                                .help("Light brightness at the top of a zone. Set below 100% to avoid overly bright lights at peak effort.")
                                            
                                            Text("\(Int(maxPowerIntensityPercent))%")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .frame(width: 40, alignment: .trailing)
                                        }
                                        
                                        Text("Light brightness will vary between \(Int(minPowerIntensityPercent))% and \(Int(maxPowerIntensityPercent))% based on your power within each zone.")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .italic()
                                    }
                                }
                                
                                if modulateIntensityWithHR && modulateIntensityWithPower {
                                    Divider()
                                    HStack(spacing: 6) {
                                        Image(systemName: "info.circle")
                                            .foregroundColor(.blue)
                                        Text("Both HR and Power modulation are enabled. When source is Power, HR modulation takes priority. When source is Heart Rate, Power modulation takes priority.")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .padding(8)
                        }
                        
                        Divider()
                        
                        // Power Smoothing Settings
                        GroupBox(label: Text("Power Smoothing").font(.subheadline)) {
                            VStack(alignment: .leading, spacing: 12) {
                                Toggle("Smooth power data with moving average", isOn: Binding(
                                    get: { powerMovingAverageSeconds > 0 },
                                    set: { newValue in
                                        powerMovingAverageSeconds = newValue ? 2.0 : 0.0
                                    }
                                ))
                                    .toggleStyle(.switch)
                                    .help("Applies a moving average window to power data before it affects zone selection, color control, and intensity modulation. Reduces light flickering from power spikes.")
                                
                                Text("When enabled, power data is smoothed with a moving average before affecting light color and brightness. Raw power values are always displayed in the UI.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                if powerMovingAverageSeconds > 0 {
                                    VStack(spacing: 12) {
                                        Divider()
                                        
                                        HStack {
                                            Text("Smoothing Window:")
                                                .frame(width: 120, alignment: .trailing)
                                            
                                            Slider(value: $powerMovingAverageSeconds, in: 0.25...5, step: 0.25)
                                                .frame(width: 200)
                                                .help("Duration of the moving average window. Higher values smooth out power spikes for more stable light behavior.")
                                            
                                            Text(String(format: "%.2fs", powerMovingAverageSeconds))
                                                .font(.caption)
                                                .monospacedDigit()
                                                .foregroundColor(.secondary)
                                                .frame(width: 50, alignment: .trailing)
                                        }
                                        
                                        Text("Smoothing window of \(String(format: "%.1f", powerMovingAverageSeconds))s applied to power data before zone selection and intensity modulation.")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .italic()
                                    }
                                }
                            }
                            .padding(8)
                        }
                        
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Button("Reset All Settings to Defaults") {
                                showingResetAlert = true
                            }
                            .foregroundColor(.red)
                            
                            Text("This will reset your FTP, DOB, weight, power smoothing, and intensity settings to defaults.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                    }
                    .padding()
                }
            }
            .onAppear {
                loadSettings()
            }
            .onChange(of: dateOfBirth) { _, _ in saveSettings() }
            .onChange(of: ftp) { _, _ in saveSettings() }
            .onChange(of: weightKg) { _, _ in saveSettings() }
            .onChange(of: modulateIntensityWithHR) { _, _ in saveSettings() }
            .onChange(of: minIntensityPercent) { _, _ in saveSettings() }
            .onChange(of: maxIntensityPercent) { _, _ in saveSettings() }
            .onChange(of: modulateIntensityWithPower) { _, _ in saveSettings() }
            .onChange(of: minPowerIntensityPercent) { _, _ in saveSettings() }
            .onChange(of: maxPowerIntensityPercent) { _, _ in saveSettings() }
            .onChange(of: powerMovingAverageSeconds) { _, _ in saveSettings() }
            .alert("Reset All Settings?", isPresented: $showingResetAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Reset", role: .destructive) {
                    resetToDefaults()
                }
            } message: {
                Text("All settings will be reset to defaults. Changes will take effect immediately.")
            }
        }
    }
}

// MARK: - Bluetooth Settings Tab (live scan + connect)

struct BluetoothSettingsTab: View {
    @EnvironmentObject var bt: BluetoothSensorsViewModel
    @EnvironmentObject var antPlus: ANTPlusSensorViewModel
    @AppStorage("lifx_bt_tacx_user_config_v10") private var configData: Data?

    @State private var autoReconnect: Bool = true
    @State private var savedHRName: String? = nil
    @State private var savedPowerName: String? = nil
    @State private var sensorSource: String = "ble"
    @State private var antPlusAutoReconnect: Bool = true
    @State private var savedANTHRName: String? = nil
    @State private var savedANTPowerName: String? = nil

    private func loadBTSettings() {
        guard let data = configData,
              let decoded = try? JSONDecoder().decode(PersistedUserConfig.self, from: data) else { return }
        autoReconnect = decoded.btAutoReconnect ?? true
        savedHRName = decoded.lastHRPeripheralName
        savedPowerName = decoded.lastPowerPeripheralName
        sensorSource = decoded.sensorInputSource ?? "ble"
        antPlusAutoReconnect = decoded.antPlusAutoReconnect ?? true
        savedANTHRName = decoded.lastANTHRDeviceName
        savedANTPowerName = decoded.lastANTPowerDeviceName
    }

    private func saveSensorSource(_ value: String) {
        guard let data = configData,
              var decoded = try? JSONDecoder().decode(PersistedUserConfig.self, from: data) else { return }
        decoded.sensorInputSource = value
        if let encoded = try? JSONEncoder().encode(decoded) {
            configData = encoded
        }
        NotificationCenter.default.post(name: .settingsDidChange, object: nil)
    }

    private func saveANTPlusAutoReconnect(_ value: Bool) {
        guard let data = configData,
              var decoded = try? JSONDecoder().decode(PersistedUserConfig.self, from: data) else { return }
        decoded.antPlusAutoReconnect = value
        if let encoded = try? JSONEncoder().encode(decoded) {
            configData = encoded
        }
        NotificationCenter.default.post(name: .settingsDidChange, object: nil)
    }

    private func saveCurrentANTDevices() {
        guard let data = configData,
              var decoded = try? JSONDecoder().decode(PersistedUserConfig.self, from: data) else { return }

        if let devNum = antPlus.connectedHRDeviceNumber, let name = antPlus.connectedHRName {
            decoded.lastANTHRDeviceNumber = devNum
            decoded.lastANTHRDeviceName = name
            savedANTHRName = name
        }
        if let devNum = antPlus.connectedPowerDeviceNumber, let name = antPlus.connectedPowerName {
            decoded.lastANTPowerDeviceNumber = devNum
            decoded.lastANTPowerDeviceName = name
            savedANTPowerName = name
        }

        if let encoded = try? JSONEncoder().encode(decoded) {
            configData = encoded
        }
        NotificationCenter.default.post(name: .settingsDidChange, object: nil)
    }

    private func clearSavedANTDevices() {
        guard let data = configData,
              var decoded = try? JSONDecoder().decode(PersistedUserConfig.self, from: data) else { return }
        decoded.lastANTHRDeviceNumber = nil
        decoded.lastANTHRDeviceName = nil
        decoded.lastANTPowerDeviceNumber = nil
        decoded.lastANTPowerDeviceName = nil
        if let encoded = try? JSONEncoder().encode(decoded) {
            configData = encoded
        }
        savedANTHRName = nil
        savedANTPowerName = nil
        NotificationCenter.default.post(name: .settingsDidChange, object: nil)
    }

    private func saveBTAutoReconnect(_ value: Bool) {
        guard let data = configData,
              var decoded = try? JSONDecoder().decode(PersistedUserConfig.self, from: data) else { return }
        decoded.btAutoReconnect = value
        if let encoded = try? JSONEncoder().encode(decoded) {
            configData = encoded
        }
        NotificationCenter.default.post(name: .settingsDidChange, object: nil)
    }

    private func clearSavedDevices() {
        guard let data = configData,
              var decoded = try? JSONDecoder().decode(PersistedUserConfig.self, from: data) else { return }
        decoded.lastHRPeripheralID = nil
        decoded.lastHRPeripheralName = nil
        decoded.lastPowerPeripheralID = nil
        decoded.lastPowerPeripheralName = nil
        if let encoded = try? JSONEncoder().encode(decoded) {
            configData = encoded
        }
        savedHRName = nil
        savedPowerName = nil
        NotificationCenter.default.post(name: .settingsDidChange, object: nil)
    }

    private func saveCurrentDevices() {
        guard let data = configData,
              var decoded = try? JSONDecoder().decode(PersistedUserConfig.self, from: data) else { return }
        
        // Snapshot whatever is currently connected
        if let hrName = bt.connectedHRName, let hrPeriphID = bt.connectedHRPeripheralID {
            decoded.lastHRPeripheralID = hrPeriphID
            decoded.lastHRPeripheralName = hrName
            savedHRName = hrName
        }
        if let pwrName = bt.connectedPowerName, let pwrPeriphID = bt.connectedPowerPeripheralID {
            decoded.lastPowerPeripheralID = pwrPeriphID
            decoded.lastPowerPeripheralName = pwrName
            savedPowerName = pwrName
        }
        
        if let encoded = try? JSONEncoder().encode(decoded) {
            configData = encoded
        }
        NotificationCenter.default.post(name: .settingsDidChange, object: nil)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Sensor Input")
                    .font(.headline)

                // Sensor source picker
                GroupBox(label: Text("Input Source").font(.subheadline)) {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Sensor source:", selection: $sensorSource) {
                            Text("Bluetooth Low Energy (BLE)").tag("ble")
                            Text("ANT+ (USB dongle)").tag("ant+")
                        }
                        .pickerStyle(.radioGroup)
                        .onChange(of: sensorSource) { _, newValue in
                            saveSensorSource(newValue)
                        }
                        .help("Choose how to connect to your heart rate monitor and power meter. BLE uses built-in Bluetooth. ANT+ requires a USB ANT+ dongle.")

                        if sensorSource == "ant+" {
                            Text("ANT+ uses a USB dongle to receive sensor data wirelessly. Most cycling sensors broadcast on both ANT+ and BLE simultaneously.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        if sensorSource == "ble" {
                            Text("BLE uses your Mac's built-in Bluetooth to connect directly to sensors.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(8)
                }

                if sensorSource == "ant+" {

                Divider()

                Text("ANT+ Sensors")
                    .font(.headline)

                // Auto-reconnect settings
                GroupBox(label: Text("Auto-Reconnect").font(.subheadline)) {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Automatically reconnect to last used sensors on app start", isOn: $antPlusAutoReconnect)
                            .toggleStyle(.switch)
                            .onChange(of: antPlusAutoReconnect) { _, newValue in
                                saveANTPlusAutoReconnect(newValue)
                            }
                            .help("When enabled, the app will automatically connect to the ANT+ USB dongle and search for saved sensors when the app starts.")

                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Image(systemName: "heart.fill").foregroundColor(.pink).font(.caption)
                                Text("Saved HR: \(savedANTHRName ?? "None")")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            HStack(spacing: 6) {
                                Image(systemName: "bolt.fill").foregroundColor(.orange).font(.caption)
                                Text("Saved Power: \(savedANTPowerName ?? "None")")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        HStack(spacing: 12) {
                            Button("Save Current Devices") {
                                saveCurrentANTDevices()
                            }
                            .disabled(antPlus.connectedHRName == nil && antPlus.connectedPowerName == nil)
                            .controlSize(.small)

                            if savedANTHRName != nil || savedANTPowerName != nil {
                                Button("Forget Saved Devices") {
                                    clearSavedANTDevices()
                                }
                                .foregroundColor(.red)
                                .controlSize(.small)
                            }
                        }

                        Text("Connect your sensors, then tap \"Save Current Devices\" to remember them for automatic reconnection. Saved device numbers allow faster pairing on next launch.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                }

                Divider()

                // Status + controls
                GroupBox(label: Text("Status").font(.subheadline)) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(antPlusStatusColor)
                                .frame(width: 10, height: 10)
                            Text("ANT+: \(antPlus.state.rawValue)")
                                .font(.caption)
                            Spacer()
                            Text(antPlus.status)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }

                        HStack(spacing: 12) {
                            Button("Start") { antPlus.start() }
                                .disabled(antPlus.state == .connected || antPlus.state == .searching)
                            Button("Stop") { antPlus.stop() }
                                .disabled(antPlus.state == .disconnected)
                        }

                        if antPlus.state == .searching {
                            Divider()
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("Searching for ANT+ sensors…")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                    .padding(8)
                }

                // Live readings
                GroupBox(label: Text("Live Readings").font(.subheadline)) {
                    HStack(spacing: 18) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Heart Rate").font(.caption).foregroundColor(.secondary)
                            Text(antPlus.heartRateBPM.map { "\($0) bpm" } ?? "—")
                                .font(.title3).monospacedDigit()
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Power").font(.caption).foregroundColor(.secondary)
                            Text(antPlus.powerWatts.map { "\($0) W" } ?? "—")
                                .font(.title3).monospacedDigit()
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Cadence").font(.caption).foregroundColor(.secondary)
                            Text(antPlus.cadenceRPM.map { "\($0) rpm" } ?? "—")
                                .font(.title3).monospacedDigit()
                        }
                        Spacer()
                    }
                    .padding(8)
                }

                // HR sensor
                GroupBox(label: Text("Heart Rate Monitor").font(.subheadline)) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "heart.fill").foregroundColor(.pink)
                            Text("Connected: \(antPlus.connectedHRName ?? "None")")
                                .font(.caption)
                            Spacer()
                        }

                        Text("ANT+ heart rate monitors are detected automatically via wildcard search (device type 120, channel period 8070).")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                }

                // Power sensor
                GroupBox(label: Text("Power Meter").font(.subheadline)) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "bolt.fill").foregroundColor(.orange)
                            Text("Connected: \(antPlus.connectedPowerName ?? "None")")
                                .font(.caption)
                            Spacer()
                        }

                        Text("ANT+ power meters are detected automatically via wildcard search (device type 11, channel period 8182). Cadence is derived from crank revolution data.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                }

                Divider()

                // Troubleshooting info
                GroupBox(label: Text("Troubleshooting").font(.subheadline)) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("USB ANT+ Dongle", systemImage: "cable.connector.horizontal")
                            .foregroundColor(.blue)
                        Text("Compatible dongles: Dynastream/Garmin ANTUSB2, ANTUSB-m, CooSpo, CYCPLUS, FITCENT (vendor ID 0x0FCF)")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Label("Supported Sensors", systemImage: "sensor.fill")
                            .foregroundColor(.green)
                        Text("Heart rate monitors (ANT+ device type 120) and cycling power meters (ANT+ device type 11)")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Divider()

                        Text("Tips:")
                            .font(.caption).foregroundColor(.secondary)
                        Text("• Make sure the ANT+ USB dongle is plugged in before starting")
                            .font(.caption).foregroundColor(.secondary)
                        Text("• Close Garmin Express — it can lock the dongle")
                            .font(.caption).foregroundColor(.secondary)
                        Text("• ANT+ sensors broadcast continuously — no pairing needed")
                            .font(.caption).foregroundColor(.secondary)
                        Text("• Keep sensors within 3m of the dongle for best signal")
                            .font(.caption).foregroundColor(.secondary)
                        Text("• Use a USB extension cable if the dongle is far from sensors")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    .padding(8)
                }
                } // end if sensorSource == "ant+"

                if sensorSource == "ble" {
                Divider()

                Text("Bluetooth Sensors")
                    .font(.headline)

                // Auto-reconnect settings
                GroupBox(label: Text("Auto-Reconnect").font(.subheadline)) {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Automatically reconnect to last used sensors on app start", isOn: $autoReconnect)
                            .toggleStyle(.switch)
                            .onChange(of: autoReconnect) { _, newValue in
                                saveBTAutoReconnect(newValue)
                            }

                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Image(systemName: "heart.fill").foregroundColor(.pink).font(.caption)
                                Text("Saved HR: \(savedHRName ?? "None")")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            HStack(spacing: 6) {
                                Image(systemName: "bolt.fill").foregroundColor(.orange).font(.caption)
                                Text("Saved Power: \(savedPowerName ?? "None")")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        HStack(spacing: 12) {
                            Button("Save Current Devices") {
                                saveCurrentDevices()
                            }
                            .disabled(bt.connectedHRName == nil && bt.connectedPowerName == nil)
                            .controlSize(.small)

                            if savedHRName != nil || savedPowerName != nil {
                                Button("Forget Saved Devices") {
                                    clearSavedDevices()
                                }
                                .foregroundColor(.red)
                                .controlSize(.small)
                            }
                        }

                        Text("Connect your sensors, then tap \"Save Current Devices\" to remember them for automatic reconnection.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                }

                Divider()

                // Status + controls
                GroupBox(label: Text("Status").font(.subheadline)) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(bt.btState == .poweredOn ? Color.green : Color.red)
                                .frame(width: 10, height: 10)
                            Text("Bluetooth: \(bt.btState.rawValue)")
                                .font(.caption)
                            Spacer()
                            Text(bt.status)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }

                        HStack(spacing: 12) {
                            Button("Scan") { bt.startScan() }
                                .disabled(bt.btState != .poweredOn)
                            Button("Stop Scan") { bt.stopScan() }
                            Button("Disconnect All") { bt.disconnectAll() }
                        }

                        // Retry status
                        if bt.isRetryingHR || bt.isRetryingPower {
                            Divider()
                            VStack(alignment: .leading, spacing: 4) {
                                if bt.isRetryingHR {
                                    HStack(spacing: 6) {
                                        ProgressView().controlSize(.small)
                                        Text("Retrying HR connection (\(bt.hrRetryCount)/5)…")
                                            .font(.caption)
                                            .foregroundColor(.orange)
                                    }
                                }
                                if bt.isRetryingPower {
                                    HStack(spacing: 6) {
                                        ProgressView().controlSize(.small)
                                        Text("Retrying Power connection (\(bt.powerRetryCount)/5)…")
                                            .font(.caption)
                                            .foregroundColor(.orange)
                                    }
                                }
                            }
                        }
                    }
                    .padding(8)
                }

                // Live readings
                GroupBox(label: Text("Live Readings").font(.subheadline)) {
                    HStack(spacing: 18) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Heart Rate").font(.caption).foregroundColor(.secondary)
                            Text(bt.heartRateBPM.map { "\($0) bpm" } ?? "—")
                                .font(.title3).monospacedDigit()
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Power").font(.caption).foregroundColor(.secondary)
                            Text(bt.powerWatts.map { "\($0) W" } ?? "—")
                                .font(.title3).monospacedDigit()
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Cadence").font(.caption).foregroundColor(.secondary)
                            Text(bt.cadenceRPM.map { "\($0) rpm" } ?? "—")
                                .font(.title3).monospacedDigit()
                        }
                        Spacer()
                    }
                    .padding(8)
                }

                // HR sensor
                GroupBox(label: Text("Heart Rate Monitor").font(.subheadline)) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "heart.fill").foregroundColor(.pink)
                            Text("Connected: \(bt.connectedHRName ?? "None")")
                                .font(.caption)
                            Spacer()
                        }

                        if !bt.hrCandidates.isEmpty {
                            Text("Available devices:")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            ForEach(bt.hrCandidates) { item in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.name).font(.caption)
                                        Text("RSSI \(item.rssi)")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Button("Connect") { bt.connectHR(id: item.id) }
                                        .controlSize(.small)
                                }
                                .padding(.vertical, 2)
                            }
                        } else {
                            Text("No HR devices found. Tap Scan to search.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(8)
                }

                // Power sensor
                GroupBox(label: Text("Power Meter").font(.subheadline)) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "bolt.fill").foregroundColor(.orange)
                            Text("Connected: \(bt.connectedPowerName ?? "None")")
                                .font(.caption)
                            Spacer()
                        }

                        if !bt.powerCandidates.isEmpty {
                            Text("Available devices:")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            ForEach(bt.powerCandidates) { item in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.name).font(.caption)
                                        Text("RSSI \(item.rssi)")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Button("Connect") { bt.connectPower(id: item.id) }
                                        .controlSize(.small)
                                }
                                .padding(.vertical, 2)
                            }
                        } else {
                            Text("No power devices found. Tap Scan to search.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(8)
                }

                Divider()

                // Troubleshooting info
                GroupBox(label: Text("Troubleshooting").font(.subheadline)) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Heart Rate Monitors (BLE)", systemImage: "heart.fill")
                            .foregroundColor(.pink)
                        Text("Standard Bluetooth LE heart rate monitors using service UUID 0x180D")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Label("Power Meters (BLE)", systemImage: "bolt.fill")
                            .foregroundColor(.orange)
                        Text("Cycling power meters using service UUID 0x1818 (e.g., Tacx trainers)")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Divider()

                        Text("Tips:")
                            .font(.caption).foregroundColor(.secondary)
                        Text("• Make sure Bluetooth is enabled in System Settings")
                            .font(.caption).foregroundColor(.secondary)
                        Text("• Sensors should be in pairing mode")
                            .font(.caption).foregroundColor(.secondary)
                        Text("• Try disconnecting and reconnecting")
                            .font(.caption).foregroundColor(.secondary)
                        Text("• Check sensor batteries")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    .padding(8)
                }
                } // end if sensorSource == "ble"
            }
            .padding()
        }
        .onAppear { loadBTSettings() }
    }

    private var antPlusStatusColor: Color {
        switch antPlus.state {
        case .connected:    return .green
        case .searching:    return .orange
        case .disconnected: return .red
        case .error:        return .red
        }
    }
}

// MARK: - Lights Settings Tab

struct LightsSettingsTab: View {
    @EnvironmentObject var lifx: LIFXDiscoveryViewModel
    @EnvironmentObject var store: UserConfigStore
    @AppStorage("lifx_bt_tacx_user_config_v10") private var configData: Data?

    @State private var autoReconnect: Bool = true
    @State private var savedLightDisplayNames: [String] = []

    private var identifyStatusText: String {
        if lifx.isIdentifying {
            if let lightID = lifx.identifyingLightID,
               let index = lifx.identifyingIndex {
                let name = lifx.displayName(for: lifx.lights.first(where: { $0.id == lightID }) ?? LIFXLight(id: lightID, label: "", ip: ""))
                return "Identifying \(index + 1)/\(lifx.lights.count): \(name)"
            }
            return "Identifying lights…"
        }
        return "Blinks each light for 5 seconds one at a time to help identify them."
    }

    private func loadLightsSettings() {
        guard let data = configData,
              let decoded = try? JSONDecoder().decode(PersistedUserConfig.self, from: data) else { return }
        autoReconnect = decoded.lifxAutoReconnect ?? true
        let entries = decoded.savedLightEntries ?? []
        updateSavedLightsDisplay(entries: entries)
    }

    /// Build display strings showing "name (ID)" for each saved light
    private func updateSavedLightsDisplay(entries: [SavedLightEntry]) {
        savedLightDisplayNames = entries.map { entry in
            let name: String
            if let alias = entry.alias, !alias.isEmpty {
                name = alias
            } else if !entry.label.isEmpty {
                name = entry.label
            } else {
                name = "Unnamed Light"
            }
            return "\(name)  (\(entry.id))"
        }
    }

    private func saveLIFXAutoReconnect(_ value: Bool) {
        guard let data = configData,
              var decoded = try? JSONDecoder().decode(PersistedUserConfig.self, from: data) else { return }
        decoded.lifxAutoReconnect = value
        if let encoded = try? JSONEncoder().encode(decoded) {
            configData = encoded
        }
        NotificationCenter.default.post(name: .settingsDidChange, object: nil)
    }

    private func saveCurrentLights() {
        guard let data = configData,
              var decoded = try? JSONDecoder().decode(PersistedUserConfig.self, from: data) else { return }

        // Only save selected lights (not all discovered)
        let selectedLights = lifx.lights.filter { lifx.selectedIDs.contains($0.id) }
        guard !selectedLights.isEmpty else { return }

        decoded.savedLightEntries = selectedLights.map { light in
            let alias = lifx.aliasByID[light.id]?.trimmingCharacters(in: .whitespacesAndNewlines)
            return SavedLightEntry(
                id: light.id,
                ip: light.ip,
                label: light.label,
                alias: (alias?.isEmpty == false) ? alias : nil
            )
        }
        // All saved lights are selected by definition
        decoded.savedSelectedLightIDs = selectedLights.map(\.id)

        if let encoded = try? JSONEncoder().encode(decoded) {
            configData = encoded
        }

        // Update local UI state
        updateSavedLightsDisplay(entries: decoded.savedLightEntries ?? [])

        NotificationCenter.default.post(name: .settingsDidChange, object: nil)
        print("💾 [LIFX] Saved \(selectedLights.count) selected light(s)")
    }

    private func forgetSavedLights() {
        guard let data = configData,
              var decoded = try? JSONDecoder().decode(PersistedUserConfig.self, from: data) else { return }
        decoded.savedLightEntries = nil
        decoded.savedSelectedLightIDs = nil
        if let encoded = try? JSONEncoder().encode(decoded) {
            configData = encoded
        }
        savedLightDisplayNames = []
        NotificationCenter.default.post(name: .settingsDidChange, object: nil)
        print("🗑️ [LIFX] Forgot saved lights")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("LIFX Lights")
                    .font(.headline)

            // Auto-reconnect settings
            GroupBox(label: Text("Auto-Reconnect").font(.subheadline)) {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Automatically reconnect to last used lights on app start", isOn: $autoReconnect)
                        .toggleStyle(.switch)
                        .onChange(of: autoReconnect) { _, newValue in
                            saveLIFXAutoReconnect(newValue)
                        }

                    if savedLightDisplayNames.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "lightbulb.slash")
                                .foregroundColor(.secondary)
                                .font(.caption)
                            Text("No saved lights")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Saved lights (\(savedLightDisplayNames.count)):")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            ForEach(savedLightDisplayNames, id: \.self) { displayName in
                                HStack(spacing: 6) {
                                    Image(systemName: "lightbulb.fill")
                                        .foregroundColor(.yellow)
                                        .font(.caption)
                                    Text(displayName)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }

                    HStack(spacing: 12) {
                        Button("Save Current Lights") {
                            saveCurrentLights()
                        }
                        .disabled(lifx.selectedIDs.isEmpty)
                        .controlSize(.small)

                        if !savedLightDisplayNames.isEmpty {
                            Button("Forget Saved Lights") {
                                forgetSavedLights()
                            }
                            .foregroundColor(.red)
                            .controlSize(.small)
                        }
                    }

                    Text("Select lights using the checkboxes below, then tap \"Save Current Lights\" to remember them for automatic reconnection. Names and IDs are stored together.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(8)
            }

            Divider()

            // Identify lights
            GroupBox(label: Text("Identify").font(.subheadline)) {
                HStack(spacing: 12) {
                    Button(action: {
                        if lifx.isIdentifying {
                            lifx.stopIdentify()
                        } else {
                            lifx.identifyLights()
                        }
                    }) {
                        HStack(spacing: 6) {
                            if lifx.isIdentifying {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Stop Blinking")
                            } else {
                                Image(systemName: "lightbulb.max")
                                Text("Identify Lights")
                            }
                        }
                    }
                    .disabled(lifx.lights.isEmpty)
                    .controlSize(.small)

                    Text(identifyStatusText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(8)
            }

            LIFXPanel(vm: lifx, store: store)
                .frame(minHeight: 420)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Troubleshooting")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text("• LIFX bulbs must be on the same Wi‑Fi network\n• Local Network permission is required\n• UDP port 56700 must be reachable\n• Firewall should allow incoming connections")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            }
        }
        .padding()
        .onAppear {
            store.load()
            lifx.aliasByID = store.aliasesByID
            loadLightsSettings()
        }
    }
}

// MARK: - Zones Settings Tab

struct ZonesSettingsTab: View {
    @EnvironmentObject var store: UserConfigStore
    @EnvironmentObject var auto: AutoColorController
    
    @State private var editableZones: [EditableZone] = []
    @State private var isCustom: Bool = false
    
    struct EditableZone: Identifiable {
        let id: Int
        var name: String
        var label: String
        var lowPercent: Int     // low threshold as integer percent
        var highPercent: Int?   // nil for last zone (no upper bound)
        var paletteIndex: Int
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Zone Configuration")
                    .font(.headline)
                
                Text("Configure the 6 training zones used for light color control. Thresholds are percentages of maxHR (heart rate source) or FTP (power source).")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                // Custom toggle
                HStack {
                    Toggle("Use custom zone thresholds", isOn: $isCustom)
                        .help("Enable to override the default Zwift zone boundaries. Disable to use Zwift defaults.")
                        .onChange(of: isCustom) { _, newValue in
                            if !newValue {
                                store.resetZonesToDefaults()
                                auto.activeZones = store.activeZones
                                loadZonesFromStore()
                            }
                        }
                    Spacer()
                    if isCustom {
                        Button("Reset to Zwift Defaults") {
                            store.resetZonesToDefaults()
                            auto.activeZones = store.activeZones
                            isCustom = false
                            loadZonesFromStore()
                        }
                        .controlSize(.small)
                        .help("Discard custom zones and restore the default 6-zone scheme.")
                    }
                }
                
                // Zone editor
                GroupBox {
                    VStack(spacing: 0) {
                        // Header
                        HStack(spacing: 0) {
                            Text("Zone").frame(width: 50, alignment: .leading)
                            Text("Label").frame(width: 120, alignment: .leading)
                            Text("Low %").frame(width: 70, alignment: .leading)
                            Text("High %").frame(width: 70, alignment: .leading)
                            Text("Color").frame(width: 160, alignment: .leading)
                            Text("Preview").frame(width: 40, alignment: .center)
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 6)
                        
                        Divider()
                        
                        ForEach($editableZones) { $zone in
                            HStack(spacing: 0) {
                                Text(zone.name)
                                    .font(.system(.body, design: .monospaced))
                                    .frame(width: 50, alignment: .leading)
                                
                                if isCustom {
                                    TextField("Label", text: $zone.label)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 110)
                                        .help("Descriptive name for this zone (e.g. Recovery, Tempo).")
                                        .padding(.trailing, 10)
                                        .onSubmit { saveCustomZones() }
                                    
                                    // Low threshold — first zone always starts at 0
                                    if zone.id == 1 {
                                        Text("0%")
                                            .font(.system(.body, design: .monospaced))
                                            .foregroundColor(.secondary)
                                            .frame(width: 60, alignment: .leading)
                                            .padding(.trailing, 10)
                                    } else {
                                        Text("\(zone.lowPercent)%")
                                            .font(.system(.body, design: .monospaced))
                                            .foregroundColor(.secondary)
                                            .frame(width: 60, alignment: .leading)
                                            .padding(.trailing, 10)
                                            .help("Low boundary is set by the previous zone's high boundary.")
                                    }
                                    
                                    // High threshold — last zone has no upper bound
                                    if zone.highPercent != nil {
                                        TextField("", value: $zone.highPercent, format: .number)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 60)
                                            .help("Upper threshold percentage. The next zone starts here.")
                                            .padding(.trailing, 10)
                                            .onChange(of: zone.highPercent) { _, _ in
                                                propagateThresholds()
                                                saveCustomZones()
                                            }
                                    } else {
                                        Text("∞")
                                            .font(.system(.body, design: .monospaced))
                                            .foregroundColor(.secondary)
                                            .frame(width: 60, alignment: .leading)
                                            .padding(.trailing, 10)
                                    }
                                    
                                    // Color picker
                                    Picker("", selection: $zone.paletteIndex) {
                                        ForEach(0..<ZwiftZonePalette.colors.count, id: \.self) { i in
                                            Text(ZwiftZonePalette.colors[i].name).tag(i)
                                        }
                                    }
                                    .frame(width: 150)
                                    .help("LIFX light color for this zone.")
                                    .onChange(of: zone.paletteIndex) { _, _ in
                                        saveCustomZones()
                                    }
                                } else {
                                    // Read-only display
                                    Text(zone.label)
                                        .frame(width: 110, alignment: .leading)
                                        .padding(.trailing, 10)
                                    
                                    Text(zone.id == 1 ? "0%" : "\(zone.lowPercent)%")
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .frame(width: 60, alignment: .leading)
                                        .padding(.trailing, 10)
                                    
                                    Text(zone.highPercent.map { "\($0)%" } ?? "∞")
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .frame(width: 60, alignment: .leading)
                                        .padding(.trailing, 10)
                                    
                                    Text(ZwiftZonePalette.colors[zone.paletteIndex].name)
                                        .frame(width: 150, alignment: .leading)
                                }
                                
                                // Color preview dot
                                Circle()
                                    .fill(ZwiftZonePalette.colors[zone.paletteIndex].preview)
                                    .overlay(Circle().stroke(Color.secondary.opacity(0.4), lineWidth: 1))
                                    .frame(width: 16, height: 16)
                                    .frame(width: 40, alignment: .center)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            
                            if zone.id < 6 { Divider() }
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                // Live preview with current settings
                GroupBox(label: Text("Computed Ranges").font(.subheadline)) {
                    let maxHR = 220 - Calendar.current.dateComponents([.year], from: store.dateOfBirth, to: Date()).year!
                    ZoneLegendView(maxHR: maxHR, ftp: store.ftp, zones: store.activeZones)
                        .padding(4)
                }
                
                if isCustom {
                    Text("Zone boundaries are contiguous — each zone's lower boundary equals the previous zone's upper boundary. Edit the \"High %\" column to adjust where zones transition.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding()
        }
        .onAppear { loadZonesFromStore() }
    }
    
    private func loadZonesFromStore() {
        let zones = store.activeZones
        isCustom = store.customZones != nil
        editableZones = zones.map { z in
            EditableZone(
                id: z.id,
                name: z.name,
                label: z.label,
                lowPercent: Int((z.low * 100).rounded()),
                highPercent: z.high.map { Int(($0 * 100).rounded()) },
                paletteIndex: z.paletteIndex
            )
        }
    }
    
    /// When a zone's high threshold changes, update the next zone's low threshold to match
    private func propagateThresholds() {
        for i in 0..<editableZones.count - 1 {
            if let hi = editableZones[i].highPercent {
                let clamped = max(editableZones[i].lowPercent + 1, hi)
                editableZones[i].highPercent = clamped
                editableZones[i + 1].lowPercent = clamped
            }
        }
    }
    
    private func saveCustomZones() {
        let persisted = editableZones.map { ez in
            PersistedZone(
                id: ez.id,
                name: ez.name,
                label: ez.label,
                low: Double(ez.lowPercent) / 100.0,
                high: ez.highPercent.map { Double($0) / 100.0 },
                paletteIndex: ez.paletteIndex
            )
        }
        store.saveCustomZones(persisted)
        auto.activeZones = store.activeZones
    }
}

struct ZoneColorIndicator: View {
    let color: Color
    let name: String
    
    var body: some View {
        VStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 20, height: 20)
                .overlay(Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 1))
            Text(name)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - About Settings Tab

struct AboutSettingsTab: View {
    var body: some View {
        ScrollView {
            Form {
                Section {
                    VStack(spacing: 16) {
                        Image(nsImage: NSApp.applicationIconImage)
                            .resizable()
                            .frame(width: 60, height: 60)
                        
                        Text("Light Up Kammy's Room")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text(appVersionString)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Divider()
                            .padding(.vertical, 8)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("About")
                                .font(.headline)
                            
                            Text("Control LIFX smart lights based on real-time fitness data from Bluetooth sensors. Map your heart rate or power to training zones using Zwift's color scheme.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Divider()
                            .padding(.vertical, 8)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Features")
                                .font(.headline)
                            
                            Label("BLE and ANT+ heart rate & power sensors", systemImage: "antenna.radiowaves.left.and.right")
                            Label("LIFX LAN protocol control", systemImage: "network")
                            Label("6 training zones", systemImage: "chart.bar.fill")
                            Label("EMA smoothing & moving averages", systemImage: "waveform.path.ecg")
                            Label("Local network only (no cloud)", systemImage: "lock.shield")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text("© 2026")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

private var appVersionString: String {
    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    return "Version \(version) (\(build))"
}
