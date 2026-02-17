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
    @Published private(set) var heartRateHistory: [DataPoint] = []
    @Published private(set) var powerHistory: [DataPoint] = []
    @Published private(set) var cadenceHistory: [DataPoint] = []
    @Published private(set) var powerToWeightHistory: [DataPoint] = []
    
    // Configuration
    private let maxDataPoints = 300 // 5 minutes at 1 sample/second
    private let samplingInterval: TimeInterval = 1.0 // 1 second
    
    private var lastSampleTime: Date?
    private var sampleTimer: Task<Void, Never>?
    
    // Reference to data sources
    weak var bt: BluetoothSensorsViewModel?
    var weightKg: Double = 70.0
    
    func bind(bt: BluetoothSensorsViewModel) {
        self.bt = bt
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
                } catch {
                    break
                }
            }
        }
    }
    
    private func sampleData() {
        guard let bt else { return }
        
        let now = Date()
        
        // Only sample if we have at least one value
        let hasData = bt.heartRateBPM != nil || bt.powerWatts != nil || bt.cadenceRPM != nil
        guard hasData else { return }
        
        // Heart Rate
        if let hr = bt.heartRateBPM {
            heartRateHistory.append(DataPoint(timestamp: now, value: Double(hr)))
            if heartRateHistory.count > maxDataPoints {
                heartRateHistory.removeFirst()
            }
        }
        
        // Power
        if let power = bt.powerWatts {
            powerHistory.append(DataPoint(timestamp: now, value: Double(power)))
            if powerHistory.count > maxDataPoints {
                powerHistory.removeFirst()
            }
            
            // Power to Weight Ratio (W/kg)
            let wkg = Double(power) / max(1.0, weightKg)
            powerToWeightHistory.append(DataPoint(timestamp: now, value: wkg))
            if powerToWeightHistory.count > maxDataPoints {
                powerToWeightHistory.removeFirst()
            }
        }
        
        // Cadence
        if let cadence = bt.cadenceRPM {
            cadenceHistory.append(DataPoint(timestamp: now, value: Double(cadence)))
            if cadenceHistory.count > maxDataPoints {
                cadenceHistory.removeFirst()
            }
        }
        
        lastSampleTime = now
    }
    
    // Computed properties for chart display
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
        let windowSize: TimeInterval = 300 // 5 minutes
        return now.addingTimeInterval(-windowSize)...now
    }
    
    // Stats
    var heartRateStats: (current: Int?, avg: Int?, max: Int?) {
        let current = bt?.heartRateBPM
        guard !heartRateHistory.isEmpty else { return (current, nil, nil) }
        let values = heartRateHistory.map { Int($0.value) }
        let avg = values.reduce(0, +) / values.count
        let max = values.max()
        return (current, avg, max)
    }
    
    var powerStats: (current: Int?, avg: Int?, max: Int?) {
        let current = bt?.powerWatts
        guard !powerHistory.isEmpty else { return (current, nil, nil) }
        let values = powerHistory.map { Int($0.value) }
        let avg = values.reduce(0, +) / values.count
        let max = values.max()
        return (current, avg, max)
    }
    
    var cadenceStats: (current: Int?, avg: Int?, max: Int?) {
        let current = bt?.cadenceRPM
        guard !cadenceHistory.isEmpty else { return (current, nil, nil) }
        let values = cadenceHistory.map { Int($0.value) }
        let avg = values.reduce(0, +) / values.count
        let max = values.max()
        return (current, avg, max)
    }
    
    // MARK: - Histogram
    
    struct HistogramBucket: Identifiable {
        let id = UUID()
        let rangeLow: Double
        let rangeHigh: Double
        let midpoint: Double
        let count: Int
        let fraction: Double // 0..1 relative to max bucket
    }
    
    /// Build histogram buckets from a data point array within a given range
    static func histogram(from points: [DataPoint], range: ClosedRange<Double>, bucketCount: Int = 20) -> [HistogramBucket] {
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
            let low = range.lowerBound + Double(i) * bucketSize
            let high = low + bucketSize
            let mid = (low + high) / 2.0
            let fraction = maxCount > 0 ? Double(counts[i]) / Double(maxCount) : 0
            return HistogramBucket(rangeLow: low, rangeHigh: high, midpoint: mid, count: counts[i], fraction: fraction)
        }
    }
}
