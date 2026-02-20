//
//  LIFXBTMacApp.swift
//  LIFXBTMacApp
//
//  App entry point. Owns all top-level @StateObject view models and wires them
//  into the main ContentView and the Settings panel. Each settings tab lives
//  in its own file (Settings+General, Settings+Sensors, Settings+Lights,
//  Settings+Zones, Settings+About).
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

@main
struct LIFXBTMacApp: App {
    @StateObject private var bt      = BluetoothSensorsViewModel()
    @StateObject private var antPlus = ANTPlusSensorViewModel()
    @StateObject private var lifx    = LIFXDiscoveryViewModel()
    @StateObject private var store   = UserConfigStore()
    @StateObject private var auto    = AutoColorController()
    @StateObject private var charts  = ChartsViewModel()

    var body: some Scene {
        WindowGroup("Light Up Kammy's Room") {
            ContentView(
                bt: bt,
                antPlus: antPlus,
                lifx: lifx,
                auto: auto,
                store: store,
                charts: charts
            )
            .onAppear {
                bringMainWindowToFront()
            }
        }
        .defaultSize(width: 1000, height: 1000)
        .defaultPosition(.center)

        #if swift(>=5.9)
        Settings {
            SettingsView()
                .frame(width: 1000, height: 600, alignment: .center)
                .environmentObject(bt)
                .environmentObject(antPlus)
                .environmentObject(lifx)
                .environmentObject(store)
                .environmentObject(auto)
                .environmentObject(charts)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 1000, height: 600)
        .defaultPosition(.center)
        #else
        Settings {
            SettingsView()
                .environmentObject(bt)
        }
        #endif
    }
}

// MARK: - Settings shell

/// Top-level settings window containing one tab per concern.
/// Each tab is defined in its own Settings+*.swift file.
struct SettingsView: View {
    var body: some View {
        TabView {
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
