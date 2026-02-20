//
//  Panels.swift
//  LIFXBTMacApp
//
//  Created by Tomasz Bak on 2/16/26.
//

import SwiftUI

// MARK: - Bluetooth Status Bar

struct BluetoothStatusBar: View {
    @ObservedObject var bt: BluetoothSensorsViewModel
    @ObservedObject var store: UserConfigStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 18) {
                Label("Bluetooth", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.headline)
                    .help("Bluetooth Low Energy sensor connections. Configure in Settings > Bluetooth.")

                Circle()
                    .fill(bt.btState == .poweredOn ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                    .help(bt.btState == .poweredOn ? "Bluetooth is active and ready." : "Bluetooth is not available. Check System Settings.")

                StatPill(title: "Heart Rate", value: bt.heartRateBPM.map { "\($0) bpm" } ?? "—")
                    .help("Live heart rate from connected BLE heart rate monitor.")
                StatPill(title: "Power", value: bt.powerWatts.map { "\($0) W" } ?? "—")
                    .help("Instantaneous power from connected BLE power meter / smart trainer.")
                StatPill(title: "Cadence", value: bt.cadenceRPM.map { "\($0) rpm" } ?? "—")
                    .help("Pedaling cadence derived from crank revolution data.")

                if bt.isRetryingHR || bt.isRetryingPower {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.small)
                        Text(retryLabel)
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    .help("Automatically retrying connection with exponential backoff.")
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("HR: \(bt.connectedHRName ?? "—")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Power: \(bt.connectedPowerName ?? "—")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .help("Currently connected sensor names.")

                Text(bt.status)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 160, alignment: .trailing)
                    .help("Current Bluetooth connection status.")
            }

            // Connect / Disconnect row
            HStack(spacing: 8) {
                ConnectSensorsButton(bt: bt, store: store)
                Spacer()
            }
        }
    }

    private var retryLabel: String {
        var parts: [String] = []
        if bt.isRetryingHR { parts.append("HR \(bt.hrRetryCount)/5") }
        if bt.isRetryingPower { parts.append("Pwr \(bt.powerRetryCount)/5") }
        return "Retrying " + parts.joined(separator: ", ")
    }
}

// MARK: - Connect Sensors Button (BLE)

/// Displays a single "Connect" button that reconnects to last-known BLE sensors.
/// Shows which devices will be targeted as a tooltip / subtitle.
private struct ConnectSensorsButton: View {
    @ObservedObject var bt: BluetoothSensorsViewModel
    @ObservedObject var store: UserConfigStore

    private var isConnected: Bool {
        bt.connectedHRName != nil || bt.connectedPowerName != nil
    }

    private var isConnecting: Bool {
        bt.isRetryingHR || bt.isRetryingPower
    }

    private var hasLastKnown: Bool {
        store.lastHRPeripheralID != nil || store.lastPowerPeripheralID != nil
    }

    private var lastKnownSummary: String {
        var parts: [String] = []
        if let name = store.lastHRPeripheralName { parts.append("HR: \(name)") }
        else if store.lastHRPeripheralID != nil { parts.append("HR: saved device") }
        if let name = store.lastPowerPeripheralName { parts.append("Power: \(name)") }
        else if store.lastPowerPeripheralID != nil { parts.append("Power: saved device") }
        return parts.isEmpty ? "No saved sensors" : parts.joined(separator: "  ·  ")
    }

    var body: some View {
        HStack(spacing: 10) {
            Button {
                bt.autoReconnect(
                    hrUUID: store.lastHRPeripheralID,
                    powerUUID: store.lastPowerPeripheralID
                )
            } label: {
                Label(isConnecting ? "Connecting…" : "Connect Sensors", systemImage: "cable.connector")
            }
            .disabled(bt.btState != .poweredOn || isConnecting || isConnected || !hasLastKnown)
            .help(hasLastKnown
                  ? "Connect to last-used BLE sensors: \(lastKnownSummary)"
                  : "No saved sensors. Connect via Settings > Bluetooth first.")

            if isConnected || isConnecting {
                Button {
                    bt.disconnectAll()
                } label: {
                    Label("Disconnect", systemImage: "cable.connector.slash")
                }
                .help("Disconnect all BLE sensors.")
            }

            Text(lastKnownSummary)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - ANT+ Status Bar

struct ANTPlusStatusBar: View {
    @ObservedObject var antPlus: ANTPlusSensorViewModel
    @ObservedObject var store: UserConfigStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 18) {
                Label("ANT+", systemImage: "cable.connector.horizontal")
                    .font(.headline)
                    .help("ANT+ USB dongle sensor connections. Configure in Settings > Bluetooth.")

                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                    .help(antPlus.state.rawValue)

                StatPill(title: "Heart Rate", value: antPlus.heartRateBPM.map { "\($0) bpm" } ?? "—")
                    .help("Live heart rate from ANT+ heart rate monitor.")
                StatPill(title: "Power", value: antPlus.powerWatts.map { "\($0) W" } ?? "—")
                    .help("Instantaneous power from ANT+ power meter / smart trainer.")
                StatPill(title: "Cadence", value: antPlus.cadenceRPM.map { "\($0) rpm" } ?? "—")
                    .help("Pedaling cadence from ANT+ power meter crank data.")

                if antPlus.state == .searching {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.small)
                        Text("Searching…")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("HR: \(antPlus.connectedHRName ?? "—")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Power: \(antPlus.connectedPowerName ?? "—")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text(antPlus.status)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 200, alignment: .trailing)
            }

            // Connect / Disconnect row
            HStack(spacing: 8) {
                ConnectANTPlusButton(antPlus: antPlus, store: store)
                Spacer()
            }
        }
    }

    private var statusColor: Color {
        switch antPlus.state {
        case .connected:    return .green
        case .searching:    return .orange
        case .disconnected: return .red
        case .error:        return .red
        }
    }
}

// MARK: - Connect ANT+ Button

private struct ConnectANTPlusButton: View {
    @ObservedObject var antPlus: ANTPlusSensorViewModel
    @ObservedObject var store: UserConfigStore

    private var isConnected: Bool { antPlus.state == .connected }
    private var isSearching: Bool { antPlus.state == .searching }

    private var hasLastKnown: Bool {
        store.lastANTHRDeviceNumber != nil || store.lastANTPowerDeviceNumber != nil
    }

    private var lastKnownSummary: String {
        var parts: [String] = []
        if let name = store.lastANTHRDeviceName { parts.append("HR: \(name)") }
        else if let num = store.lastANTHRDeviceNumber { parts.append("HR: #\(num)") }
        if let name = store.lastANTPowerDeviceName { parts.append("Power: \(name)") }
        else if let num = store.lastANTPowerDeviceNumber { parts.append("Power: #\(num)") }
        return parts.isEmpty ? "No saved sensors" : parts.joined(separator: "  ·  ")
    }

    var body: some View {
        HStack(spacing: 10) {
            Button {
                antPlus.autoReconnect(
                    hrDeviceNumber: store.lastANTHRDeviceNumber,
                    powerDeviceNumber: store.lastANTPowerDeviceNumber
                )
            } label: {
                Label(isSearching ? "Searching…" : "Connect Sensors", systemImage: "cable.connector")
            }
            .disabled(isSearching || isConnected || !hasLastKnown)
            .help(hasLastKnown
                  ? "Connect to last-used ANT+ sensors: \(lastKnownSummary)"
                  : "No saved sensors. Connect via Settings > Bluetooth first.")

            if isConnected || isSearching {
                Button {
                    antPlus.stop()
                } label: {
                    Label("Disconnect", systemImage: "cable.connector.slash")
                }
                .help("Stop ANT+ and disconnect all sensors.")
            }

            Text(lastKnownSummary)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Auto Color

struct AutoColorPanel: View {
    @ObservedObject var auto: AutoColorController
    @ObservedObject var store: UserConfigStore
    let formatter: NumberFormatter

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text("Auto Color").font(.headline)
                    .help("Automatically changes light color based on your training zone. Select a source to enable.")

                Picker("Source", selection: $auto.source) {
                    ForEach(AutoColorController.Source.allCases) { s in
                        Text(s.rawValue).tag(s)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 560)
                .help("Off = manual control. Heart Rate = zones based on %maxHR. Power = zones based on %FTP.")

                Spacer()

                Text(auto.lastInputText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 8)
                    .help("Current sensor reading and the reference value used for zone calculation.")
            }

            HStack(spacing: 18) {
                HStack(spacing: 10) {
                    Text("Age \(auto.ageYears)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .help("Calculated from your date of birth. Change in Settings > General.")

                    Text("MaxHR \(auto.maxHR)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .help("Estimated maximum heart rate (220 − age). Used to calculate HR training zones.")

                    Text("FTP \(auto.ftp)W")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .help("Functional Threshold Power. Change in Settings > General.")

                    Text("Weight \(String(format: "%.1f", auto.weightKg))kg")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .help("Body weight used for W/kg calculation. Change in Settings > General.")
                }

                Spacer()

                AppliedColorIndicator(auto: auto)

                Text(auto.lastZoneID.map { "Zone \($0)/7" } ?? "Zone —")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .help("Current training zone (1–6). Zone color is applied to all selected LIFX lights.")
            }

            ZoneLegendView(maxHR: auto.maxHR, ftp: auto.ftp, zones: store.activeZones)
        }
        .onChange(of: auto.source) { _, newValue in
            store.autoSourceRaw = newValue.rawValue
        }
    }
}

// MARK: - Applied Color Indicator

struct AppliedColorIndicator: View {
    @ObservedObject var auto: AutoColorController

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 4)
                .fill(colorForCurrentState(paletteIndex: auto.appliedPaletteIndex, intensityPercent: auto.appliedIntensityPercent))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.secondary.opacity(0.4), lineWidth: 1)
                )
                .frame(width: 28, height: 16)
                .shadow(color: colorForCurrentState(paletteIndex: auto.appliedPaletteIndex, intensityPercent: auto.appliedIntensityPercent).opacity(0.5), radius: 4)

            if let intensity = auto.appliedIntensityPercent {
                Text("\(Int(intensity.rounded()))%")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundColor(.secondary)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: auto.appliedPaletteIndex ?? -1)
        .animation(.easeInOut(duration: 0.3), value: auto.appliedIntensityPercent ?? -1)
        .help(auto.appliedIntensityPercent != nil
              ? "Current zone color and brightness being sent to selected lights."
              : "Shows the zone color being applied. No intensity modulation active.")
    }

    private func colorForCurrentState(paletteIndex: Int?, intensityPercent: Double?) -> Color {
        guard let idx = paletteIndex else { return .gray.opacity(0.3) }
        let safeIdx = max(0, min(ZwiftZonePalette.colors.count - 1, idx))
        let p = ZwiftZonePalette.colors[safeIdx]
        let brightness = (intensityPercent ?? 100.0) / 100.0
        if p.satU16 == 0 {
            return Color(hue: 0, saturation: 0, brightness: max(0.15, brightness * 0.7))
        }
        return Color(
            hue: Double(p.hueU16) / 65535.0,
            saturation: Double(p.satU16) / 65535.0,
            brightness: max(0.15, brightness * 0.9)
        )
    }
}

// MARK: - Zone Legend

struct ZoneLegendView: View {
    let maxHR: Int
    let ftp: Int
    var zones: [Zone] = ZoneDefs.zones

    private func pct(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }

    private func bpmRange(_ z: Zone) -> String {
        let lo = Int((z.low * Double(maxHR)).rounded(.toNearestOrAwayFromZero))
        let hi = z.high.map { Int(($0 * Double(maxHR)).rounded(.toNearestOrAwayFromZero)) - 1 }
        if let hi { return "\(lo)–\(max(hi, lo))" }
        return "≥\(lo)"
    }

    private func wattRange(_ z: Zone) -> String {
        let ftpSafe = max(1, ftp)
        let lo = Int((z.low * Double(ftpSafe)).rounded(.toNearestOrAwayFromZero))
        let hi = z.high.map { Int(($0 * Double(ftpSafe)).rounded(.toNearestOrAwayFromZero)) - 1 }
        if let hi { return "\(lo)–\(max(hi, lo))" }
        return "≥\(lo)"
    }

    private let cols: [GridItem] = [
        GridItem(.fixed(54), alignment: .leading),
        GridItem(.fixed(90), alignment: .leading),
        GridItem(.fixed(110), alignment: .leading),
        GridItem(.fixed(120), alignment: .leading),
        GridItem(.flexible(minimum: 140), alignment: .leading)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Zone palette + ranges (applies to selected lights)")
                .font(.caption)
                .foregroundColor(.secondary)
                .help("Training zones follow a 6-zone color scheme. Thresholds are based on your maxHR and FTP settings.")

            HStack(spacing: 10) {
                ForEach(zones) { z in
                    let c = ZwiftZonePalette.colors[z.paletteIndex].preview
                    VStack(spacing: 4) {
                        Circle().fill(c).frame(width: 14, height: 14)
                            .overlay(Circle().stroke(Color.secondary.opacity(0.4), lineWidth: 1))
                        Text(z.name).font(.caption2).foregroundColor(.secondary)
                    }
                    .frame(width: 44)
                    .help("\(z.name) — \(z.label): \(Int(z.low * 100))%\(z.high.map { "–\(Int($0 * 100))%" } ?? "+")")
                }
                Spacer()
            }

            LazyVGrid(columns: cols, alignment: .leading, spacing: 6) {
                Text("Zone").font(.caption).foregroundColor(.secondary)
                Text("%").font(.caption).foregroundColor(.secondary)
                Text("HR (bpm)").font(.caption).foregroundColor(.secondary)
                Text("Power (W)").font(.caption).foregroundColor(.secondary)
                Text("Color").font(.caption).foregroundColor(.secondary)

                ForEach(zones) { z in
                    let pLo = pct(z.low)
                    let pHi = z.high.map { pct($0) } ?? "∞"
                    let colorName = ZwiftZonePalette.colors[z.paletteIndex].name

                    Text(z.name).font(.caption).monospacedDigit()
                    Text("\(pLo)–\(pHi)").font(.caption).monospacedDigit()
                    Text(bpmRange(z)).font(.caption).monospacedDigit()
                    Text(wattRange(z)).font(.caption).monospacedDigit()
                    Text(colorName).font(.caption).foregroundColor(.secondary)
                }
            }
            .padding(10)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}

// MARK: - LIFX Panel

struct LIFXPanel: View {
    @ObservedObject var vm: LIFXDiscoveryViewModel
    @ObservedObject var store: UserConfigStore

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                // Connect to last-known lights button
                ConnectLightsButton(vm: vm, store: store)

                Divider().frame(height: 20)

                // Manual scan for new lights
                Button("Scan for New Lights") { vm.scan() }
                    .help("Broadcast a UDP discovery packet to find all LIFX lights on your local network.")

                Text(vm.status).foregroundColor(.secondary)
                Spacer()
                Button("Select All") { vm.selectAll() }.disabled(vm.lights.isEmpty)
                    .help("Select all discovered lights for auto color control.")
                Button("Select None") { vm.selectNone() }.disabled(vm.selectedIDs.isEmpty)
                    .help("Deselect all lights.")
            }

            HStack(spacing: 12) {
                Button("Turn ON Selected") { vm.setPowerForSelected(true) }.disabled(vm.selectedIDs.isEmpty)
                    .help("Power on all selected lights.")
                Button("Turn OFF Selected") { vm.setPowerForSelected(false) }.disabled(vm.selectedIDs.isEmpty)
                    .help("Power off all selected lights.")
                Spacer()
                Text("\(vm.selectedIDs.count) selected").foregroundColor(.secondary)
                    .help("Number of lights that will receive auto color updates.")
            }

            List(vm.lights) { light in
                LightRow(
                    light: light,
                    displayName: vm.displayName(for: light),
                    alias: vm.aliasByID[light.id] ?? "",
                    isSelected: vm.selectedIDs.contains(light.id),
                    isPoweredOn: vm.powerByID[light.id],
                    onToggleSelect: { vm.toggleSelection(for: light) },
                    onAliasChanged: { newAlias in
                        vm.setAlias(lightID: light.id, alias: newAlias)
                        store.aliasesByID = vm.aliasByID
                        store.save()
                    }
                )
            }
        }
    }
}

// MARK: - Connect Lights Button

/// Reconnects to last-known LIFX lights (saved IPs / selection) without a full scan.
private struct ConnectLightsButton: View {
    @ObservedObject var vm: LIFXDiscoveryViewModel
    @ObservedObject var store: UserConfigStore

    private var hasLastKnown: Bool { !store.savedLightEntries.isEmpty }

    private var isConnecting: Bool {
        vm.status.hasPrefix("Reconnecting") || vm.status.hasPrefix("Scanning")
    }

    private var lastKnownSummary: String {
        guard !store.savedLightEntries.isEmpty else { return "No saved lights" }
        let names = store.savedLightEntries.prefix(3).map { entry in
            store.aliasesByID[entry.id] ?? entry.alias ?? entry.label
        }
        let suffix = store.savedLightEntries.count > 3 ? " +\(store.savedLightEntries.count - 3) more" : ""
        return names.joined(separator: ", ") + suffix
    }

    var body: some View {
        HStack(spacing: 10) {
            Button {
                vm.aliasByID = store.aliasesByID
                vm.autoReconnectLights(
                    savedEntries: store.savedLightEntries,
                    savedSelectedIDs: store.savedSelectedLightIDs
                )
            } label: {
                Label(isConnecting ? "Connecting…" : "Connect Lights", systemImage: "lightbulb")
            }
            .disabled(isConnecting || !hasLastKnown)
            .help(hasLastKnown
                  ? "Reconnect to last-used lights: \(lastKnownSummary)"
                  : "No saved lights. Use 'Scan for New Lights' first.")

            if !store.savedLightEntries.isEmpty {
                Text(lastKnownSummary)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }
}
