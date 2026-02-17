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
                
                Picker("Chart Type", selection: $selectedChart) {
                    ForEach(ChartType.allCases) { type in
                        Label(type.rawValue, systemImage: type.icon)
                            .tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 500)
                
                Spacer()
                
                Button(action: { charts.clearAll() }) {
                    Label("Clear", systemImage: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundColor(.secondary)
            }
            
            // Chart display
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
            .frame(height: 260)
            
            // Histogram
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                
                VStack(spacing: 0) {
                    HStack {
                        Text("Distribution")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))
                    
                    Divider()
                    
                    histogramView(for: selectedChart)
                        .frame(height: 100)
                        .padding(16)
                }
            }
            .frame(height: 160)
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
    
    private func histogramData(for type: ChartType) -> (buckets: [ChartsViewModel.HistogramBucket], color: Color, range: ClosedRange<Double>) {
        switch type {
        case .heartRate:
            return (ChartsViewModel.histogram(from: charts.heartRateHistory, range: charts.heartRateRange), .red, charts.heartRateRange)
        case .power:
            return (ChartsViewModel.histogram(from: charts.powerHistory, range: charts.powerRange), .orange, charts.powerRange)
        case .cadence:
            return (ChartsViewModel.histogram(from: charts.cadenceHistory, range: charts.cadenceRange), .blue, charts.cadenceRange)
        case .powerToWeight:
            return (ChartsViewModel.histogram(from: charts.powerToWeightHistory, range: charts.powerToWeightRange), .purple, charts.powerToWeightRange)
        }
    }
    
    @ViewBuilder
    private func histogramView(for type: ChartType) -> some View {
        let data = histogramData(for: type)
        
        if data.buckets.isEmpty {
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
            let maxCount = data.buckets.map(\.count).max() ?? 1
            Chart(data.buckets) { bucket in
                BarMark(
                    x: .value("Value", bucket.midpoint),
                    y: .value("Count", bucket.count)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [data.color.opacity(0.7), data.color.opacity(0.3)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            .chartXScale(domain: data.range)
            .chartYScale(domain: 0...(Double(maxCount) * 1.1))
            .chartXAxis {
                AxisMarks(position: .bottom) { value in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            switch type {
                            case .powerToWeight:
                                Text(String(format: "%.1f", v))
                                    .font(.caption)
                            default:
                                Text("\(Int(v))")
                                    .font(.caption)
                            }
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine()
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
