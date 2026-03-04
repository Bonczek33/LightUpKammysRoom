//
//  AutoColorController.swift
//  LIFXBTMacApp
//
//  FIXES:
//  1. Bug 1 – Double pushPowerSample: tick() computes smoothedPowerRatio once
//     and passes it into calculateModulatedBrightness. The brightness method
//     no longer calls pushPowerSample, fixing the corrupted moving-average window.
//  2. Bug 2 – Stale send: shouldSendUpdate forces a resend after 30 s even when
//     color appears unchanged, so externally-changed lights recover automatically.
//  3. Bug 11 – HR ratio clamped to 1.0 so zones with thresholds >1.0 (defined
//     for %FTP) are never incorrectly entered via the heart-rate path.
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
    @Published var powerMovingAverageSeconds: Double = 2.0
    @Published private(set) var lastZoneID: Int? = nil
    @Published private(set) var lastInputText: String = "—"
    @Published private(set) var appliedPaletteIndex: Int? = nil
    @Published private(set) var appliedIntensityPercent: Double? = nil

    var dateOfBirth: Date = UserConfigStore.defaultsDOB
    var ftp: Int = 150
    var weightKg: Double = 70.0
    var modulateIntensityWithHR: Bool = false
    var minIntensityPercent: Double = 10.0
    var maxIntensityPercent: Double = 100.0
    var modulateIntensityWithPower: Bool = false
    var minPowerIntensityPercent: Double = 10.0
    var maxPowerIntensityPercent: Double = 100.0
    var activeZones: [Zone] = ZoneDefs.zones

    weak var lifx: LIFXDiscoveryViewModel?
    weak var bt: BluetoothSensorsViewModel?
    weak var antPlus: ANTPlusSensorViewModel?
    var useANTPlus: Bool = false

    private var task: Task<Void, Never>?
    private let smoothingTimeConstant: Double = 0.25
    private let sampleInterval: Double = 0.25

    /// Re-send after this interval even if color looks unchanged,
    /// recovering lights modified externally (LIFX app / power cycle).
    private let stalenessTimeout: TimeInterval = 30.0

    private var smoothedRatio: Double? = nil
    private var lastSampleT: TimeInterval? = nil
    private var lastSource: Source = .off

    private var lastSentT: TimeInterval = 0
    private var lastSentHue: UInt16?
    private var lastSentSat: UInt16?
    private var lastSentKelvin: UInt16?
    private var lastSentBrightness: UInt16?

    private var powerSamples: [Int] = []
    private var powerSampleCap: Int = 0

    private var activeHR: Int?      { useANTPlus ? antPlus?.heartRateBPM : bt?.heartRateBPM }
    private var activePower: Int?   { useANTPlus ? antPlus?.powerWatts   : bt?.powerWatts   }
    private var activeCadence: Int? { useANTPlus ? antPlus?.cadenceRPM   : bt?.cadenceRPM   }

    func bind(lifx: LIFXDiscoveryViewModel, bt: BluetoothSensorsViewModel,
              antPlus: ANTPlusSensorViewModel? = nil, useANTPlus: Bool = false) {
        task?.cancel(); task = nil
        self.lifx = lifx; self.bt = bt; self.antPlus = antPlus; self.useANTPlus = useANTPlus
        resetSmoothing()
        startLoop()
        print("✅ [AutoColor] Bound to LIFX and \(useANTPlus ? "ANT+" : "BLE"), starting control loop")
    }

    func stop() {
        task?.cancel(); task = nil
        resetSmoothing()
        print("🛑 [AutoColor] Stopped control loop")
    }

    var ageYears: Int {
        max(0, Calendar.current.dateComponents([.year], from: dateOfBirth, to: Date()).year ?? 0)
    }
    var maxHR: Int { max(80, 220 - ageYears) }

    // MARK: - Private

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
                    print("ℹ️ [AutoColor] Control loop cancelled"); break
                }
            }
            print("🛑 [AutoColor] Control loop ended")
        }
    }

    private func resetSmoothing() {
        smoothedRatio = nil; lastSampleT = nil; lastZoneID = nil
        lastSentT = 0; lastSentHue = nil; lastSentSat = nil
        lastSentKelvin = nil; lastSentBrightness = nil
        powerSamples.removeAll(); powerSampleCap = 0
    }

    private func updatePowerSampleCap() {
        let seconds = max(0.0, min(10.0, powerMovingAverageSeconds))
        if seconds == 0 { powerSampleCap = 0; powerSamples.removeAll(); return }
        let cap = max(1, Int((seconds / sampleInterval).rounded()))
        if cap != powerSampleCap {
            powerSampleCap = cap
            if powerSamples.count > cap { powerSamples = Array(powerSamples.suffix(cap)) }
        }
    }

    /// Push one power sample and return the moving average.
    /// MUST be called exactly once per tick per sensor path.
    /// calculateModulatedBrightness must NOT call this — it receives a pre-computed ratio.
    private func pushPowerSample(_ w: Int) -> Int {
        updatePowerSampleCap()
        guard powerSampleCap > 0 else { return w }
        powerSamples.append(w)
        if powerSamples.count > powerSampleCap {
            powerSamples.removeFirst(powerSamples.count - powerSampleCap)
        }
        return Int(Double(powerSamples.reduce(0, +)) / Double(powerSamples.count))
    }

    private func tick() async {
        guard let lifx else { return }

        if source != lastSource {
            lastSource = source; resetSmoothing()
            print("ℹ️ [AutoColor] Source changed to: \(source.rawValue)")
        }

        guard source != .off else {
            if lastInputText != "—" { resetSmoothing(); lastInputText = "—" }
            return
        }
        guard !lifx.selectedIDs.isEmpty else {
            if lastInputText != "Select lights" { resetSmoothing(); lastInputText = "Select lights" }
            return
        }

        // FIX 1: pushPowerSample is called at most ONCE per tick.
        // smoothedPowerRatio is forwarded to calculateModulatedBrightness
        // so it never needs to call pushPowerSample itself.
        let rawRatio: Double?
        var smoothedPowerRatio: Double? = nil

        switch source {
        case .heartRate:
            guard let bpm = activeHR else {
                if lastInputText != "HR: —" { lastInputText = "HR: —"; resetSmoothing() }
                return
            }
            lastInputText = "HR: \(bpm) / \(maxHR)  (age \(ageYears))"
            // FIX 11: clamp to 1.0 — HR cannot exceed maxHR; zone thresholds
            // above 1.0 are defined for %FTP and must not be entered via HR.
            rawRatio = min(1.0, Double(bpm) / Double(maxHR))
            // Pre-compute power ratio for optional intensity modulation (one push only).
            if let wRaw = activePower {
                let wSmoothed = pushPowerSample(wRaw)
                smoothedPowerRatio = Double(wSmoothed) / Double(max(1, ftp))
            }

        case .power:
            guard let wRaw = activePower else {
                if lastInputText != "Pwr: —" { lastInputText = "Pwr: —"; resetSmoothing() }
                return
            }
            let wCtrl = pushPowerSample(wRaw)   // ← the one and only push this tick
            let ftpSafe = max(1, ftp)
            lastInputText = powerMovingAverageSeconds > 0
                ? "Pwr: \(wRaw)W (avg \(wCtrl)W) / FTP \(ftpSafe)"
                : "Pwr: \(wRaw)W / FTP \(ftpSafe)"
            let ratio = Double(wCtrl) / Double(ftpSafe)
            rawRatio = ratio
            smoothedPowerRatio = ratio   // reused for modulation — no second push

        case .off:
            rawRatio = nil
        }

        guard let r = rawRatio else { return }

        // EMA smoothing on ratio
        let now = Date().timeIntervalSinceReferenceDate
        let dt: Double
        if let last = lastSampleT { dt = max(0.0, min(2.0, now - last)) } else { dt = 0.0 }
        lastSampleT = now
        if smoothedRatio == nil || dt == 0 {
            smoothedRatio = r
        } else {
            let alpha = 1.0 - exp(-dt / smoothingTimeConstant)
            smoothedRatio = (smoothedRatio ?? r) + alpha * (r - (smoothedRatio ?? r))
        }
        guard let rs = smoothedRatio else { return }

        let zone = ZoneDefs.zone(for: rs, in: activeZones)
        appliedPaletteIndex = zone.paletteIndex
        if lastZoneID != zone.id {
            print("🎨 [AutoColor] Zone change: Z\(lastZoneID ?? 0) → Z\(zone.id)")
            lastZoneID = zone.id
        }

        let p = ZwiftZonePalette.colors[zone.paletteIndex]
        let modulatedBrightness = calculateModulatedBrightness(zone: zone,
                                                                smoothedPowerRatio: smoothedPowerRatio)

        if let finalBrightness = modulatedBrightness {
            if shouldSendUpdate(hue: p.hueU16, sat: p.satU16, kelvin: p.kelvin,
                                brightness: finalBrightness, now: now) {
                lifx.applyAutoPaletteIndexToSelected(zone.paletteIndex, durationMs: 450,
                                                     brightness: finalBrightness)
                recordSent(hue: p.hueU16, sat: p.satU16, kelvin: p.kelvin,
                           brightness: finalBrightness, t: now)
            }
        } else {
            appliedIntensityPercent = nil
            if shouldSendUpdate(hue: p.hueU16, sat: p.satU16, kelvin: p.kelvin,
                                brightness: nil, now: now) {
                lifx.applyAutoPaletteIndexToSelected(zone.paletteIndex, durationMs: 450)
                recordSent(hue: p.hueU16, sat: p.satU16, kelvin: p.kelvin,
                           brightness: nil, t: now)
            }
        }
    }

    /// Determine modulated brightness.
    /// - Parameter smoothedPowerRatio: pre-computed from tick() — do NOT call pushPowerSample here.
    private func calculateModulatedBrightness(zone: Zone, smoothedPowerRatio: Double?) -> UInt16? {
        switch source {
        case .power:
            if modulateIntensityWithHR, let hrBPM = activeHR {
                let i = calculateHRIntensityModulation(hrBPM: hrBPM, zone: zone)
                appliedIntensityPercent = max(0, min(100, i * 100))
                return UInt16(max(0, min(65535, i * 65535)))
            } else if modulateIntensityWithPower, let ratio = smoothedPowerRatio {
                let i = calculatePowerIntensityModulation(powerRatio: ratio, zone: zone)
                appliedIntensityPercent = max(0, min(100, i * 100))
                return UInt16(max(0, min(65535, i * 65535)))
            }
        case .heartRate:
            if modulateIntensityWithPower, let ratio = smoothedPowerRatio {
                let i = calculatePowerIntensityModulation(powerRatio: ratio, zone: zone)
                appliedIntensityPercent = max(0, min(100, i * 100))
                return UInt16(max(0, min(65535, i * 65535)))
            } else if modulateIntensityWithHR, let hrBPM = activeHR {
                let i = calculateHRIntensityModulation(hrBPM: hrBPM, zone: zone)
                appliedIntensityPercent = max(0, min(100, i * 100))
                return UInt16(max(0, min(65535, i * 65535)))
            }
        case .off: break
        }
        return nil
    }

    private func calculateHRIntensityModulation(hrBPM: Int, zone: Zone) -> Double {
        let clamped = max(0.0, min(1.0, Double(hrBPM) / Double(maxHR)))
        let zoneRatio: Double
        if let hi = zone.high {
            zoneRatio = min(1, max(0, (clamped - zone.low) / max(0.000001, hi - zone.low)))
        } else {
            zoneRatio = min(1, max(0, (clamped - zone.low) / max(0.000001, 1.0 - zone.low)))
        }
        return (minIntensityPercent / 100.0) + zoneRatio * ((maxIntensityPercent - minIntensityPercent) / 100.0)
    }

    private func calculatePowerIntensityModulation(powerRatio: Double, zone: Zone) -> Double {
        let clamped = max(0.0, min(2.0, powerRatio))
        let zoneRatio: Double
        if let hi = zone.high {
            zoneRatio = min(1, max(0, (clamped - zone.low) / max(0.000001, hi - zone.low)))
        } else {
            zoneRatio = min(1, max(0, (clamped - zone.low) / max(0.000001, 1.5 - zone.low)))
        }
        return (minPowerIntensityPercent / 100.0) + zoneRatio * ((maxPowerIntensityPercent - minPowerIntensityPercent) / 100.0)
    }

    /// FIX 2: Forces a resend after stalenessTimeout even when color matches,
    /// so lights changed externally recover within ~30 s.
    private func shouldSendUpdate(hue: UInt16, sat: UInt16, kelvin: UInt16,
                                   brightness: UInt16?, now: TimeInterval) -> Bool {
        let stale = (now - lastSentT) >= stalenessTimeout
        let changed = lastSentHue == nil || lastSentHue != hue
            || lastSentSat != sat || lastSentKelvin != kelvin
            || lastSentBrightness != brightness
        return changed || stale
    }

    private func recordSent(hue: UInt16, sat: UInt16, kelvin: UInt16,
                             brightness: UInt16?, t: TimeInterval) {
        lastSentHue = hue; lastSentSat = sat; lastSentKelvin = kelvin
        lastSentBrightness = brightness; lastSentT = t
    }
}
