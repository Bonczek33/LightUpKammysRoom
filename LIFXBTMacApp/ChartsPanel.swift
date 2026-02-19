//
//  ChartsPanel.swift
//  LIFXBTMacApp
//
//  Created by Tomasz Bak on 2/13/26.
//


import SwiftUI
import Charts

struct ChartsPanel: View {
    @ObservedObject var charts: ChartsViewModel
    @ObservedObject var store: UserConfigStore
    @State private var selectedChart: ChartType = .heartRate

    enum HistogramMode: String, CaseIterable, Identifiable {
        case minutes = "Minutes"
        case percent = "%"
        var id: String { rawValue }
    }
    @State private var histogramMode: HistogramMode = .percent
    
    enum ChartType: String, CaseIterable, Identifiable {
        case heartRate = "Heart Rate"
        case power = "Power"
        case cadence = "Cadence"
        case powerToWeight = "Power/Weight"
        
        var id: String { rawValue }
        
        var icon: String {
            switch self {
            case .heartRate: return "heart.fill"
            case .power: return "bolt.fill"
            case .cadence: return "gauge.with.dots.needle.bottom.50percent"
            case .powerToWeight: return "scalemass.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .heartRate: return .red
            case .power: return .orange
            case .cadence: return .blue
            case .powerToWeight: return .purple
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // Chart selector
            HStack(spacing: 12) {
                Text("Performance Charts")
                    .font(.headline)
                    .help("Real-time plots of sensor data. Up to 5 minutes of history at 1 sample/second.")
                
                Picker("Chart Type", selection: $selectedChart) {
                    ForEach(ChartType.allCases) { type in
                        Label(type.rawValue, systemImage: type.icon)
                            .tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 500)
                .help("Switch between Heart Rate, Power, Cadence, and Power-to-Weight ratio views.")
                
                Spacer()
                
                Button(action: { charts.clearAll() }) {
                    Label("Clear", systemImage: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundColor(.secondary)
                .help("Clear all chart history. New data will start accumulating immediately.")
            }
            // Charts + Histogram (inline)
            HStack(spacing: 12) {

                // Main performance chart (2/3)
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )

                    VStack(spacing: 0) {
                        // Stats bar
                        statsBar(for: selectedChart)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))

                        Divider()

                        // Time series chart
                        chartView(for: selectedChart)
                            .frame(height: 180)
                            .padding(16)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 260)
                .layoutPriority(1)

                // Histogram (1/3)
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )

                    VStack(spacing: 0) {
    HStack(spacing: 10) {
        Text("Distribution")
            .font(.subheadline)
            .foregroundColor(.secondary)
            .help("Histogram showing how much time you've spent at each intensity level.")
        Spacer()
        Picker("", selection: $histogramMode) {
            ForEach(HistogramMode.allCases) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 120)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))

    Divider()
    histogramView(for: selectedChart)
                            .frame(height: 180)
                            .padding(16)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 260)
                .layoutPriority(1)
            }
        }
    }
    
    @ViewBuilder
    private func statsBar(for type: ChartType) -> some View {
        HStack(spacing: 24) {
            switch type {
            case .heartRate:
                let stats = charts.heartRateStats
                statItem(label: "Current", value: stats.current.map { "\($0) bpm" } ?? "—", color: .red)
                statItem(label: "Average", value: stats.avg.map { "\($0) bpm" } ?? "—", color: .secondary)
                statItem(label: "Max", value: stats.max.map { "\($0) bpm" } ?? "—", color: .secondary)
                
            case .power:
                let stats = charts.powerStats
                statItem(label: "Current", value: stats.current.map { "\($0) W" } ?? "—", color: .orange)
                statItem(label: "Average", value: stats.avg.map { "\($0) W" } ?? "—", color: .secondary)
                statItem(label: "Max", value: stats.max.map { "\($0) W" } ?? "—", color: .secondary)
                
            case .cadence:
                let stats = charts.cadenceStats
                statItem(label: "Current", value: stats.current.map { "\($0) rpm" } ?? "—", color: .blue)
                statItem(label: "Average", value: stats.avg.map { "\($0) rpm" } ?? "—", color: .secondary)
                statItem(label: "Max", value: stats.max.map { "\($0) rpm" } ?? "—", color: .secondary)
                
            case .powerToWeight:
                if let current = charts.powerStats.current {
                    let wkg = Double(current) / max(1.0, charts.weightKg)
                    statItem(label: "Current", value: String(format: "%.1f W/kg", wkg), color: .purple)
                } else {
                    statItem(label: "Current", value: "—", color: .purple)
                }
                
                if !charts.powerToWeightHistory.isEmpty {
                    let values = charts.powerToWeightHistory.map(\.value)
                    let avg = values.reduce(0, +) / Double(values.count)
                    let max = values.max() ?? 0
                    statItem(label: "Average", value: String(format: "%.1f W/kg", avg), color: .secondary)
                    statItem(label: "Max", value: String(format: "%.1f W/kg", max), color: .secondary)
                } else {
                    statItem(label: "Average", value: "—", color: .secondary)
                    statItem(label: "Max", value: "—", color: .secondary)
                }
            }
            
            Spacer()
            
            // Data points count
            let count = dataPointCount(for: type)
            if count > 0 {
                Text("\(count) samples")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func statItem(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(color)
                .monospacedDigit()
        }
    }
    
    @ViewBuilder
    private func chartView(for type: ChartType) -> some View {
        switch type {
        case .heartRate:
            if charts.heartRateHistory.isEmpty {
                emptyChartPlaceholder(icon: "heart.fill", message: "No heart rate data yet")
            } else {
                Chart(charts.heartRateHistory) { point in
                    LineMark(
                        x: .value("Time", point.timestamp),
                        y: .value("HR", point.value)
                    )
                    .foregroundStyle(Color.red.gradient)
                    .interpolationMethod(.catmullRom)
                }
                .chartYScale(domain: charts.heartRateRange)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .second, count: 60)) { _ in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel(format: .dateTime.minute().second(), centered: false)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel {
                            if let intValue = value.as(Double.self) {
                                Text("\(Int(intValue))")
                                    .font(.caption)
                            }
                        }
                    }
                }
            }
            
        case .power:
            if charts.powerHistory.isEmpty {
                emptyChartPlaceholder(icon: "bolt.fill", message: "No power data yet")
            } else {
                Chart(charts.powerHistory) { point in
                    LineMark(
                        x: .value("Time", point.timestamp),
                        y: .value("Power", point.value)
                    )
                    .foregroundStyle(Color.orange.gradient)
                    .interpolationMethod(.catmullRom)
                }
                .chartYScale(domain: charts.powerRange)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .second, count: 60)) { _ in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel(format: .dateTime.minute().second(), centered: false)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel {
                            if let intValue = value.as(Double.self) {
                                Text("\(Int(intValue))")
                                    .font(.caption)
                            }
                        }
                    }
                }
            }
            
        case .cadence:
            if charts.cadenceHistory.isEmpty {
                emptyChartPlaceholder(icon: "gauge.with.dots.needle.bottom.50percent", message: "No cadence data yet")
            } else {
                Chart(charts.cadenceHistory) { point in
                    LineMark(
                        x: .value("Time", point.timestamp),
                        y: .value("Cadence", point.value)
                    )
                    .foregroundStyle(Color.blue.gradient)
                    .interpolationMethod(.catmullRom)
                }
                .chartYScale(domain: charts.cadenceRange)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .second, count: 60)) { _ in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel(format: .dateTime.minute().second(), centered: false)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel {
                            if let intValue = value.as(Double.self) {
                                Text("\(Int(intValue))")
                                    .font(.caption)
                            }
                        }
                    }
                }
            }
            
        case .powerToWeight:
            if charts.powerToWeightHistory.isEmpty {
                emptyChartPlaceholder(icon: "scalemass.fill", message: "No power/weight data yet")
            } else {
                Chart(charts.powerToWeightHistory) { point in
                    LineMark(
                        x: .value("Time", point.timestamp),
                        y: .value("W/kg", point.value)
                    )
                    .foregroundStyle(Color.purple.gradient)
                    .interpolationMethod(.catmullRom)
                }
                .chartYScale(domain: charts.powerToWeightRange)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .second, count: 60)) { _ in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel(format: .dateTime.minute().second(), centered: false)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel {
                            if let doubleValue = value.as(Double.self) {
                                Text(String(format: "%.1f", doubleValue))
                                    .font(.caption)
                            }
                        }
                    }
                }
            }
        }
    }
    
    
// MARK: - Histogram (time in zones / time in range)

private struct TimeBin: Identifiable {
    let id: String
    let label: String
    let seconds: Double
}

private func maxHeartRate() -> Double {
    // Same common approximation used elsewhere: 220 - age
    let cal = Calendar.current
    let age = cal.dateComponents([.year], from: store.dateOfBirth, to: Date()).year ?? 0
    return max(60.0, 220.0 - Double(age))
}

private func seriesFor(_ type: ChartType) -> [ChartsViewModel.DataPoint] {
    switch type {
    case .heartRate: return charts.heartRateHistory
    case .power: return charts.powerHistory
    case .cadence: return charts.cadenceHistory
    case .powerToWeight: return charts.powerToWeightHistory
    }
}

/// Converts a list of points into (value, secondsUntilNextPoint) pairs.
private func valuesWithDurations(_ points: [ChartsViewModel.DataPoint]) -> [(value: Double, dt: Double)] {
    guard !points.isEmpty else { return [] }

    // Compute dt using timestamps; clamp to avoid huge gaps (sleep/background).
    var pairs: [(Double, Double)] = []
    pairs.reserveCapacity(points.count)

    var lastDt: Double = 1.0
    for i in 0..<points.count {
        let v = points[i].value
        var dt = lastDt
        if i + 1 < points.count {
            dt = points[i + 1].timestamp.timeIntervalSince(points[i].timestamp)
            // clamp: ignore long gaps, and protect against negative/zero
            dt = min(max(dt, 0.2), 5.0)
            lastDt = dt
        }
        pairs.append((v, dt))
    }
    return pairs
}

private func timeInZones(type: ChartType) -> [TimeBin]? {
    let pairs = valuesWithDurations(seriesFor(type))
    guard !pairs.isEmpty else { return nil }

    let zones = store.activeZones

    // Determine ratio mapping
    let ratioForValue: (Double) -> Double?
    switch type {
    case .power:
        let ftp = Double(store.ftp)
        guard ftp > 0 else { return nil }
        ratioForValue = { watts in watts / ftp }
    case .heartRate:
        let maxHR = maxHeartRate()
        guard maxHR > 0 else { return nil }
        ratioForValue = { bpm in bpm / maxHR }
    default:
        return nil
    }

    // Accumulate seconds per zone
    var secondsByZone: [Int: Double] = [:]
    for z in zones { secondsByZone[z.id] = 0 }

    for (value, dt) in pairs {
        guard let ratio = ratioForValue(value) else { continue }

        if let z = zones.first(where: { ratio >= $0.low && ($0.high == nil || ratio < $0.high!) }) {
            secondsByZone[z.id, default: 0] += dt
        }
    }

    // Build bins in zone order, showing minutes
    let bins: [TimeBin] = zones.map { z in
        TimeBin(id: z.name, label: z.name, seconds: secondsByZone[z.id, default: 0])
    }
    return bins
}

private func timeInRange(type: ChartType, maxBuckets: Int = 10) -> [TimeBin] {
    let pairs = valuesWithDurations(seriesFor(type))
    guard !pairs.isEmpty else { return [] }

    let values = pairs.map { $0.value }
    guard let vMin = values.min(), let vMax = values.max() else { return [] }

    let bucketCount = max(1, min(maxBuckets, 10))
    let span = vMax - vMin
    let width = span <= 0 ? 1.0 : (span / Double(bucketCount))

    func labelFor(_ lo: Double, _ hi: Double) -> String {
        switch type {
        case .powerToWeight:
            return String(format: "%.1f–%.1f", lo, hi)
        default:
            return "\(Int(lo))–\(Int(hi))"
        }
    }

    var seconds = Array(repeating: 0.0, count: bucketCount)
    for (v, dt) in pairs {
        var idx = 0
        if span > 0 {
            idx = Int(((v - vMin) / width).rounded(.down))
            if idx >= bucketCount { idx = bucketCount - 1 }
            if idx < 0 { idx = 0 }
        }
        seconds[idx] += dt
    }

    var bins: [TimeBin] = []
    bins.reserveCapacity(bucketCount)
    for i in 0..<bucketCount {
        let lo = vMin + Double(i) * width
        let hi = (i == bucketCount - 1) ? vMax : (vMin + Double(i + 1) * width)
        bins.append(TimeBin(id: "\(i)", label: labelFor(lo, hi), seconds: seconds[i]))
    }
    return bins
}

@ViewBuilder
private func histogramView(for type: ChartType) -> some View {
    // Prefer zones for HR/Power
    let zoneBins = timeInZones(type: type)

    let useZones = (type == .heartRate || type == .power) && (zoneBins != nil)
    let bins: [TimeBin] = useZones ? (zoneBins ?? []) : timeInRange(type: type, maxBuckets: 10)
    let xTitle: String = useZones ? "Zone" : "Range"
    // Drop empty bins (0 seconds)
    let nonZeroBins = bins.filter { $0.seconds > 0 }

    if nonZeroBins.isEmpty {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 28))
                .foregroundColor(.secondary.opacity(0.5))
            Text("No data yet")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
        // Zone colors from your existing ZwiftZonePalette / zone settings.
let zoneColorByLabel: [String: Color] = {
    var dict: [String: Color] = [:]
    for z in store.activeZones {
        let i = max(0, min(ZwiftZonePalette.colors.count - 1, z.paletteIndex))
        dict[z.name] = ZwiftZonePalette.colors[i].preview
    }
    return dict
}()
let isZoneHistogram = (xTitle == "Zone")
let totalSeconds = nonZeroBins.reduce(0.0) { $0 + $1.seconds }

        // Precompute y values depending on mode
        let values: [Double] = nonZeroBins.map { b in
            switch histogramMode {
            case .minutes:
                return b.seconds / 60.0
            case .percent:
                return totalSeconds > 0 ? (b.seconds / totalSeconds) * 100.0 : 0.0
            }
        }
        let maxY = values.max() ?? 0.0
        let yUpper = maxY * 1.1 + (histogramMode == .percent ? 2.0 : 0.2)

        Chart(Array(zip(nonZeroBins, values)), id: \.0.id) { pair in
            let b = pair.0
            let y = pair.1

            BarMark(
                x: .value(xTitle, b.label),
                y: .value(histogramMode == .percent ? "Percent" : "Minutes", y)
            )
            .foregroundStyle({
    if isZoneHistogram {
        // Prefer explicit mapping from settings (Zone.paletteIndex → ZwiftZonePalette).
        if let c = zoneColorByLabel[b.label] { return c }

        // Fallback: parse "Z1".."Z7" from the label.
        let digits = b.label.filter { $0.isNumber }
        if let n = Int(digits), n > 0 {
            return zoneColorByLabel["Z\(n)"] ?? type.color
        }

        return type.color
    } else {
        return type.color
    }
}())
        }
        .chartYScale(domain: 0...yUpper)
        .chartXAxis {
            AxisMarks(position: .bottom) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let s = value.as(String.self) {
                        Text(s).font(.caption2)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        switch histogramMode {
                        case .minutes:
                            Text(v < 10 ? String(format: "%.1f min", v) : "\(Int(v)) min")
                                .font(.caption2)
                        case .percent:
                            Text("\(Int(v))%")
                                .font(.caption2)
                        }
                    }
                }
            }
        }
    }
}
private func emptyChartPlaceholder(icon: String, message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("Connect sensors and start exercising to see data")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func dataPointCount(for type: ChartType) -> Int {
        switch type {
        case .heartRate: return charts.heartRateHistory.count
        case .power: return charts.powerHistory.count
        case .cadence: return charts.cadenceHistory.count
        case .powerToWeight: return charts.powerToWeightHistory.count
        }
    }
}

