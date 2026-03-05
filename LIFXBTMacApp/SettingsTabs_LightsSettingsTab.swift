//
//  SettingsTabs_LightsSettingsTab.swift
//  LIFXBTMacApp
//
//  Created by Tomasz Bak on 2/20/26.
//


//
//  Settings+Lights.swift
//  LIFXBTMacApp
//
//  Lights Settings tab — save/forget LIFX light sets for auto-reconnect,
//  identify lights by blinking them, and the full light management panel
//  (scan, select, power on/off, alias editor).
//
//  Owned config fields:
//    lifxAutoReconnect, savedLightEntries, savedSelectedLightIDs
//

import SwiftUI

// MARK: - Lights Settings Tab

struct LightsSettingsTab: View {
    @EnvironmentObject var lifx:  LIFXDiscoveryViewModel
    @EnvironmentObject var store: UserConfigStore

    // Computed directly from store — always current, no onAppear sync needed
    private var savedLightDisplayNames: [String] {
        store.savedLightEntries.map { entry in
            let name = (entry.alias?.isEmpty == false) ? entry.alias! : (entry.label.isEmpty ? "Unnamed Light" : entry.label)
            return "\(name)  (\(entry.id))"
        }
    }

    // MARK: Computed

    private var identifyStatusText: String {
        guard lifx.isIdentifying else {
            return "Blinks each light for 5 seconds one at a time to help identify them."
        }
        if let lightID = lifx.identifyingLightID, let index = lifx.identifyingIndex {
            let placeholder = LIFXLight(id: lightID, label: "", ip: "")
            let light = lifx.lights.first(where: { $0.id == lightID }) ?? placeholder
            return "Identifying \(index + 1)/\(lifx.lights.count): \(lifx.displayName(for: light))"
        }
        return "Identifying lights…"
    }

    // MARK: Persistence



    private func saveLIFXAutoReconnect(_ value: Bool) {
        store.lifxAutoReconnect = value
        store.save()
        NotificationCenter.default.post(name: .settingsDidChange, object: nil)
    }

    private func saveCurrentLights() {
        let selectedLights = lifx.lights.filter { lifx.selectedIDs.contains($0.id) }
        guard !selectedLights.isEmpty else { return }

        store.savedLightEntries = selectedLights.map { light in
            let alias = lifx.aliasByID[light.id]?.trimmingCharacters(in: .whitespacesAndNewlines)
            return SavedLightEntry(
                id: light.id, ip: light.ip, label: light.label,
                alias: (alias?.isEmpty == false) ? alias : nil
            )
        }
        store.savedSelectedLightIDs = selectedLights.map(\.id)
        store.save()
        NotificationCenter.default.post(name: .settingsDidChange, object: nil)
        print("💾 [LIFX] Saved \(selectedLights.count) selected light(s)")
    }

    private func forgetSavedLights() {
        store.savedLightEntries = []
        store.savedSelectedLightIDs = []
        store.save()
        NotificationCenter.default.post(name: .settingsDidChange, object: nil)
        print("🗑️ [LIFX] Forgot saved lights")
    }

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("LIFX Lights").font(.headline)

                // Auto-reconnect
                GroupBox(label: Text("Auto-Reconnect").font(.subheadline)) {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Automatically reconnect to last used lights on app start",
                               isOn: $store.lifxAutoReconnect)
                            .toggleStyle(.switch)
                            .onChange(of: store.lifxAutoReconnect) { _, _ in
                                store.save()
                                NotificationCenter.default.post(name: .settingsDidChange, object: nil)
                            }
                        Divider()
                        if savedLightDisplayNames.isEmpty {
                            HStack(spacing: 6) {
                                Image(systemName: "lightbulb.slash").foregroundColor(.secondary).font(.caption)
                                Text("No saved lights").font(.caption).foregroundColor(.secondary)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Saved lights (\(savedLightDisplayNames.count)):")
                                    .font(.caption).foregroundColor(.secondary)
                                ForEach(savedLightDisplayNames, id: \.self) { name in
                                    HStack(spacing: 6) {
                                        Image(systemName: "lightbulb.fill").foregroundColor(.yellow).font(.caption)
                                        Text(name).font(.caption).foregroundColor(.secondary)
                                    }
                                }
                            }
                        }

                        HStack(spacing: 12) {
                            Button("Save Current Lights") { saveCurrentLights() }
                                .disabled(lifx.selectedIDs.isEmpty).controlSize(.small)
                            if !savedLightDisplayNames.isEmpty {
                                Button("Forget Saved Lights") { forgetSavedLights() }
                                    .foregroundColor(.red).controlSize(.small)
                            }
                        }

                        Text("Select lights using the checkboxes below, then tap \"Save Current Lights\" to remember them for automatic reconnection.")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    .padding(8)
                }

                Divider()

                // Identify
                GroupBox(label: Text("Identify").font(.subheadline)) {
                    Divider()
                    HStack(spacing: 12) {
                        Button {
                            lifx.isIdentifying ? lifx.stopIdentify() : lifx.identifyLights()
                        } label: {
                            HStack(spacing: 6) {
                                if lifx.isIdentifying {
                                    ProgressView().controlSize(.small)
                                    Text("Stop Blinking")
                                } else {
                                    Image(systemName: "lightbulb.max")
                                    Text("Identify Lights")
                                }
                            }
                        }
                        .disabled(lifx.lights.isEmpty).controlSize(.small)

                        Text(identifyStatusText).font(.caption).foregroundColor(.secondary)
                    }
                    .padding(8)
                }

                // Full light management panel
                
                Divider()
                
                LIFXPanel(vm: lifx, store: store)
                    .frame(minHeight: 420)

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Troubleshooting").font(.subheadline).foregroundColor(.secondary)
                    Text("• LIFX bulbs must be on the same Wi‑Fi network\n• Local Network permission is required\n• UDP port 56700 must be reachable\n• Firewall should allow incoming connections")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .onAppear {
            lifx.aliasByID = store.aliasesByID
        }
    }
}
