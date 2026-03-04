//
//  ChartsViewModel.swift
//  LIFXBTMacApp
//
//  Created by Tomasz Bak on 2/16/26.
//

import Foundation
import SwiftUI

/// Manages historical data for charts/plots
@MainActor
final class ChartsViewModel: ObservableObject {
    struct DataPoint: Identifiable {
        let id = UUID()
        let timestamp: Date
        let value: Double
    }

    // Historical data arrays
    @Published private(set) var heartRateHistory:     [DataPoint] = []
    @Published private(set) var powerHistory:         [DataPoint] = []
    @Published private(set) var cadenceHistory:       [DataPoint] = []
    @Published private(set) var powerToWeightHistory: [DataPoint] = []

    // Configuration
    private let maxDataPoints = 300         // 5 minutes at 1 sample/second
    private let samplingInterval: TimeInterval = 1.0

    private var lastSampleTime: Date?
    private var sampleTimer: Task<Void, Never>?

    // Reference to data sources
    weak var bt: BluetoothSensorsViewModel?
    weak var antPlus: ANTPlusSensorViewModel?
    var useANTPlus: Bool = false
    var weightKg: Double = 70.0

    /// Zone list forwarded from UserConfigStore (set by ContentView via applyStore)
    var activeZones: [Zone] = ZoneDefs.zones

    /// Max heart rate forwarded from AutoColorController (set by ContentView via applyStore)
    var maxHR: Int = 190

    /// FTP forwarded from UserConfigStore (set by ContentView via applyStore)
    var ftp: Int = 150

    // Convenience: read from active source
    private var activeHR:      Int? { useANTPlus ? antPlus?.heartRateBPM : bt?.heartRateBPM }
    private var activePower:   Int? { useANTPlus ? antPlus?.powerWatts   : bt?.powerWatts   }
    private var activeCadence: Int? { useANTPlus ? antPlus?.cadenceRPM   : bt?.cadenceRPM   }

    func bind(bt: BluetoothSensorsViewModel, antPlus: ANTPlusSensorViewModel? = nil, useANTPlus: Bool = false) {
        self.bt = bt
        self.antPlus = antPlus
        self.useANTPlus = useANTPlus
        startSampling()
    }

    func stop() {
        sampleTimer?.cancel()
        sampleTimer = nil
    }

    func clearAll() {
        heartRateHistory.removeAll()
        powerHistory.removeAll()
        cadenceHistory.removeAll()
        powerToWeightHistory.removeAll()
        lastSampleTime = nil
    }

    private func startSampling() {
        sampleTimer?.cancel()
        sampleTimer = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                self.sampleData()
                do {
                    try await Task.sleep(nanoseconds: UInt64(samplingInterval * 1_000_000_000))
                } catch { break }
            }
        }
    }

    private func sampleData() {
        let now = Date()
        let hasData = activeHR != nil || activePower != nil || activeCadence != nil
        guard hasData else { return }

        if let hr = activeHR {
            heartRateHistory.append(DataPoint(timestamp: now, value: Double(hr)))
            if heartRateHistory.count > maxDataPoints { heartRateHistory.removeFirst() }
        }

        if let power = activePower {
            powerHistory.append(DataPoint(timestamp: now, value: Double(power)))
            if powerHistory.count > maxDataPoints { powerHistory.removeFirst() }

            let wkg = Double(power) / max(1.0, weightKg)
            powerToWeightHistory.append(DataPoint(timestamp: now, value: wkg))
            if powerToWeightHistory.count > maxDataPoints { powerToWeightHistory.removeFirst() }
        }

        if let cadence = activeCadence {
            cadenceHistory.append(DataPoint(timestamp: now, value: Double(cadence)))
            if cadenceHistory.count > maxDataPoints { cadenceHistory.removeFirst() }
        }

        lastSampleTime = now
    }

    // MARK: - Ranges

    var heartRateRange: ClosedRange<Double> {
        guard !heartRateHistory.isEmpty else { return 0...200 }
        let values = heartRateHistory.map(\.value)
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 200
        let padding = (maxValue - minValue) * 0.1
        return Swift.max(0, minValue - padding)...Swift.min(200, maxValue + padding)
    }

    var powerRange: ClosedRange<Double> {
        guard !powerHistory.isEmpty else { return 0...400 }
        let values = powerHistory.map(\.value)
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 400
        let padding = (maxValue - minValue) * 0.1
        return Swift.max(0, minValue - padding)...(maxValue + padding)
    }

    var cadenceRange: ClosedRange<Double> {
        guard !cadenceHistory.isEmpty else { return 0...120 }
        let values = cadenceHistory.map(\.value)
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 120
        let padding = (maxValue - minValue) * 0.1
        return Swift.max(0, minValue - padding)...Swift.min(200, maxValue + padding)
    }

    var powerToWeightRange: ClosedRange<Double> {
        guard !powerToWeightHistory.isEmpty else { return 0...6 }
        let values = powerToWeightHistory.map(\.value)
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 6
        let padding = (maxValue - minValue) * 0.1
        return Swift.max(0, minValue - padding)...(maxValue + padding)
    }

    // Time window for display
    var timeWindow: ClosedRange<Date> {
        let now = Date()
        return now.addingTimeInterval(-300)...now
    }

    // MARK: - Stats

    var heartRateStats: (current: Int?, avg: Int?, max: Int?) {
        let current = activeHR
        guard !heartRateHistory.isEmpty else { return (current, nil, nil) }
        let values = heartRateHistory.map { Int($0.value) }
        return (current, values.reduce(0,+) / values.count, values.max())
    }

    var powerStats: (current: Int?, avg: Int?, max: Int?) {
        let current = activePower
        guard !powerHistory.isEmpty else { return (current, nil, nil) }
        let values = powerHistory.map { Int($0.value) }
        return (current, values.reduce(0,+) / values.count, values.max())
    }

    var cadenceStats: (current: Int?, avg: Int?, max: Int?) {
        let current = activeCadence
        guard !cadenceHistory.isEmpty else { return (current, nil, nil) }
        let values = cadenceHistory.map { Int($0.value) }
        return (current, values.reduce(0,+) / values.count, values.max())
    }

    // MARK: - Histogram types

    /// A zone-aligned histogram bucket (HR or Power)
    struct ZoneBucket: Identifiable {
        let id = UUID()
        let zone: Zone
        let count: Int
        /// SwiftUI Color derived from the zone's palette entry
        var color: Color {
            let p = ZwiftZonePalette.colors[zone.paletteIndex]
            if p.satU16 == 0 { return Color(hue: 0, saturation: 0, brightness: 0.65) }
            return Color(hue: Double(p.hueU16) / 65535.0,
                         saturation: Double(p.satU16) / 65535.0,
                         brightness: 0.85)
        }
        var label: String { zone.name }
    }

    /// An equal-width histogram bucket (cadence, W/kg)
    struct HistogramBucket: Identifiable {
        let id = UUID()
        let rangeLow: Double
        let rangeHigh: Double
        let midpoint: Double
        let count: Int
        let fraction: Double
    }

    // MARK: - Zone histograms

    // MARK: - Convenience instance wrappers (FIX 7)
    // The static histogram methods require callers to pass maxHR/ftp/zones manually,
    // which is error-prone. These instance wrappers capture the current values.

    func hrZoneHistogram(from points: [DataPoint]) -> [ZoneBucket] {
        ChartsViewModel.hrZoneHistogram(from: points, zones: activeZones, maxHR: maxHR)
    }

    func powerZoneHistogram(from points: [DataPoint]) -> [ZoneBucket] {
        ChartsViewModel.powerZoneHistogram(from: points, zones: activeZones, ftp: ftp)
    }

        /// HR zone histogram: counts samples per zone using %maxHR thresholds.
    static func hrZoneHistogram(from points: [DataPoint], zones: [Zone], maxHR: Int) -> [ZoneBucket] {
        guard !points.isEmpty, maxHR > 0 else { return [] }
        var counts = [Int: Int]()
        for z in zones { counts[z.id] = 0 }

        for point in points {
            let ratio = point.value / Double(maxHR)
            let zone = ZoneDefs.zone(for: ratio, in: zones)
            counts[zone.id, default: 0] += 1
        }

        return zones.map { ZoneBucket(zone: $0, count: counts[$0.id] ?? 0) }
    }

    /// Power zone histogram: counts samples per zone using %FTP thresholds.
    static func powerZoneHistogram(from points: [DataPoint], zones: [Zone], ftp: Int) -> [ZoneBucket] {
        guard !points.isEmpty, ftp > 0 else { return [] }
        var counts = [Int: Int]()
        for z in zones { counts[z.id] = 0 }

        for point in points {
            let ratio = point.value / Double(ftp)
            let zone = ZoneDefs.zone(for: ratio, in: zones)
            counts[zone.id, default: 0] += 1
        }

        return zones.map { ZoneBucket(zone: $0, count: counts[$0.id] ?? 0) }
    }

    // MARK: - Equal-width histogram (cadence, W/kg)

    static func equalBucketHistogram(from points: [DataPoint],
                                     range: ClosedRange<Double>,
                                     bucketCount: Int = 10) -> [HistogramBucket] {
        guard !points.isEmpty, range.upperBound > range.lowerBound else { return [] }

        let span = range.upperBound - range.lowerBound
        let bucketSize = span / Double(bucketCount)
        var counts = [Int](repeating: 0, count: bucketCount)

        for point in points {
            var idx = Int((point.value - range.lowerBound) / bucketSize)
            idx = Swift.max(0, Swift.min(bucketCount - 1, idx))
            counts[idx] += 1
        }

        let maxCount = counts.max() ?? 1
        return (0..<bucketCount).map { i in
            let low  = range.lowerBound + Double(i) * bucketSize
            let high = low + bucketSize
            let mid  = (low + high) / 2.0
            return HistogramBucket(
                rangeLow: low, rangeHigh: high, midpoint: mid,
                count: counts[i],
                fraction: maxCount > 0 ? Double(counts[i]) / Double(maxCount) : 0
            )
        }
    }

    // MARK: - Legacy (kept for any external callers)

    static func histogram(from points: [DataPoint],
                          range: ClosedRange<Double>,
                          bucketCount: Int = 20) -> [HistogramBucket] {
        equalBucketHistogram(from: points, range: range, bucketCount: bucketCount)
    }
}

