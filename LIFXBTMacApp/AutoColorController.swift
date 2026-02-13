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

    // Bindings to store values
    var dateOfBirth: Date = UserConfigStore.defaultsDOB
    var ftp: Int = 150
    var weightKg: Double = 70.0
    var modulateIntensityWithHR: Bool = false
    var minIntensityPercent: Double = 10.0
    var maxIntensityPercent: Double = 100.0

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

    // Moving-average storage for power control
    private var powerSamples: [Int] = []
    private var powerSampleCap: Int = 0

    // FIXED: Proper task cancellation in bind()
    func bind(lifx: LIFXDiscoveryViewModel, bt: BluetoothSensorsViewModel) {
        // Cancel existing task before binding new instances
        task?.cancel()
        task = nil
        
        self.lifx = lifx
        self.bt = bt
        
        // Reset state when binding new instances
        resetSmoothing()
        
        startLoop()
        print("✅ [AutoColor] Bound to LIFX and BLE, starting control loop")
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
        guard let lifx, let bt else { 
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
            guard let bpm = bt.heartRateBPM else {
                if lastInputText != "HR: —" {
                    lastInputText = "HR: —"
                    resetSmoothing()
                }
                return
            }
            lastInputText = "HR: \(bpm) / \(maxHR)  (age \(ageYears))"
            rawRatio = Double(bpm) / Double(maxHR)

        case .power:
            guard let wRaw = bt.powerWatts else {
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

        let zone = ZoneDefs.zone(for: rs)
        
        // Only log zone changes to reduce console spam
        if lastZoneID != zone.id {
            print("🎨 [AutoColor] Zone change: Z\(lastZoneID ?? 0) → Z\(zone.id)")
            lastZoneID = zone.id
        }

        // Apply discrete zone color
        let p = ZwiftZonePalette.colors[zone.paletteIndex]
        
        // Modulate brightness based on heart rate WITHIN the current zone
        if source == .power && modulateIntensityWithHR, let hrBPM = bt.heartRateBPM {
            let intensity = calculateIntensityModulation(hrBPM: hrBPM, zone: zone)
            let finalBrightness = UInt16(max(0, min(65535, intensity * 65535.0)))
            
            // Send update if color changed
            if shouldSendUpdate(hue: p.hueU16, sat: p.satU16, kelvin: p.kelvin) {
                lifx.applyAutoPaletteIndexToSelected(zone.paletteIndex, durationMs: 450, brightness: finalBrightness)
                lastSentHue = p.hueU16
                lastSentSat = p.satU16
                lastSentKelvin = p.kelvin
                lastSentT = now
            }
        } else {
            // No modulation - use light's current brightness
            if shouldSendUpdate(hue: p.hueU16, sat: p.satU16, kelvin: p.kelvin) {
                lifx.applyAutoPaletteIndexToSelected(zone.paletteIndex, durationMs: 450)
                lastSentHue = p.hueU16
                lastSentSat = p.satU16
                lastSentKelvin = p.kelvin
                lastSentT = now
            }
        }
    }
    
    /// Calculate intensity modulation based on HR position within zone
    /// Extracted for testability and clarity
    private func calculateIntensityModulation(hrBPM: Int, zone: Zone) -> Double {
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
    
    /// Determine if we should send an update to avoid redundant commands
    private func shouldSendUpdate(hue: UInt16, sat: UInt16, kelvin: UInt16) -> Bool {
        return lastSentHue == nil || 
               lastSentHue != hue || 
               lastSentSat != sat || 
               lastSentKelvin != kelvin
    }
}
