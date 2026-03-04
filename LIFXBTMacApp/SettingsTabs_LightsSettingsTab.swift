//
//  SettingsTabs_LightsSettingsTab.swift
//  LIFXBTMacApp
//
//  FIX 6: Replaced @AppStorage + manual JSON decode/encode with direct
//  @EnvironmentObject UserConfigStore access.
//  FIX 10: Removed store.load() from onAppear to avoid clobbering in-flight state.
//

import SwiftUI

// MARK: - Lights Settings Tab

struct LightsSettingsTab: View {
    @EnvironmentObject var lifx:  LIFXDiscoveryViewModel
    @EnvironmentObject var store: UserConfigStore

    @State private var autoReconnect:          Bool     = true
    @State private var savedLightDisplayNames: [String] = []

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
        return "Identifying lights..."
    }

    // MARK: Persistence (FIX 6: direct store access, no JSON encode/decode)

    private func loadLightsSettings() {
        autoReconnect = store.lifxAutoReconnect
        updateSavedLightsDisplay(entries: store.savedLightEntries)
    }

    private func updateSavedLightsDisplay(entries: [SavedLightEntry]) {
        savedLightDisplayNames = entries.map { entry in
            let name: String
            if let alias = entry.alias, !alias.isEmpty { name = alias }
            else if !entry.label.isEmpty               { name = entry.label }
            else                                        { name = "Unnamed Light" }
            return "\(name)  (\(entry.id))"
        }
    }

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
            let cap   = lifx.deviceTypeByID[light.id] ?? light.deviceType
            let zones = lifx.zoneCountByID[light.id]  ?? light.zoneCount
            return SavedLightEntry(
                id: light.id, ip: light.ip, label: light.label,
                alias: (alias?.isEmpty == false) ? alias : nil,
                deviceType: cap == .bulb ? nil : cap,
                zoneCount: zones > 0 ? zones : nil
            )
        }
        store.savedSelectedLightIDs = selectedLights.map(\.id)
        store.save()
        updateSavedLightsDisplay(entries: store.savedLightEntries)
        NotificationCenter.default.post(name: .settingsDidChange, object: nil)
        print("[LIFX] Saved \(selectedLights.count) selected light(s)")
    }

    private func forgetSavedLights() {
        store.savedLightEntries = []
        store.savedSelectedLightIDs = []
        store.save()
        savedLightDisplayNames = []
        NotificationCenter.default.post(name: .settingsDidChange, object: nil)
        print("[LIFX] Forgot saved lights")
    }

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("LIFX Lights").font(.headline)

                GroupBox(label: Text("Auto-Reconnect").font(.subheadline)) {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Automatically reconnect to last used lights on app start",
                               isOn: $autoReconnect)
                            .toggleStyle(.switch)
                            .onChange(of: autoReconnect) { _, v in saveLIFXAutoReconnect(v) }
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

                Divider()

                LIFXPanel(vm: lifx, store: store)
                    .frame(minHeight: 420)

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Troubleshooting").font(.subheadline).foregroundColor(.secondary)
                    Text("- LIFX bulbs must be on the same WiFi network\n - Local Network permission is required\n - UDP port 56700 must be reachable\n - Firewall should allow incoming connections")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .onAppear {
            // FIX 10: Don't call store.load() here -- it overwrites in-flight state.
            lifx.aliasByID = store.aliasesByID
            loadLightsSettings()
        }
    }
}
