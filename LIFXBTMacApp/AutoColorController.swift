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
    @Published private(set) var lastInputText: String = "—"
    @Published private(set) var appliedPaletteIndex: Int? = nil
    @Published private(set) var appliedIntensityPercent: Double? = nil

    // Bindings to store values
    var dateOfBirth: Date = UserConfigStore.defaultsDOB
    var ftp: Int = 150
    var weightKg: Double = 70.0
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

    // Moving-average storage for power control
    private var powerSamples: [Int] = []
    private var powerSampleCap: Int = 0

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
        lastZoneID = nil
        lastSentT = 0
        lastSentHue = nil
        lastSentSat = nil
        lastSentKelvin = nil
        lastSentBrightness = nil

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
        guard let lifx else {
            // No bindings yet
            return
        }

        if source != lastSource {
            lastSource = source
            resetSmoothing()
            print("ℹ️ [AutoColor] Source changed to: \(source.rawValue)")
        }

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

        case .power:
            guard let wRaw = activePower else {
                if lastInputText != "Pwr: —" {
                    lastInputText = "Pwr: —"
                    resetSmoothing()
                }
                return
            }

            // Apply moving-average ONLY for control
            let wCtrl = pushPowerSample(wRaw)
            let ftpSafe = max(1, ftp)

            if powerMovingAverageSeconds > 0 {
                lastInputText = "Pwr: \(wRaw)W (avg \(wCtrl)W) / FTP \(ftpSafe)"
            } else {
                lastInputText = "Pwr: \(wRaw)W / FTP \(ftpSafe)"
            }

            rawRatio = Double(wCtrl) / Double(ftpSafe)

        case .off:
            rawRatio = nil
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
        
        // Only log zone changes to reduce console spam
        if lastZoneID != zone.id {
            print("🎨 [AutoColor] Zone change: Z\(lastZoneID ?? 0) → Z\(zone.id)")
            lastZoneID = zone.id
        }

        // Apply discrete zone color
        let p = ZwiftZonePalette.colors[zone.paletteIndex]
        
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
    private func calculateModulatedBrightness(zone: Zone) -> UInt16? {
        switch source {
        case .power:
            // When source is Power, can modulate intensity with HR (existing behavior)
            // or with power position within zone
            if modulateIntensityWithHR, let hrBPM = activeHR {
                let intensity = calculateHRIntensityModulation(hrBPM: hrBPM, zone: zone)
                appliedIntensityPercent = max(0.0, min(100.0, intensity * 100.0))
                return UInt16(max(0, min(65535, intensity * 65535.0)))
            } else if modulateIntensityWithPower, let wRaw = activePower {
                let ftpSafe = max(1, ftp)
                // Apply moving-average smoothing (same window as zone control)
                let wSmoothed = pushPowerSample(wRaw)
                let powerRatio = Double(wSmoothed) / Double(ftpSafe)
                let intensity = calculatePowerIntensityModulation(powerRatio: powerRatio, zone: zone)
                appliedIntensityPercent = max(0.0, min(100.0, intensity * 100.0))
                return UInt16(max(0, min(65535, intensity * 65535.0)))
            }
            
        case .heartRate:
            // When source is HR, can modulate intensity with power position within zone
            // or with HR position within zone
            if modulateIntensityWithPower, let wRaw = activePower {
                let ftpSafe = max(1, ftp)
                // Apply moving-average smoothing to power for intensity modulation
                let wSmoothed = pushPowerSample(wRaw)
                let powerRatio = Double(wSmoothed) / Double(ftpSafe)
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
    
    /// Calculate intensity modulation based on HR position within zone
    /// Extracted for testability and clarity
    private func calculateHRIntensityModulation(hrBPM: Int, zone: Zone) -> Double {
        // Calculate HR ratio (0.0 to 1.0)
        let hrRatio = Double(hrBPM) / Double(maxHR)
        let clampedHRRatio = max(0.0, min(1.0, hrRatio))
        
        // Find HR position within current zone
        let zoneHRRatio: Double
        if let zoneHigh = zone.high {
            // Zone has upper bound - map HR within zone bounds
            let zoneSpan = max(0.000001, zoneHigh - zone.low)
            zoneHRRatio = min(1.0, max(0.0, (clampedHRRatio - zone.low) / zoneSpan))
        } else {
            // Last zone (no upper bound) - use 0.0 at zone start, 1.0 at maxHR
            let zoneSpan = max(0.000001, 1.0 - zone.low)
            zoneHRRatio = min(1.0, max(0.0, (clampedHRRatio - zone.low) / zoneSpan))
        }
        
        // Map zone position to intensity range
        let minIntensity = minIntensityPercent / 100.0
        let maxIntensity = maxIntensityPercent / 100.0
        let intensityRange = maxIntensity - minIntensity
        let intensity = minIntensity + (zoneHRRatio * intensityRange)
        
        return intensity
    }
    
    /// Calculate intensity modulation based on power ratio position within zone
    /// Mirrors HR modulation logic but uses power/FTP ratio instead of HR/maxHR
    private func calculatePowerIntensityModulation(powerRatio: Double, zone: Zone) -> Double {
        let clampedRatio = max(0.0, min(2.0, powerRatio))
        
        // Find power position within current zone
        let zonePositionRatio: Double
        if let zoneHigh = zone.high {
            let zoneSpan = max(0.000001, zoneHigh - zone.low)
            zonePositionRatio = min(1.0, max(0.0, (clampedRatio - zone.low) / zoneSpan))
        } else {
            // Last zone (no upper bound) - use 0.0 at zone start, 1.0 at ~1.5x threshold
            let zoneSpan = max(0.000001, 1.5 - zone.low)
            zonePositionRatio = min(1.0, max(0.0, (clampedRatio - zone.low) / zoneSpan))
        }
        
        // Map zone position to intensity range (using power-specific min/max)
        let minIntensity = minPowerIntensityPercent / 100.0
        let maxIntensity = maxPowerIntensityPercent / 100.0
        let intensityRange = maxIntensity - minIntensity
        let intensity = minIntensity + (zonePositionRatio * intensityRange)
        
        return intensity
    }
    
    /// Determine if we should send an update to avoid redundant commands
    private func shouldSendUpdate(hue: UInt16, sat: UInt16, kelvin: UInt16, brightness: UInt16?) -> Bool {
        return lastSentHue == nil ||
               lastSentHue != hue ||
               lastSentSat != sat ||
               lastSentKelvin != kelvin ||
               lastSentBrightness != brightness
    }
}
