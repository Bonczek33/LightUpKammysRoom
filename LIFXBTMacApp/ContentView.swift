//
//  ContentView.swift
//  LIFXBTMacApp
//
//  Created by Tomasz Bak on 2/16/26.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var bt: BluetoothSensorsViewModel
    @ObservedObject var antPlus: ANTPlusSensorViewModel
    @ObservedObject var lifx: LIFXDiscoveryViewModel
    @ObservedObject var auto: AutoColorController
    @ObservedObject var store: UserConfigStore
    @ObservedObject var charts: ChartsViewModel

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



// Startup master switch (BLE / ANT+ / LIFX)
Toggle("Auto-connect on launch", isOn: $store.connectOnLaunch)
    .toggleStyle(.switch)
    .help("If disabled, the app will not auto-connect sensors or lights on launch. Use the Connect buttons to start/stop connections.")

                AutoColorPanel(
                    auto: auto,
                    store: store,
                    formatter: intFormatter
                )

                Divider()

                ChartsPanel(charts: charts, store: store)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .environmentObject(bt)
        .task {
            store.load()

            // Bind auto color controller and charts to the active sensor source
            bindSensorSource()
            applyStore()

            // Remember connected BT devices for auto-reconnect
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

            // Auto-reconnect to last known BT devices (only in BLE mode)
            if store.connectOnLaunch && store.sensorInputSource == "ble" && store.btAutoReconnect {
                bt.autoReconnect(
                    hrUUID: store.lastHRPeripheralID,
                    powerUUID: store.lastPowerPeripheralID
                )
            }

            // Start ANT+ if that's the selected source and auto-reconnect is enabled
            if store.connectOnLaunch && store.sensorInputSource == "ant+" && store.antPlusAutoReconnect {
                antPlus.autoReconnect(
                    hrDeviceNumber: store.lastANTHRDeviceNumber,
                    powerDeviceNumber: store.lastANTPowerDeviceNumber
                )
            }

            // Remember connected ANT+ devices for auto-reconnect
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

            // Auto-reconnect to last known LIFX lights
            if store.connectOnLaunch && store.lifxAutoReconnect, !store.savedLightEntries.isEmpty {
                lifx.aliasByID = store.aliasesByID
                lifx.autoReconnectLights(
                    savedEntries: store.savedLightEntries,
                    savedSelectedIDs: store.savedSelectedLightIDs
                )
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
                    bindSensorSource()
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
            switchSensorSource(to: newValue)
        }
        .onDisappear {
            saveAll()
        }
    }

    /// Bind the AutoColorController and Charts to the active sensor source
    private func bindSensorSource() {
        let useANT = store.sensorInputSource == "ant+"
        auto.bind(lifx: lifx, bt: bt, antPlus: antPlus, useANTPlus: useANT)
        charts.bind(bt: bt, antPlus: antPlus, useANTPlus: useANT)
    }

    /// Handle switching between BLE and ANT+ at runtime
    private func switchSensorSource(to source: String) {
        if source == "ant+" {
            antPlus.autoReconnect(
                hrDeviceNumber: store.lastANTHRDeviceNumber,
                powerDeviceNumber: store.lastANTPowerDeviceNumber
            )
        } else {
            antPlus.stop()
            if store.btAutoReconnect {
                bt.autoReconnect(
                    hrUUID: store.lastHRPeripheralID,
                    powerUUID: store.lastPowerPeripheralID
                )
            }
        }
        bindSensorSource()
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

