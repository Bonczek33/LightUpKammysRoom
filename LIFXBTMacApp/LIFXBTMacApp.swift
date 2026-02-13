import SwiftUI

extension Notification.Name {
    static let settingsDidChange = Notification.Name("settingsDidChange")
}

@main
struct LIFXBTMacApp: App {
    var body: some Scene {
        WindowGroup("Light Up Kammy's Room") {
            ContentView()
        }
        // REMOVED: Duplicate Settings menu command
        // macOS automatically creates Settings menu when Settings scene exists
        
        #if swift(>=5.9)
        Settings {
            SettingsView()
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 600, height: 500)
        #else
        Settings {
            SettingsView()
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
        powerMovingAverageSeconds = decoded.powerMovingAverageSeconds
    }
    
    private func saveSettings() {
        // Create config with current values
        let config = PersistedUserConfig(
            dateOfBirth: dateOfBirth,
            ftp: max(50, min(500, ftp)),
            weightKg: max(30.0, min(200.0, weightKg)),
            autoSourceRaw: "Off", // Will be loaded from main app
            powerMovingAverageSeconds: max(0.0, min(10.0, powerMovingAverageSeconds)),
            aliasesByID: [:], // Will be merged from main app
            modulateIntensityWithHR: modulateIntensityWithHR,
            minIntensityPercent: max(0.0, min(100.0, minIntensityPercent)),
            maxIntensityPercent: max(0.0, min(100.0, maxIntensityPercent))
        )
        
        if let encoded = try? JSONEncoder().encode(config) {
            configData = encoded
        }
        
        // Notify main app to reload settings
        NotificationCenter.default.post(name: .settingsDidChange, object: nil)
    }
    
    // FIXED: Proper reset implementation
    private func resetToDefaults() {
        // Reset all state variables to defaults
        dateOfBirth = UserConfigStore.defaultsDOB
        ftp = UserConfigStore.defaultsFTP
        weightKg = UserConfigStore.defaultsWeightKg
        modulateIntensityWithHR = UserConfigStore.defaultsModulateIntensityWithHR
        minIntensityPercent = UserConfigStore.defaultsMinIntensityPercent
        maxIntensityPercent = UserConfigStore.defaultsMaxIntensityPercent
        powerMovingAverageSeconds = UserConfigStore.defaultsPowerMovingAverageSeconds
        
        // Create default config
        let config = PersistedUserConfig(
            dateOfBirth: UserConfigStore.defaultsDOB,
            ftp: UserConfigStore.defaultsFTP,
            weightKg: UserConfigStore.defaultsWeightKg,
            autoSourceRaw: "Off",
            powerMovingAverageSeconds: UserConfigStore.defaultsPowerMovingAverageSeconds,
            aliasesByID: [:],
            modulateIntensityWithHR: UserConfigStore.defaultsModulateIntensityWithHR,
            minIntensityPercent: UserConfigStore.defaultsMinIntensityPercent,
            maxIntensityPercent: UserConfigStore.defaultsMaxIntensityPercent
        )
        
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
                                    
                                    TextField("150", value: $ftp, formatter: intFormatter)
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
                                    
                                    TextField("50.0", value: $weightKg, formatter: doubleFormatter)
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
                        
                        // Intensity Modulation Settings (for Power mode)
                        GroupBox(label: Text("Intensity Modulation").font(.subheadline)) {
                            VStack(alignment: .leading, spacing: 12) {
                                Toggle("Modulate intensity with heart rate when using power", isOn: $modulateIntensityWithHR)
                                    .toggleStyle(.switch)
                                
                                Text("When enabled and using Power mode, light brightness changes based on your heart rate position within the current power zone.")
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
                                        
                                        Text("Light brightness will vary between \(Int(minIntensityPercent))% and \(Int(maxIntensityPercent))% based on your heart rate within each power zone.")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .italic()
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
                        
                        Divider()
                        
                        HStack {
                            Spacer()
                            
                            Button("Save Settings") {
                                saveSettings()
                            }
                            .keyboardShortcut("s", modifiers: .command)
                        }
                    }
                    .padding()
                }
            }
            .onAppear {
                loadSettings()
            }
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

// MARK: - Bluetooth Settings Tab

struct BluetoothSettingsTab: View {
    var body: some View {
        ScrollView {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Bluetooth Settings")
                            .font(.headline)
                        
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Supported Devices")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
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
                        }
                        
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Troubleshooting")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            Text("• Make sure Bluetooth is enabled in System Settings")
                            Text("• Sensors should be in pairing mode")
                            Text("• Try disconnecting and reconnecting")
                            Text("• Check sensor batteries")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                    .padding()
                }
            }
        }
    }
}

// MARK: - Lights Settings Tab

struct LightsSettingsTab: View {
    var body: some View {
        ScrollView {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("LIFX Settings")
                            .font(.headline)
                        
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Network Requirements")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            Text("• LIFX bulbs must be on the same WiFi network")
                            Text("• Local network access permission required (macOS 15+)")
                            Text("• UDP port 56700 must be accessible")
                            Text("• Firewall should allow incoming connections")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Troubleshooting")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            Text("If lights aren't discovered:")
                            Text("• Check System Settings → Privacy & Security → Local Network")
                            Text("• Ensure this app has permission enabled")
                            Text("• Check your WiFi network allows device discovery")
                            Text("• Try restarting the LIFX bulbs")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                    .padding()
                }
            }
        }
    }
}

// MARK: - Zones Settings Tab

struct ZonesSettingsTab: View {
    var body: some View {
        ScrollView {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Training Zones")
                            .font(.headline)
                        
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Zwift Color Scheme")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            HStack(spacing: 12) {
                                ZoneColorIndicator(color: .gray, name: "Z1")
                                ZoneColorIndicator(color: .blue, name: "Z2")
                                ZoneColorIndicator(color: .green, name: "Z3")
                                ZoneColorIndicator(color: .yellow, name: "Z4")
                                ZoneColorIndicator(color: .orange, name: "Z5")
                                ZoneColorIndicator(color: .red, name: "Z6")
                                ZoneColorIndicator(color: .purple, name: "Z7")
                            }
                        }
                        
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Zone Ranges")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            Text("Z1: 0-60% (Easy) - Grey")
                            Text("Z2: 60-70% (Endurance) - Blue")
                            Text("Z3: 70-80% (Tempo) - Green")
                            Text("Z4: 80-90% (Threshold) - Yellow")
                            Text("Z5: 90-100% (VO2 Max) - Orange")
                            Text("Z6: 100-110% (Anaerobic) - Red")
                            Text("Z7: 110%+ (Sprint) - Purple")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        
                        Divider()
                        
                        Text("Zones are calculated based on your FTP (power) or max heart rate (age-based formula: 220 - age).")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                }
            }
        }
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
                        Image(systemName: "lightbulb.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.yellow)
                        
                        Text("Light Up Kammy's Room")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("Version 1.0.0")
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
