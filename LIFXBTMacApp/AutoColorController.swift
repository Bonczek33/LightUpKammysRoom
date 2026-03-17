//
//  AutoColorController.swift
//  LIFXBTMacApp
//
//  Created by Tomasz Bak on 2/16/26.
//

import Foundation
import SwiftUI

@MainActor
final class AutoColorController: ObservableObject {
    enum Source: String, CaseIterable, Identifiable {
        case off = "Off"
        case heartRate = "Heart Rate"
        case power = "Power (FTP)"
        var id: String { rawValue }
    }

    @Published var source: Source = .off

    /// Moving average window for power control (seconds), 0 = off, max 10
    @Published var powerMovingAverageSeconds: Double = 2.0

    @Published private(set) var lastZoneID: Int? = nil
    private var lastZone: Zone? = nil
    /// Zone ID whose effect should fire on the next tick (after colour was sent this tick).
    private var effectPendingZoneID: Int? = nil
    /// Phase accumulators for software effects (0..2π unless noted).
    private var effectPhase: Double = 0        // breathe / pulse / strobe / police shared phase
    private var cometPosition: Double = 0      // 0..zoneCount, head position
    private var rainbowOffset: Double = 0      // hue offset 0..1, advances each tick
    private var lavaBlobs: [(pos: Double, size: Double, speed: Double)] = []  // lava blob state
    private var moveOffset: Double = 0       // software move: current scroll offset in zones
    // Auto effect state
    private var autoEffectActive: Bool = false          // true while an auto effect is running
    private var autoEffectStartedAt: Date? = nil        // when current auto effect began
    private var autoEffectEffect: ZoneEffect? = nil     // which effect is running
    private var lastActivityAt: Date = Date()           // last time HR or power was non-zero
    private var inactivityEffectTriggeredAt: Date? = nil // when inactivity effect last started
    private var inactivityActivationCount: Int = 0        // how many times inactivity has fired
    private var reminderLastFiredDate: Date? = nil        // calendar date of last reminder fire
    private static let inactivityMaxActivations = 2       // after this, turn lights off
    private static let autoEffectDuration: TimeInterval = 15 * 60   // 15 min
    private static let inactivityThreshold: TimeInterval = 15 * 60  // idle for 15 min before trigger
    private static let autoEffectCandidates: [ZoneEffect] = [
        .breathe, .pulse, .comet, .rainbow, .lava, .swMoveToward, .swMoveAway
    ]
    private var lightningTimer: Int = 0        // ticks until next lightning strike
    private var lightningZones: [(zone: Int, bri: Double)] = []  // active flash zones
    @Published private(set) var lastInputText: String = "—"
    @Published private(set) var appliedPaletteIndex: Int? = nil
    @Published private(set) var appliedIntensityPercent: Double? = nil

    // Bindings to store values
    var dateOfBirth: Date = UserConfigStore.defaultsDOB
    var ftp: Int = 150
    var weightKg: Double = 70.0
    var modulateEffectSpeedWithPower: Bool = false
    var minEffectSpeedPercent: Double = 30.0   // speed multiplier at bottom of zone
    var maxEffectSpeedPercent: Double = 100.0  // speed multiplier at top of zone
    // Auto effects
    var inactivityEffectEnabled: Bool = true
    var reminderEffectEnabled: Bool = true
    var reminderDays: [Int] = [0,1,2,3,4,5,6]
    var reminderHour: Int = 6
    var reminderMinute: Int = 0
    var excludedFromAutoEffectsIDs: Set<String> = []
    var modulateIntensityWithHR: Bool = false
    var minIntensityPercent: Double = 10.0
    var maxIntensityPercent: Double = 100.0
    var modulateIntensityWithPower: Bool = false
    var minPowerIntensityPercent: Double = 10.0
    var maxPowerIntensityPercent: Double = 100.0

    /// Custom zone list from settings (nil = use defaults)
    var activeZones: [Zone] = ZoneDefs.zones

    weak var lifx: LIFXDiscoveryViewModel?
    weak var bt: BluetoothSensorsViewModel?

    private var task: Task<Void, Never>?

    /// EMA smoothing time constant (250ms provides responsive but stable output)
    private let smoothingTimeConstant: Double = 0.25

    /// Sampling interval for the control loop (4 Hz / 250ms)
    private let sampleInterval: Double = 0.25

    private var smoothedRatio: Double? = nil
    private var lastSampleT: TimeInterval? = nil
    private var lastSource: Source = .off

    // Rate limit / dedupe sends
    private var lastSentT: TimeInterval = 0
    private var lastSentHue: UInt16?
    private var lastSentSat: UInt16?
    private var lastSentKelvin: UInt16?
    private var lastSentBrightness: UInt16?

    // Moving-average storage for power control.
    // FIX: only one buffer is used; pushPowerSample is called exactly once per tick
    // (for zone selection) and the result is passed through to calculateModulatedBrightness
    // via smoothedPowerRatio, eliminating the double-push bug.
    private var powerSamples: [Int] = []
    private var powerSampleCap: Int = 0

    // Cached per-tick smoothed power ratio — set in tick(), read in calculateModulatedBrightness().
    // Avoids calling pushPowerSample() a second time for brightness modulation.
    private var smoothedPowerRatioForTick: Double? = nil

    weak var antPlus: ANTPlusSensorViewModel?
    var useANTPlus: Bool = false

    // Convenience: read sensor data from whichever source is active
    private var activeHR: Int? { useANTPlus ? antPlus?.heartRateBPM : bt?.heartRateBPM }
    private var activePower: Int? { useANTPlus ? antPlus?.powerWatts : bt?.powerWatts }
    private var activeCadence: Int? { useANTPlus ? antPlus?.cadenceRPM : bt?.cadenceRPM }

    // FIXED: Proper task cancellation in bind()
    func bind(lifx: LIFXDiscoveryViewModel, bt: BluetoothSensorsViewModel, antPlus: ANTPlusSensorViewModel? = nil, useANTPlus: Bool = false) {
        // Cancel existing task before binding new instances
        task?.cancel()
        task = nil

        self.lifx = lifx
        self.bt = bt
        self.antPlus = antPlus
        self.useANTPlus = useANTPlus

        // Reset state when binding new instances
        resetSmoothing()

        startLoop()
        let source = useANTPlus ? "ANT+" : "BLE"
        print("✅ [AutoColor] Bound to LIFX and \(source), starting control loop")
    }

    func stop() {
        task?.cancel()
        task = nil
        resetSmoothing()
        lastZoneID = nil
        lastZone = nil
        effectPendingZoneID = nil
        print("🛑 [AutoColor] Stopped control loop")
    }

    var ageYears: Int {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year], from: dateOfBirth, to: Date())
        return max(0, comps.year ?? 0)
    }

    var maxHR: Int { max(80, 220 - ageYears) }

    private func startLoop() {
        task?.cancel()
        task = Task { [weak self] in
            guard let self else { return }

            print("🔄 [AutoColor] Starting control loop (sampling every \(self.sampleInterval)s)")

            while !Task.isCancelled {
                await self.tick()

                do {
                    try await Task.sleep(nanoseconds: UInt64(sampleInterval * 1_000_000_000))
                } catch {
                    // Task was cancelled
                    print("ℹ️ [AutoColor] Control loop cancelled")
                    break
                }
            }

            print("🛑 [AutoColor] Control loop ended")
        }
    }

    private func resetSmoothing() {
        smoothedRatio = nil
        lastSampleT = nil
        // NOTE: lastZoneID, lastZone, and effectPendingZoneID are intentionally NOT
        // cleared here. The two-tick effect handoff (colour tick N → effect tick N+1)
        // must survive source-change resets that happen between ticks. Clearing
        // lastZoneID would make tick N+1 see isZoneEntry=true again, sending colour
        // a second time and skipping the effect fire. The pendingID == zone.id guard
        // ensures stale state from a different zone never fires incorrectly.
        lastSentT = 0
        lastSentHue = nil
        lastSentSat = nil
        lastSentKelvin = nil
        lastSentBrightness = nil
        smoothedPowerRatioForTick = nil

        powerSamples.removeAll()
        powerSampleCap = 0
    }

    private func updatePowerSampleCap() {
        let seconds = max(0.0, min(10.0, powerMovingAverageSeconds))
        if seconds == 0 {
            powerSampleCap = 0
            powerSamples.removeAll()
            return
        }
        let cap = max(1, Int((seconds / sampleInterval).rounded()))
        if cap != powerSampleCap {
            powerSampleCap = cap
            if powerSamples.count > cap {
                powerSamples = Array(powerSamples.suffix(cap))
            }
        }
    }

    private func pushPowerSample(_ w: Int) -> Int {
        updatePowerSampleCap()
        guard powerSampleCap > 0 else { return w } // Moving average OFF

        powerSamples.append(w)
        if powerSamples.count > powerSampleCap {
            powerSamples.removeFirst(powerSamples.count - powerSampleCap)
        }

        let sum = powerSamples.reduce(0, +)
        return Int(Double(sum) / Double(powerSamples.count))
    }

    private func tick() async {
        guard let lifx else { return }

        if source != lastSource {
            let previous = lastSource
            lastSource = source
            resetSmoothing()
            print("ℹ️ [AutoColor] Source changed to: \(source.rawValue)")
            // When switching to Off, stop any active zone effect and fall back to white at 50%
            if source == .off && previous != .off && !lifx.selectedIDs.isEmpty {
                if let e = lastZone?.effect, e != .none { lifx.setZoneEffect(e, active: false) }
                let halfBrightness: UInt16 = 32767
                // Palette index 0 = Z1 Grey (sat=0, kelvin=6500) — neutral white
                lifx.applyAutoPaletteIndexToSelected(0, durationMs: 800, brightness: halfBrightness)
                appliedPaletteIndex = nil
                appliedIntensityPercent = nil
                // Full zone reset — no longer in any zone, cancel any pending effect
                lastZoneID = nil
                lastZone = nil
                effectPendingZoneID = nil
                lastInputText = "—"
                print("💡 [AutoColor] Off — reset to white 50%")
            }
        }

        // Auto effects (inactivity + reminder) — checked every tick regardless of source
        await checkAutoEffects()

        guard source != .off else {
            if lastInputText != "—" {
                resetSmoothing()
                lastInputText = "—"
            }
            return
        }

        guard !lifx.selectedIDs.isEmpty else {
            if lastInputText != "Select lights" {
                resetSmoothing()
                lastInputText = "Select lights"
            }
            return
        }

        let rawRatio: Double?
        switch source {
        case .heartRate:
            guard let bpm = activeHR else {
                if lastInputText != "HR: —" {
                    lastInputText = "HR: —"
                    resetSmoothing()
                }
                return
            }
            lastInputText = "HR: \(bpm) / \(maxHR)  (age \(ageYears))"
            rawRatio = Double(bpm) / Double(maxHR)
            // Clear cached power ratio — HR source may still use power for brightness modulation,
            // but we compute it fresh inside calculateModulatedBrightness using the live value.
            smoothedPowerRatioForTick = nil

        case .power:
            guard let wRaw = activePower else {
                if lastInputText != "Pwr: —" {
                    lastInputText = "Pwr: —"
                    resetSmoothing()
                }
                return
            }

            // FIX: pushPowerSample is called exactly once per tick here.
            // The result is stored in smoothedPowerRatioForTick so that
            // calculateModulatedBrightness can reuse it without pushing again.
            let wCtrl = pushPowerSample(wRaw)
            let ftpSafe = max(1, ftp)
            smoothedPowerRatioForTick = Double(wCtrl) / Double(ftpSafe)

            if powerMovingAverageSeconds > 0 {
                lastInputText = "Pwr: \(wRaw)W (avg \(wCtrl)W) / FTP \(ftpSafe)"
            } else {
                lastInputText = "Pwr: \(wRaw)W / FTP \(ftpSafe)"
            }

            rawRatio = smoothedPowerRatioForTick

        case .off:
            rawRatio = nil
            smoothedPowerRatioForTick = nil
        }

        guard let r = rawRatio else { return }

        // EMA smoothing on ratio
        let now = Date().timeIntervalSinceReferenceDate
        let dt: Double
        if let last = lastSampleT {
            dt = max(0.0, min(2.0, now - last))
        } else {
            dt = 0.0
        }
        lastSampleT = now

        if smoothedRatio == nil || dt == 0 {
            smoothedRatio = r
        } else {
            let alpha = 1.0 - exp(-dt / smoothingTimeConstant)
            let prev = smoothedRatio ?? r
            smoothedRatio = prev + alpha * (r - prev)
        }

        guard let rs = smoothedRatio else { return }

        let zone = ZoneDefs.zone(for: rs, in: activeZones)
        appliedPaletteIndex = zone.paletteIndex

        // Effect + colour management.
        //
        // Key constraint: SetExtendedColorZones cancels any running firmware effect.
        // So colour and effect CANNOT be sent on the same tick — the device processes
        // them in arrival order and the last one wins. UDP order is not guaranteed.
        //
        // Strategy (two-tick handoff):
        //   Tick N   (zone entry):  send colour only; set effectPendingZoneID
        //   Tick N+1 (effect tick): send effect only; clear effectPendingZoneID
        //   Tick N+2+: effect zone → suppress colour; effect alive via flameActiveIDs
        //
        // On probe-race (deviceType unknown): applyAutoPalette skips the light,
        // effectPendingZoneID stays set, colour retried next tick, effect fires after.
        let p = ZwiftZonePalette.colors[zone.paletteIndex]
        let isZoneEntry = lastZoneID != zone.id

        if isZoneEntry {
            print("🎨 [AutoColor] Zone change: Z\(lastZoneID ?? 0) → Z\(zone.id) (effect: \(zone.effect.rawValue))")
            let previousEffect = lastZone?.effect ?? .none
            // Stop any effect from the previous zone
            if previousEffect != .none {
                lifx.setZoneEffect(previousEffect, active: false)
            }
            lastZoneID = zone.id
            lastZone   = zone
            // Schedule effect for next tick; send colour this tick
            effectPendingZoneID = zone.effect.isFirmwareEffect ? zone.id : nil
            effectPhase = 0; cometPosition = 0; rainbowOffset = 0
            lavaBlobs = []; lightningTimer = 0; lightningZones = []; moveOffset = 0  // restart effects on zone entry
            stopAutoEffect()
        }

        // Tick N+1: fire the pending firmware effect now that colour has had a tick to arrive
        if let pendingID = effectPendingZoneID, pendingID == zone.id, !isZoneEntry {
            effectPendingZoneID = nil
            if zone.effect != .none {
                // Build the zone's palette colour so setZoneEffect can paint a
                // brightness gradient before MOVE starts (MOVE scrolls existing zone
                // colours — flat solid = no visible motion).
                let bri = lastSentBrightness ?? 49151
                let paletteColor = LIFXColor(
                    hue: Double(p.hueU16) / 65535.0,
                    saturation: Double(p.satU16) / 65535.0,
                    brightness: Double(bri) / 65535.0,
                    hueU16: p.hueU16, satU16: p.satU16, briU16: bri, kelvin: p.kelvin
                )
                lifx.setZoneEffect(zone.effect, active: true, paletteColor: paletteColor)
            }
            // Suppress colour this tick — don't cancel the effect we just sent
            lastSentHue    = p.hueU16
            lastSentSat    = p.satU16
            lastSentKelvin = p.kelvin
            return
        }

        // ── Software effects ─────────────────────────────────────────────────────
        // All software effects run every tick (not just zone entry) and return early
        // so the normal colour-send path is bypassed.
        if !isZoneEntry {
            switch zone.effect {

            case .breathe:
                // Slow deep sine wave: ~0.5 Hz, range 40%–100%, durationMs=400
                effectPhase += 0.13 * effectSpeedRatio(zone: zone)
                if effectPhase > 2 * .pi { effectPhase -= 2 * .pi }
                let bt = (sin(effectPhase) + 1.0) / 2.0
                let breatheBri = UInt16((0.40 + bt * 0.60) * 65535)
                lifx.applyAutoPaletteIndexToSelected(zone.paletteIndex, durationMs: 400, brightness: breatheBri, quiet: true)
                lastSentBrightness = breatheBri; lastSentT = now

            case .pulse:
                // Fast sine wave: ~2.9 Hz, range 10%–100%, durationMs=200
                effectPhase += 0.45 * effectSpeedRatio(zone: zone)
                if effectPhase > 2 * .pi { effectPhase -= 2 * .pi }
                let pt = (sin(effectPhase) + 1.0) / 2.0
                let pulseBri = UInt16((0.10 + pt * 0.90) * 65535)
                lifx.applyAutoPaletteIndexToSelected(zone.paletteIndex, durationMs: 200, brightness: pulseBri, quiet: true)
                lastSentBrightness = pulseBri; lastSentT = now

            case .strobe:
                // Binary on/off. Speed ratio controls flash rate: slow → fewer flips per tick.
                // Accumulate fractional phase; only flip when it crosses an integer.
                effectPhase += effectSpeedRatio(zone: zone)
                let strobeBri: UInt16 = Int(effectPhase) % 2 == 0 ? 65535 : 3277  // 100% / 5%
                lifx.applyAutoPaletteIndexToSelected(zone.paletteIndex, durationMs: 0, brightness: strobeBri, quiet: true)
                lastSentBrightness = strobeBri; lastSentT = now

            case .comet:
                // Bright head sweeps the strip; zones behind it decay exponentially.
                // Uses per-zone colour arrays via setExtendedColorZonesEffect.
                let zoneCount = lifx.zoneCountForSelected() ?? 60
                cometPosition = fmod(cometPosition + 1.5 * effectSpeedRatio(zone: zone), Double(zoneCount))
                lifx.setCometEffect(paletteIndex: zone.paletteIndex,
                                    zoneCount: zoneCount,
                                    headPosition: cometPosition)
                lastSentT = now

            case .rainbow:
                let zoneCount = lifx.zoneCountForSelected() ?? 60
                rainbowOffset = fmod(rainbowOffset + 0.016 * effectSpeedRatio(zone: zone), 1.0)
                lifx.setRainbowEffect(baseHueU16: p.hueU16, zoneCount: zoneCount, offset: rainbowOffset)
                lastSentT = now

            case .police:
                // Alternating red/blue halves. Speed ratio controls swap rate.
                effectPhase += effectSpeedRatio(zone: zone)
                let policeFlip = Int(effectPhase) % 4  // 0,1 = red left; 2,3 = blue left
                let zoneCount = lifx.zoneCountForSelected() ?? 60
                lifx.setPoliceEffect(zoneCount: zoneCount, flip: policeFlip < 2)
                lastSentT = now

            case .heartbeat:
                // Lub-dub double-thump. Speed ratio compresses the period at high effort.
                effectPhase += effectSpeedRatio(zone: zone)
                let beat = Int(effectPhase) % 16
                let hbBri: UInt16
                switch beat {
                case 0, 1:  hbBri = 65535        // lub — full
                case 2:     hbBri = 16383         // decay
                case 3, 4:  hbBri = 58981         // dub — strong
                case 5:     hbBri = 8191          // decay
                default:    hbBri = 3277          // rest at 5%
                }
                lifx.applyAutoPaletteIndexToSelected(zone.paletteIndex, durationMs: 0, brightness: hbBri, quiet: true)
                lastSentBrightness = hbBri; lastSentT = now

            case .lava:
                // 4–6 slow-moving brightness blobs drift along the strip
                let zoneCount = lifx.zoneCountForSelected() ?? 60
                if lavaBlobs.isEmpty {
                    // Seed blobs with random positions and speeds
                    lavaBlobs = (0..<5).map { _ in
                        (pos: Double.random(in: 0..<Double(zoneCount)),
                         size: Double.random(in: 6...14),
                         speed: Double.random(in: 0.2...0.6) * (Bool.random() ? 1 : -1))
                    }
                }
                let lavaSpeedMult = effectSpeedRatio(zone: zone)
                lavaBlobs = lavaBlobs.map { b in
                    let newPos = fmod(b.pos + b.speed * lavaSpeedMult + Double(zoneCount), Double(zoneCount))
                    return (pos: newPos, size: b.size, speed: b.speed)
                }
                lifx.setLavaEffect(paletteIndex: zone.paletteIndex, zoneCount: zoneCount, blobs: lavaBlobs)
                lastSentT = now

            case .lightning:
                // Random white spike on 1-3 zones, every 3-8 ticks
                let zoneCount = lifx.zoneCountForSelected() ?? 60
                lightningTimer -= 1
                // Decay existing flashes
                lightningZones = lightningZones.compactMap { z in
                    let newBri = z.bri * 0.4
                    return newBri > 0.05 ? (zone: z.zone, bri: newBri) : nil
                }
                if lightningTimer <= 0 {
                    // New strike
                    let strikeZone = Int.random(in: 0..<zoneCount)
                    let width = Int.random(in: 1...3)
                    for offset in -width...width {
                        let z = (strikeZone + offset + zoneCount) % zoneCount
                        lightningZones.append((zone: z, bri: 1.0))
                    }
                    // Speed ratio compresses the inter-strike interval
                    let maxWait = max(2, Int(8.0 / effectSpeedRatio(zone: zone)))
                    lightningTimer = Int.random(in: 2...maxWait)
                }
                lifx.setLightningEffect(paletteIndex: zone.paletteIndex,
                                        zoneCount: zoneCount, strikes: lightningZones)
                lastSentT = now

            case .vuMeter:
                let ratio = smoothedPowerRatioForTick ?? smoothedRatio ?? 0
                let zoneCount = lifx.zoneCountForSelected() ?? 60
                lifx.setVuMeterEffect(paletteIndex: zone.paletteIndex,
                                      zoneCount: zoneCount, fillRatio: min(1.0, max(0, ratio)))
                lastSentT = now

            case .swMoveToward, .swMoveAway:
                // Software MOVE: shift a brightness gradient by moveOffset each tick.
                // durationMs=220 (≈tick interval) lets the bulb interpolate between frames
                // so motion appears smooth despite 4 fps packet rate.
                let swZoneCount = lifx.zoneCountForSelected() ?? 60
                let step = 1.5 * effectSpeedRatio(zone: zone)
                moveOffset = fmod(
                    moveOffset + (zone.effect == .swMoveToward ? step : -step) + Double(swZoneCount),
                    Double(swZoneCount)
                )
                lifx.setSoftwareMoveEffect(paletteIndex: zone.paletteIndex,
                                           zoneCount: swZoneCount,
                                           offset: moveOffset,
                                           durationMs: 220)
                lastSentT = now

            default:
                break
            }

            if zone.effect != .none && !zone.effect.isFirmwareEffect {
                lastSentHue = p.hueU16; lastSentSat = p.satU16; lastSentKelvin = p.kelvin
                return
            }
        }

        // Suppress colour on all subsequent ticks while a firmware effect is running
        guard !zone.effect.isFirmwareEffect || isZoneEntry else {
            lastSentHue    = p.hueU16
            lastSentSat    = p.satU16
            lastSentKelvin = p.kelvin
            return
        }

        // Zone entry: send colour now (firmware effect will fire next tick via effectPendingZoneID)
        if isZoneEntry {
            let entryBrightness = calculateModulatedBrightness(zone: zone)
            if let b = entryBrightness {
                lifx.applyAutoPaletteIndexToSelected(zone.paletteIndex, durationMs: 0, brightness: b)
            } else {
                lifx.applyAutoPaletteIndexToSelected(zone.paletteIndex, durationMs: 0)
            }
            lastSentHue        = p.hueU16
            lastSentSat        = p.satU16
            lastSentKelvin     = p.kelvin
            lastSentBrightness = entryBrightness
            lastSentT          = now
            return
        }

        // Determine intensity modulation
        let modulatedBrightness: UInt16? = calculateModulatedBrightness(zone: zone)

        if let finalBrightness = modulatedBrightness {
            // Send update if color or brightness changed
            if shouldSendUpdate(hue: p.hueU16, sat: p.satU16, kelvin: p.kelvin, brightness: finalBrightness) {
                lifx.applyAutoPaletteIndexToSelected(zone.paletteIndex, durationMs: 450, brightness: finalBrightness)
                lastSentHue = p.hueU16
                lastSentSat = p.satU16
                lastSentKelvin = p.kelvin
                lastSentBrightness = finalBrightness
                lastSentT = now
            }
        } else {
            appliedIntensityPercent = nil
            // No modulation - use light's current brightness
            if shouldSendUpdate(hue: p.hueU16, sat: p.satU16, kelvin: p.kelvin, brightness: nil) {
                lifx.applyAutoPaletteIndexToSelected(zone.paletteIndex, durationMs: 450)
                lastSentHue = p.hueU16
                lastSentSat = p.satU16
                lastSentKelvin = p.kelvin
                lastSentBrightness = nil
                lastSentT = now
            }
        }
    }

    /// Determine the modulated brightness for the current source and zone.
    /// Returns nil if no modulation is active or data is unavailable.
    ///
    /// Cross-modulation: when zone colour comes from source X,
    /// brightness is modulated by the *other* metric (if enabled).
    /// HR source → power modulates intensity; Power source → HR modulates intensity.
    ///
    /// FIX: power modulation reads smoothedPowerRatioForTick (computed once in tick())
    /// instead of calling pushPowerSample() again, eliminating the double-push bug.
    private func calculateModulatedBrightness(zone: Zone) -> UInt16? {
        switch source {
        case .power:
            // Power source: HR cross-modulates brightness (priority), else power position within zone
            if modulateIntensityWithHR, let hrBPM = activeHR {
                let intensity = calculateHRIntensityModulation(hrBPM: hrBPM, zone: zone)
                appliedIntensityPercent = max(0.0, min(100.0, intensity * 100.0))
                return UInt16(max(0, min(65535, intensity * 65535.0)))
            } else if modulateIntensityWithPower, let powerRatio = smoothedPowerRatioForTick {
                // Reuse the already-smoothed ratio from tick() — no second push
                let intensity = calculatePowerIntensityModulation(powerRatio: powerRatio, zone: zone)
                appliedIntensityPercent = max(0.0, min(100.0, intensity * 100.0))
                return UInt16(max(0, min(65535, intensity * 65535.0)))
            }

        case .heartRate:
            // HR source: power cross-modulates brightness (priority), else HR position within zone
            if modulateIntensityWithPower, let wRaw = activePower {
                let ftpSafe = max(1, ftp)
                // For HR source, power is not pushed into the zone-selection buffer;
                // we compute a one-shot ratio here without touching powerSamples.
                let powerRatio = Double(wRaw) / Double(ftpSafe)
                let intensity = calculatePowerIntensityModulation(powerRatio: powerRatio, zone: zone)
                appliedIntensityPercent = max(0.0, min(100.0, intensity * 100.0))
                return UInt16(max(0, min(65535, intensity * 65535.0)))
            } else if modulateIntensityWithHR, let hrBPM = activeHR {
                let intensity = calculateHRIntensityModulation(hrBPM: hrBPM, zone: zone)
                appliedIntensityPercent = max(0.0, min(100.0, intensity * 100.0))
                return UInt16(max(0, min(65535, intensity * 65535.0)))
            }

        case .off:
            break
        }

        return nil
    }

    /// Calculate intensity modulation based on HR position within zone.
    private func calculateHRIntensityModulation(hrBPM: Int, zone: Zone) -> Double {
        let hrRatio = Double(hrBPM) / Double(maxHR)
        let clampedHRRatio = max(0.0, min(1.0, hrRatio))

        let zoneHRRatio: Double
        if let zoneHigh = zone.high {
            let zoneSpan = max(0.000001, zoneHigh - zone.low)
            zoneHRRatio = min(1.0, max(0.0, (clampedHRRatio - zone.low) / zoneSpan))
        } else {
            let zoneSpan = max(0.000001, 1.0 - zone.low)
            zoneHRRatio = min(1.0, max(0.0, (clampedHRRatio - zone.low) / zoneSpan))
        }

        let minIntensity = minIntensityPercent / 100.0
        let maxIntensity = maxIntensityPercent / 100.0
        return minIntensity + (zoneHRRatio * (maxIntensity - minIntensity))
    }

    /// Calculate intensity modulation based on power ratio position within zone.
    private func calculatePowerIntensityModulation(powerRatio: Double, zone: Zone) -> Double {
        let clampedRatio = max(0.0, min(2.0, powerRatio))

        let zonePositionRatio: Double
        if let zoneHigh = zone.high {
            let zoneSpan = max(0.000001, zoneHigh - zone.low)
            zonePositionRatio = min(1.0, max(0.0, (clampedRatio - zone.low) / zoneSpan))
        } else {
            let zoneSpan = max(0.000001, 1.5 - zone.low)
            zonePositionRatio = min(1.0, max(0.0, (clampedRatio - zone.low) / zoneSpan))
        }

        let minIntensity = minPowerIntensityPercent / 100.0
        let maxIntensity = maxPowerIntensityPercent / 100.0
        return minIntensity + (zonePositionRatio * (maxIntensity - minIntensity))
    }

    // MARK: - Auto Effects (Inactivity + Reminder)

    /// Pick a random software effect from the candidates list.
    private func randomAutoEffect() -> ZoneEffect {
        Self.autoEffectCandidates.randomElement() ?? .breathe
    }

    /// Stop any running auto effect and restore the light to idle white.
    private func stopAutoEffect() {
        guard autoEffectActive, let lifx else { return }
        autoEffectActive = false
        autoEffectStartedAt = nil
        autoEffectEffect = nil
        autoEffectPhase = 0; autoEffectCometPos = 0; autoEffectRainbowOffset = 0
        autoEffectMoveOffset = 0; autoEffectLavaBlobs = []
        // Restore to neutral white at 50%
        lifx.applyAutoPaletteIndexToSelected(0, durationMs: 800, brightness: 32767)
        print("🎨 [AutoEffect] stopped — restored white")
    }

    /// Drive the currently active auto effect for one tick.
    private func tickAutoEffect() async {
        guard autoEffectActive, let effect = autoEffectEffect, let lifx else { return }
        // Only apply to selected lights that are NOT excluded from auto effects
        let eligibleIDs = lifx.selectedIDs.filter { !excludedFromAutoEffectsIDs.contains($0) }
        guard !eligibleIDs.isEmpty else { stopAutoEffect(); return }

        // Stop if duration elapsed
        if let start = autoEffectStartedAt,
           Date().timeIntervalSince(start) >= Self.autoEffectDuration {
            stopAutoEffect()
            return
        }

        // Use palette index 0 (neutral white/grey) so auto effects are colour-neutral
        let paletteIndex = 0
        let zoneCount = lifx.zoneCountForSelected() ?? 60

        // All effect sends are scoped to eligible (non-excluded) lights only
        lifx.withSelectedIDs(eligibleIDs) {
            switch effect {
            case .breathe:
                // Full 100% ceiling, near-off floor — maximum visible contrast
                autoEffectPhase += 0.13
                if autoEffectPhase > 2 * .pi { autoEffectPhase -= 2 * .pi }
                let bt = (sin(autoEffectPhase) + 1.0) / 2.0
                lifx.applyAutoPaletteIndexToSelected(paletteIndex, durationMs: 400,
                    brightness: UInt16((0.05 + bt * 0.95) * 65535), quiet: true)

            case .pulse:
                // Full 100% ceiling, near-off floor
                autoEffectPhase += 0.45
                if autoEffectPhase > 2 * .pi { autoEffectPhase -= 2 * .pi }
                let pt = (sin(autoEffectPhase) + 1.0) / 2.0
                lifx.applyAutoPaletteIndexToSelected(paletteIndex, durationMs: 200,
                    brightness: UInt16((0.05 + pt * 0.95) * 65535), quiet: true)

            case .comet:
                autoEffectCometPos = fmod(autoEffectCometPos + 1.5, Double(zoneCount))
                lifx.setCometEffect(paletteIndex: paletteIndex, zoneCount: zoneCount,
                                    headPosition: autoEffectCometPos)

            case .rainbow:
                autoEffectRainbowOffset = fmod(autoEffectRainbowOffset + 0.016, 1.0)
                let baseHue = UInt16(0.6 * 65535)
                lifx.setRainbowEffect(baseHueU16: baseHue, zoneCount: zoneCount,
                                      offset: autoEffectRainbowOffset)

            case .lava:
                if autoEffectLavaBlobs.isEmpty {
                    autoEffectLavaBlobs = (0..<5).map { _ in
                        (pos: Double.random(in: 0..<Double(zoneCount)),
                         size: Double.random(in: 6...14),
                         speed: Double.random(in: 0.2...0.6) * (Bool.random() ? 1 : -1))
                    }
                }
                autoEffectLavaBlobs = autoEffectLavaBlobs.map { b in
                    (pos: fmod(b.pos + b.speed + Double(zoneCount), Double(zoneCount)),
                     size: b.size, speed: b.speed)
                }
                lifx.setLavaEffect(paletteIndex: paletteIndex, zoneCount: zoneCount,
                                   blobs: autoEffectLavaBlobs)

            case .swMoveToward, .swMoveAway:
                let step = 1.5
                autoEffectMoveOffset = fmod(
                    autoEffectMoveOffset + (effect == .swMoveToward ? step : -step) + Double(zoneCount),
                    Double(zoneCount)
                )
                lifx.setSoftwareMoveEffect(paletteIndex: paletteIndex, zoneCount: zoneCount,
                                           offset: autoEffectMoveOffset, durationMs: 220)

            default:
                break
            }
        }
    }

    // Separate phase state for auto effects — independent from zone effect state
    private var autoEffectPhase: Double = 0
    private var autoEffectCometPos: Double = 0
    private var autoEffectRainbowOffset: Double = 0
    private var autoEffectMoveOffset: Double = 0
    private var autoEffectLavaBlobs: [(pos: Double, size: Double, speed: Double)] = []

    /// Check and trigger inactivity and reminder auto effects each tick.
    @MainActor
    private func checkAutoEffects() async {
        guard let lifx, !lifx.selectedIDs.isEmpty else { return }

        // IDs eligible for auto effects (selected and not excluded)
        let eligibleIDs = lifx.selectedIDs.filter { !excludedFromAutoEffectsIDs.contains($0) }
        guard !eligibleIDs.isEmpty else { return }
        let anyLightOn = eligibleIDs.contains { lifx.powerByID[$0] == true }

        // Track activity — HR or power non-zero resets inactivity counter
        let isActive = (activeHR ?? 0) > 0 || (activePower ?? 0) > 0
        if isActive {
            lastActivityAt = Date()
            if inactivityActivationCount > 0 {
                inactivityActivationCount = 0
                print("💤 [AutoEffect] activity resumed — inactivity count reset")
            }
        }

        // Stop auto effect if all eligible lights turned off externally
        if autoEffectActive && !anyLightOn {
            stopAutoEffect()
            return
        }

        // If auto effect is running, tick it and return
        if autoEffectActive {
            await tickAutoEffect()
            return
        }

        let now = Date()

        // ── Reminder check ────────────────────────────────────────────────────
        // Reminder fires regardless of light state — powers on eligible lights if needed.
        if reminderEffectEnabled && !isActive {
            let cal = Calendar.current
            let comps = cal.dateComponents([.weekday, .hour, .minute], from: now)
            let weekday = (comps.weekday ?? 1) - 1
            let hour    = comps.hour   ?? 0
            let minute  = comps.minute ?? 0

            if reminderDays.contains(weekday) && hour == reminderHour && minute == reminderMinute {
                let fireKey  = cal.dateComponents([.year,.month,.day,.hour,.minute], from: now)
                let fireDate = cal.date(from: fireKey) ?? now
                if reminderLastFiredDate != fireDate {
                    reminderLastFiredDate = fireDate
                    // Power on any eligible lights that are currently off
                    lifx.powerOn(ids: eligibleIDs)
                    startAutoEffect(reason: "reminder")
                    return
                }
            }
        }

        // Inactivity only fires when lights are already on
        guard anyLightOn else { return }

        // ── Inactivity check ─────────────────────────────────────────────────
        if inactivityEffectEnabled && !isActive {
            // After max activations, turn off eligible lights instead of running another effect
            if inactivityActivationCount >= Self.inactivityMaxActivations {
                print("💤 [AutoEffect] max inactivity activations reached — turning off lights")
                lifx.withSelectedIDs(eligibleIDs) {
                    lifx.setPowerForSelected(false)
                }
                // Reset so next session can fire again once rider resumes
                inactivityActivationCount = 0
                lastActivityAt = Date()   // treat as activity to prevent re-triggering immediately
                return
            }

            let idle = now.timeIntervalSince(lastActivityAt)
            let canFire: Bool
            if let last = inactivityEffectTriggeredAt {
                canFire = idle >= Self.inactivityThreshold &&
                          now.timeIntervalSince(last) >= Self.autoEffectDuration * 2
            } else {
                canFire = idle >= Self.inactivityThreshold
            }
            if canFire {
                inactivityEffectTriggeredAt = now
                inactivityActivationCount += 1
                startAutoEffect(reason: "inactivity (\(inactivityActivationCount)/\(Self.inactivityMaxActivations))")
            }
        }
    }

    /// Start an auto effect, picking a random eligible effect.
    private func startAutoEffect(reason: String) {
        autoEffectEffect = randomAutoEffect()
        autoEffectActive = true
        autoEffectStartedAt = Date()
        print("🎨 [AutoEffect] fired: \(reason) — \(autoEffectEffect!.rawValue)")
    }

    /// Returns a speed multiplier (0.0–1.0+) based on power position within the current zone.
    /// At zone bottom → minEffectSpeedPercent/100; at zone top → maxEffectSpeedPercent/100.
    /// Returns 1.0 if modulation is disabled or no power data is available.
    private func effectSpeedRatio(zone: Zone) -> Double {
        guard modulateEffectSpeedWithPower else { return 1.0 }
        let powerRatio: Double
        if let r = smoothedPowerRatioForTick {
            powerRatio = r
        } else if let r = smoothedRatio {
            powerRatio = r
        } else {
            return 1.0
        }
        let clampedRatio = max(0.0, min(2.0, powerRatio))
        let zonePos: Double
        if let zoneHigh = zone.high {
            let span = max(0.000001, zoneHigh - zone.low)
            zonePos = min(1.0, max(0.0, (clampedRatio - zone.low) / span))
        } else {
            let span = max(0.000001, 1.5 - zone.low)
            zonePos = min(1.0, max(0.0, (clampedRatio - zone.low) / span))
        }
        let minS = minEffectSpeedPercent / 100.0
        let maxS = maxEffectSpeedPercent / 100.0
        return minS + zonePos * (maxS - minS)
    }

    /// Determine if we should send an update to avoid redundant commands.
    private func shouldSendUpdate(hue: UInt16, sat: UInt16, kelvin: UInt16, brightness: UInt16?) -> Bool {
        return lastSentHue == nil ||
               lastSentHue != hue ||
               lastSentSat != sat ||
               lastSentKelvin != kelvin ||
               lastSentBrightness != brightness
    }
}
