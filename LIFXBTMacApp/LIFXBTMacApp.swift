//
//  LIFXBTMacApp.swift
//  LIFXBTMacApp
//
//  App entry point. Owns all top-level @StateObject view models and wires them
//  into the main ContentView and the Settings panel. Each settings tab lives
//  in its own file:
//    Settings+Profile.swift  — rider profiles (DOB / FTP / weight)
//    Settings+General.swift  — intensity modulation & power smoothing
//    Settings+Sensors.swift  — BLE / ANT+ sensor management
//    Settings+Lights.swift   — LIFX light management
//    Settings+Zones.swift    — training zone configuration
//    Settings+About.swift    — app info
//
//  Profile → store pipeline
//  ─────────────────────────
//  ProfileStore.activate / update  →  posts activeProfileDidChange
//  ContentView.activeProfileDidChange → calls UserConfigStore.applyProfile(_:) then applyStore()
//  UserConfigStore.applyProfile    →  sets dateOfBirth/ftp/weightKg in memory only
//                                     (no save — ProfileStore owns these fields)
//
//  Created by Tomasz Bak on 2/16/26.
//

import SwiftUI
import AppKit

// MARK: - Notification names

extension Notification.Name {
    /// Posted by any Settings tab when the user changes a persisted value.
    /// ContentView observes this to reload and re-apply the store.
    static let settingsDidChange = Notification.Name("settingsDidChange")
}

// MARK: - App

// MARK: - App Delegate
// applicationWillTerminate is the only reliable save point on macOS —
// onDisappear on WindowGroup does not fire when the user quits with Cmd+Q.
final class AppDelegate: NSObject, NSApplicationDelegate {
    var onTerminate: (() -> Void)?

    func applicationWillTerminate(_ notification: Notification) {
        onTerminate?()
    }
}

@main
struct LIFXBTMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var bt       = BluetoothSensorsViewModel()
    @StateObject private var antPlus  = ANTPlusSensorViewModel()
    @StateObject private var lifx     = LIFXDiscoveryViewModel()
    @StateObject private var store    = UserConfigStore()
    @StateObject private var auto     = AutoColorController()
    @StateObject private var charts   = ChartsViewModel()
    @StateObject private var profiles = ProfileStore()

    var body: some Scene {
        WindowGroup("Light Up Kammy's Room") {
            ContentView(
                bt:       bt,
                antPlus:  antPlus,
                lifx:     lifx,
                auto:     auto,
                store:    store,
                charts:   charts,
                profiles: profiles
            )
            .onAppear {
                bringMainWindowToFront()
                // Apply the persisted active profile on first launch
                if let p = profiles.activeProfile { store.applyProfile(p) }
                // Wire up quit-time save. Captures store/lifx/auto by reference.
                appDelegate.onTerminate = {
                    // Sync light selection into store before encoding
                    let selected = lifx.lights.filter { lifx.selectedIDs.contains($0.id) }
                    if !selected.isEmpty {
                        store.savedLightEntries = selected.map { light in
                            let alias = lifx.aliasByID[light.id]?
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            return SavedLightEntry(
                                id: light.id, ip: light.ip, label: light.label,
                                alias: (alias?.isEmpty == false) ? alias : nil
                            )
                        }
                        store.savedSelectedLightIDs = selected.map(\.id)
                    }
                    store.autoSourceRaw = auto.source.rawValue
                    store.aliasesByID   = lifx.aliasByID
                    store.save()
                    print("💾 [App] Saved state on terminate")
                }
            }
        }
        .defaultSize(width: 1000, height: 1000)
        .defaultPosition(.center)

        #if swift(>=5.9)
        Settings {
            SettingsView()
                .frame(width: 1100, height: 650, alignment: .center)
                .environmentObject(bt)
                .environmentObject(antPlus)
                .environmentObject(lifx)
                .environmentObject(store)
                .environmentObject(auto)
                .environmentObject(charts)
                .environmentObject(profiles)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 1100, height: 650)
        .defaultPosition(.center)
        #else
        Settings {
            SettingsView()
                .environmentObject(bt)
                .environmentObject(profiles)
        }
        #endif
    }
}

// MARK: - Settings shell

/// Top-level settings window. One tab per concern.
struct SettingsView: View {
    var body: some View {
        TabView {
            ProfileSettingsTab()
                .tabItem { Label("Profile", systemImage: "person.2") }

            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gear") }

            BluetoothSettingsTab()
                .tabItem { Label("Sensors", systemImage: "antenna.radiowaves.left.and.right") }

            LightsSettingsTab()
                .tabItem { Label("Lights", systemImage: "lightbulb") }

            ZonesSettingsTab()
                .tabItem { Label("Zones", systemImage: "chart.bar.fill") }

            AboutSettingsTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .padding(20)
    }
}

// MARK: - Helpers

private func bringMainWindowToFront() {
    DispatchQueue.main.async {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }
}
