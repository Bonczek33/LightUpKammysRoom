//
//  ZwiftZonePalette.swift
//  LIFXBTMacApp
//
//  Created by Tomasz Bak on 2/16/26.
//

import SwiftUI

struct LIFXBasicColor: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let hueU16: UInt16
    let satU16: UInt16
    let kelvin: UInt16

    var preview: Color {
        Color(
            hue: Double(hueU16) / 65535.0,
            saturation: Double(satU16) / 65535.0,
            brightness: satU16 == 0 ? 0.65 : 0.90
        )
    }
}

func u16Hue(_ degrees: Double) -> UInt16 {
    let d = max(0, min(360, degrees))
    return UInt16(((d / 360.0) * 65535.0).rounded())
}

enum ZwiftZonePalette {
    // Available zone colors (Z7 Purple kept as option for custom zones)
    // Default 6 zones use indices 0–5
    static let colors: [LIFXBasicColor] = [
        .init(name: "Z1 Grey",   hueU16: u16Hue(0),   satU16: 0,     kelvin: 6500),
        .init(name: "Z2 Blue",   hueU16: u16Hue(210), satU16: 65535, kelvin: 3500),
        .init(name: "Z3 Green",  hueU16: u16Hue(120), satU16: 65535, kelvin: 3500),
        .init(name: "Z4 Yellow", hueU16: u16Hue(60),  satU16: 65535, kelvin: 3500),
        .init(name: "Z5 Orange", hueU16: u16Hue(30),  satU16: 65535, kelvin: 3500),
        .init(name: "Z6 Red",    hueU16: u16Hue(0),   satU16: 65535, kelvin: 3500),
        .init(name: "Z7 Purple", hueU16: u16Hue(270), satU16: 65535, kelvin: 3500),
    ]
}
