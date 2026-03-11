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
    @Published private(set) var status: String = "Idle"

    @Published var selectedIDs: Set<String> = []

    @Published private(set) var powerByID: [String: Bool] = [:]
    @Published private(set) var colorByID: [String: LIFXColor] = [:]
    @Published private(set) var brightnessByID: [String: UInt16] = [:]

    // Device type and zone count — populated from StateVersion during discovery/scan
    @Published private(set) var deviceTypeByID: [String: LIFXDeviceType] = [:]
    @Published private(set) var zoneCountByID:  [String: Int] = [:]

    // Per-zone color state for multizone devices (Neon / Lightstrip).
    // Populated by the polling loop via GetColorZones (502).
    // Use this in preference to colorByID for multizone lights — it reflects
    // what the hardware is actually showing, not just what we last sent.
    @Published private(set) var zoneColorsByID: [String: [LIFXColor]] = [:]

    // Wi-Fi signal strength in dBm, refreshed every polling cycle.
    // nil = not yet polled or device did not respond to GetWifiInfo.
    @Published private(set) var wifiSignalDBmByID: [String: Int] = [:]

    // Firmware version, populated once during probeDeviceType.
    @Published private(set) var firmwareByID: [String: LIFXLanControl.FirmwareVersion] = [:]

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

    // Tracks which multizone lights are currently running a firmware effect (MOVE).
    private var effectActiveIDs: Set<String> = []

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
        zoneColorsByID.removeAll()
        wifiSignalDBmByID.removeAll()
        firmwareByID.removeAll()

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
                    // Probe device type if not yet known
                    if self.deviceTypeByID[light.id] == nil {
                        Task { await self.probeDeviceType(light) }
                    }
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
                    if self.deviceTypeByID[light.id] == nil {
                        Task { await self.probeDeviceType(light) }
                    }
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

        let dt    = deviceTypeByID[light.id] ?? .bulb
        let zones = zoneCountByID[light.id]  ?? 0
        control.setColorDispatch(ip: light.ip, targetHex: light.id, color: updated,
                                 deviceType: dt, zoneCount: zones, durationMs: 0)
        colorByID[lightID] = updated
    }

    // Manual / Auto palette index apply (0..6)
    func applyPaletteIndexToSelected(_ paletteIndex: Int, durationMs: UInt32, brightness: UInt16? = nil, quiet: Bool = false) {
        let palette = ZwiftZonePalette.colors
        let safe = max(0, min(palette.count - 1, paletteIndex))

        let selected = lights.filter { selectedIDs.contains($0.id) }
        guard !selected.isEmpty else { return }

        for light in selected {
            // Skip lights whose device type hasn't been probed yet to avoid
            // sending SetColor to a multizone device that needs SetExtendedColorZones.
            guard deviceTypeByID[light.id] != nil else {
                print("⏳ [LIFX] \(light.label) — device type not yet known, skipping command")
                continue
            }
            let bri = brightness ?? brightnessByID[light.id] ?? 32768
            let c = makeColorFromPalette(index: safe, bri: bri)
            let dt    = deviceTypeByID[light.id] ?? .bulb
            let zones = zoneCountByID[light.id]  ?? 0
            print("🎨 [LIFX] \(light.label) dt=\(dt) zones=\(zones) hue=\(Int(c.hue*360))° -> \(dt.isMultizone ? "SetExtendedColorZones" : "SetColor")")
            control.setColorDispatch(ip: light.ip, targetHex: light.id, color: c,
                                     deviceType: dt, zoneCount: zones, durationMs: durationMs)
            colorByID[light.id] = c
            if let brightness { brightnessByID[light.id] = brightness }
            // SetExtendedColorZones cancels any running firmware effect on multizone devices.
            // Clear effectActiveIDs so setFlameEffect re-sends the effect on the next tick.
            if dt.isMultizone { effectActiveIDs.remove(light.id) }
        }
    }

    func applyAutoPaletteIndexToSelected(_ paletteIndex: Int, durationMs: UInt32, brightness: UInt16? = nil, quiet: Bool = false) {
        applyPaletteIndexToSelected(paletteIndex, durationMs: durationMs, brightness: brightness, quiet: quiet)
    }

    /// Returns the zone count for the first selected multizone light, or nil.
    func zoneCountForSelected() -> Int? {
        lights.first { selectedIDs.contains($0.id) && (deviceTypeByID[$0.id]?.isMultizone == true) }
              .flatMap { zoneCountByID[$0.id] }
    }

    /// Sends a per-zone colour array creating a comet sweep effect.
    /// Head zone = zone colour at full brightness; tail decays exponentially.
    func setCometEffect(paletteIndex: Int, zoneCount: Int, headPosition: Double) {
        let palette = ZwiftZonePalette.colors
        let p = palette[max(0, min(palette.count - 1, paletteIndex))]
        let selected = lights.filter { selectedIDs.contains($0.id) && (deviceTypeByID[$0.id]?.isMultizone == true) }
        for light in selected {
            let zones = zoneCountByID[light.id] ?? zoneCount
            var colors: [(h: UInt16, s: UInt16, b: UInt16, k: UInt16)] = []
            for i in 0..<min(zones, 82) {
                // Distance behind the head (wrapping)
                var dist = fmod(Double(i) - headPosition + Double(zones), Double(zones))
                if dist > Double(zones) / 2 { dist = Double(zones) - dist } // shortest arc
                let decay = exp(-dist * 0.28)  // tail length ~10 zones
                let bri = UInt16(max(0.03, decay) * 65535)
                // Head zone gets boosted white-shifted (higher kelvin feel via reduced sat)
                let sat = dist < 2 ? UInt16(Double(p.satU16) * max(0.3, 1.0 - (2 - dist) * 0.35)) : p.satU16
                colors.append((p.hueU16, sat, bri, p.kelvin))
            }
            control.setExtendedColorZonesArray(ip: light.ip, targetHex: light.id, colors: colors)
        }
    }

    /// Sends a per-zone colour array creating a rolling rainbow across the strip.
    /// Each zone gets a hue offset from the base, creating a full colour wheel spread.
    func setRainbowEffect(baseHueU16: UInt16, zoneCount: Int, offset: Double) {
        let selected = lights.filter { selectedIDs.contains($0.id) && (deviceTypeByID[$0.id]?.isMultizone == true) }
        for light in selected {
            let zones = zoneCountByID[light.id] ?? zoneCount
            var colors: [(h: UInt16, s: UInt16, b: UInt16, k: UInt16)] = []
            for i in 0..<min(zones, 82) {
                // Spread a full hue rotation across the strip, shifted by offset each tick
                let hueShift = (Double(i) / Double(zones) + offset)
                let hueU16 = UInt16((fmod(hueShift, 1.0)) * 65535)
                colors.append((hueU16, 65535, 52428, 3500))  // full sat, ~80% bri, neutral kelvin
            }
            control.setExtendedColorZonesArray(ip: light.ip, targetHex: light.id, colors: colors)
        }
    }

    // MARK: - Software effect helpers (new)

    /// Police: left half red, right half blue (or flipped). Hard cut, no duration.
    func setPoliceEffect(zoneCount: Int, flip: Bool) {
        let selected = lights.filter { selectedIDs.contains($0.id) && (deviceTypeByID[$0.id]?.isMultizone == true) }
        for light in selected {
            let zones = zoneCountByID[light.id] ?? zoneCount
            let mid = zones / 2
            var colors: [(h: UInt16, s: UInt16, b: UInt16, k: UInt16)] = []
            for i in 0..<min(zones, 82) {
                let isLeft = i < mid
                // red = hue 0 (0x0000), blue = hue 170/360 * 65535 ≈ 0x6200
                let hue: UInt16 = (isLeft != flip) ? 0 : 0x6200
                colors.append((hue, 65535, 65535, 3500))
            }
            control.setExtendedColorZonesArray(ip: light.ip, targetHex: light.id, colors: colors)
        }
    }

    /// Lava: brightness blobs drift along the strip at the palette colour's hue.
    func setLavaEffect(paletteIndex: Int, zoneCount: Int,
                       blobs: [(pos: Double, size: Double, speed: Double)]) {
        let palette = ZwiftZonePalette.colors
        let p = palette[max(0, min(palette.count - 1, paletteIndex))]
        let selected = lights.filter { selectedIDs.contains($0.id) && (deviceTypeByID[$0.id]?.isMultizone == true) }
        for light in selected {
            let zones = zoneCountByID[light.id] ?? zoneCount
            var brightness = [Double](repeating: 0.05, count: min(zones, 82))
            for blob in blobs {
                for i in 0..<brightness.count {
                    let dist = min(abs(Double(i) - blob.pos),
                                   abs(Double(i) - blob.pos + Double(zones)),
                                   abs(Double(i) - blob.pos - Double(zones)))
                    let contrib = max(0, 1.0 - (dist / (blob.size * 0.5)))
                    brightness[i] = min(1.0, brightness[i] + contrib * contrib)  // smooth falloff
                }
            }
            let colors: [(h: UInt16, s: UInt16, b: UInt16, k: UInt16)] = brightness.map { bri in
                (p.hueU16, p.satU16, UInt16(bri * 65535), p.kelvin)
            }
            control.setExtendedColorZonesArray(ip: light.ip, targetHex: light.id, colors: colors)
        }
    }

    /// Lightning: dark background with bright white spikes at strike zones.
    func setLightningEffect(paletteIndex: Int, zoneCount: Int,
                            strikes: [(zone: Int, bri: Double)]) {
        let palette = ZwiftZonePalette.colors
        let p = palette[max(0, min(palette.count - 1, paletteIndex))]
        let selected = lights.filter { selectedIDs.contains($0.id) && (deviceTypeByID[$0.id]?.isMultizone == true) }
        for light in selected {
            let zones = zoneCountByID[light.id] ?? zoneCount
            var colors: [(h: UInt16, s: UInt16, b: UInt16, k: UInt16)] =
                Array(repeating: (p.hueU16, p.satU16, 3277, p.kelvin), count: min(zones, 82))
            for strike in strikes {
                guard strike.zone < colors.count else { continue }
                let bri = UInt16(min(1.0, strike.bri) * 65535)
                // White flash: desaturate toward white at full brightness
                let sat = UInt16(Double(p.satU16) * (1.0 - strike.bri * 0.85))
                colors[strike.zone] = (p.hueU16, sat, bri, 6500)  // 6500K = cool white
            }
            control.setExtendedColorZonesArray(ip: light.ip, targetHex: light.id, colors: colors)
        }
    }

    /// VU meter: fill strip from zone 0 proportional to `fillRatio`. Lit zones = full colour,
    /// unlit zones = 5% brightness dim. Gives a classic level-meter look.
    func setVuMeterEffect(paletteIndex: Int, zoneCount: Int, fillRatio: Double) {
        let palette = ZwiftZonePalette.colors
        let p = palette[max(0, min(palette.count - 1, paletteIndex))]
        let selected = lights.filter { selectedIDs.contains($0.id) && (deviceTypeByID[$0.id]?.isMultizone == true) }
        for light in selected {
            let zones = zoneCountByID[light.id] ?? zoneCount
            let fillCount = Int((Double(zones) * fillRatio).rounded())
            var colors: [(h: UInt16, s: UInt16, b: UInt16, k: UInt16)] = []
            for i in 0..<min(zones, 82) {
                if i < fillCount {
                    // Colour gradient: green→yellow→red as fill increases
                    let hueShift = (1.0 - fillRatio) * 0.33   // 0.33=green, 0=red
                    let hue = UInt16(fmod(hueShift, 1.0) * 65535)
                    colors.append((hue, 65535, 52428, p.kelvin))
                } else {
                    colors.append((p.hueU16, p.satU16, 3277, p.kelvin))  // dim
                }
            }
            control.setExtendedColorZonesArray(ip: light.ip, targetHex: light.id, colors: colors)
        }
    }

    // MARK: - Zone effects

    /// Starts or stops the firmware MOVE effect on all selected multizone lights.
    /// `paletteColor` is used to pre-paint a brightness gradient so the scroll is visible.
    /// Pulse (.pulse) is a software effect driven by the ACC tick — it never calls here.
    /// Idempotent via effectActiveIDs; probe-race safe (skips if deviceType unknown).
    func setZoneEffect(_ effect: ZoneEffect, active: Bool, paletteColor: LIFXColor? = nil) {
        let selected = lights.filter { selectedIDs.contains($0.id) }
        for light in selected {
            let knownType = deviceTypeByID[light.id]
            if active {
                guard let dt = knownType, dt.isMultizone else { continue }
                guard !effectActiveIDs.contains(light.id) else { continue }
                let zones = zoneCountByID[light.id] ?? 60
                switch effect {
                case .moveToward, .moveAway:
                    // LIFX LAN spec: direction is the SECOND parameter field (bytes 4-7).
                    // 0 = TOWARDS (toward zone 0), 1 = AWAY (toward max zone).
                    let dir: UInt32 = effect == .moveToward ? 0 : 1
                    if let c = paletteColor {
                        control.setExtendedColorZonesGradient(ip: light.ip, targetHex: light.id,
                                                              color: c, zoneCount: zones,
                                                              reversed: false)
                    }
                    control.setMultizoneEffect(ip: light.ip, targetHex: light.id, effect: .move,
                                               speedMs: 3000, parameter: dir)
                case .none, .breathe, .pulse, .strobe, .comet, .rainbow,
                     .police, .heartbeat, .lava, .lightning, .vuMeter:
                    break  // software effects are driven by the ACC tick loop; never reach here
                }
                effectActiveIDs.insert(light.id)
                print("\u{2728} [LIFX] \(light.label) effect \(effect.rawValue) ON")
                // Readback: verify device actually accepted the effect
                let lightIP = light.ip; let lightID = light.id; let lightLabel = light.label
                Task {
                    try? await Task.sleep(nanoseconds: 600_000_000)  // 600ms — after retransmits settle
                    await control.getMultiZoneEffect(ip: lightIP, targetHex: lightID)
                    print("✨ [LIFX] \(lightLabel) readback done")
                }
            } else {
                guard effectActiveIDs.contains(light.id) else { continue }
                control.stopMultizoneEffect(ip: light.ip, targetHex: light.id)
                effectActiveIDs.remove(light.id)
                print("\u{2728} [LIFX] \(light.label) effect OFF")
            }
        }
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

    // MARK: - Polling

    private func startPollingAllLights(everySeconds: Double) {
        pollTask?.cancel()
        pollTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.refreshStates(forLights: self.lights)
                try? await Task.sleep(nanoseconds: UInt64(everySeconds * 1_000_000_000))
            }
        }
    }

    /// Polling loop: refresh power/color state for all lights.
    /// For multizone devices, also read per-zone colors and Wi-Fi signal.
    private func refreshStates(forLights lights: [LIFXLight]) async {
        for light in lights {
            if Task.isCancelled { return }

            // Basic state (power + color) — works for all device types
            if let state = await control.getLightState(ip: light.ip, targetHex: light.id, timeoutSeconds: 1.0) {
                powerByID[light.id] = state.powerOn
                colorByID[light.id] = state.color
                if brightnessDebounce[light.id] == nil {
                    brightnessByID[light.id] = state.color.briU16
                }
            }

            // Multizone: read actual per-zone colors so colorByID stays accurate
            // even if another app (e.g. LIFX app) changed the strip mid-session.
            if (deviceTypeByID[light.id] ?? .bulb).isMultizone,
               let zoneCount = zoneCountByID[light.id], zoneCount > 0 {
                if let zoneColors = await control.getZoneColors(
                    ip: light.ip, targetHex: light.id, zoneCount: zoneCount, timeoutSeconds: 1.5) {
                    zoneColorsByID[light.id] = zoneColors
                    // Keep colorByID in sync with zone 0 as a representative value
                    colorByID[light.id] = zoneColors[0]
                }
            }

            // Wi-Fi signal — polled every cycle so the UI can warn about weak links
            if let dBm = await control.getWifiSignalDBm(ip: light.ip, targetHex: light.id, timeoutSeconds: 1.0) {
                wifiSignalDBmByID[light.id] = dBm
            }
        }
    }

    // MARK: - Apply explicit HSB (raw)

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
            let dt    = deviceTypeByID[light.id] ?? .bulb
            let zones = zoneCountByID[light.id]  ?? 0
            control.setColorDispatch(ip: light.ip, targetHex: light.id, color: c,
                                     deviceType: dt, zoneCount: zones, durationMs: durationMs)
            colorByID[light.id] = c
        }
    }

    // MARK: - Device type probing

    /// Sends GetVersion (type 32) and maps the product ID to LIFXDeviceType.
    /// Also fetches firmware version (GetHostFirmware) in parallel.
    /// Updates deviceTypeByID, zoneCountByID, firmwareByID on @MainActor.
    private func probeDeviceType(_ light: LIFXLight) async {
        guard let (dt, zc, label) = await control.getDeviceTypeAndZoneCount(ip: light.ip, targetHex: light.id) else {
            print("🔍 [LIFX] \(light.ip) — no StateVersion response, defaulting to Bulb")
            await MainActor.run { self.deviceTypeByID[light.id] = .bulb }
            return
        }

        // Fetch firmware version alongside the device type probe — one extra round trip
        // on first discovery; result is cached in firmwareByID for the session.
        let fw = await control.getFirmwareVersion(ip: light.ip, targetHex: light.id)

        print("🔍 [LIFX] \(light.ip) -> \(dt) zones=\(zc) label='\(label ?? "—")' fw=\(fw?.description ?? "?")")
        await MainActor.run {
            self.deviceTypeByID[light.id] = dt
            self.zoneCountByID[light.id]  = zc
            if let fw { self.firmwareByID[light.id] = fw }
            // Sync deviceType, zoneCount, and label back into the lights array
            if let idx = self.lights.firstIndex(where: { $0.id == light.id }) {
                self.lights[idx].deviceType = dt
                self.lights[idx].productID  = nil
                if let label, !label.isEmpty {
                    self.lights[idx].label = label
                    print("🏷 [LIFX] \(light.ip) label from control: '\(label)'")
                }
            }
        }
    }
}
