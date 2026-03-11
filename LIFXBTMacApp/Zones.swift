//
//  Zones.swift
//  LIFXBTMacApp
//
//  Created by Tomasz Bak on 2/16/26.
//

import Foundation

/// Light effect that fires when the rider enters a zone.
///
/// Firmware effects (multizone strip devices — Neon, Lightstrip, Beam, String only):
///   moveToward / moveAway — SetMultizoneEffect(508) type=MOVE, scrolls gradient
///
/// Software effects (driven by the 250ms ACC tick loop, work on all device types):
///   breathe  — slow deep sine-wave brightness fade (restful zones)
///   pulse    — fast brightness oscillation (threshold/VO2 intensity)
///   strobe   — binary on/off flash every tick (anaerobic sprint)
///   comet    — bright head sweeps along strip with exponential tail decay
///   rainbow  — hue rotates across all zones like a rolling colour wheel
enum ZoneEffect: String, Codable, CaseIterable, Identifiable {
    case none       = "None"
    case moveToward = "Move →"
    case moveAway   = "Move ←"
    case breathe    = "Breathe"
    case pulse      = "Pulse"
    case strobe     = "Strobe"
    case comet      = "Comet"
    case rainbow    = "Rainbow"
    case police     = "Police"
    case heartbeat  = "Heartbeat"
    case lava       = "Lava"
    case lightning  = "Lightning"
    case vuMeter    = "VU Meter"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .none:       return "minus"
        case .moveToward: return "arrow.right.circle.fill"
        case .moveAway:   return "arrow.left.circle.fill"
        case .breathe:    return "lungs.fill"
        case .pulse:      return "waveform.path.ecg"
        case .strobe:     return "bolt.fill"
        case .comet:      return "flame.fill"
        case .rainbow:    return "rainbow"
        case .police:     return "light.beacon.max.fill"
        case .heartbeat:  return "heart.fill"
        case .lava:       return "drop.fill"
        case .lightning:  return "cloud.bolt.fill"
        case .vuMeter:    return "speaker.wave.3.fill"
        }
    }

    /// True if this effect is driven by firmware (SetMultizoneEffect).
    /// False = software effect driven by the ACC tick loop.
    var isFirmwareEffect: Bool {
        switch self {
        case .moveToward, .moveAway: return true
        default:                     return false
        }
    }
}

struct Zone: Identifiable, Hashable {
    let id: Int              // 1..6
    let name: String         // "Z1"
    let low: Double          // inclusive
    let high: Double?        // exclusive, nil => no upper bound
    let paletteIndex: Int    // 0..6 in ZwiftZonePalette
    let label: String
    var effect: ZoneEffect = .none   // multizone light effect while in this zone
}

enum ZoneDefs {
    // thresholds in ratio units (0..)
    // Z6 ships with .flame by default; all others start as .none.
    static let zones: [Zone] = [
        .init(id: 1, name: "Z1", low: 0.00, high: 0.60, paletteIndex: 0, label: "Recovery",  effect: .none),
        .init(id: 2, name: "Z2", low: 0.60, high: 0.75, paletteIndex: 1, label: "Endurance", effect: .none),
        .init(id: 3, name: "Z3", low: 0.75, high: 0.90, paletteIndex: 2, label: "Tempo",     effect: .none),
        .init(id: 4, name: "Z4", low: 0.90, high: 1.05, paletteIndex: 3, label: "Threshold", effect: .none),
        .init(id: 5, name: "Z5", low: 1.05, high: 1.18, paletteIndex: 4, label: "VO2 Max",   effect: .none),
        .init(id: 6, name: "Z6", low: 1.18, high: nil,  paletteIndex: 5, label: "Anaerobic", effect: .strobe),
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
