//
//  UserConfigStore.swift
//  LIFXBTMacApp
//
//  Persists and vends all user configuration except profile data (DOB, FTP,
//  weight), which is managed by ProfileStore / UserProfile.
//
//  applyProfile(_:) pushes a UserProfile's values into memory only — it does
//  NOT call save(). ProfileStore is the single source of truth for ftp/dob/weight.
//
//  Created by Tomasz Bak on 2/16/26.
//

import Foundation
import SwiftUI

struct PersistedUserConfig: Codable {
    var dateOfBirth: Date
    var ftp: Int
    var weightKg: Double
    var autoSourceRaw: String
    var powerMovingAverageSeconds: Double
    var aliasesByID: [String: String]
    var modulateIntensityWithHR: Bool
    var minIntensityPercent: Double
    var maxIntensityPercent: Double
    var modulateIntensityWithPower: Bool?
    var minPowerIntensityPercent: Double?
    var maxPowerIntensityPercent: Double?
    var modulateEffectSpeedWithPower: Bool?     // effect speed scales with power position within zone
    var minEffectSpeedPercent: Double?          // speed at bottom of zone (0–100)
    var maxEffectSpeedPercent: Double?          // speed at top of zone (0–100)
    // Auto effects
    var inactivityEffectEnabled: Bool?          // show random effect after idle
    var reminderEffectEnabled: Bool?            // scheduled reminder effect
    var reminderDays: [Int]?                    // 0=Sun..6=Sat
    var reminderHour: Int?                      // 0–23
    var reminderMinute: Int?                    // 0–59
    var excludedFromAutoEffectsIDs: [String]?   // light IDs excluded from auto effects
    var btAutoReconnect: Bool?
    var lastHRPeripheralID: String?
    var lastHRPeripheralName: String?
    var lastPowerPeripheralID: String?
    var lastPowerPeripheralName: String?
    var lifxAutoReconnect: Bool?
    var savedLightEntries: [SavedLightEntry]?
    var savedSelectedLightIDs: [String]?
    var customZones: [PersistedZone]?
    var sensorInputSource: String?
    var antPlusAutoReconnect: Bool?
    var lastANTHRDeviceNumber: UInt16?
    var lastANTHRDeviceName: String?
    var lastANTPowerDeviceNumber: UInt16?
    var lastANTPowerDeviceName: String?
}

struct PersistedZone: Codable, Hashable {
    var id: Int
    var name: String
    var label: String
    var low: Double
    var high: Double?
    var paletteIndex: Int
    var effect: ZoneEffect = .none   // additive — old saves decode to .none automatically
}

struct SavedLightEntry: Codable, Hashable {
    let id: String
    let ip: String
    let label: String
    let alias: String?
}

@MainActor
final class UserConfigStore: ObservableObject {

    static let defaultsDOB: Date = {
        var c = DateComponents(); c.year = 1989; c.month = 11; c.day = 14
        return Calendar.current.date(from: c) ?? Date(timeIntervalSince1970: 0)
    }()
    static let defaultsFTP = 150
    static let defaultsWeightKg: Double = 50.0
    static let defaultsPowerMovingAverageSeconds: Double = 2.0
    static let defaultsModulateIntensityWithHR: Bool = false
    static let defaultsMinIntensityPercent: Double = 10.0
    static let defaultsMaxIntensityPercent: Double = 100.0
    static let defaultsModulateIntensityWithPower: Bool = true
    static let defaultsMinPowerIntensityPercent: Double = 10.0
    static let defaultsMaxPowerIntensityPercent: Double = 100.0
    static let defaultsBTAutoReconnect: Bool = false
    static let defaultsLIFXAutoReconnect: Bool = false

    private let key = "lifx_bt_tacx_user_config_v10"

    @Published var dateOfBirth: Date = defaultsDOB
    @Published var ftp: Int = defaultsFTP
    @Published var weightKg: Double = defaultsWeightKg
    @Published var autoSourceRaw: String = AutoColorController.Source.off.rawValue
    @Published var powerMovingAverageSeconds: Double = defaultsPowerMovingAverageSeconds
    @Published var aliasesByID: [String: String] = [:]
    @Published var modulateIntensityWithHR: Bool = defaultsModulateIntensityWithHR
    @Published var minIntensityPercent: Double = defaultsMinIntensityPercent
    @Published var maxIntensityPercent: Double = defaultsMaxIntensityPercent
    @Published var modulateIntensityWithPower: Bool = defaultsModulateIntensityWithPower
    @Published var minPowerIntensityPercent: Double = defaultsMinPowerIntensityPercent
    @Published var maxPowerIntensityPercent: Double = defaultsMaxPowerIntensityPercent
    @Published var modulateEffectSpeedWithPower: Bool = false
    @Published var minEffectSpeedPercent: Double = 30.0
    @Published var maxEffectSpeedPercent: Double = 100.0
    // Auto effects
    @Published var inactivityEffectEnabled: Bool = true
    @Published var reminderEffectEnabled: Bool = true
    @Published var reminderDays: [Int] = [0,1,2,3,4,5,6]   // daily by default
    @Published var reminderHour: Int = 6
    @Published var reminderMinute: Int = 0
    @Published var excludedFromAutoEffectsIDs: Set<String> = []
    @Published var btAutoReconnect: Bool = defaultsBTAutoReconnect
    @Published var lastHRPeripheralID: String? = nil
    @Published var lastHRPeripheralName: String? = nil
    @Published var lastPowerPeripheralID: String? = nil
    @Published var lastPowerPeripheralName: String? = nil
    @Published var lifxAutoReconnect: Bool = defaultsLIFXAutoReconnect
    @Published var savedLightEntries: [SavedLightEntry] = []
    @Published var savedSelectedLightIDs: [String] = []
    @Published var customZones: [PersistedZone]? = nil
    @Published var sensorInputSource: String = "ble"
    @Published var antPlusAutoReconnect: Bool = false
    @Published var lastANTHRDeviceNumber: UInt16? = nil
    @Published var lastANTHRDeviceName: String? = nil
    @Published var lastANTPowerDeviceNumber: UInt16? = nil
    @Published var lastANTPowerDeviceName: String? = nil

    // MARK: - Load

    func load() {
        guard let data = UserDefaults.standard.data(forKey: key) else {
            print("💾 [Store] load() — NO DATA for key '\(key)'")
            return
        }
        guard let d = try? JSONDecoder().decode(PersistedUserConfig.self, from: data) else {
            print("💾 [Store] load() — DECODE FAILED")
            return
        }
        print("💾 [Store] load() \(data.count)b src=\(d.autoSourceRaw) modHR=\(d.modulateIntensityWithHR) modPwr=\(d.modulateIntensityWithPower ?? false) ma=\(d.powerMovingAverageSeconds) btAR=\(d.btAutoReconnect ?? true) hrName=\(d.lastHRPeripheralName ?? "nil") pwrName=\(d.lastPowerPeripheralName ?? "nil") lifxAR=\(d.lifxAutoReconnect ?? true) lights=\(d.savedLightEntries?.count ?? 0) sensor=\(d.sensorInputSource ?? "ble") antAR=\(d.antPlusAutoReconnect ?? true) minHR=\(d.minIntensityPercent) maxHR=\(d.maxIntensityPercent) minP=\(d.minPowerIntensityPercent ?? 0) maxP=\(d.maxPowerIntensityPercent ?? 0)")

        dateOfBirth              = d.dateOfBirth
        ftp                      = d.ftp
        weightKg                 = d.weightKg
        autoSourceRaw            = d.autoSourceRaw
        powerMovingAverageSeconds = d.powerMovingAverageSeconds
        aliasesByID              = d.aliasesByID
        modulateIntensityWithHR  = d.modulateIntensityWithHR
        minIntensityPercent      = d.minIntensityPercent
        maxIntensityPercent      = d.maxIntensityPercent
        modulateIntensityWithPower = d.modulateIntensityWithPower  ?? Self.defaultsModulateIntensityWithPower
        minPowerIntensityPercent = d.minPowerIntensityPercent      ?? Self.defaultsMinPowerIntensityPercent
        maxPowerIntensityPercent = d.maxPowerIntensityPercent      ?? Self.defaultsMaxPowerIntensityPercent
        modulateEffectSpeedWithPower = d.modulateEffectSpeedWithPower ?? false
        minEffectSpeedPercent        = d.minEffectSpeedPercent       ?? 30.0
        maxEffectSpeedPercent        = d.maxEffectSpeedPercent       ?? 100.0
        inactivityEffectEnabled = d.inactivityEffectEnabled ?? true
        reminderEffectEnabled   = d.reminderEffectEnabled   ?? true
        reminderDays            = d.reminderDays            ?? [0,1,2,3,4,5,6]
        reminderHour            = d.reminderHour            ?? 6
        reminderMinute          = d.reminderMinute          ?? 0
        excludedFromAutoEffectsIDs = Set(d.excludedFromAutoEffectsIDs ?? [])
        btAutoReconnect          = d.btAutoReconnect               ?? Self.defaultsBTAutoReconnect
        lastHRPeripheralID       = d.lastHRPeripheralID
        lastHRPeripheralName     = d.lastHRPeripheralName
        lastPowerPeripheralID    = d.lastPowerPeripheralID
        lastPowerPeripheralName  = d.lastPowerPeripheralName
        lifxAutoReconnect        = d.lifxAutoReconnect             ?? Self.defaultsLIFXAutoReconnect
        savedLightEntries        = d.savedLightEntries             ?? []
        savedSelectedLightIDs    = d.savedSelectedLightIDs         ?? []
        customZones              = d.customZones
        sensorInputSource        = d.sensorInputSource             ?? "ble"
        antPlusAutoReconnect     = d.antPlusAutoReconnect          ?? true
        lastANTHRDeviceNumber    = d.lastANTHRDeviceNumber
        lastANTHRDeviceName      = d.lastANTHRDeviceName
        lastANTPowerDeviceNumber = d.lastANTPowerDeviceNumber
        lastANTPowerDeviceName   = d.lastANTPowerDeviceName

        // Merge aliases from saved entries so they're available before a scan completes
        for entry in savedLightEntries {
            if let alias = entry.alias, !alias.isEmpty {
                if aliasesByID[entry.id]?.isEmpty ?? true {
                    aliasesByID[entry.id] = alias
                }
            }
        }
    }

    // MARK: - Save

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
            modulateIntensityWithPower: modulateIntensityWithPower,
            minPowerIntensityPercent: minPowerIntensityPercent,
            maxPowerIntensityPercent: maxPowerIntensityPercent,
            modulateEffectSpeedWithPower: modulateEffectSpeedWithPower,
            minEffectSpeedPercent: minEffectSpeedPercent,
            maxEffectSpeedPercent: maxEffectSpeedPercent,
            inactivityEffectEnabled: inactivityEffectEnabled,
            reminderEffectEnabled: reminderEffectEnabled,
            reminderDays: reminderDays,
            reminderHour: reminderHour,
            reminderMinute: reminderMinute,
            excludedFromAutoEffectsIDs: Array(excludedFromAutoEffectsIDs),
            btAutoReconnect: btAutoReconnect,
            lastHRPeripheralID: lastHRPeripheralID,
            lastHRPeripheralName: lastHRPeripheralName,
            lastPowerPeripheralID: lastPowerPeripheralID,
            lastPowerPeripheralName: lastPowerPeripheralName,
            lifxAutoReconnect: lifxAutoReconnect,
            savedLightEntries: savedLightEntries,
            savedSelectedLightIDs: savedSelectedLightIDs,
            customZones: customZones,
            sensorInputSource: sensorInputSource,
            antPlusAutoReconnect: antPlusAutoReconnect,
            lastANTHRDeviceNumber: lastANTHRDeviceNumber,
            lastANTHRDeviceName: lastANTHRDeviceName,
            lastANTPowerDeviceNumber: lastANTPowerDeviceNumber,
            lastANTPowerDeviceName: lastANTPowerDeviceName
        )
        guard let data = try? JSONEncoder().encode(payload) else {
            print("💾 [Store] save() — ENCODE FAILED")
            return
        }
        UserDefaults.standard.set(data, forKey: key)
        UserDefaults.standard.synchronize()
        print("💾 [Store] save() \(data.count)b src=\(autoSourceRaw) modHR=\(modulateIntensityWithHR) modPwr=\(modulateIntensityWithPower) ma=\(powerMovingAverageSeconds) btAR=\(btAutoReconnect) hrName=\(lastHRPeripheralName ?? "nil") pwrName=\(lastPowerPeripheralName ?? "nil") lifxAR=\(lifxAutoReconnect) lights=\(savedLightEntries.count) sensor=\(sensorInputSource) antAR=\(antPlusAutoReconnect) minHR=\(minIntensityPercent) maxHR=\(maxIntensityPercent) minP=\(minPowerIntensityPercent) maxP=\(maxPowerIntensityPercent)")
    }

    // MARK: - Reset

    func resetToDefaults() {
        dateOfBirth              = Self.defaultsDOB
        ftp                      = Self.defaultsFTP
        weightKg                 = Self.defaultsWeightKg
        autoSourceRaw            = AutoColorController.Source.off.rawValue
        powerMovingAverageSeconds = Self.defaultsPowerMovingAverageSeconds
        aliasesByID              = [:]
        modulateIntensityWithHR  = Self.defaultsModulateIntensityWithHR
        minIntensityPercent      = Self.defaultsMinIntensityPercent
        maxIntensityPercent      = Self.defaultsMaxIntensityPercent
        modulateIntensityWithPower = Self.defaultsModulateIntensityWithPower
        minPowerIntensityPercent = Self.defaultsMinPowerIntensityPercent
        maxPowerIntensityPercent = Self.defaultsMaxPowerIntensityPercent
        btAutoReconnect          = Self.defaultsBTAutoReconnect
        lastHRPeripheralID       = nil
        lastHRPeripheralName     = nil
        lastPowerPeripheralID    = nil
        lastPowerPeripheralName  = nil
        lifxAutoReconnect        = Self.defaultsLIFXAutoReconnect
        savedLightEntries        = []
        savedSelectedLightIDs    = []
        customZones              = nil
        sensorInputSource        = "ble"
        antPlusAutoReconnect     = true
        lastANTHRDeviceNumber    = nil
        lastANTHRDeviceName      = nil
        lastANTPowerDeviceNumber = nil
        lastANTPowerDeviceName   = nil
        save()
    }

    // MARK: - Computed

    /// Active zone list — custom if configured, otherwise Zwift defaults.
    var activeZones: [Zone] {
        guard let cz = customZones, cz.count == 6 else { return ZoneDefs.zones }
        return cz.map { Zone(id: $0.id, name: $0.name, low: $0.low, high: $0.high, paletteIndex: $0.paletteIndex, label: $0.label, effect: $0.effect) }
    }

    // MARK: - Profile

    /// Push a UserProfile's physiological values into memory only.
    /// Does NOT call save() — ftp/dob/weight are owned by ProfileStore.
    func applyProfile(_ profile: UserProfile) {
        print("💾 [Store] applyProfile() ftp=\(profile.ftp) kg=\(profile.weightKg)")
        dateOfBirth = profile.dateOfBirth
        ftp         = profile.ftp
        weightKg    = profile.weightKg
    }

    // MARK: - Zones

    func saveCustomZones(_ zones: [PersistedZone]) {
        customZones = zones
        save()
    }

    func resetZonesToDefaults() {
        customZones = nil
        save()
    }
}
