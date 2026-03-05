//
//  ContentView.swift
//  LIFXBTMacApp
//
//  Created by Tomasz Bak on 2/16/26.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var bt:       BluetoothSensorsViewModel
    @ObservedObject var antPlus:  ANTPlusSensorViewModel
    @ObservedObject var lifx:     LIFXDiscoveryViewModel
    @ObservedObject var auto:     AutoColorController
    @ObservedObject var store:    UserConfigStore
    @ObservedObject var charts:   ChartsViewModel
    @ObservedObject var profiles: ProfileStore

    private let intFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .none
        return f
    }()

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {

                // Compact sensor status bar — shows BLE or ANT+ based on setting
                if store.sensorInputSource == "ant+" {
                    ANTPlusStatusBar(antPlus: antPlus, store: store)
                } else {
                    BluetoothStatusBar(bt: bt, store: store)
                }

                Divider()
                
                LIFXStatusBar(vm: lifx, store: store)

                Divider()
                

                AutoColorPanel(
                    auto: auto,
                    store: store,
                    formatter: intFormatter
                )

                Divider()
                Divider()

                ChartsPanel(charts: charts)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .environmentObject(bt)
        .task {
            store.load()

            // Apply the active profile's physiological values on startup.
            if let p = profiles.activeProfile { store.applyProfile(p) }

            // Bind auto color controller and charts to the active sensor source.
            // No auto-reconnect here — user connects manually via the Connect buttons.
            bindSensorSource()
            applyStore()

            // Remember the last connected BLE devices so Connect can restore them.
            bt.onDeviceConnected = { [weak store] id, name, isHR, isPower in
                guard let store else { return }
                if isHR {
                    store.lastHRPeripheralID = id
                    store.lastHRPeripheralName = name
                }
                if isPower {
                    store.lastPowerPeripheralID = id
                    store.lastPowerPeripheralName = name
                }
                store.save()
            }

            // Remember the last connected ANT+ devices so Connect can restore them.
            antPlus.onDeviceConnected = { [weak store] deviceNumber, name, isHR, isPower in
                guard let store else { return }
                if isHR {
                    store.lastANTHRDeviceNumber = deviceNumber
                    store.lastANTHRDeviceName = name
                }
                if isPower {
                    store.lastANTPowerDeviceNumber = deviceNumber
                    store.lastANTPowerDeviceName = name
                }
                store.save()
            }

            // Listen for settings changes
            NotificationCenter.default.addObserver(
                forName: .settingsDidChange,
                object: nil,
                queue: .main
            ) { _ in
                Task { @MainActor in
                    store.load()
                    applyStore()
                    // bindSensorSource() is NOT called here — sensor source changes
                    // are handled by .onChange(of: store.sensorInputSource) below,
                    // which only fires when the source actually switches.
                }
            }

            // When the active profile changes, push values into memory + re-apply to auto.
            // applyProfile no longer calls save() so we call applyStore() explicitly.
            NotificationCenter.default.addObserver(
                forName: .activeProfileDidChange,
                object: nil,
                queue: .main
            ) { note in
                Task { @MainActor in
                    if let profile = note.userInfo?["profile"] as? UserProfile {
                        store.applyProfile(profile)
                        applyStore()
                    }
                }
            }
        }
        .onChange(of: lifx.aliasByID) { _, newValue in
            store.aliasesByID = newValue
        }
        .onChange(of: store.weightKg) { _, newValue in
            charts.weightKg = newValue
        }
        .onChange(of: store.sensorInputSource) { _, newValue in
            // Stop the old source when switching; user must reconnect manually.
            if newValue == "ble" {
                antPlus.stop()
            }
            bindSensorSource()
        }
        .onDisappear {
            saveAll()
        }
    }

    /// Bind the AutoColorController and Charts to the active sensor source.
    private func bindSensorSource() {
        let useANT = store.sensorInputSource == "ant+"
        auto.bind(lifx: lifx, bt: bt, antPlus: antPlus, useANTPlus: useANT)
        charts.bind(bt: bt, antPlus: antPlus, useANTPlus: useANT)
    }

    private func applyStore() {
        print("💾 [ContentView] applyStore() ftp=\(store.ftp) src=\(store.autoSourceRaw) modHR=\(store.modulateIntensityWithHR) modPwr=\(store.modulateIntensityWithPower) ma=\(store.powerMovingAverageSeconds) lights=\(store.savedLightEntries.count) hrID=\(store.lastHRPeripheralID ?? "nil")")
        auto.dateOfBirth = store.dateOfBirth
        auto.ftp = store.ftp
        auto.weightKg = store.weightKg
        auto.source = AutoColorController.Source(rawValue: store.autoSourceRaw) ?? .off
        auto.powerMovingAverageSeconds = store.powerMovingAverageSeconds
        auto.modulateIntensityWithHR = store.modulateIntensityWithHR
        auto.minIntensityPercent = store.minIntensityPercent
        auto.maxIntensityPercent = store.maxIntensityPercent
        auto.modulateIntensityWithPower = store.modulateIntensityWithPower
        auto.minPowerIntensityPercent = store.minPowerIntensityPercent
        auto.maxPowerIntensityPercent = store.maxPowerIntensityPercent
        auto.activeZones = store.activeZones

        lifx.aliasByID = store.aliasesByID
        charts.weightKg = store.weightKg
        charts.ftp = store.ftp
        charts.maxHR = auto.maxHR
        charts.activeZones = store.activeZones
    }

    private func saveAll() {
        // Note: full save (including lights) is done in AppDelegate.applicationWillTerminate.
        // This is a best-effort save for the case where the window is closed without quitting.
        store.autoSourceRaw = auto.source.rawValue
        store.aliasesByID   = lifx.aliasByID
        let selected = lifx.lights.filter { lifx.selectedIDs.contains($0.id) }
        if !selected.isEmpty {
            store.savedLightEntries = selected.map { light in
                let alias = lifx.aliasByID[light.id]?.trimmingCharacters(in: .whitespacesAndNewlines)
                return SavedLightEntry(
                    id: light.id, ip: light.ip, label: light.label,
                    alias: (alias?.isEmpty == false) ? alias : nil
                )
            }
            store.savedSelectedLightIDs = selected.map(\.id)
        }
        store.save()
    }

    private func resetAll() {
        store.resetToDefaults()
        applyStore()
    }
}
