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
//  Connection pool: idle-only cleanup (no timer-based thrashing).
//

import Foundation
import Network

final class LIFXLanControl {
    struct LightState { var powerOn: Bool; var color: LIFXColor }

    private let lifxPort: NWEndpoint.Port = 56700
    private let queue = DispatchQueue(label: "lifx.lan.control")
    private var source: UInt32 = .random(in: 1...UInt32.max)
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
