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
    let lifxColor: LIFXColor?

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

                LEDDot(fill: colorLEDColor(lifxColor), stroke: .secondary, size: 12)
                    .help(lifxColor != nil ? "Current color reported by the light." : "No color data — light may be off or unreachable.")

                VStack(alignment: .leading, spacing: 4) {
                    Text(displayName)
                        .font(.headline)

                    HStack(spacing: 10) {
                        Text(light.ip).font(.caption).foregroundColor(.secondary)
                            .help("IP address on your local network. May change if DHCP assigns a new address.")
                        Text(light.id).font(.caption2).foregroundColor(.secondary)
                            .help("Hardware serial number (MAC-based). This never changes.")
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

                        Button("Clear") { aliasDraft = ""; onAliasChanged("") }
                            .disabled(alias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .help("Remove the custom name. The light's built-in label will be shown instead.")
                    }
                }

                Spacer()

                Text(!isSelected ? "Select to enable" : "")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 6)
        .onAppear { aliasDraft = alias }
        .onChange(of: alias) { oldValue, newValue in
            if aliasDraft != newValue { aliasDraft = newValue }
        }
    }

    private func colorLEDColor(_ c: LIFXColor?) -> Color {
        guard let c else { return .gray }
        return Color(hue: c.hue, saturation: c.saturation, brightness: max(0.05, c.brightness))
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
