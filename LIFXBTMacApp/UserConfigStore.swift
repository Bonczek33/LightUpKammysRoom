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
    static let defaultsModulateIntensityWithHR: Bool = false
    static let defaultsMinIntensityPercent: Double = 10.0
    static let defaultsMaxIntensityPercent: Double = 100.0

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
            maxIntensityPercent: maxIntensityPercent
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
        save()
    }
}
