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
    let brightness: UInt16

    let onToggleSelect: () -> Void
    let onBrightnessChanged: (UInt16) -> Void
    let onAliasChanged: (String) -> Void

    @State private var aliasDraft: String = ""

    private var brightnessBinding: Binding<Double> {
        Binding(
            get: { Double(brightness) },
            set: { newValue in
                let v = UInt16(max(0, min(65535, Int(newValue.rounded()))))
                onBrightnessChanged(v)
            }
        )
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Toggle("", isOn: .init(get: { isSelected }, set: { _ in onToggleSelect() }))
                    .toggleStyle(.checkbox)
                    .labelsHidden()

                LEDDot(fill: colorLEDColor(lifxColor), stroke: .secondary, size: 12)

                VStack(alignment: .leading, spacing: 4) {
                    Text(displayName)
                        .font(.headline)

                    HStack(spacing: 10) {
                        Text(light.ip).font(.caption).foregroundColor(.secondary)
                        Text(light.id).font(.caption2).foregroundColor(.secondary)
                    }

                    HStack(spacing: 10) {
                        Text("Name").font(.caption).foregroundColor(.secondary)

                        TextField("Add a name (stored locally)", text: Binding(
                            get: { aliasDraft },
                            set: { aliasDraft = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 280)

                        Button("Set") { onAliasChanged(aliasDraft) }
                            .disabled(aliasDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                                      alias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button("Clear") { aliasDraft = ""; onAliasChanged("") }
                            .disabled(alias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                Spacer()

                Text(!isSelected ? "Select to enable" : "")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 12) {
                Text("Brightness").font(.caption).foregroundColor(.secondary).frame(width: 80, alignment: .leading)
                Slider(value: brightnessBinding, in: 0...65535, step: 256)
                    .frame(maxWidth: 460)
                    .disabled(!isSelected)
                Text("\(brightness)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundColor(.secondary)
                    .frame(width: 90, alignment: .trailing)
                Spacer()
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
