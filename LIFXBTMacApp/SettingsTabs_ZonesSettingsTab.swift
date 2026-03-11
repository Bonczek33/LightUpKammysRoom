//
//  SettingsTabs_ZonesSettingsTab.swift
//  LIFXBTMacApp
//
//  Created by Tomasz Bak on 2/20/26.
//


//
//  Settings+Zones.swift
//  LIFXBTMacApp
//
//  Zones Settings tab — view and optionally customise the 6 training zones
//  used for light color control. Supports editing zone labels, thresholds
//  (%maxHR / %FTP), and palette colors. Shows a live computed-ranges table.
//
//  Zone boundaries are contiguous: each zone's lower bound equals the
//  previous zone's upper bound. Editing the "High %" column automatically
//  updates the adjacent zone's lower bound (propagateThresholds).
//
//  Owned config fields:  customZones (via UserConfigStore.saveCustomZones)
//

import SwiftUI

// MARK: - Zones Settings Tab

struct ZonesSettingsTab: View {
    @EnvironmentObject var store: UserConfigStore
    @EnvironmentObject var auto:  AutoColorController

    @State private var editableZones: [EditableZone] = []
    @State private var isCustom:      Bool           = false

    // MARK: Supporting types

    struct EditableZone: Identifiable {
        let id:          Int
        var name:        String
        var label:       String
        var lowPercent:  Int    // lower threshold as integer percent
        var highPercent: Int?   // nil for the last zone (no upper bound)
        var paletteIndex: Int
        var effect:      ZoneEffect
    }

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Zone Configuration").font(.headline)
                Divider()
                Text("Configure the 6 training zones used for light color control. Thresholds are percentages of maxHR (heart rate source) or FTP (power source).")
                    .font(.caption).foregroundColor(.secondary)
              
                // Custom toggle
                HStack {
                    Toggle("Use custom zone thresholds", isOn: $isCustom)
                        .help("Enable to override the default Zwift zone boundaries.")
                        .onChange(of: isCustom) { _, newValue in
                            if !newValue {
                                store.resetZonesToDefaults()
                                auto.activeZones = store.activeZones
                                loadZonesFromStore()
                            }
                        }
                    Spacer()
                    if isCustom {
                        Button("Reset to Zwift Defaults") {
                            store.resetZonesToDefaults()
                            auto.activeZones = store.activeZones
                            isCustom = false
                            loadZonesFromStore()
                        }
                        .controlSize(.small)
                        .help("Discard custom zones and restore the default 6-zone scheme.")
                    }
                }

                // Zone editor table
                GroupBox {
                    VStack(spacing: 0) {
                        // Header row
                        HStack(spacing: 0) {
                            Text("Zone")   .frame(width: 50,  alignment: .leading)
                            Text("Label")  .frame(width: 120, alignment: .leading)
                            Text("Low %")  .frame(width: 70,  alignment: .leading)
                            Text("High %") .frame(width: 70,  alignment: .leading)
                            Text("Color")  .frame(width: 160, alignment: .leading)
                            Text("Effect") .frame(width: 100, alignment: .leading)
                            Text("Preview").frame(width: 40,  alignment: .center)
                        }
                        .font(.caption).foregroundColor(.secondary)
                        .padding(.horizontal, 8).padding(.bottom, 6)

                        Divider()

                        ForEach($editableZones) { $zone in
                            HStack(spacing: 0) {
                                Text(zone.name)
                                    .font(.system(.body, design: .monospaced))
                                    .frame(width: 50, alignment: .leading)

                                if isCustom {
                                    // Editable label
                                    TextField("Label", text: $zone.label)
                                        .textFieldStyle(.roundedBorder).frame(width: 110)
                                        .help("Descriptive name for this zone.")
                                        .padding(.trailing, 10)
                                        .onSubmit { saveCustomZones() }

                                    // Low % — first zone always 0, others derived from previous high
                                    Group {
                                        if zone.id == 1 {
                                            Text("0%")
                                        } else {
                                            Text("\(zone.lowPercent)%")
                                                .help("Set by the previous zone's high boundary.")
                                        }
                                    }
                                    .font(.system(.body, design: .monospaced)).foregroundColor(.secondary)
                                    .frame(width: 60, alignment: .leading).padding(.trailing, 10)

                                    // High % — last zone is unbounded
                                    if zone.highPercent != nil {
                                        TextField("", value: $zone.highPercent, format: .number)
                                            .textFieldStyle(.roundedBorder).frame(width: 60)
                                            .help("Upper threshold %. The next zone starts here.")
                                            .padding(.trailing, 10)
                                            .onChange(of: zone.highPercent) { _, _ in
                                                propagateThresholds()
                                                saveCustomZones()
                                            }
                                    } else {
                                        Text("∞")
                                            .font(.system(.body, design: .monospaced)).foregroundColor(.secondary)
                                            .frame(width: 60, alignment: .leading).padding(.trailing, 10)
                                    }

                                    // Color picker
                                    Picker("", selection: $zone.paletteIndex) {
                                        ForEach(0..<ZwiftZonePalette.colors.count, id: \.self) { i in
                                            Text(ZwiftZonePalette.colors[i].name).tag(i)
                                        }
                                    }
                                    .frame(width: 150)
                                    .help("LIFX light color for this zone.")
                                    .onChange(of: zone.paletteIndex) { _, _ in saveCustomZones() }

                                    // Effect picker (multizone lights only)
                                    Picker("", selection: $zone.effect) {
                                        ForEach(ZoneEffect.allCases) { e in
                                            Label(e.rawValue, systemImage: e.symbolName).tag(e)
                                        }
                                    }
                                    .frame(width: 95)
                                    .help("Light effect while in this zone. Flame only applies to multizone devices (Neon / Lightstrip).")
                                    .onChange(of: zone.effect) { _, _ in saveCustomZones() }

                                } else {
                                    // Read-only display
                                    Text(zone.label).frame(width: 110, alignment: .leading).padding(.trailing, 10)
                                    Text(zone.id == 1 ? "0%" : "\(zone.lowPercent)%")
                                        .font(.system(.body, design: .monospaced)).foregroundColor(.secondary)
                                        .frame(width: 60, alignment: .leading).padding(.trailing, 10)
                                    Text(zone.highPercent.map { "\($0)%" } ?? "∞")
                                        .font(.system(.body, design: .monospaced)).foregroundColor(.secondary)
                                        .frame(width: 60, alignment: .leading).padding(.trailing, 10)
                                    Text(ZwiftZonePalette.colors[zone.paletteIndex].name)
                                        .frame(width: 150, alignment: .leading)
                                    Label(zone.effect.rawValue, systemImage: zone.effect.symbolName)
                                        .font(.caption2)
                                        .foregroundColor(zone.effect == .none ? .secondary : .orange)
                                        .frame(width: 95, alignment: .leading)
                                }

                                // Color preview dot
                                Circle()
                                    .fill(ZwiftZonePalette.colors[zone.paletteIndex].preview)
                                    .overlay(Circle().stroke(Color.secondary.opacity(0.4), lineWidth: 1))
                                    .frame(width: 16, height: 16)
                                    .frame(width: 40, alignment: .center)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 5)

                            if zone.id < 6 { Divider() }
                        }
                    }
                    .padding(.vertical, 8)
                }
                Divider()
                // Computed ranges preview
                GroupBox(label: Text("Computed Ranges").font(.subheadline)) {
                    let maxHR = 220 - (Calendar.current.dateComponents([.year], from: store.dateOfBirth, to: Date()).year ?? 0)
                    ZoneLegendView(maxHR: maxHR, ftp: store.ftp, zones: store.activeZones)
                        .padding(4)
                }

                if isCustom {
                    Text("Zone boundaries are contiguous — each zone's lower boundary equals the previous zone's upper boundary. Edit the \"High %\" column to adjust where zones transition.")
                        .font(.caption).foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding()
        }
        .onAppear { loadZonesFromStore() }
    }

    // MARK: Helpers

    private func loadZonesFromStore() {
        isCustom = store.customZones != nil
        editableZones = store.activeZones.map { z in
            EditableZone(
                id:           z.id,
                name:         z.name,
                label:        z.label,
                lowPercent:   Int((z.low * 100).rounded()),
                highPercent:  z.high.map { Int(($0 * 100).rounded()) },
                paletteIndex: z.paletteIndex,
                effect:       z.effect
            )
        }
    }

    /// Propagate contiguous boundaries: when zone N's high changes, zone N+1's low updates to match.
    private func propagateThresholds() {
        for i in 0..<editableZones.count - 1 {
            if let hi = editableZones[i].highPercent {
                let clamped = max(editableZones[i].lowPercent + 1, hi)
                editableZones[i].highPercent     = clamped
                editableZones[i + 1].lowPercent  = clamped
            }
        }
    }

    private func saveCustomZones() {
        let persisted = editableZones.map { ez in
            PersistedZone(
                id:           ez.id,
                name:         ez.name,
                label:        ez.label,
                low:          Double(ez.lowPercent) / 100.0,
                high:         ez.highPercent.map { Double($0) / 100.0 },
                paletteIndex: ez.paletteIndex,
                effect:       ez.effect
            )
        }
        store.saveCustomZones(persisted)
        auto.activeZones = store.activeZones
    }
}

// MARK: - Zone Color Indicator

/// Small color swatch + name label used in zone-related views.
struct ZoneColorIndicator: View {
    let color: Color
    let name:  String

    var body: some View {
        VStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 20, height: 20)
                .overlay(Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 1))
            Text(name)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}
