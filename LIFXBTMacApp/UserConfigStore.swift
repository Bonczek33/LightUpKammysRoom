import Foundation
import SwiftUI

struct PersistedUserConfig: Codable {
    var dateOfBirth: Date
    var ftp: Int
    var weightKg: Double
    var autoSourceRaw: String
    var powerMovingAverageSeconds: Double
    var aliasesByID: [String: String]
    
    // Intensity modulation with heart rate
    var modulateIntensityWithHR: Bool
    var minIntensityPercent: Double
    var maxIntensityPercent: Double
    
    // Bluetooth auto-reconnect
    var btAutoReconnect: Bool?            // nil for migration from older configs
    var lastHRPeripheralID: String?       // UUID string of last connected HR device
    var lastHRPeripheralName: String?     // Display name for UI
    var lastPowerPeripheralID: String?    // UUID string of last connected Power device
    var lastPowerPeripheralName: String?  // Display name for UI
}

@MainActor
final class UserConfigStore: ObservableObject {
    static let defaultsDOB: Date = {
        var c = DateComponents()
        c.year = 1989
        c.month = 11
        c.day = 14
        return Calendar.current.date(from: c) ?? Date(timeIntervalSince1970: 0)
    }()

    static let defaultsFTP = 150
    static let defaultsWeightKg: Double = 50.0
    static let defaultsPowerMovingAverageSeconds: Double = 2.0
    static let defaultsModulateIntensityWithHR: Bool = true
    static let defaultsMinIntensityPercent: Double = 10.0
    static let defaultsMaxIntensityPercent: Double = 100.0
    static let defaultsBTAutoReconnect: Bool = true

    // bump key because schema changed
    private let key = "lifx_bt_tacx_user_config_v9"

    @Published var dateOfBirth: Date = defaultsDOB
    @Published var ftp: Int = defaultsFTP
    @Published var weightKg: Double = 50.0
    @Published var autoSourceRaw: String = AutoColorController.Source.off.rawValue
    @Published var powerMovingAverageSeconds: Double = defaultsPowerMovingAverageSeconds
    @Published var aliasesByID: [String: String] = [:]
    
    @Published var modulateIntensityWithHR: Bool = defaultsModulateIntensityWithHR
    @Published var minIntensityPercent: Double = defaultsMinIntensityPercent
    @Published var maxIntensityPercent: Double = defaultsMaxIntensityPercent
    
    @Published var btAutoReconnect: Bool = defaultsBTAutoReconnect
    @Published var lastHRPeripheralID: String? = nil
    @Published var lastHRPeripheralName: String? = nil
    @Published var lastPowerPeripheralID: String? = nil
    @Published var lastPowerPeripheralName: String? = nil

    func load() {
        guard let data = UserDefaults.standard.data(forKey: key) else { return }
        if let decoded = try? JSONDecoder().decode(PersistedUserConfig.self, from: data) {
            dateOfBirth = decoded.dateOfBirth
            ftp = decoded.ftp
            weightKg = decoded.weightKg
            autoSourceRaw = decoded.autoSourceRaw
            powerMovingAverageSeconds = decoded.powerMovingAverageSeconds
            aliasesByID = decoded.aliasesByID
            modulateIntensityWithHR = decoded.modulateIntensityWithHR
            minIntensityPercent = decoded.minIntensityPercent
            maxIntensityPercent = decoded.maxIntensityPercent
            btAutoReconnect = decoded.btAutoReconnect ?? Self.defaultsBTAutoReconnect
            lastHRPeripheralID = decoded.lastHRPeripheralID
            lastHRPeripheralName = decoded.lastHRPeripheralName
            lastPowerPeripheralID = decoded.lastPowerPeripheralID
            lastPowerPeripheralName = decoded.lastPowerPeripheralName
        }
    }

    func save() {
        let payload = PersistedUserConfig(
            dateOfBirth: dateOfBirth,
            ftp: ftp,
            weightKg: weightKg,
            autoSourceRaw: autoSourceRaw,
            powerMovingAverageSeconds: powerMovingAverageSeconds,
            aliasesByID: aliasesByID,
            modulateIntensityWithHR: modulateIntensityWithHR,
            minIntensityPercent: minIntensityPercent,
            maxIntensityPercent: maxIntensityPercent,
            btAutoReconnect: btAutoReconnect,
            lastHRPeripheralID: lastHRPeripheralID,
            lastHRPeripheralName: lastHRPeripheralName,
            lastPowerPeripheralID: lastPowerPeripheralID,
            lastPowerPeripheralName: lastPowerPeripheralName
        )
        if let data = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func resetToDefaults() {
        dateOfBirth = Self.defaultsDOB
        ftp = Self.defaultsFTP
        weightKg = Self.defaultsWeightKg
        autoSourceRaw = AutoColorController.Source.off.rawValue
        powerMovingAverageSeconds = Self.defaultsPowerMovingAverageSeconds
        aliasesByID = [:]
        modulateIntensityWithHR = Self.defaultsModulateIntensityWithHR
        minIntensityPercent = Self.defaultsMinIntensityPercent
        maxIntensityPercent = Self.defaultsMaxIntensityPercent
        btAutoReconnect = Self.defaultsBTAutoReconnect
        lastHRPeripheralID = nil
        lastHRPeripheralName = nil
        lastPowerPeripheralID = nil
        lastPowerPeripheralName = nil
        save()
    }
}
