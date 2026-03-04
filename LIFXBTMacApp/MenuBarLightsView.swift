//
//  MenuBarLightsView.swift
//  LIFXBTMacApp
//
//  Created by Tomasz Bak on 2/13/26.
//

import SwiftUI

@available(macOS 13.0, *)
struct MenuBarLightsView: View {
    @EnvironmentObject var lifx: LIFXDiscoveryViewModel
    @EnvironmentObject var store: UserConfigStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button("Scan") { lifx.scan() }
                    .help("Scan your local network for LIFX lights.")
                Spacer()
                Text(lifx.status)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                Button("All") { lifx.selectAll() }
                    .disabled(lifx.lights.isEmpty)
                    .help("Select all discovered lights.")
                Button("None") { lifx.selectNone() }
                    .disabled(lifx.selectedIDs.isEmpty)
                    .help("Deselect all lights.")
                Spacer()
                Text("\(lifx.selectedIDs.count) selected")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 8) {
                Button("On") { lifx.setPowerForSelected(true) }
                    .disabled(lifx.selectedIDs.isEmpty)
                    .help("Power on all selected lights.")
                Button("Off") { lifx.setPowerForSelected(false) }
                    .disabled(lifx.selectedIDs.isEmpty)
                    .help("Power off all selected lights.")
                Spacer()
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(lifx.lights) { light in
                        Toggle(
                            isOn: Binding(
                                get: { lifx.selectedIDs.contains(light.id) },
                                set: { _ in lifx.toggleSelection(for: light) }
                            )
                        ) {
                            Text(lifx.displayName(for: light))
                                .lineLimit(1)
                        }
                        .toggleStyle(.checkbox)
                    }

                    if lifx.lights.isEmpty {
                        Text("No lights found yet.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 6)
                    }
                }
                .padding(.top, 4)
            }
            .frame(width: 300, height: 280)
        }
        .padding(12)
        .onAppear {
            // FIX 10: Don't call store.load() on every appearance — it can
            // overwrite in-flight state (e.g. a scan running in the background).
            // Aliases are populated by ContentView on startup; just sync here.
            if lifx.aliasByID.isEmpty {
                lifx.aliasByID = store.aliasesByID
            }
        }
    }
}
