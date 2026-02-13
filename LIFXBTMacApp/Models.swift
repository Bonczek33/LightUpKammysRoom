import Foundation
import SwiftUI

struct LIFXLight: Identifiable, Hashable {
    let id: String
    var label: String
    var ip: String
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
