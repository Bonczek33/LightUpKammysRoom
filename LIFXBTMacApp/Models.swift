//
//  Models.swift
//  LIFXBTMacApp
//
//  Created by Tomasz Bak on 2/16/26.
//

import Foundation
import SwiftUI

struct LIFXLight: Identifiable, Hashable {
    let id: String
    var label: String
    var ip: String
    /// Populated from StateVersion during discovery. Defaults to .bulb until probed.
    var deviceType: LIFXDeviceType = .bulb
    /// Raw product ID from StateVersion, kept for diagnostics.
    var productID: UInt32? = nil
}

// MARK: - Device Type

/// Whether a LIFX device is a single-zone bulb or a multizone strip/neon.
enum LIFXDeviceType: String, Codable, CaseIterable {
    case bulb       = "Bulb"
    case lightstrip = "Lightstrip"
    case neon       = "Neon"

    var displayName: String { rawValue }

    var symbolName: String {
        switch self {
        case .bulb:              return "lightbulb.fill"
        case .lightstrip, .neon: return "light.strip.2.fill"
        }
    }

    var badgeColor: Color {
        switch self {
        case .bulb:       return .yellow
        case .lightstrip: return .cyan
        case .neon:       return .purple
        }
    }

    /// True when the device needs SetExtendedColorZones instead of SetColor.
    var isMultizone: Bool {
        switch self {
        case .bulb:              return false
        case .lightstrip, .neon: return true
        }
    }

    // Product registry — source: https://github.com/LIFX/products/blob/master/products.json
    static func from(productID: UInt32) -> LIFXDeviceType? {
        switch productID {
        // Multizone: LIFX Z / Beam / Lightstrip
        case 31, 32, 38, 55, 81, 82:            return .lightstrip
        // Multizone: LIFX Neon
        case 96, 141, 142, 160, 161, 162, 163:  return .neon
        // Single-zone bulbs (non-exhaustive — add new PIDs as needed)
        case 1, 3, 10, 11, 18, 20, 22, 27, 28, 29, 36, 43, 44, 45,
             49, 50, 51, 52, 53, 57, 58, 59, 60, 68, 70, 71,
             87, 88, 89, 90, 91, 92, 93, 94, 95,
             97, 98, 99, 100, 101, 102, 103, 104,
             105, 106, 107, 108, 109, 110, 111, 112, 113, 114,
             115, 116, 117, 118, 119, 120, 121, 122,
             181, 182:                           return .bulb
        default:
            print("⚠️ [LIFX] UNKNOWN PID \(productID) — defaulting to Bulb. Add to LIFXDeviceType.from()")
            return nil
        }
    }
}

struct LIFXColor: Hashable {
    var hue: Double
    var saturation: Double
    var brightness: Double
    var hueU16: UInt16
    var satU16: UInt16
    var briU16: UInt16
    var kelvin: UInt16
}
