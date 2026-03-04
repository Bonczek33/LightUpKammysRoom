//
//  LightRow.swift
//  LIFXBTMacApp
//
//  Created by Tomasz Bak on 2/16/26.
//

import SwiftUI

struct DeviceList: View {
    let title: String
    let items: [BluetoothSensorsViewModel.PeripheralItem]
    let onConnect: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundColor(.secondary)
            List(items) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                        Text("RSSI \(item.rssi)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Connect") { onConnect(item.id) }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

struct StatPill: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundColor(.secondary)
            Text(value).font(.title3).monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct LightRow: View {
    let light: LIFXLight
    let displayName: String
    let alias: String
    let isSelected: Bool
    let isPoweredOn: Bool?

    let onToggleSelect: () -> Void
    let onAliasChanged: (String) -> Void

    @State private var aliasDraft: String = ""

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Toggle("", isOn: .init(get: { isSelected }, set: { _ in onToggleSelect() }))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .help("Select this light to include it in auto color control.")

                // Power on/off indicator
                PowerIndicator(isPoweredOn: isPoweredOn)

                // Device type indicator — always shown, mirrors power indicator style
                DeviceTypeIndicator(deviceType: light.deviceType)

                VStack(alignment: .leading, spacing: 4) {
                    Text(displayName)
                        .font(.headline)

                    HStack(spacing: 10) {
                        Text(light.ip).font(.caption).foregroundColor(.secondary)
                            .help("IP address on your local network. May change if DHCP assigns a new address.")
                        Text(light.id).font(.caption2).foregroundColor(.secondary)
                            .help("Hardware serial number (MAC-based). This never changes.")
                        if let pid = light.productID {
                            Text("PID \(pid)").font(.caption2).foregroundColor(.secondary)
                                .help("LIFX product ID from StateVersion. Used to detect device type.")
                        }
                    }

                    HStack(spacing: 10) {
                        Text("Name").font(.caption).foregroundColor(.secondary)

                        TextField("Add a name (stored locally)", text: Binding(
                            get: { aliasDraft },
                            set: { aliasDraft = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 280)
                        .help("Give this light a friendly name. Stored locally on your Mac, not on the bulb.")

                        Button("Set") { onAliasChanged(aliasDraft) }
                            .disabled(aliasDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                                      alias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .help("Save the name for this light.")

                        Button("Reset") {
                            onAliasChanged("")
                            aliasDraft = light.label.isEmpty ? "" : light.label
                        }
                            .disabled(alias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .help("Reset to the light's built-in label.")
                    }
                }

                Spacer()

                Text(!isSelected ? "Select to enable" : "")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 6)
        .onAppear { aliasDraft = alias.isEmpty ? light.label : alias }
        .onChange(of: alias) { oldValue, newValue in
            if newValue.isEmpty {
                aliasDraft = light.label
            } else if aliasDraft != newValue {
                aliasDraft = newValue
            }
        }
    }
}

// MARK: - Device Type Indicator

/// Shows the device form factor (Bulb / Lightstrip / Neon) using the same
/// pill style as PowerIndicator: SF symbol + short label, coloured bg tint.
struct DeviceTypeIndicator: View {
    let deviceType: LIFXDeviceType

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: iconName)
                .font(.caption)
                .foregroundColor(indicatorColor)
            Text(label)
                .font(.caption2)
                .foregroundColor(indicatorColor)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(indicatorColor.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .help(tooltip)
    }

    private var iconName: String {
        deviceType.symbolName
    }

    private var label: String {
        deviceType.displayName
    }

    private var indicatorColor: Color {
        deviceType.badgeColor
    }

    private var tooltip: String {
        switch deviceType {
        case .bulb:
            return "Single-zone bulb. Colour is set with SetColor (type 102)."
        case .lightstrip:
            return "LIFX Lightstrip — multizone. All zones set with SetExtendedColorZones (type 510)."
        case .neon:
            return "LIFX Neon — multizone flexible tube. All zones set with SetExtendedColorZones (type 510)."
        }
    }
}

struct LEDDot: View {
    let fill: Color
    let stroke: Color
    let size: CGFloat
    var body: some View {
        Circle()
            .fill(fill)
            .overlay(Circle().stroke(stroke.opacity(0.5), lineWidth: 1))
            .overlay(Circle().fill(fill.opacity(0.35)).blur(radius: 3).scaleEffect(1.2))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct PowerIndicator: View {
    let isPoweredOn: Bool?

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: iconName)
                .font(.caption)
                .foregroundColor(iconColor)
            Text(label)
                .font(.caption2)
                .foregroundColor(iconColor)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(bgColor)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .help(tooltip)
    }

    private var iconName: String {
        switch isPoweredOn {
        case true:  return "power"
        case false: return "power"
        case nil:   return "questionmark.circle"
        case .some(_): return "questionmark.circle"
        }
    }

    private var label: String {
        switch isPoweredOn {
        case true:  return "ON"
        case false: return "OFF"
        case nil:   return "?"
        case .some(_): return "?"
        }
    }

    private var iconColor: Color {
        switch isPoweredOn {
        case true:  return .green
        case false: return .secondary
        case nil:   return .secondary.opacity(0.5)
        case .some(_): return .secondary.opacity(0.5)
        }
    }

    private var bgColor: Color {
        switch isPoweredOn {
        case true:  return .green.opacity(0.12)
        case false: return .secondary.opacity(0.08)
        case nil:   return .clear
        case .some(_): return .clear
        }
    }

    private var tooltip: String {
        switch isPoweredOn {
        case true:  return "Light is powered on."
        case false: return "Light is powered off."
        case nil:   return "Power state unknown — no response yet."
        case .some(_): return "Power state unknown."
        }
    }
}
