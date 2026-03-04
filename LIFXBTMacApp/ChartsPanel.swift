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
    @State private var selectedChart: ChartType = .heartRate


    enum DistributionMode: String, CaseIterable, Identifiable {
        case time = "Time"
        case percent = "%"
        var id: String { rawValue }
    }

    @State private var distributionMode: DistributionMode = .time
    enum ChartType: String, CaseIterable, Identifiable {
        case heartRate   = "Heart Rate"
        case power       = "Power"
        case cadence     = "Cadence"
        case powerToWeight = "Power/Weight"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .heartRate:     return "heart.fill"
            case .power:         return "bolt.fill"
            case .cadence:       return "gauge.with.dots.needle.bottom.50percent"
            case .powerToWeight: return "scalemass.fill"
            }
        }

        var color: Color {
            switch self {
            case .heartRate:     return .red
            case .power:         return .orange
            case .cadence:       return .blue
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
                        Label(type.rawValue, systemImage: type.icon).tag(type)
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
                .help("Clear all chart history.")
            }

            // Time series + histogram side by side
            HStack(alignment: .top, spacing: 12) {

                // Left: time series + stats
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .overlay(RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1))

                    VStack(spacing: 0) {
                        statsBar(for: selectedChart)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))

                        Divider()

                        chartView(for: selectedChart)
                            .frame(height: 180)
                            .padding(16)
                    }
                }

                // Right: histogram
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .overlay(RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1))

                    VStack(spacing: 0) {
                        HStack {
                            Text("Distribution")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .help("Time spent at each intensity level.")
                            Spacer()
                            Picker("", selection: $distributionMode) {
                                ForEach(DistributionMode.allCases) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 140)
                            .help("Show distribution as seconds (sample count) or percent of total samples.")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))

                        Divider()

                        histogramView(for: selectedChart)
                            .padding(16)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .frame(height: 260)
        }
    }

    // MARK: - Stats bar

    @ViewBuilder
    private func statsBar(for type: ChartType) -> some View {
        HStack(spacing: 24) {
            switch type {
            case .heartRate:
                let stats = charts.heartRateStats
                statItem(label: "Current", value: stats.current.map { "\($0) bpm" } ?? "—", color: .red)
                statItem(label: "Average", value: stats.avg.map     { "\($0) bpm" } ?? "—", color: .secondary)
                statItem(label: "Max",     value: stats.max.map     { "\($0) bpm" } ?? "—", color: .secondary)

            case .power:
                let stats = charts.powerStats
                statItem(label: "Current", value: stats.current.map { "\($0) W" } ?? "—", color: .orange)
                statItem(label: "Average", value: stats.avg.map     { "\($0) W" } ?? "—", color: .secondary)
                statItem(label: "Max",     value: stats.max.map     { "\($0) W" } ?? "—", color: .secondary)

            case .cadence:
                let stats = charts.cadenceStats
                statItem(label: "Current", value: stats.current.map { "\($0) rpm" } ?? "—", color: .blue)
                statItem(label: "Average", value: stats.avg.map     { "\($0) rpm" } ?? "—", color: .secondary)
                statItem(label: "Max",     value: stats.max.map     { "\($0) rpm" } ?? "—", color: .secondary)

            case .powerToWeight:
                if let current = charts.powerStats.current {
                    let wkg = Double(current) / max(1.0, charts.weightKg)
                    statItem(label: "Current", value: String(format: "%.1f W/kg", wkg), color: .purple)
                } else {
                    statItem(label: "Current", value: "—", color: .purple)
                }
                if !charts.powerToWeightHistory.isEmpty {
                    let values = charts.powerToWeightHistory.map(\.value)
                    statItem(label: "Average", value: String(format: "%.1f W/kg", values.reduce(0,+) / Double(values.count)), color: .secondary)
                    statItem(label: "Max",     value: String(format: "%.1f W/kg", values.max() ?? 0),                          color: .secondary)
                } else {
                    statItem(label: "Average", value: "—", color: .secondary)
                    statItem(label: "Max",     value: "—", color: .secondary)
                }
            }

            Spacer()

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
            Text(label).font(.caption).foregroundColor(.secondary)
            Text(value).font(.title3).fontWeight(.semibold).foregroundColor(color).monospacedDigit()
        }
    }

    // MARK: - Time series chart

    @ViewBuilder
    private func chartView(for type: ChartType) -> some View {
        switch type {
        case .heartRate:
            if charts.heartRateHistory.isEmpty {
                emptyChartPlaceholder(icon: "heart.fill", message: "No heart rate data yet")
            } else {
                Chart(charts.heartRateHistory) { point in
                    LineMark(x: .value("Time", point.timestamp), y: .value("HR", point.value))
                        .foregroundStyle(Color.red.gradient)
                        .interpolationMethod(.catmullRom)
                }
                .chartYScale(domain: charts.heartRateRange)
                .timeSeriesXAxis()
                .intYAxis()
            }

        case .power:
            if charts.powerHistory.isEmpty {
                emptyChartPlaceholder(icon: "bolt.fill", message: "No power data yet")
            } else {
                Chart(charts.powerHistory) { point in
                    LineMark(x: .value("Time", point.timestamp), y: .value("Power", point.value))
                        .foregroundStyle(Color.orange.gradient)
                        .interpolationMethod(.catmullRom)
                }
                .chartYScale(domain: charts.powerRange)
                .timeSeriesXAxis()
                .intYAxis()
            }

        case .cadence:
            if charts.cadenceHistory.isEmpty {
                emptyChartPlaceholder(icon: "gauge.with.dots.needle.bottom.50percent", message: "No cadence data yet")
            } else {
                Chart(charts.cadenceHistory) { point in
                    LineMark(x: .value("Time", point.timestamp), y: .value("Cadence", point.value))
                        .foregroundStyle(Color.blue.gradient)
                        .interpolationMethod(.catmullRom)
                }
                .chartYScale(domain: charts.cadenceRange)
                .timeSeriesXAxis()
                .intYAxis()
            }

        case .powerToWeight:
            if charts.powerToWeightHistory.isEmpty {
                emptyChartPlaceholder(icon: "scalemass.fill", message: "No power/weight data yet")
            } else {
                Chart(charts.powerToWeightHistory) { point in
                    LineMark(x: .value("Time", point.timestamp), y: .value("W/kg", point.value))
                        .foregroundStyle(Color.purple.gradient)
                        .interpolationMethod(.catmullRom)
                }
                .chartYScale(domain: charts.powerToWeightRange)
                .timeSeriesXAxis()
                .decimalYAxis()
            }
        }
    }

    // MARK: - Histogram

    @ViewBuilder
    private func histogramView(for type: ChartType) -> some View {
        switch type {

        case .heartRate:
            let buckets = ChartsViewModel.hrZoneHistogram(
                from: charts.heartRateHistory,
                zones: charts.activeZones,
                maxHR: charts.maxHR
            )
            if buckets.isEmpty {
                histogramEmpty()
            } else {
                ZoneHistogramChart(buckets: buckets, mode: distributionMode)
            }

        case .power:
            let buckets = ChartsViewModel.powerZoneHistogram(
                from: charts.powerHistory,
                zones: charts.activeZones,
                ftp: charts.ftp
            )
            if buckets.isEmpty {
                histogramEmpty()
            } else {
                ZoneHistogramChart(buckets: buckets, mode: distributionMode)
            }

        case .cadence:
            let buckets = ChartsViewModel.equalBucketHistogram(
                from: charts.cadenceHistory,
                range: charts.cadenceRange,
                bucketCount: 10
            )
            if buckets.isEmpty {
                histogramEmpty()
            } else {
                EqualHistogramChart(buckets: buckets, color: .blue, mode: distributionMode, formatLabel: { "\(Int($0))" })
            }

        case .powerToWeight:
            let buckets = ChartsViewModel.equalBucketHistogram(
                from: charts.powerToWeightHistory,
                range: charts.powerToWeightRange,
                bucketCount: 10
            )
            if buckets.isEmpty {
                histogramEmpty()
            } else {
                EqualHistogramChart(buckets: buckets, color: .purple, mode: distributionMode, formatLabel: { String(format: "%.1f", $0) })
            }
        }
    }

    private func histogramEmpty() -> some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 24))
                .foregroundColor(.secondary.opacity(0.5))
            Text("No data yet")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

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
        case .heartRate:     return charts.heartRateHistory.count
        case .power:         return charts.powerHistory.count
        case .cadence:       return charts.cadenceHistory.count
        case .powerToWeight: return charts.powerToWeightHistory.count
        }
    }
}

// MARK: - Zone Histogram Chart (HR + Power)

/// Renders one bar per training zone, colored by the zone's palette color.
private struct ZoneHistogramChart: View {
    let buckets: [ChartsViewModel.ZoneBucket]
    let mode: ChartsPanel.DistributionMode

    var body: some View {
        let total = buckets.reduce(0) { $0 + $1.count }

        Chart {
            ForEach(buckets) { bucket in
                let yValue: Double = {
                    switch mode {
                    case .time:
                        return Double(bucket.count)
                    case .percent:
                        guard total > 0 else { return 0 }
                        return Double(bucket.count) / Double(total) * 100.0
                    }
                }()

                BarMark(
                    x: .value("Zone", bucket.label),
                    y: .value(mode == .time ? "Seconds" : "Percent", yValue)
                )
                .foregroundStyle(bucket.color.opacity(0.85))
                .annotation(position: .top, alignment: .center) {
                    Text(labelText(count: bucket.count, total: total))
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .monospacedDigit()
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic) { _ in
                AxisGridLine()
                AxisTick()
                AxisValueLabel()
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        switch mode {
                        case .time:
                            Text("\(Int(v))").font(.caption)
                        case .percent:
                            Text(String(format: "%.0f%%", v)).font(.caption)
                        }
                    }
                }
            }
        }
    }

    private func labelText(count: Int, total: Int) -> String {
        switch mode {
        case .time:
            return "\(count)s"
        case .percent:
            guard total > 0 else { return "0%" }
            let pct = Double(count) / Double(total) * 100.0
            return String(format: "%.1f%%", pct)
        }
    }
}

// MARK: - Equal-bucket Histogram Chart (Cadence + W/kg)

private struct EqualHistogramChart: View {
    let buckets: [ChartsViewModel.HistogramBucket]
    let color: Color
    let mode: ChartsPanel.DistributionMode
    let formatLabel: (Double) -> String

    var body: some View {
        let total = buckets.reduce(0) { $0 + $1.count }

        Chart {
            ForEach(buckets) { bucket in
                let xLabel = "\(formatLabel(bucket.rangeLow))–\(formatLabel(bucket.rangeHigh))"

                let yValue: Double = {
                    switch mode {
                    case .time:
                        return Double(bucket.count)
                    case .percent:
                        guard total > 0 else { return 0 }
                        return Double(bucket.count) / Double(total) * 100.0
                    }
                }()

                BarMark(
                    x: .value("Range", xLabel),
                    y: .value(mode == .time ? "Seconds" : "Percent", yValue)
                )
                .foregroundStyle(color.opacity(0.75))
                .annotation(position: .top, alignment: .center) {
                    Text(labelText(count: bucket.count, total: total))
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .monospacedDigit()
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic) { _ in
                AxisGridLine()
                AxisTick()
                AxisValueLabel()
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        switch mode {
                        case .time:
                            Text("\(Int(v))").font(.caption)
                        case .percent:
                            Text(String(format: "%.0f%%", v)).font(.caption)
                        }
                    }
                }
            }
        }
    }

    private func labelText(count: Int, total: Int) -> String {
        switch mode {
        case .time:
            return "\(count)s"
        case .percent:
            guard total > 0 else { return "0%" }
            let pct = Double(count) / Double(total) * 100.0
            return String(format: "%.1f%%", pct)
        }
    }
}

// MARK: - Chart view modifiers


private extension View {
    func timeSeriesXAxis() -> some View {
        self.chartXAxis {
            AxisMarks(values: .stride(by: .second, count: 60)) { _ in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: .dateTime.minute().second(), centered: false)
            }
        }
    }

    func intYAxis() -> some View {
        self.chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let v = value.as(Double.self) { Text("\(Int(v))").font(.caption) }
                }
            }
        }
    }

    func decimalYAxis() -> some View {
        self.chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let v = value.as(Double.self) { Text(String(format: "%.1f", v)).font(.caption) }
                }
            }
        }
    }
}

