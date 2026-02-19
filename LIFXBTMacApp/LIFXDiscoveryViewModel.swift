//
//  LIFXDiscoveryViewModel.swift
//  LIFXBTMacApp
//
//  Created by Tomasz Bak on 2/16/26.
//

import Foundation
import SwiftUI
import Network

@MainActor
final class LIFXDiscoveryViewModel: ObservableObject {
    @Published private(set) var lights: [LIFXLight] = []
    @Published var status: String = "Idle"

    var isActive: Bool {
        status != "Idle"
    }

    @Published var selectedIDs: Set<String> = []

    @Published private(set) var powerByID: [String: Bool] = [:]
    @Published private(set) var colorByID: [String: LIFXColor] = [:]
    @Published private(set) var brightnessByID: [String: UInt16] = [:]

    // Local aliases (stored on Mac, not on bulb)
    @Published var aliasByID: [String: String] = [:]

    private let discovery = LIFXLanDiscovery()
    private let control = LIFXLanControl()

    private var pollTask: Task<Void, Never>?
    private let pollingIntervalSeconds: Double = 2.0

    // IMPORTANT: Keep debounce tasks on MainActor too.
    private var brightnessDebounce: [String: Task<Void, Never>] = [:]

    // Identify lights state
    @Published private(set) var isIdentifying: Bool = false
    @Published private(set) var identifyingLightID: String? = nil
    @Published private(set) var identifyingIndex: Int? = nil
    private var identifyTask: Task<Void, Never>?

    private func isSelected(_ lightID: String) -> Bool { selectedIDs.contains(lightID) }

    func displayName(for light: LIFXLight) -> String {
        let alias = aliasByID[light.id]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !alias.isEmpty { return alias }
        if !light.label.isEmpty { return light.label }
        return "Unnamed Light"
    }

    func setAlias(lightID: String, alias: String) {
        let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { aliasByID.removeValue(forKey: lightID) }
        else { aliasByID[lightID] = trimmed }
    }

    func scan() {
        stop()

        lights.removeAll()
        status = "Scanning…"
        selectedIDs.removeAll()

        powerByID.removeAll()
        colorByID.removeAll()
        brightnessByID.removeAll()

        for (_, t) in brightnessDebounce { t.cancel() }
        brightnessDebounce.removeAll()

        discovery.startScan(
            onStatus: { [weak self] text in Task { @MainActor in self?.status = text } },
            onLight: { [weak self] light in
                Task { @MainActor in
                    guard let self else { return }
                    if let idx = self.lights.firstIndex(where: { $0.id == light.id }) {
                        self.lights[idx] = light
                    } else {
                        self.lights.append(light)
                    }
                    if self.brightnessByID[light.id] == nil { self.brightnessByID[light.id] = 32768 }
                }
            }
        )

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            self.discovery.stop()
            self.status = "Done (poll 2s)"
            self.startPollingAllLights(everySeconds: self.pollingIntervalSeconds)
        }
    }

    func stop() {
        discovery.stop()
        pollTask?.cancel(); pollTask = nil
        for (_, t) in brightnessDebounce { t.cancel() }
        brightnessDebounce.removeAll()
        status = "Idle"
    }

    /// Auto-reconnect: populate lights from saved entries, scan to refresh IPs, then restore selection.
    func autoReconnectLights(savedEntries: [SavedLightEntry], savedSelectedIDs: [String]) {
        guard !savedEntries.isEmpty else { return }

        // Populate lights list from saved data so the UI shows them immediately
        for entry in savedEntries {
            let light = LIFXLight(id: entry.id, label: entry.label, ip: entry.ip)
            if !lights.contains(where: { $0.id == entry.id }) {
                lights.append(light)
            }
            if brightnessByID[light.id] == nil { brightnessByID[light.id] = 32768 }
            
            // Restore alias if it was saved and not already set
            if let alias = entry.alias, !alias.isEmpty,
               (aliasByID[entry.id]?.isEmpty ?? true) {
                aliasByID[entry.id] = alias
            }
        }

        // Restore selection
        selectedIDs = Set(savedSelectedIDs)

        // Run a scan to refresh IPs and discover any new lights
        status = "Reconnecting saved lights…"
        print("🔄 [LIFX] Auto-reconnect: restoring \(savedEntries.count) light(s), \(savedSelectedIDs.count) selected")

        discovery.startScan(
            onStatus: { [weak self] text in Task { @MainActor in self?.status = text } },
            onLight: { [weak self] light in
                Task { @MainActor in
                    guard let self else { return }
                    if let idx = self.lights.firstIndex(where: { $0.id == light.id }) {
                        self.lights[idx] = light  // Update IP/label from fresh scan
                    } else {
                        self.lights.append(light)
                    }
                    if self.brightnessByID[light.id] == nil { self.brightnessByID[light.id] = 32768 }
                }
            }
        )

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            self.discovery.stop()
            self.status = "Reconnected (poll 2s)"
            self.startPollingAllLights(everySeconds: self.pollingIntervalSeconds)
        }
    }

    // Selection
    func toggleSelection(for light: LIFXLight) {
        if selectedIDs.contains(light.id) { selectedIDs.remove(light.id) }
        else { selectedIDs.insert(light.id) }
    }
    func selectAll() { selectedIDs = Set(lights.map(\.id)) }
    func selectNone() { selectedIDs.removeAll() }

    // Bulk power
    func setPowerForSelected(_ on: Bool) {
        let selected = lights.filter { selectedIDs.contains($0.id) }
        guard !selected.isEmpty else { return }
        for light in selected {
            control.setPower(ip: light.ip, targetHex: light.id, on: on, durationMs: 0)
            powerByID[light.id] = on
        }
    }

    /// Identify lights one at a time: each light blinks for 5s (1s on, 0.5s off), then the next light starts
    func identifyLights() {
        guard !lights.isEmpty else { return }
        
        identifyTask?.cancel()
        isIdentifying = true
        identifyingIndex = 0
        
        let allLights = lights
        let ctrl = control
        
        identifyTask = Task { [weak self] in
            let onDuration: UInt64 = 1_000_000_000   // 1s
            let offDuration: UInt64 = 500_000_000     // 0.5s
            let perLightDuration: Double = 5.0        // 5s per light
            
            for (index, light) in allLights.enumerated() {
                guard !Task.isCancelled else { break }
                
                await MainActor.run {
                    self?.identifyingLightID = light.id
                    self?.identifyingIndex = index
                }
                
                // Blink this light for 5 seconds
                let start = Date()
                while Date().timeIntervalSince(start) < perLightDuration {
                    guard !Task.isCancelled else { break }
                    
                    // ON at 100% brightness (white)
                    ctrl.setPower(ip: light.ip, targetHex: light.id, on: true, durationMs: 0)
                    ctrl.setColor(ip: light.ip, targetHex: light.id, color: LIFXColor(
                        hue: 0, saturation: 0, brightness: 1.0,
                        hueU16: 0, satU16: 0, briU16: 65535, kelvin: 6500
                    ), durationMs: 0)
                    do { try await Task.sleep(nanoseconds: onDuration) } catch { break }
                    
                    guard !Task.isCancelled else { break }
                    
                    // OFF
                    ctrl.setPower(ip: light.ip, targetHex: light.id, on: false, durationMs: 0)
                    do { try await Task.sleep(nanoseconds: offDuration) } catch { break }
                }
                
                // Leave this light ON before moving to the next
                ctrl.setPower(ip: light.ip, targetHex: light.id, on: true, durationMs: 0)
            }
            
            await MainActor.run {
                self?.isIdentifying = false
                self?.identifyingLightID = nil
                self?.identifyingIndex = nil
            }
        }
    }
    
    func stopIdentify() {
        identifyTask?.cancel()
        identifyTask = nil
        isIdentifying = false
        identifyingLightID = nil
        identifyingIndex = nil
        
        // Leave lights on
        for light in lights {
            control.setPower(ip: light.ip, targetHex: light.id, on: true, durationMs: 0)
        }
    }

    // Brightness (selected-gated, debounced)
    func setBrightness(lightID: String, level: UInt16) {
        guard isSelected(lightID) else { return }
        brightnessByID[lightID] = level

        brightnessDebounce[lightID]?.cancel()

        brightnessDebounce[lightID] = Task { @MainActor [weak self] in
            guard let self else { return }
            do { try await Task.sleep(nanoseconds: 200_000_000) }
            catch { self.brightnessDebounce[lightID] = nil; return }

            guard self.isSelected(lightID) else { self.brightnessDebounce[lightID] = nil; return }
            await self.sendBrightness(lightID: lightID)
            self.brightnessDebounce[lightID] = nil
        }
    }

    private func sendBrightness(lightID: String) async {
        guard let light = lights.first(where: { $0.id == lightID }) else { return }
        guard let bri = brightnessByID[lightID] else { return }

        let current = colorByID[lightID] ?? LIFXColor(
            hue: 0, saturation: 0, brightness: Double(bri) / 65535.0,
            hueU16: 0, satU16: 0, briU16: bri, kelvin: 3500
        )

        let updated = LIFXColor(
            hue: current.hue, saturation: current.saturation, brightness: Double(bri) / 65535.0,
            hueU16: current.hueU16, satU16: current.satU16, briU16: bri, kelvin: current.kelvin
        )

        control.setColor(ip: light.ip, targetHex: light.id, color: updated, durationMs: 0)
        colorByID[lightID] = updated
    }

    // Manual / Auto palette index apply (0..6)
    func applyPaletteIndexToSelected(_ paletteIndex: Int, durationMs: UInt32, brightness: UInt16? = nil) {
        let palette = ZwiftZonePalette.colors
        let safe = max(0, min(palette.count - 1, paletteIndex))

        let selected = lights.filter { selectedIDs.contains($0.id) }
        guard !selected.isEmpty else { return }

        for light in selected {
            let bri = brightness ?? brightnessByID[light.id] ?? 32768
            let c = makeColorFromPalette(index: safe, bri: bri)
            control.setColor(ip: light.ip, targetHex: light.id, color: c, durationMs: durationMs)
            colorByID[light.id] = c
            
            // Update stored brightness if overridden
            if let brightness {
                brightnessByID[light.id] = brightness
            }
        }
    }

    func applyAutoPaletteIndexToSelected(_ paletteIndex: Int, durationMs: UInt32, brightness: UInt16? = nil) {
        applyPaletteIndexToSelected(paletteIndex, durationMs: durationMs, brightness: brightness)
    }

    private func makeColorFromPalette(index: Int, bri: UInt16) -> LIFXColor {
        let palette = ZwiftZonePalette.colors
        let safeIdx = max(0, min(palette.count - 1, index))
        let p = palette[safeIdx]
        return LIFXColor(
            hue: Double(p.hueU16) / 65535.0,
            saturation: Double(p.satU16) / 65535.0,
            brightness: Double(bri) / 65535.0,
            hueU16: p.hueU16, satU16: p.satU16, briU16: bri, kelvin: p.kelvin
        )
    }

    // Polling (read-only)
    private func startPollingAllLights(everySeconds: Double) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.refreshStates(forLights: self.lights)
                try? await Task.sleep(nanoseconds: UInt64(everySeconds * 1_000_000_000))
            }
        }
    }

    private func refreshStates(forLights lights: [LIFXLight]) async {
        for light in lights {
            if Task.isCancelled { return }
            if let state = await control.getLightState(ip: light.ip, targetHex: light.id, timeoutSeconds: 1.0) {
                powerByID[light.id] = state.powerOn
                colorByID[light.id] = state.color
                if brightnessDebounce[light.id] == nil {
                    brightnessByID[light.id] = state.color.briU16
                }
            }
        }
    }
    
    // Apply explicit HSB (raw) to selected lights, preserving each light's current brightness setting
    func applyExplicitHSKToSelected(hueU16: UInt16, satU16: UInt16, kelvin: UInt16, durationMs: UInt32) {
        let selected = lights.filter { selectedIDs.contains($0.id) }
        guard !selected.isEmpty else { return }

        for light in selected {
            let bri = brightnessByID[light.id] ?? 32768
            let c = LIFXColor(
                hue: Double(hueU16) / 65535.0,
                saturation: Double(satU16) / 65535.0,
                brightness: Double(bri) / 65535.0,
                hueU16: hueU16,
                satU16: satU16,
                briU16: bri,
                kelvin: kelvin
            )
            control.setColor(ip: light.ip, targetHex: light.id, color: c, durationMs: durationMs)
            colorByID[light.id] = c
        }
    }

}

