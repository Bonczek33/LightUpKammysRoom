//
//  UserConfigStore.swift
//  LIFXBTMacApp
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
    
    // Intensity modulation with heart rate
    var modulateIntensityWithHR: Bool
    var minIntensityPercent: Double
    var maxIntensityPercent: Double
    
    // Intensity modulation with power
    var modulateIntensityWithPower: Bool?
    var minPowerIntensityPercent: Double?
    var maxPowerIntensityPercent: Double?
    
    // Bluetooth auto-reconnect
    var btAutoReconnect: Bool?            // nil for migration from older configs
    var lastHRPeripheralID: String?       // UUID string of last connected HR device
    var lastHRPeripheralName: String?     // Display name for UI
    var lastPowerPeripheralID: String?    // UUID string of last connected Power device
    var lastPowerPeripheralName: String?  // Display name for UI
    
    // LIFX auto-reconnect
    var lifxAutoReconnect: Bool?          // nil for migration from older configs
    var savedLightEntries: [SavedLightEntry]?  // Known lights (id, ip, label)
    var savedSelectedLightIDs: [String]?  // Which lights were selected
    
    // Custom zone configuration
    var customZones: [PersistedZone]?
    
    // App startup behavior
    var connectOnLaunch: Bool?  // nil defaults to true (migration)

    // Sensor input source
    var sensorInputSource: String?  // "ble" or "ant+" — nil defaults to "ble"
    var antPlusAutoReconnect: Bool?  // nil defaults to true
    var lastANTHRDeviceNumber: UInt16?
    var lastANTHRDeviceName: String?
    var lastANTPowerDeviceNumber: UInt16?
    var lastANTPowerDeviceName: String?
}

struct PersistedZone: Codable, Hashable {
    var id: Int              // 1..6
    var name: String         // "Z1"
    var label: String        // "Easy", "Endurance", etc.
    var low: Double          // inclusive ratio (0.0 .. )
    var high: Double?        // exclusive ratio, nil => no upper bound
    var paletteIndex: Int    // index into ZwiftZonePalette.colors
}

/// A minimal snapshot of a discovered LIFX light for persistence
struct SavedLightEntry: Codable, Hashable {
    let id: String      // MAC-based hex ID
    let ip: String      // Last known IP
    let label: String   // Device label at time of save
    let alias: String?  // User-assigned name at time of save
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
    static let defaultsModulateIntensityWithPower: Bool = true
    static let defaultsMinPowerIntensityPercent: Double = 10.0
    static let defaultsMaxPowerIntensityPercent: Double = 100.0
    static let defaultsBTAutoReconnect: Bool = true
    static let defaultsLIFXAutoReconnect: Bool = true

    // bump key because schema changed
    private let key = "lifx_bt_tacx_user_config_v10"

    @Published var dateOfBirth: Date = defaultsDOB
    @Published var ftp: Int = defaultsFTP
    @Published var weightKg: Double = 50.0
    @Published var autoSourceRaw: String = AutoColorController.Source.off.rawValue
    @Published var powerMovingAverageSeconds: Double = defaultsPowerMovingAverageSeconds
    @Published var aliasesByID: [String: String] = [:]
    
    @Published var modulateIntensityWithHR: Bool = defaultsModulateIntensityWithHR
    @Published var minIntensityPercent: Double = defaultsMinIntensityPercent
    @Published var maxIntensityPercent: Double = defaultsMaxIntensityPercent
    
    @Published var modulateIntensityWithPower: Bool = defaultsModulateIntensityWithPower
    @Published var minPowerIntensityPercent: Double = defaultsMinPowerIntensityPercent
    @Published var maxPowerIntensityPercent: Double = defaultsMaxPowerIntensityPercent
    
    @Published var btAutoReconnect: Bool = defaultsBTAutoReconnect
    @Published var lastHRPeripheralID: String? = nil
    @Published var lastHRPeripheralName: String? = nil
    @Published var lastPowerPeripheralID: String? = nil
    @Published var lastPowerPeripheralName: String? = nil
    
    @Published var lifxAutoReconnect: Bool = defaultsLIFXAutoReconnect
    @Published var savedLightEntries: [SavedLightEntry] = []
    @Published var savedSelectedLightIDs: [String] = []
    @Published var customZones: [PersistedZone]? = nil  // nil = use defaults
    @Published var sensorInputSource: String = "ble"   // "ble" or "ant+"
    @Published var antPlusAutoReconnect: Bool = true

    /// If false, the app will NOT attempt to auto-connect BLE/ANT+/LIFX on launch.
    @Published var connectOnLaunch: Bool = false
@Published var lastANTHRDeviceNumber: UInt16? = nil
    @Published var lastANTHRDeviceName: String? = nil
    @Published var lastANTPowerDeviceNumber: UInt16? = nil
    @Published var lastANTPowerDeviceName: String? = nil

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
            modulateIntensityWithPower = decoded.modulateIntensityWithPower ?? Self.defaultsModulateIntensityWithPower
            minPowerIntensityPercent = decoded.minPowerIntensityPercent ?? Self.defaultsMinPowerIntensityPercent
            maxPowerIntensityPercent = decoded.maxPowerIntensityPercent ?? Self.defaultsMaxPowerIntensityPercent
            btAutoReconnect = decoded.btAutoReconnect ?? Self.defaultsBTAutoReconnect
            lastHRPeripheralID = decoded.lastHRPeripheralID
            lastHRPeripheralName = decoded.lastHRPeripheralName
            lastPowerPeripheralID = decoded.lastPowerPeripheralID
            lastPowerPeripheralName = decoded.lastPowerPeripheralName
            lifxAutoReconnect = decoded.lifxAutoReconnect ?? Self.defaultsLIFXAutoReconnect
            savedLightEntries = decoded.savedLightEntries ?? []
            savedSelectedLightIDs = decoded.savedSelectedLightIDs ?? []
            customZones = decoded.customZones
            sensorInputSource = decoded.sensorInputSource ?? "ble"
            antPlusAutoReconnect = decoded.antPlusAutoReconnect ?? true
            lastANTHRDeviceNumber = decoded.lastANTHRDeviceNumber
            lastANTHRDeviceName = decoded.lastANTHRDeviceName
            lastANTPowerDeviceNumber = decoded.lastANTPowerDeviceNumber
            lastANTPowerDeviceName = decoded.lastANTPowerDeviceName
            
            // Merge aliases from saved light entries into the canonical aliases dictionary
            // so they're available immediately at startup before any scan completes
            for entry in savedLightEntries {
                if let alias = entry.alias, !alias.isEmpty {
                    if aliasesByID[entry.id]?.isEmpty ?? true {
                        aliasesByID[entry.id] = alias
                    }
                }
            }
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
            modulateIntensityWithPower: modulateIntensityWithPower,
            minPowerIntensityPercent: minPowerIntensityPercent,
            maxPowerIntensityPercent: maxPowerIntensityPercent,
            btAutoReconnect: btAutoReconnect,
            lastHRPeripheralID: lastHRPeripheralID,
            lastHRPeripheralName: lastHRPeripheralName,
            lastPowerPeripheralID: lastPowerPeripheralID,
            lastPowerPeripheralName: lastPowerPeripheralName,
            lifxAutoReconnect: lifxAutoReconnect,
            savedLightEntries: savedLightEntries,
            savedSelectedLightIDs: savedSelectedLightIDs,
            customZones: customZones,
            connectOnLaunch: connectOnLaunch,
            sensorInputSource: sensorInputSource,
            antPlusAutoReconnect: antPlusAutoReconnect,
            lastANTHRDeviceNumber: lastANTHRDeviceNumber,
            lastANTHRDeviceName: lastANTHRDeviceName,
            lastANTPowerDeviceNumber: lastANTPowerDeviceNumber,
            lastANTPowerDeviceName: lastANTPowerDeviceName
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
        modulateIntensityWithPower = Self.defaultsModulateIntensityWithPower
        minPowerIntensityPercent = Self.defaultsMinPowerIntensityPercent
        maxPowerIntensityPercent = Self.defaultsMaxPowerIntensityPercent
        btAutoReconnect = Self.defaultsBTAutoReconnect
        lastHRPeripheralID = nil
        lastHRPeripheralName = nil
        lastPowerPeripheralID = nil
        lastPowerPeripheralName = nil
        lifxAutoReconnect = Self.defaultsLIFXAutoReconnect
        savedLightEntries = []
        savedSelectedLightIDs = []
        customZones = nil
        sensorInputSource = "ble"
        antPlusAutoReconnect = true
        lastANTHRDeviceNumber = nil
        lastANTHRDeviceName = nil
        lastANTPowerDeviceNumber = nil
        lastANTPowerDeviceName = nil
        save()
    }
    
    /// Returns the active zone list — custom if configured, otherwise defaults
    var activeZones: [Zone] {
        guard let cz = customZones, cz.count == 6 else { return ZoneDefs.zones }
        return cz.map { Zone(id: $0.id, name: $0.name, low: $0.low, high: $0.high, paletteIndex: $0.paletteIndex, label: $0.label) }
    }
    
    /// Persist zone edits from the UI
    func saveCustomZones(_ zones: [PersistedZone]) {
        customZones = zones
        save()
    }
    
    /// Reset zones back to Zwift defaults
    func resetZonesToDefaults() {
        customZones = nil
        save()
    }
}

