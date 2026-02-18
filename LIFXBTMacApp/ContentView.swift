//
//  ContentView.swift
//  LIFXBTMacApp
//
//  Created by Tomasz Bak on 2/16/26.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var bt: BluetoothSensorsViewModel
    @ObservedObject var lifx: LIFXDiscoveryViewModel
    @ObservedObject var auto: AutoColorController
    @ObservedObject var store: UserConfigStore
    @ObservedObject var charts: ChartsViewModel  // Charts view model

    private let intFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .none
        return f
    }()

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {

                // Compact BT status bar (config moved to Settings)
                BluetoothStatusBar(bt: bt)

                // NOTE: LIFX discovery/selection UI moved to Settings > Lights, and Menu Bar
                AutoColorPanel(
                    auto: auto,
                    store: store,
                    formatter: intFormatter
                )

                Divider()

                ChartsPanel(charts: charts)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .environmentObject(bt)
        .task {
            store.load()

            // Bind controllers/view-models
            auto.bind(lifx: lifx, bt: bt)
            charts.bind(bt: bt)

            applyStore()

            // Remember connected devices for auto-reconnect
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

            // Auto-reconnect to last known BT devices
            if store.btAutoReconnect {
                bt.autoReconnect(
                    hrUUID: store.lastHRPeripheralID,
                    powerUUID: store.lastPowerPeripheralID
                )
            }

            // Auto-reconnect to last known LIFX lights
            if store.lifxAutoReconnect, !store.savedLightEntries.isEmpty {
                lifx.aliasByID = store.aliasesByID
                lifx.autoReconnectLights(
                    savedEntries: store.savedLightEntries,
                    savedSelectedIDs: store.savedSelectedLightIDs
                )
            }

            // Listen for settings changes from Settings window
            NotificationCenter.default.addObserver(
                forName: .settingsDidChange,
                object: nil,
                queue: .main
            ) { _ in
                Task { @MainActor in
                    store.load()
                    applyStore()
                }
            }
        }
        .onChange(of: lifx.aliasByID) { _, newValue in
            store.aliasesByID = newValue
        }
        .onChange(of: store.weightKg) { _, newValue in
            charts.weightKg = newValue
        }
        .onDisappear {
            // Do not stop LIFX / BT / Auto / Charts here:
            // the app may continue running via Menu Bar and Settings.
            saveAll()
        }
    }

    private func applyStore() {
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
    }

    private func saveAll() {
        store.dateOfBirth = auto.dateOfBirth
        store.ftp = auto.ftp
        store.weightKg = auto.weightKg
        store.autoSourceRaw = auto.source.rawValue
        store.powerMovingAverageSeconds = auto.powerMovingAverageSeconds
        store.modulateIntensityWithHR = auto.modulateIntensityWithHR
        store.minIntensityPercent = auto.minIntensityPercent
        store.maxIntensityPercent = auto.maxIntensityPercent
        store.modulateIntensityWithPower = auto.modulateIntensityWithPower
        store.minPowerIntensityPercent = auto.minPowerIntensityPercent
        store.maxPowerIntensityPercent = auto.maxPowerIntensityPercent
        store.aliasesByID = lifx.aliasByID
        store.save()
    }

    private func resetAll() {
        store.resetToDefaults()
        applyStore()
    }
}
