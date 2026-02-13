import Foundation
import Network

final class LIFXLanControl {
    struct LightState { var powerOn: Bool; var color: LIFXColor }

    private let lifxPort: NWEndpoint.Port = 56700
    private let queue = DispatchQueue(label: "lifx.lan.control")

    private var source: UInt32 = .random(in: 1...UInt32.max)
    private var seq: UInt8 = 0

    func getLightState(ip: String, targetHex: String, timeoutSeconds: Double = 1.0) async -> LightState? {
        guard let target = dataFromHex8(targetHex) else { return nil }

        let packet = makePacket(tagged: false, target: target, type: 101, payload: Data())
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(ip), port: lifxPort)

        let conn = NWConnection(to: endpoint, using: .udp)
        conn.start(queue: queue)

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            conn.send(content: packet, completion: .contentProcessed { _ in cont.resume() })
        }

        let data: Data? = await withTaskGroup(of: Data?.self) { group in
            group.addTask {
                await withCheckedContinuation { (cont: CheckedContinuation<Data?, Never>) in
                    conn.receiveMessage { data, _, _, _ in cont.resume(returning: data) }
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }

        conn.cancel()

        guard let reply = data, reply.count >= 36 else { return nil }
        let type = readUInt16LE(reply, offset: 32)
        guard type == 107 else { return nil } // Light.State

        let o = 36
        guard reply.count >= o + 12 else { return nil }

        let hueU16 = readUInt16LE(reply, offset: o + 0)
        let satU16 = readUInt16LE(reply, offset: o + 2)
        let briU16 = readUInt16LE(reply, offset: o + 4)
        let kelvin = readUInt16LE(reply, offset: o + 6)
        let power = readUInt16LE(reply, offset: o + 10)

        let color = LIFXColor(
            hue: Double(hueU16) / 65535.0,
            saturation: Double(satU16) / 65535.0,
            brightness: Double(briU16) / 65535.0,
            hueU16: hueU16, satU16: satU16, briU16: briU16, kelvin: kelvin
        )

        return LightState(powerOn: power > 0, color: color)
    }

    func setPower(ip: String, targetHex: String, on: Bool, durationMs: UInt32 = 0) {
        guard let target = dataFromHex8(targetHex) else { return }
        let level: UInt16 = on ? 65535 : 0
        var payload = Data()
        payload.append(withBytes(level.littleEndian))
        payload.append(withBytes(durationMs.littleEndian))
        let packet = makePacket(tagged: false, target: target, type: 117, payload: payload)
        send(toIP: ip, packet: packet)
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
        let packet = makePacket(tagged: false, target: target, type: 102, payload: payload)
        send(toIP: ip, packet: packet)
    }

    private func send(toIP ip: String, packet: Data) {
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(ip), port: lifxPort)
        let conn = NWConnection(to: endpoint, using: .udp)
        conn.start(queue: queue)
        conn.send(content: packet, completion: .contentProcessed { _ in conn.cancel() })
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

        seq &+= 1
        header[23] = seq
        header.replaceSubrange(32..<34, with: withBytes(type.littleEndian))
        return header + payload
    }

    private func readUInt16LE(_ data: Data, offset: Int) -> UInt16 {
        guard data.count >= offset + 2 else { return 0 }
        return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private func dataFromHex8(_ hex: String) -> Data? {
        let clean = hex.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard clean.count == 16 else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(8)
        var i = clean.startIndex
        for _ in 0..<8 {
            let j = clean.index(i, offsetBy: 2)
            guard let b = UInt8(clean[i..<j], radix: 16) else { return nil }
            bytes.append(b)
            i = j
        }
        return Data(bytes)
    }

    private func withBytes<T: BitwiseCopyable>(_ value: T) -> Data {
        var v = value
        return Data(bytes: &v, count: MemoryLayout<T>.size)
    }
}
