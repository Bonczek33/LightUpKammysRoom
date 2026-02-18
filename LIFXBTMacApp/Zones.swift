//
//  Zones.swift
//  LIFXBTMacApp
//
//  Created by Tomasz Bak on 2/16/26.
//

import Foundation

struct Zone: Identifiable, Hashable {
    let id: Int              // 1..6
    let name: String         // "Z1"
    let low: Double          // inclusive
    let high: Double?        // exclusive, nil => no upper bound
    let paletteIndex: Int    // 0..6 in ZwiftZonePalette
    let label: String
}

enum ZoneDefs {
    // thresholds in ratio units (0..)
    static let zones: [Zone] = [
        .init(id: 1, name: "Z1", low: 0.00, high: 0.60, paletteIndex: 0, label: "Recovery"),
        .init(id: 2, name: "Z2", low: 0.60, high: 0.75, paletteIndex: 1, label: "Endurance"),
        .init(id: 3, name: "Z3", low: 0.75, high: 0.90, paletteIndex: 2, label: "Tempo"),
        .init(id: 4, name: "Z4", low: 0.90, high: 1.05, paletteIndex: 3, label: "Threshold"),
        .init(id: 5, name: "Z5", low: 1.05, high: 1.18, paletteIndex: 4, label: "VO2 Max"),
        .init(id: 6, name: "Z6", low: 1.18, high: nil,  paletteIndex: 5, label: "Anaerobic"),
    ]

    static func zone(for ratio: Double) -> Zone {
        return zone(for: ratio, in: zones)
    }
    
    static func zone(for ratio: Double, in zoneList: [Zone]) -> Zone {
        let r = max(0, ratio)
        for z in zoneList {
            if let hi = z.high {
                if r >= z.low && r < hi { return z }
            } else {
                if r >= z.low { return z }
            }
        }
        return zoneList.last!
    }
}
