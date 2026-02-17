import SwiftUI
import AppKit

extension Notification.Name {
    static let settingsDidChange = Notification.Name("settingsDidChange")
}

@main
struct LIFXBTMacApp: App {
    @StateObject private var bt = BluetoothSensorsViewModel()
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

        // Menu bar quick controls (macOS 13+)
        if #available(macOS 13.0, *) {
            MenuBarExtra("Lights", systemImage: "lightbulb") {
                MenuBarLightsView()
                    .environmentObject(lifx)
                    .environmentObject(store)
            }
        }

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
                    Label("Bluetooth", systemImage: "antenna.radiowaves.left.and.right")
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
    @AppStorage("lifx_bt_tacx_user_config_v9") private var configData: Data?
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
                                Text("Moving average window for power-based light control.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                HStack {
                                    Text("Smoothing Window:")
                                        .frame(width: 120, alignment: .trailing)
                                    
                                    Slider(value: $powerMovingAverageSeconds, in: 0...5, step: 0.25)
                                        .frame(width: 200)
                                    
                                    Text(String(format: "%.2fs", powerMovingAverageSeconds))
                                        .font(.caption)
                                        .monospacedDigit()
                                        .foregroundColor(.secondary)
                                        .frame(width: 50, alignment: .trailing)
                                }
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("• 0s = No smoothing (instant response)")
                                    Text("• 1-2s = Moderate smoothing (recommended)")
                                    Text("• 3-5s = Heavy smoothing (very noisy data)")
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
                                
                                Text("Note: Raw power values are always displayed; smoothing only affects light color control.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .italic()
                            }
                            .padding(8)
                        }
                        
                        Divider()
                        
                        HStack {
                            Text("App Version:")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("1.0.0")
                                .monospacedDigit()
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
    @AppStorage("lifx_bt_tacx_user_config_v9") private var configData: Data?

    @State private var autoReconnect: Bool = true
    @State private var savedHRName: String? = nil
    @State private var savedPowerName: String? = nil

    private func loadBTSettings() {
        guard let data = configData,
              let decoded = try? JSONDecoder().decode(PersistedUserConfig.self, from: data) else { return }
        autoReconnect = decoded.btAutoReconnect ?? true
        savedHRName = decoded.lastHRPeripheralName
        savedPowerName = decoded.lastPowerPeripheralName
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
            }
            .padding()
        }
        .onAppear { loadBTSettings() }
    }
}

// MARK: - Lights Settings Tab

struct LightsSettingsTab: View {
    @EnvironmentObject var lifx: LIFXDiscoveryViewModel
    @EnvironmentObject var store: UserConfigStore
    @AppStorage("lifx_bt_tacx_user_config_v9") private var configData: Data?

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
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Zones")
                .font(.headline)
            Text("Configure zone colors and thresholds here. (Coming soon)")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding()
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
                            
                            Label("Bluetooth heart rate & power sensors", systemImage: "antenna.radiowaves.left.and.right")
                            Label("LIFX LAN protocol control", systemImage: "network")
                            Label("7 training zones (Zwift colors)", systemImage: "chart.bar.fill")
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
