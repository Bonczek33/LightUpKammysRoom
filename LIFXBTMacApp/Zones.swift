//
//  Zones.swift
//  LIFXBTMacApp
//
//  Created by Tomasz Bak on 2/16/26.
//

import Foundation

struct Zone: Identifiable, Hashable {
    let id: Int              // 1..7
    let name: String         // "Z1"
    let low: Double          // inclusive
    let high: Double?        // exclusive, nil => no upper bound
    let paletteIndex: Int    // 0..6 in ZwiftZonePalette
    let label: String
}

enum ZoneDefs {
    // thresholds in ratio units (0..)
    static let zones: [Zone] = [
        .init(id: 1, name: "Z1", low: 0.00, high: 0.60, paletteIndex: 0, label: "Easy"),
        .init(id: 2, name: "Z2", low: 0.60, high: 0.70, paletteIndex: 1, label: "Endurance"),
        .init(id: 3, name: "Z3", low: 0.70, high: 0.80, paletteIndex: 2, label: "Tempo"),
        .init(id: 4, name: "Z4", low: 0.80, high: 0.90, paletteIndex: 3, label: "Threshold"),
        .init(id: 5, name: "Z5", low: 0.90, high: 1.00, paletteIndex: 4, label: "VO2"),
        .init(id: 6, name: "Z6", low: 1.00, high: 1.10, paletteIndex: 5, label: "Anaerobic"),
        .init(id: 7, name: "Z7", low: 1.10, high: nil,  paletteIndex: 6, label: "Sprint"),
    ]

    static func zone(for ratio: Double) -> Zone {
        let r = max(0, ratio)
        for z in zones {
            if let hi = z.high {
                if r >= z.low && r < hi { return z }
            } else {
                if r >= z.low { return z }
            }
        }
        return zones.last!
    }
}

