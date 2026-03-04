//
//  Models.swift
//  LIFXBTMacApp
//
//  ADDED: LIFXDeviceType enum — distinguishes single-zone bulbs from
//  multizone devices (LIFX Z lightstrip, LIFX Beam, LIFX Neon).
//  Type is detected during discovery via GetVersion/StateVersion (type 32/33)
//  and stored on LIFXLight so the control layer can choose the right
//  set-color command.
//

import Foundation
import SwiftUI

// MARK: - Device Type

/// Whether a LIFX device is a single-zone bulb or a multizone strip/neon.
enum LIFXDeviceType: String, Codable, CaseIterable {
    /// Ordinary bulb or single-zone tile — uses SetColor (type 102).
    case bulb       = "Bulb"
    /// LIFX Z lightstrip gen 1/2, LIFX Beam — uses SetExtendedColorZones (type 510).
    case lightstrip = "Lightstrip"
    /// LIFX Neon — uses SetExtendedColorZones (type 510).
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

    /// True when the device uses multizone Extended colour commands.
    var isMultizone: Bool {
        switch self {
        case .bulb:              return false
        case .lightstrip, .neon: return true
        }
    }

    // MARK: Product registry
    // Source: https://github.com/LIFX/products/blob/master/products.json (vendor 1 = LiFi Labs)
    // Last updated: 2026-03. Add new IDs here as LIFX releases new products.

    /// Returns the device type for a known LIFX product ID.
    /// Returns nil for unrecognised IDs — callers log the PID and default to .bulb.
    static func from(productID: UInt32) -> LIFXDeviceType? {
        switch productID {

        // -- Multizone: LIFX Z (lightstrip) ----------------------------------
        case 31, 32:        return .lightstrip  // LIFX Z gen 1 (AU/US)
        case 38:            return .lightstrip  // LIFX Beam
        case 55:            return .lightstrip  // LIFX Z 2018 refresh
        case 81, 82:        return .lightstrip  // LIFX Lightstrip 2021

        // -- Multizone: LIFX Neon --------------------------------------------
        case 96:                         return .neon  // LIFX Neon (2023)
        case 141:                        return .neon  // LIFX Neon US (2024)
        case 142:                        return .neon  // LIFX Neon Intl (2024)
        case 160, 161, 162, 163:         return .neon  // Neon regional variants

        // -- Single-zone bulbs & panels --------------------------------------
        case 1, 3:                       return .bulb  // Original LIFX (2013-14)
        case 10, 11, 18, 20:             return .bulb  // Color 1000 / White 800
        case 22, 27, 28, 29:             return .bulb  // Color 650 / A19 / BR30
        case 36:                         return .bulb  // LIFX+ infrared
        case 43, 44, 45:                 return .bulb  // A19 / BR30 2018
        case 49, 50, 51, 52, 53:         return .bulb  // Mini range
        case 57, 58, 59, 60:             return .bulb  // GU10 / Candle
        case 68, 70, 71:                 return .bulb  // Night Vision / Filament
        case 87, 88, 89, 90, 91, 92,
             93, 94, 95:                 return .bulb  // Candle Color / Downlight / Ceiling
        case 97, 98, 99, 100, 101,
             102, 103, 104:              return .bulb  // A19 2022+ / Color 1100
        case 105, 106, 107, 108, 109,
             110, 111, 112, 113, 114:    return .bulb  // Candle 2022+ / panels
        case 115, 116, 117, 118, 119,
             120, 121, 122:              return .bulb  // Clean / Path / Ceiling 2023+
        case 181, 182:                   return .bulb  // LIFX Color US/Intl (2024)

        default:
            // Product ID not yet in registry.
            // Check Xcode console for "UNKNOWN PID" lines and report the number
            // so it can be added above.
            return nil
        }
    }

} // end LIFXDeviceType

// MARK: - LIFX Light

struct LIFXLight: Identifiable, Hashable {
    let id: String            // MAC-based hex (16 chars)
    var label: String
    var ip: String
    /// Device type, populated from StateVersion during discovery.
    /// Defaults to .bulb until the response arrives.
    var deviceType: LIFXDeviceType = .bulb
    /// Raw product ID from StateVersion, kept for diagnostics / future use.
    var productID: UInt32? = nil
    /// Number of addressable colour zones (multizone devices only). 0 = not yet known.
    var zoneCount: Int = 0
}

// MARK: - LIFX Color

struct LIFXColor: Hashable {
    var hue: Double
    var saturation: Double
    var brightness: Double
    var hueU16: UInt16
    var satU16: UInt16
    var briU16: UInt16
    var kelvin: UInt16
}
