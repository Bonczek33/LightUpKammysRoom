//
//  AboutSettingsTab.swift
//  LIFXBTMacApp
//
//  Created by Tomasz Bak on 2/20/26.
//


//
//  Settings+About.swift
//  LIFXBTMacApp
//
//  About Settings tab — app icon, version string, description, and
//  feature list. No user-editable state.
//

import SwiftUI
import AppKit

// MARK: - About Settings Tab

struct AboutSettingsTab: View {
    var body: some View {
        ScrollView {
            Form {
                Section {
                    VStack(spacing: 16) {
                        Image(nsImage: NSApp.applicationIconImage)
                            .resizable()
                            .frame(width: 60, height: 60)

                        Text("Light Up Kammy's Room")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text(appVersionString)
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Divider().padding(.vertical, 8)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("About").font(.headline)
                            Text("Control LIFX smart lights based on real-time fitness data from Bluetooth sensors. Map your heart rate or power to training zones using Zwift's color scheme.")
                                .font(.caption).foregroundColor(.secondary)
                        }

                        Divider().padding(.vertical, 8)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Features").font(.headline)
                            Label("BLE and ANT+ heart rate & power sensors",  systemImage: "antenna.radiowaves.left.and.right")
                            Label("LIFX LAN protocol control",                systemImage: "network")
                            Label("6 training zones",                         systemImage: "chart.bar.fill")
                            Label("EMA smoothing & moving averages",          systemImage: "waveform.path.ecg")
                            Label("Local network only (no cloud)",            systemImage: "lock.shield")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)

                        Spacer()

                        Text("© 2026")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

// MARK: - Helpers

private var appVersionString: String {
    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    let build   = Bundle.main.infoDictionary?["CFBundleVersion"]            as? String ?? "?"
    return "Version \(version) (\(build))"
}