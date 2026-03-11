//
//  LIFXLanControl.swift
//  LIFXBTMacApp
//
//  Multizone support:
//  - probeDeviceType()         GetVersion(32) -> StateVersion(33) -> LIFXDeviceType
//  - getZoneCount()            GetExtendedColorZones(511) -> StateExtendedColorZones(512)
//  - setExtendedColorZones()   SetExtendedColorZones(510) paints all zones one colour
//  - setColorDispatch()        routes to setExtendedColorZones or setColor by device type
//
//  Extended info:
//  - getWifiInfo()             GetWifiInfo(16) -> StateWifiInfo(17) -> signal RSSI (dBm)
//  - getFirmwareVersion()      GetHostFirmware(14) -> StateHostFirmware(15) -> major.minor
//  - getZoneColors()           GetColorZones(502) -> StateMultiZone(506) -> per-zone HSBK array
//  - setMultizoneEffect()      SetMultizoneEffect(508) -> MOVE animation (multizone only)
//  - stopMultizoneEffect()     SetMultizoneEffect(508) with effectType=OFF
//
//  NOTE: FLAME (type=3) is Tile/matrix-only firmware. Neon accepts the packet
//  but does nothing. Use software Pulse effect via the ACC tick loop instead.
//
//  Connection pool: idle-only cleanup (no timer-based thrashing).
//

import Foundation
import Network

final class LIFXLanControl {
    struct LightState { var powerOn: Bool; var color: LIFXColor }

    /// Firmware version returned by GetHostFirmware (14).
    struct FirmwareVersion: CustomStringConvertible {
        let major: UInt16
        let minor: UInt16
        var description: String { "\(major).\(minor)" }
    }

    /// Firmware-driven multizone animation type for SetMultizoneEffect (508).
    enum MultizoneEffectType: UInt8 {
        case off   = 0
        case move  = 1
        case flame = 3   // Tile/matrix only — NOT supported on Neon/Strip/Beam
    }

    private let lifxPort: NWEndpoint.Port = 56700
    private let queue = DispatchQueue(label: "lifx.lan.control")
    private var source: UInt32 = .random(in: 2...UInt32.max)  // avoid 0 and 1 per LIFX spec
    private var effectInstanceID: UInt32 = .random(in: 1...UInt32.max)
    private var seq: UInt8 = 0

    private let connectionLock = NSLock()
    private struct PoolEntry { let connection: NWConnection; var lastUsed: Date }
    private var connectionPool: [String: PoolEntry] = [:]
    private let maxPoolSize = 10
    private let connectionIdleTimeout: TimeInterval = 15.0

    deinit {
        connectionLock.lock()
        for (_, e) in connectionPool { e.connection.cancel() }
        connectionPool.removeAll()
        connectionLock.unlock()
    }

    // MARK: - Device type probing

    /// Sends GetVersion (32), reads StateVersion (33).
    /// Returns (LIFXDeviceType, rawProductID) or nil on timeout.
    func probeDeviceType(ip: String, targetHex: String,
                         timeoutSeconds: Double = 2.0) async -> (LIFXDeviceType, UInt32)? {
        guard let target = dataFromHex8(targetHex) else { return nil }
        let pkt = makePacket(tagged: false, target: target, type: 32, payload: Data())
        guard let reply = await sendAndReceive(ip: ip, packet: pkt, expectedType: 33, timeout: timeoutSeconds),
              reply.count >= 36 + 12 else { return nil }
        // StateVersion payload: vendor(4) product(4) version(4)
        let product = readUInt32LE(reply, offset: 36 + 4)
        let dt = LIFXDeviceType.from(productID: product) ?? .bulb
        if LIFXDeviceType.from(productID: product) == nil {
            print("⚠️ [LIFX] \(ip) UNKNOWN PID \(product) — defaulting to Bulb. Add this ID to LIFXDeviceType.from() in Models.swift")
        } else {
            print("🔍 [LIFX] \(ip) product \(product) -> \(dt.displayName)")
        }
        return (dt, product)
    }

    /// Sends GetLabel (23), reads StateLabel (25).
    /// Returns the device label string, or nil on timeout.
    func getLabel(ip: String, targetHex: String,
                  timeoutSeconds: Double = 2.0) async -> String? {
        guard let target = dataFromHex8(targetHex) else { return nil }
        let pkt = makePacket(tagged: false, target: target, type: 23, payload: Data())
        guard let reply = await sendAndReceive(ip: ip, packet: pkt, expectedType: 25, timeout: timeoutSeconds),
              reply.count >= 36 + 32 else { return nil }
        // StateLabel payload: label (32 bytes, null-terminated UTF-8)
        let labelData = reply.subdata(in: 36..<68)
        let label = String(decoding: labelData.prefix { $0 != 0 }, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return label.isEmpty ? nil : label
    }

    /// Sends GetExtendedColorZones (511), reads StateExtendedColorZones (512).
    /// Returns the zone count reported by the device, or nil on timeout.
    func getZoneCount(ip: String, targetHex: String,
                      timeoutSeconds: Double = 2.0) async -> Int? {
        guard let target = dataFromHex8(targetHex) else { return nil }
        let pkt = makePacket(tagged: false, target: target, type: 511, payload: Data())
        guard let reply = await sendAndReceive(ip: ip, packet: pkt, expectedType: 512, timeout: timeoutSeconds),
              reply.count >= 36 + 2 else { return nil }
        // StateExtendedColorZones payload: zones_count(2LE) zone_index(2LE) colors_count(1) colors(82*8)
        let count = Int(readUInt16LE(reply, offset: 36))
        print("🔍 [LIFX] \(ip) reports \(count) zones")
        return count > 0 ? count : nil
    }

    /// Combined convenience: probes device type, zone count, and label.
    /// Returns (LIFXDeviceType, zoneCount, label?) — zoneCount is 0 for bulbs.
    func getDeviceTypeAndZoneCount(ip: String, targetHex: String,
                                   timeoutSeconds: Double = 2.0) async -> (LIFXDeviceType, Int, String?)? {
        guard let (dt, _) = await probeDeviceType(ip: ip, targetHex: targetHex, timeoutSeconds: timeoutSeconds) else {
            return nil
        }
        var zoneCount = 0
        if dt.isMultizone {
            zoneCount = await getZoneCount(ip: ip, targetHex: targetHex, timeoutSeconds: timeoutSeconds) ?? 0
        }
        let label = await getLabel(ip: ip, targetHex: targetHex, timeoutSeconds: timeoutSeconds)
        return (dt, zoneCount, label)
    }

    // MARK: - Extended device info

    /// Sends GetWifiInfo (16), reads StateWifiInfo (17).
    /// Returns Wi-Fi signal strength in dBm, or nil on timeout / no response.
    ///
    /// StateWifiInfo payload layout (offset from header end = 36):
    ///   signal   Float32 (4)  — signal strength in mW; convert to dBm via 10*log10(signal)
    ///   reserved UInt32  (4)
    ///   reserved UInt32  (4)
    ///   reserved UInt16  (2)
    func getWifiSignalDBm(ip: String, targetHex: String,
                          timeoutSeconds: Double = 2.0) async -> Int? {
        guard let target = dataFromHex8(targetHex) else { return nil }
        let pkt = makePacket(tagged: false, target: target, type: 16, payload: Data())
        guard let reply = await sendAndReceive(ip: ip, packet: pkt, expectedType: 17, timeout: timeoutSeconds),
              reply.count >= 36 + 4 else { return nil }
        // signal is a float32 in milliwatts
        let raw = readUInt32LE(reply, offset: 36)
        let b0 = UInt8(raw        & 0xFF)
        let b1 = UInt8((raw >>  8) & 0xFF)
        let b2 = UInt8((raw >> 16) & 0xFF)
        let b3 = UInt8((raw >> 24) & 0xFF)
        var mw: Float = 0
        withUnsafeMutableBytes(of: &mw) { $0.copyBytes(from: [b0, b1, b2, b3]) }
        guard mw > 0 else { return nil }
        let dBm = Int((10.0 * log10(Double(mw))).rounded())
        print("📶 [LIFX] \(ip) Wi-Fi signal: \(dBm) dBm (\(mw) mW)")
        return dBm
    }

    /// Converts a raw dBm value to a 0–4 bar count for UI display.
    static func wifiBarCount(dBm: Int) -> Int {
        switch dBm {
        case ..<(-80): return 0   // very weak / dropping commands
        case -80 ..< -70: return 1
        case -70 ..< -60: return 2
        case -60 ..< -50: return 3
        default:          return 4   // -50 dBm or better
        }
    }

    /// Sends GetHostFirmware (14), reads StateHostFirmware (15).
    /// Returns (major, minor) firmware version, or nil on timeout.
    ///
    /// StateHostFirmware payload layout:
    ///   build       UInt64 (8)  — Unix timestamp of firmware build (nanoseconds)
    ///   reserved    UInt64 (8)
    ///   version     UInt32 (4)  — packed: major = bits[31:16], minor = bits[15:0]
    func getFirmwareVersion(ip: String, targetHex: String,
                            timeoutSeconds: Double = 2.0) async -> FirmwareVersion? {
        guard let target = dataFromHex8(targetHex) else { return nil }
        let pkt = makePacket(tagged: false, target: target, type: 14, payload: Data())
        guard let reply = await sendAndReceive(ip: ip, packet: pkt, expectedType: 15, timeout: timeoutSeconds),
              reply.count >= 36 + 20 else { return nil }
        // version field is at offset 36 + 8 (build) + 8 (reserved) = 36 + 16
        let packed = readUInt32LE(reply, offset: 36 + 16)
        let major  = UInt16((packed >> 16) & 0xFFFF)
        let minor  = UInt16(packed & 0xFFFF)
        print("🔧 [LIFX] \(ip) firmware \(major).\(minor)")
        return FirmwareVersion(major: major, minor: minor)
    }

    /// Sends GetColorZones (502), reads StateMultiZone (506) replies until all zones are collected.
    /// Returns an array of LIFXColor per zone (length = zoneCount), or nil on timeout.
    ///
    /// GetColorZones payload: start_index(1) end_index(1)
    /// StateMultiZone payload:
    ///   zones_count  UInt8  (1)
    ///   zone_index   UInt8  (1)
    ///   colors[8]    8 x HSBK (8 bytes each = 64 bytes total)
    ///
    /// The device sends multiple StateMultiZone replies (8 zones per packet).
    /// We use sendAndReceiveMultiple to collect all of them within the timeout.
    func getZoneColors(ip: String, targetHex: String,
                       zoneCount: Int,
                       timeoutSeconds: Double = 2.0) async -> [LIFXColor]? {
        guard zoneCount > 0, let target = dataFromHex8(targetHex) else { return nil }
        var payload = Data()
        payload.append(UInt8(0))                     // start_index
        payload.append(UInt8(min(zoneCount - 1, 255))) // end_index
        let pkt = makePacket(tagged: false, target: target, type: 502, payload: payload)
        // Collect up to ceil(zoneCount/8) replies
        let expectedReplies = (zoneCount + 7) / 8
        let replies = await sendAndReceiveMultiple(ip: ip, packet: pkt, expectedType: 506,
                                                   count: expectedReplies, timeout: timeoutSeconds)
        guard !replies.isEmpty else { return nil }

        var colors = [LIFXColor?](repeating: nil, count: zoneCount)
        for reply in replies {
            // payload starts at offset 36: zones_count(1) zone_index(1) colors[8 x 8]
            guard reply.count >= 36 + 2 + 64 else { continue }
            let startZone = Int(reply[36 + 1])
            for i in 0..<8 {
                let zoneIdx = startZone + i
                guard zoneIdx < zoneCount else { break }
                let base = 36 + 2 + i * 8
                guard reply.count >= base + 8 else { break }
                let h = readUInt16LE(reply, offset: base)
                let s = readUInt16LE(reply, offset: base + 2)
                let b = readUInt16LE(reply, offset: base + 4)
                let k = readUInt16LE(reply, offset: base + 6)
                colors[zoneIdx] = LIFXColor(hue: Double(h)/65535.0, saturation: Double(s)/65535.0,
                                            brightness: Double(b)/65535.0,
                                            hueU16: h, satU16: s, briU16: b, kelvin: k)
            }
        }
        let result = colors.compactMap { $0 }
        guard result.count == zoneCount else { return nil }
        return result
    }

    // MARK: - Multizone effects

    /// Sends SetMultizoneEffect (508) to start a firmware-driven animation.
    ///
    /// SetMultizoneEffect payload layout (LIFX public-protocol spec, total 59 bytes):
    ///   instanceid  UInt32   (4)  — arbitrary effect instance ID; use 0
    ///   type        UInt8    (1)  — 0=OFF, 1=MOVE, 3=FLAME
    ///   reserved    UInt16   (2)
    ///   speed       UInt32   (4)  — ms per animation cycle
    ///   duration    UInt64   (8)  — total run time ns (0 = run forever)
    ///   reserved    UInt32   (4)
    ///   reserved    UInt32   (4)
    ///   parameters  [UInt8] (32)  — MultiZoneEffectParameter; for MOVE byte[0]=direction
    ///                               (0=toward, 1=away); all others zero
    func setMultizoneEffect(ip: String, targetHex: String,
                            effect: MultizoneEffectType,
                            speedMs: UInt32 = 5000,
                            durationNs: UInt64 = 0,
                            parameter: UInt32 = 0) {
        guard let target = dataFromHex8(targetHex) else { return }
        // Each effect invocation gets a unique instanceID — some firmware uses this
        // to distinguish new effects from duplicate retransmissions.
        effectInstanceID &+= 1
        var payload = Data()
        payload.append(withBytes(effectInstanceID.littleEndian))       // instanceid  (4)
        payload.append(effect.rawValue)                                // type        (1)
        payload.append(withBytes(UInt16(0).littleEndian))              // reserved    (2)
        payload.append(withBytes(speedMs.littleEndian))                // speed       (4)
        payload.append(withBytes(durationNs.littleEndian))             // duration    (8)
        payload.append(withBytes(UInt32(0).littleEndian))              // reserved    (4)
        payload.append(withBytes(UInt32(0).littleEndian))              // reserved    (4)
        // parameters: 32-byte block of 8x UInt32 fields.
        // Per LIFX LAN spec: for MOVE, the SECOND field (bytes 4-7) is the
        // direction enum. 0=TOWARDS, 1=AWAY. The first field is reserved/ignored.
        var params = Data(count: 32)
        if parameter != 0 {
            let p = parameter.littleEndian
            withUnsafeBytes(of: p) { params.replaceSubrange(4..<8, with: $0) }
        }
        payload.append(params)                                         // parameters (32)
        // Sanity check: payload must be exactly 59 bytes
        assert(payload.count == 59, "SetMultizoneEffect payload must be 59 bytes, got \(payload.count)")
        // Send with ack_required=1 and 3x retransmit — effect messages are
        // heavier state changes and silently dropped more often than colour ticks.
        let pkt = makePacketAck(tagged: false, target: target, type: 508, payload: payload)
        sendReliable(toIP: ip, packet: pkt)
        print("✨ [LIFX] \(ip) SetMultizoneEffect type=\(effect) speed=\(speedMs)ms payload=\(payload.count)b")
    }

    /// Sends GetMultiZoneEffect (507), reads StateMultiZoneEffect (509).
    ///
    /// StateMultiZoneEffect payload = MultiZoneEffectSettings (59 bytes):
    ///   instanceid  UInt32  (4)
    ///   type        UInt8   (1)   0=OFF 1=MOVE 3=FLAME
    ///   reserved    UInt16  (2)
    ///   speed       UInt32  (4)   ms per cycle
    ///   duration    UInt64  (8)   ns remaining (0=infinite)
    ///   reserved    UInt32  (4)
    ///   reserved    UInt32  (4)
    ///   parameters  [UInt8] (32)
    ///
    /// Returns (instanceid, type, speedMs) or nil on timeout.
    @discardableResult
    func getMultiZoneEffect(ip: String, targetHex: String,
                            timeoutSeconds: Double = 2.0) async -> (instanceID: UInt32, type: UInt8, speedMs: UInt32)? {
        guard let target = dataFromHex8(targetHex) else { return nil }
        let pkt = makePacket(tagged: false, target: target, type: 507, payload: Data())
        guard let reply = await sendAndReceive(ip: ip, packet: pkt, expectedType: 509, timeout: timeoutSeconds),
              reply.count >= 36 + 9 else {
            print("✨ [LIFX] \(ip) GetMultiZoneEffect — no reply (timeout or unsupported)")
            return nil
        }
        let instanceID = readUInt32LE(reply, offset: 36)
        let effectType = reply[36 + 4]
        let speedMs    = readUInt32LE(reply, offset: 36 + 7)
        let typeName: String
        switch effectType {
        case 0: typeName = "OFF"
        case 1: typeName = "MOVE"
        case 3: typeName = "FLAME"
        default: typeName = "UNKNOWN(\(effectType))"
        }
        print("✨ [LIFX] \(ip) StateMultiZoneEffect: type=\(typeName) instanceID=\(instanceID) speed=\(speedMs)ms")
        return (instanceID: instanceID, type: effectType, speedMs: speedMs)
    }

    /// Convenience: stops any running firmware animation on a multizone device.
    func stopMultizoneEffect(ip: String, targetHex: String) {
        setMultizoneEffect(ip: ip, targetHex: targetHex, effect: .off)
    }

    // MARK: - Single-zone control

    func getLightState(ip: String, targetHex: String,
                       timeoutSeconds: Double = 1.0) async -> LightState? {
        guard let target = dataFromHex8(targetHex) else { return nil }
        let pkt = makePacket(tagged: false, target: target, type: 101, payload: Data())
        guard let reply = await sendAndReceive(ip: ip, packet: pkt, expectedType: 107, timeout: timeoutSeconds),
              reply.count >= 36 + 12 else { return nil }
        let o = 36
        let hueU16 = readUInt16LE(reply, offset: o)
        let satU16 = readUInt16LE(reply, offset: o + 2)
        let briU16 = readUInt16LE(reply, offset: o + 4)
        let kelvin = readUInt16LE(reply, offset: o + 6)
        let power  = readUInt16LE(reply, offset: o + 10)
        let color  = LIFXColor(hue: Double(hueU16)/65535.0, saturation: Double(satU16)/65535.0,
                               brightness: Double(briU16)/65535.0,
                               hueU16: hueU16, satU16: satU16, briU16: briU16, kelvin: kelvin)
        return LightState(powerOn: power > 0, color: color)
    }

    func setPower(ip: String, targetHex: String, on: Bool, durationMs: UInt32 = 0) {
        guard let target = dataFromHex8(targetHex) else { return }
        let level: UInt16 = on ? 65535 : 0
        var payload = Data()
        payload.append(withBytes(level.littleEndian))
        payload.append(withBytes(durationMs.littleEndian))
        sendFast(toIP: ip, packet: makePacket(tagged: false, target: target, type: 117, payload: payload))
    }

    func setColor(ip: String, targetHex: String, color: LIFXColor, durationMs: UInt32 = 0) {
        guard let target = dataFromHex8(targetHex) else { return }
        var payload = Data()
        payload.append(UInt8(0))
        payload.append(withBytes(color.hueU16.littleEndian))
        payload.append(withBytes(color.satU16.littleEndian))
        payload.append(withBytes(color.briU16.littleEndian))
        payload.append(withBytes(color.kelvin.littleEndian))
        payload.append(withBytes(durationMs.littleEndian))
        sendFast(toIP: ip, packet: makePacket(tagged: false, target: target, type: 102, payload: payload))
    }

    // MARK: - Multizone control

    /// Paints every zone of a multizone device (Lightstrip / Neon) with one uniform HSBK.
    ///
    /// SetExtendedColorZones (type 510) payload:
    ///   duration(4LE)  apply(1)=1  zone_index(2LE)=0  colors_count(2LE)
    ///   colors[N x 8]: hue(2) sat(2) bri(2) kelvin(2) each LE
    ///
    /// zoneCount: pass the value from getZoneCount(). Pass 0 when unknown —
    /// the firmware ignores entries beyond its actual zone count.
    func setExtendedColorZones(ip: String, targetHex: String,
                               color: LIFXColor, zoneCount: Int,
                               durationMs: UInt32 = 0) {
        guard let target = dataFromHex8(targetHex) else { return }
        // Per LIFX LAN spec (type 510):
        //   duration    Uint32  (4 bytes)
        //   apply       Uint8   (1 byte)  — 1 = APPLY
        //   zone_index  Uint16  (2 bytes) — first zone to apply from
        //   colors_count Uint8  (1 byte)  — number of active colors
        //   colors      82 x Color (82 * 8 = 656 bytes) — ALWAYS 82 entries, zero-pad unused
        let activeCount = zoneCount > 0 ? min(zoneCount, 82) : 82
        var payload = Data()
        payload.append(withBytes(durationMs.littleEndian))   // duration    (4)
        payload.append(UInt8(1))                             // apply=APPLY (1)
        payload.append(withBytes(UInt16(0).littleEndian))    // zone_index  (2)
        payload.append(UInt8(activeCount))                   // colors_count (1) ← was UInt16, off by 1 byte
        // Always write exactly 82 Color entries (spec fixed-size)
        for i in 0..<82 {
            if i < activeCount {
                payload.append(withBytes(color.hueU16.littleEndian))
                payload.append(withBytes(color.satU16.littleEndian))
                payload.append(withBytes(color.briU16.littleEndian))
                payload.append(withBytes(color.kelvin.littleEndian))
            } else {
                payload.append(contentsOf: [UInt8](repeating: 0, count: 8))
            }
        }
        sendFast(toIP: ip, packet: makePacket(tagged: false, target: target, type: 510, payload: payload))
    }

    /// Paints each zone with an individually specified HSBK colour.
    /// `colors` is a flat array of (hue, sat, bri, kelvin) tuples, one per zone.
    /// Used by software effects (comet, rainbow) that need per-zone control.
    func setExtendedColorZonesArray(ip: String, targetHex: String,
                                    colors: [(h: UInt16, s: UInt16, b: UInt16, k: UInt16)]) {
        guard let target = dataFromHex8(targetHex), !colors.isEmpty else { return }
        let activeCount = min(colors.count, 82)
        var payload = Data()
        payload.append(withBytes(UInt32(0).littleEndian))    // duration = 0
        payload.append(UInt8(1))                             // apply = APPLY
        payload.append(withBytes(UInt16(0).littleEndian))    // zone_index = 0
        payload.append(UInt8(activeCount))                   // colors_count
        for i in 0..<82 {
            if i < activeCount {
                payload.append(withBytes(colors[i].h.littleEndian))
                payload.append(withBytes(colors[i].s.littleEndian))
                payload.append(withBytes(colors[i].b.littleEndian))
                payload.append(withBytes(colors[i].k.littleEndian))
            } else {
                payload.append(contentsOf: [UInt8](repeating: 0, count: 8))
            }
        }
        sendFast(toIP: ip, packet: makePacket(tagged: false, target: target, type: 510, payload: payload))
    }

    /// Paints a repeating sawtooth brightness gradient across all zones.
    /// Used as the colour canvas before starting a MOVE effect — MOVE scrolls
    /// whatever colours are in the zones, so a flat colour produces no motion.
    ///
    /// Pattern (per 10-zone period): full brightness → dark → full brightness
    /// hue and saturation are fixed from `color`; only brightness varies.
    /// `reversed`: flip the gradient direction so the bright→dark slope matches
    /// the MOVE scroll direction and produces visible motion.
    func setExtendedColorZonesGradient(ip: String, targetHex: String,
                                       color: LIFXColor, zoneCount: Int,
                                       reversed: Bool = false) {
        guard let target = dataFromHex8(targetHex) else { return }
        let activeCount = zoneCount > 0 ? min(zoneCount, 82) : 82
        let period = 10
        var payload = Data()
        payload.append(withBytes(UInt32(0).littleEndian))
        payload.append(UInt8(1))
        payload.append(withBytes(UInt16(0).littleEndian))
        payload.append(UInt8(activeCount))
        for i in 0..<82 {
            if i < activeCount {
                let idx = reversed ? (activeCount - 1 - i) : i
                let phase = Double(idx % period) / Double(period)
                let t = 1.0 - abs(phase - 0.5) * 2.0
                let bri = UInt16(max(0.05, t) * 65535)
                payload.append(withBytes(color.hueU16.littleEndian))
                payload.append(withBytes(color.satU16.littleEndian))
                payload.append(withBytes(bri.littleEndian))
                payload.append(withBytes(color.kelvin.littleEndian))
            } else {
                payload.append(contentsOf: [UInt8](repeating: 0, count: 8))
            }
        }
        sendFast(toIP: ip, packet: makePacket(tagged: false, target: target, type: 510, payload: payload))
    }

    /// Dispatches to setExtendedColorZones (multizone) or setColor (bulb).
    /// Multizone devices always receive durationMs=0: a non-zero transition causes
    /// the firmware to sweep colour zone-by-zone, which looks like a one-zone offset.
    func setColorDispatch(ip: String, targetHex: String, color: LIFXColor,
                          deviceType: LIFXDeviceType, zoneCount: Int,
                          durationMs: UInt32 = 0) {
        if deviceType.isMultizone {
            setExtendedColorZones(ip: ip, targetHex: targetHex, color: color,
                                  zoneCount: zoneCount, durationMs: 0)
        } else {
            setColor(ip: ip, targetHex: targetHex, color: color, durationMs: durationMs)
        }
    }

    // MARK: - Private: request/response

    private func sendAndReceive(ip: String, packet: Data,
                                expectedType: UInt16, timeout: Double) async -> Data? {
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(ip), port: lifxPort)
        let conn = NWConnection(to: endpoint, using: .udp)
        conn.start(queue: queue)
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            conn.send(content: packet, completion: .contentProcessed { _ in cont.resume() })
        }
        let result: Data? = await withTaskGroup(of: Data?.self) { group in
            group.addTask {
                await withCheckedContinuation { (cont: CheckedContinuation<Data?, Never>) in
                    conn.receiveMessage { data, _, _, _ in cont.resume(returning: data) }
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        conn.cancel()
        guard let reply = result, reply.count >= 36 else { return nil }
        let pktType = readUInt16LE(reply, offset: 32)
        guard pktType == expectedType else { return nil }
        return reply
    }

    /// Like sendAndReceive but collects up to `count` matching replies within `timeout`.
    /// Used for GetColorZones which produces one StateMultiZone packet per 8 zones.
    private func sendAndReceiveMultiple(ip: String, packet: Data,
                                        expectedType: UInt16,
                                        count: Int,
                                        timeout: Double) async -> [Data] {
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(ip), port: lifxPort)
        let conn = NWConnection(to: endpoint, using: .udp)
        conn.start(queue: queue)
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            conn.send(content: packet, completion: .contentProcessed { _ in cont.resume() })
        }

        var collected: [Data] = []
        let deadline = Date().addingTimeInterval(timeout)

        while collected.count < count && Date() < deadline {
            let remaining = max(0.05, deadline.timeIntervalSinceNow)
            let reply: Data? = await withTaskGroup(of: Data?.self) { group in
                group.addTask {
                    await withCheckedContinuation { (cont: CheckedContinuation<Data?, Never>) in
                        conn.receiveMessage { data, _, _, _ in cont.resume(returning: data) }
                    }
                }
                group.addTask {
                    try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
                    return nil
                }
                let first = await group.next() ?? nil
                group.cancelAll()
                return first
            }
            guard let r = reply, r.count >= 36 else { break }
            let pktType = readUInt16LE(r, offset: 32)
            if pktType == expectedType { collected.append(r) }
        }

        conn.cancel()
        return collected
    }

    // MARK: - Private: connection pool (idle-only cleanup)

    private func sendFast(toIP ip: String, packet: Data) {
        connectionLock.lock()
        if var entry = connectionPool[ip], entry.connection.state == .ready {
            entry.lastUsed = Date()
            connectionPool[ip] = entry
            connectionLock.unlock()
            entry.connection.send(content: packet, completion: .contentProcessed { _ in })
            return
        }
        let cutoff = Date().addingTimeInterval(-connectionIdleTimeout)
        for (k, e) in connectionPool where e.connection.state != .ready || e.lastUsed < cutoff {
            e.connection.cancel(); connectionPool.removeValue(forKey: k)
        }
        if connectionPool.count >= maxPoolSize,
           let oldest = connectionPool.min(by: { $0.value.lastUsed < $1.value.lastUsed })?.key {
            connectionPool[oldest]?.connection.cancel()
            connectionPool.removeValue(forKey: oldest)
        }
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(ip), port: lifxPort)
        let conn = NWConnection(to: endpoint, using: .udp)
        connectionPool[ip] = PoolEntry(connection: conn, lastUsed: Date())
        connectionLock.unlock()
        conn.stateUpdateHandler = { [weak self] state in
            if case .failed(let error) = state {
                print("conn failed [LIFX] \(ip): \(error)")
                self?.removeFromPool(ip: ip)
            }
        }
        conn.start(queue: queue)
        conn.send(content: packet, completion: .contentProcessed { _ in })
        queue.asyncAfter(deadline: .now() + connectionIdleTimeout) { [weak self] in
            guard let self else { return }
            self.connectionLock.lock()
            if let entry = self.connectionPool[ip],
               Date().timeIntervalSince(entry.lastUsed) >= self.connectionIdleTimeout {
                entry.connection.cancel()
                self.connectionPool.removeValue(forKey: ip)
            }
            self.connectionLock.unlock()
        }
    }

    private func removeFromPool(ip: String) {
        connectionLock.lock()
        connectionPool.removeValue(forKey: ip)?.connection.cancel()
        connectionLock.unlock()
    }

    // MARK: - Private: packet helpers

    /// Sends a packet 3 times with a small gap — for state-change messages where
    /// fire-and-forget is unreliable (e.g. SetMultizoneEffect).
    private func sendReliable(toIP ip: String, packet: Data) {
        sendFast(toIP: ip, packet: packet)
        queue.asyncAfter(deadline: .now() + 0.04) { [weak self] in self?.sendFast(toIP: ip, packet: packet) }
        queue.asyncAfter(deadline: .now() + 0.10) { [weak self] in self?.sendFast(toIP: ip, packet: packet) }
    }

    private func makePacket(tagged: Bool, target: Data, type: UInt16, payload: Data) -> Data {
        var header = Data(count: 36)
        header.replaceSubrange(0..<2, with: withBytes(UInt16(36 + payload.count).littleEndian))
        let frame: UInt16 = 0x0400 | 0x1000 | (tagged ? 0x2000 : 0x0000)
        header.replaceSubrange(2..<4, with: withBytes(frame.littleEndian))
        header.replaceSubrange(4..<8, with: withBytes(source.littleEndian))
        var tgt = target
        if tgt.count < 8 { tgt.append(contentsOf: repeatElement(UInt8(0), count: 8 - tgt.count)) }
        header.replaceSubrange(8..<16, with: tgt.prefix(8))
        seq &+= 1; header[23] = seq
        header.replaceSubrange(32..<34, with: withBytes(type.littleEndian))
        return header + payload
    }

    /// Like makePacket but with ack_required=1 (byte 22 bit 1).
    private func makePacketAck(tagged: Bool, target: Data, type: UInt16, payload: Data) -> Data {
        var pkt = makePacket(tagged: tagged, target: target, type: type, payload: payload)
        pkt[22] = pkt[22] | 0x02   // ack_required bit
        return pkt
    }

    private func readUInt16LE(_ data: Data, offset: Int) -> UInt16 {
        guard data.count >= offset + 2 else { return 0 }
        return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private func readUInt32LE(_ data: Data, offset: Int) -> UInt32 {
        guard data.count >= offset + 4 else { return 0 }
        return UInt32(data[offset]) | (UInt32(data[offset+1]) << 8)
             | (UInt32(data[offset+2]) << 16) | (UInt32(data[offset+3]) << 24)
    }

    private func dataFromHex8(_ hex: String) -> Data? {
        let clean = hex.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard clean.count == 16 else { return nil }
        var bytes: [UInt8] = []; bytes.reserveCapacity(8)
        var i = clean.startIndex
        for _ in 0..<8 {
            let j = clean.index(i, offsetBy: 2)
            guard let b = UInt8(clean[i..<j], radix: 16) else { return nil }
            bytes.append(b); i = j
        }
        return Data(bytes)
    }

    private func withBytes<T: BitwiseCopyable>(_ value: T) -> Data {
        var v = value; return Data(bytes: &v, count: MemoryLayout<T>.size)
    }
}
