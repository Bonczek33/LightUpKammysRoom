import SwiftUI

// MARK: - Bluetooth Status Bar (compact — config is in Settings)

struct BluetoothStatusBar: View {
    @ObservedObject var bt: BluetoothSensorsViewModel

    var body: some View {
        HStack(spacing: 18) {
            Label("Bluetooth", systemImage: "antenna.radiowaves.left.and.right")
                .font(.headline)

            Circle()
                .fill(bt.btState == .poweredOn ? Color.green : Color.red)
                .frame(width: 8, height: 8)

            StatPill(title: "Heart Rate", value: bt.heartRateBPM.map { "\($0) bpm" } ?? "—")
            StatPill(title: "Power", value: bt.powerWatts.map { "\($0) W" } ?? "—")
            StatPill(title: "Cadence", value: bt.cadenceRPM.map { "\($0) rpm" } ?? "—")

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("HR: \(bt.connectedHRName ?? "—")")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Power: \(bt.connectedPowerName ?? "—")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text(bt.status)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .frame(maxWidth: 160, alignment: .trailing)
        }
    }
}

// MARK: - Auto Color

struct AutoColorPanel: View {
    @ObservedObject var auto: AutoColorController
    @ObservedObject var store: UserConfigStore
    let formatter: NumberFormatter

    let onSave: () -> Void
    let onReset: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text("Auto Color").font(.headline)

                Picker("Source", selection: $auto.source) {
                    ForEach(AutoColorController.Source.allCases) { s in
                        Text(s.rawValue).tag(s)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 560)

                Spacer()

                Button("Save") { onSave() }
                Button("Reset Defaults") { onReset() }

                Text(auto.lastInputText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 8)
            }

            HStack(spacing: 18) {
                HStack(spacing: 10) {
                    Text("Age \(auto.ageYears)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("MaxHR \(auto.maxHR)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("FTP \(auto.ftp)W")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("Weight \(String(format: "%.1f", auto.weightKg))kg")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text(auto.lastZoneID.map { "Zone \($0)/7" } ?? "Zone —")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            ZoneLegendView(maxHR: auto.maxHR, ftp: auto.ftp)
        }
        .onChange(of: auto.source) { _, newValue in
            store.autoSourceRaw = newValue.rawValue
        }
    }
}

// MARK: - Zone Legend

struct ZoneLegendView: View {
    let maxHR: Int
    let ftp: Int

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
            Text("Zone palette + ranges (ZWIFT colors, applies to selected lights)")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 10) {
                ForEach(ZoneDefs.zones) { z in
                    let c = ZwiftZonePalette.colors[z.paletteIndex].preview
                    VStack(spacing: 4) {
                        Circle().fill(c).frame(width: 14, height: 14)
                            .overlay(Circle().stroke(Color.secondary.opacity(0.4), lineWidth: 1))
                        Text(z.name).font(.caption2).foregroundColor(.secondary)
                    }
                    .frame(width: 44)
                }
                Spacer()
            }

            LazyVGrid(columns: cols, alignment: .leading, spacing: 6) {
                Text("Zone").font(.caption).foregroundColor(.secondary)
                Text("%").font(.caption).foregroundColor(.secondary)
                Text("HR (bpm)").font(.caption).foregroundColor(.secondary)
                Text("Power (W)").font(.caption).foregroundColor(.secondary)
                Text("Color").font(.caption).foregroundColor(.secondary)

                ForEach(ZoneDefs.zones) { z in
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

// MARK: - LIFX

struct LIFXPanel: View {
    @ObservedObject var vm: LIFXDiscoveryViewModel
    @ObservedObject var store: UserConfigStore

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button("Scan LIFX") { vm.scan() }
                Text(vm.status).foregroundColor(.secondary)
                Spacer()
                Button("Select All") { vm.selectAll() }.disabled(vm.lights.isEmpty)
                Button("Select None") { vm.selectNone() }.disabled(vm.selectedIDs.isEmpty)
            }

            HStack(spacing: 12) {
                Button("Turn ON Selected") { vm.setPowerForSelected(true) }.disabled(vm.selectedIDs.isEmpty)
                Button("Turn OFF Selected") { vm.setPowerForSelected(false) }.disabled(vm.selectedIDs.isEmpty)
                Spacer()
                Text("\(vm.selectedIDs.count) selected").foregroundColor(.secondary)
            }

            List(vm.lights) { light in
                LightRow(
                    light: light,
                    displayName: vm.displayName(for: light),
                    alias: vm.aliasByID[light.id] ?? "",
                    isSelected: vm.selectedIDs.contains(light.id),
                    lifxColor: vm.colorByID[light.id],
                    brightness: vm.brightnessByID[light.id] ?? 32768,
                    onToggleSelect: { vm.toggleSelection(for: light) },
                    onBrightnessChanged: { vm.setBrightness(lightID: light.id, level: $0) },
                    onAliasChanged: { newAlias in
                        vm.setAlias(lightID: light.id, alias: newAlias)
                    }
                )
            }
        }
    }
}
