//
//  BluetoothSettingsTab.swift
//  LIFXBTMacApp
//
//  Created by Tomasz Bak on 2/20/26.
//


//
//  Settings+Sensors.swift
//  LIFXBTMacApp
//
//  Sensors Settings tab — input source selector (BLE vs ANT+), device
//  scanning, save/forget saved devices, live readings, and troubleshooting
//  tips. The tab shows only the section relevant to the active source.
//
//  Owned config fields:
//    sensorInputSource, btAutoReconnect,
//    lastHRPeripheralID/Name, lastPowerPeripheralID/Name,
//    antPlusAutoReconnect,
//    lastANTHRDeviceNumber/Name, lastANTPowerDeviceNumber/Name
//

import SwiftUI

// MARK: - Bluetooth / Sensors Settings Tab

struct BluetoothSettingsTab: View {
    @EnvironmentObject var bt:      BluetoothSensorsViewModel
    @EnvironmentObject var antPlus: ANTPlusSensorViewModel
    @EnvironmentObject var store:   UserConfigStore

    // No local @State mirrors — all controls bind directly to store.*
    // so values are always current regardless of when store.load() ran.

    // MARK: Persistence helpers

    private func saveSensorSource(_ value: String) {
        store.sensorInputSource = value
        store.save()
        NotificationCenter.default.post(name: .settingsDidChange, object: nil)
    }

    private func saveBTAutoReconnect(_ value: Bool) {
        store.btAutoReconnect = value
        store.save()
        NotificationCenter.default.post(name: .settingsDidChange, object: nil)
    }

    private func saveCurrentDevices() {
        if let name = bt.connectedHRName, let id = bt.connectedHRPeripheralID {
            store.lastHRPeripheralID = id; store.lastHRPeripheralName = name
        }
        if let name = bt.connectedPowerName, let id = bt.connectedPowerPeripheralID {
            store.lastPowerPeripheralID = id; store.lastPowerPeripheralName = name
        }
        store.save()
        NotificationCenter.default.post(name: .settingsDidChange, object: nil)
    }

    private func clearSavedDevices() {
        store.lastHRPeripheralID = nil;   store.lastHRPeripheralName = nil
        store.lastPowerPeripheralID = nil; store.lastPowerPeripheralName = nil
        store.save()
        NotificationCenter.default.post(name: .settingsDidChange, object: nil)
    }

    private func saveANTPlusAutoReconnect(_ value: Bool) {
        store.antPlusAutoReconnect = value
        store.save()
        NotificationCenter.default.post(name: .settingsDidChange, object: nil)
    }

    private func saveCurrentANTDevices() {
        if let num = antPlus.connectedHRDeviceNumber, let name = antPlus.connectedHRName {
            store.lastANTHRDeviceNumber = num; store.lastANTHRDeviceName = name
        }
        if let num = antPlus.connectedPowerDeviceNumber, let name = antPlus.connectedPowerName {
            store.lastANTPowerDeviceNumber = num; store.lastANTPowerDeviceName = name
        }
        store.save()
        NotificationCenter.default.post(name: .settingsDidChange, object: nil)
    }

    private func clearSavedANTDevices() {
        store.lastANTHRDeviceNumber = nil;   store.lastANTHRDeviceName = nil
        store.lastANTPowerDeviceNumber = nil; store.lastANTPowerDeviceName = nil
        store.save()
        NotificationCenter.default.post(name: .settingsDidChange, object: nil)
    }



    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Sensor Input").font(.headline)

                // Source selector
                GroupBox(label: Text("Input Source").font(.subheadline)) {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Sensor source:", selection: $store.sensorInputSource) {
                            Text("Bluetooth Low Energy (BLE)").tag("ble")
                            Text("ANT+ (USB dongle)").tag("ant+")
                        }
                        .pickerStyle(.radioGroup)
                        .onChange(of: store.sensorInputSource) { _, newValue in saveSensorSource(newValue) }
                        .help("BLE uses built-in Bluetooth. ANT+ requires a USB ANT+ dongle.")

                        if store.sensorInputSource == "ant+" {
                            Text("ANT+ uses a USB dongle. Most cycling sensors broadcast on both ANT+ and BLE simultaneously.")
                                .font(.caption).foregroundColor(.secondary)
                        } else {
                            Text("BLE uses your Mac's built-in Bluetooth to connect directly to sensors.")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                    .padding(8)
                }

                // ANT+ section
                if store.sensorInputSource == "ant+" {
                    Divider()
                    Text("ANT+ Sensors").font(.headline)
                    antPlusSavedDevicesBox()
                    Divider()
                    antPlusStatusBox()
                    antPlusLiveReadingsBox()
                    antPlusHRBox()
                    antPlusPowerBox()
                    Divider()
                    antPlusTroubleshootingBox()
                }

                // BLE section
                if store.sensorInputSource == "ble" {
                    Divider()
                    Text("Bluetooth Sensors").font(.headline)
                    bleSavedDevicesBox()
                    Divider()
                    bleStatusBox()
                    bleLiveReadingsBox()
                    bleHRBox()
                    blePowerBox()
                    Divider()
                    bleTroubleshootingBox()
                }
            }
            .padding()
        }

    }

    // MARK: ANT+ boxes

    private func antPlusSavedDevicesBox() -> some View {
        GroupBox(label: Text("Auto-Reconnect").font(.subheadline)) {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Automatically reconnect to last used sensors on app start",
                       isOn: $store.antPlusAutoReconnect)
                    .toggleStyle(.switch)
                    .onChange(of: store.antPlusAutoReconnect) { _, v in saveANTPlusAutoReconnect(v) }
                    .help("Connects to the ANT+ dongle and searches for saved sensors on launch.")

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "heart.fill").foregroundColor(.pink).font(.caption)
                        Text("Saved HR: \(store.lastANTHRDeviceName ?? "None")").font(.caption).foregroundColor(.secondary)
                    }
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.fill").foregroundColor(.orange).font(.caption)
                        Text("Saved Power: \(store.lastANTPowerDeviceName ?? "None")").font(.caption).foregroundColor(.secondary)
                    }
                }

                HStack(spacing: 12) {
                    Button("Save Current Devices") { saveCurrentANTDevices() }
                        .disabled(antPlus.connectedHRName == nil && antPlus.connectedPowerName == nil)
                        .controlSize(.small)
                    if store.lastANTHRDeviceName != nil || store.lastANTPowerDeviceName != nil {
                        Button("Forget Saved Devices") { clearSavedANTDevices() }
                            .foregroundColor(.red).controlSize(.small)
                    }
                }

                Text("Connect your sensors, then tap \"Save Current Devices\" to remember them for reconnection.")
                    .font(.caption).foregroundColor(.secondary)
            }
            .padding(8)
        }
    }

    private func antPlusStatusBox() -> some View {
        GroupBox(label: Text("Status").font(.subheadline)) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Circle().fill(antPlusStatusColor).frame(width: 10, height: 10)
                    Text("ANT+: \(antPlus.state.rawValue)").font(.caption)
                    Spacer()
                    Text(antPlus.status).font(.caption).foregroundColor(.secondary).lineLimit(2)
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
                        Text("Searching for ANT+ sensors…").font(.caption).foregroundColor(.orange)
                    }
                }
            }
            .padding(8)
        }
    }

    private func antPlusLiveReadingsBox() -> some View {
        GroupBox(label: Text("Live Readings").font(.subheadline)) {
            HStack(spacing: 18) {
                readingCell(label: "Heart Rate", value: antPlus.heartRateBPM.map { "\($0) bpm" } ?? "—")
                readingCell(label: "Power",      value: antPlus.powerWatts.map   { "\($0) W"   } ?? "—")
                readingCell(label: "Cadence",    value: antPlus.cadenceRPM.map   { "\($0) rpm" } ?? "—")
                Spacer()
            }
            .padding(8)
        }
    }

    private func antPlusHRBox() -> some View {
        GroupBox(label: Text("Heart Rate Monitor").font(.subheadline)) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "heart.fill").foregroundColor(.pink)
                    Text("Connected: \(antPlus.connectedHRName ?? "None")").font(.caption)
                    Spacer()
                }
                Text("ANT+ HR monitors are detected automatically (device type 120, channel period 8070).")
                    .font(.caption).foregroundColor(.secondary)
            }
            .padding(8)
        }
    }

    private func antPlusPowerBox() -> some View {
        GroupBox(label: Text("Power Meter").font(.subheadline)) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "bolt.fill").foregroundColor(.orange)
                    Text("Connected: \(antPlus.connectedPowerName ?? "None")").font(.caption)
                    Spacer()
                }
                Text("ANT+ power meters are detected automatically (device type 11, channel period 8182). Cadence from crank revolution data.")
                    .font(.caption).foregroundColor(.secondary)
            }
            .padding(8)
        }
    }

    private func antPlusTroubleshootingBox() -> some View {
        GroupBox(label: Text("Troubleshooting").font(.subheadline)) {
            VStack(alignment: .leading, spacing: 6) {
                Label("USB ANT+ Dongle", systemImage: "cable.connector.horizontal").foregroundColor(.blue)
                Text("Compatible dongles: Dynastream/Garmin ANTUSB2, ANTUSB-m, CooSpo, CYCPLUS, FITCENT (vendor ID 0x0FCF)")
                    .font(.caption).foregroundColor(.secondary)
                Label("Supported Sensors", systemImage: "sensor.fill").foregroundColor(.green)
                Text("Heart rate monitors (type 120) and cycling power meters (type 11).")
                    .font(.caption).foregroundColor(.secondary)
                Divider()
                tipText("Make sure the ANT+ USB dongle is plugged in before starting")
                tipText("Close Garmin Express — it can lock the dongle")
                tipText("ANT+ sensors broadcast continuously — no pairing needed")
                tipText("Keep sensors within 3m of the dongle for best signal")
                tipText("Use a USB extension cable if the dongle is far from sensors")
            }
            .padding(8)
        }
    }

    // MARK: BLE boxes

    private func bleSavedDevicesBox() -> some View {
        GroupBox(label: Text("Auto-Reconnect").font(.subheadline)) {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Automatically reconnect to last used sensors on app start",
                       isOn: $store.btAutoReconnect)
                    .toggleStyle(.switch)
                    .onChange(of: store.btAutoReconnect) { _, v in saveBTAutoReconnect(v) }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "heart.fill").foregroundColor(.pink).font(.caption)
                        Text("Saved HR: \(store.lastHRPeripheralName ?? "None")").font(.caption).foregroundColor(.secondary)
                    }
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.fill").foregroundColor(.orange).font(.caption)
                        Text("Saved Power: \(store.lastPowerPeripheralName ?? "None")").font(.caption).foregroundColor(.secondary)
                    }
                }

                HStack(spacing: 12) {
                    Button("Save Current Devices") { saveCurrentDevices() }
                        .disabled(bt.connectedHRName == nil && bt.connectedPowerName == nil)
                        .controlSize(.small)
                    if store.lastHRPeripheralName != nil || store.lastPowerPeripheralName != nil {
                        Button("Forget Saved Devices") { clearSavedDevices() }
                            .foregroundColor(.red).controlSize(.small)
                    }
                }

                Text("Connect your sensors, then tap \"Save Current Devices\" to remember them for reconnection.")
                    .font(.caption).foregroundColor(.secondary)
            }
            .padding(8)
        }
    }

    private func bleStatusBox() -> some View {
        GroupBox(label: Text("Status").font(.subheadline)) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Circle().fill(bt.btState == .poweredOn ? Color.green : Color.red).frame(width: 10, height: 10)
                    Text("Bluetooth: \(bt.btState.rawValue)").font(.caption)
                    Spacer()
                    Text(bt.status).font(.caption).foregroundColor(.secondary).lineLimit(2)
                }
                HStack(spacing: 12) {
                    Button("Scan")           { bt.startScan()    }.disabled(bt.btState != .poweredOn)
                    Button("Stop Scan")      { bt.stopScan()     }
                    Button("Disconnect All") { bt.disconnectAll() }
                }
                if bt.isRetryingHR || bt.isRetryingPower {
                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        if bt.isRetryingHR {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("Retrying HR connection (\(bt.hrRetryCount)/5)…")
                                    .font(.caption).foregroundColor(.orange)
                            }
                        }
                        if bt.isRetryingPower {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("Retrying Power connection (\(bt.powerRetryCount)/5)…")
                                    .font(.caption).foregroundColor(.orange)
                            }
                        }
                    }
                }
            }
            .padding(8)
        }
    }

    private func bleLiveReadingsBox() -> some View {
        GroupBox(label: Text("Live Readings").font(.subheadline)) {
            HStack(spacing: 18) {
                readingCell(label: "Heart Rate", value: bt.heartRateBPM.map { "\($0) bpm" } ?? "—")
                readingCell(label: "Power",      value: bt.powerWatts.map   { "\($0) W"   } ?? "—")
                readingCell(label: "Cadence",    value: bt.cadenceRPM.map   { "\($0) rpm" } ?? "—")
                Spacer()
            }
            .padding(8)
        }
    }

    private func bleHRBox() -> some View {
        GroupBox(label: Text("Heart Rate Monitor").font(.subheadline)) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "heart.fill").foregroundColor(.pink)
                    Text("Connected: \(bt.connectedHRName ?? "None")").font(.caption)
                    Spacer()
                }
                if !bt.hrCandidates.isEmpty {
                    Text("Available devices:").font(.caption).foregroundColor(.secondary)
                    ForEach(bt.hrCandidates) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name).font(.caption)
                                Text("RSSI \(item.rssi)").font(.caption2).foregroundColor(.secondary)
                            }
                            Spacer()
                            Button("Connect") { bt.connectHR(id: item.id) }.controlSize(.small)
                        }
                        .padding(.vertical, 2)
                    }
                } else {
                    Text("No HR devices found. Tap Scan to search.").font(.caption).foregroundColor(.secondary)
                }
            }
            .padding(8)
        }
    }

    private func blePowerBox() -> some View {
        GroupBox(label: Text("Power Meter").font(.subheadline)) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "bolt.fill").foregroundColor(.orange)
                    Text("Connected: \(bt.connectedPowerName ?? "None")").font(.caption)
                    Spacer()
                }
                if !bt.powerCandidates.isEmpty {
                    Text("Available devices:").font(.caption).foregroundColor(.secondary)
                    ForEach(bt.powerCandidates) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name).font(.caption)
                                Text("RSSI \(item.rssi)").font(.caption2).foregroundColor(.secondary)
                            }
                            Spacer()
                            Button("Connect") { bt.connectPower(id: item.id) }.controlSize(.small)
                        }
                        .padding(.vertical, 2)
                    }
                } else {
                    Text("No power devices found. Tap Scan to search.").font(.caption).foregroundColor(.secondary)
                }
            }
            .padding(8)
        }
    }

    private func bleTroubleshootingBox() -> some View {
        GroupBox(label: Text("Troubleshooting").font(.subheadline)) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Heart Rate Monitors (BLE)", systemImage: "heart.fill").foregroundColor(.pink)
                Text("Standard BLE HR monitors using service UUID 0x180D.")
                    .font(.caption).foregroundColor(.secondary)
                Label("Power Meters (BLE)", systemImage: "bolt.fill").foregroundColor(.orange)
                Text("Cycling power meters using service UUID 0x1818 (e.g., Tacx trainers).")
                    .font(.caption).foregroundColor(.secondary)
                Divider()
                tipText("Make sure Bluetooth is enabled in System Settings")
                tipText("Sensors should be in pairing mode")
                tipText("Try disconnecting and reconnecting")
                tipText("Check sensor batteries")
            }
            .padding(8)
        }
    }

    // MARK: Shared helpers

    private func readingCell(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundColor(.secondary)
            Text(value).font(.title3).monospacedDigit()
        }
    }

    private func tipText(_ text: String) -> some View {
        Text("• \(text)").font(.caption).foregroundColor(.secondary)
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
