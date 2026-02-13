import Foundation
import Network

final class LIFXLanDiscovery {
    private let lifxPort: NWEndpoint.Port = 56700
    private let queue = DispatchQueue(label: "lifx.lan.discovery")

    private var listener: NWListener?
    private var listenPort: NWEndpoint.Port?

    private var source: UInt32 = .random(in: 1...UInt32.max)
    private var seq: UInt8 = 0

    private var devices: [String: LIFXLight] = [:]
    private var labelRequested: Set<String> = []

    func startScan(onStatus: @escaping (String) -> Void,
                   onLight: @escaping (LIFXLight) -> Void) {
        stop()
        devices.removeAll()
        labelRequested.removeAll()
        source = .random(in: 1...UInt32.max)
        seq = 0
        listenPort = nil

        do {
            let params = NWParameters.udp
            params.allowLocalEndpointReuse = true
            
            // ✅ macOS Sequoia compatibility: specify interface requirements
            params.requiredInterfaceType = .wifi
            params.prohibitedInterfaceTypes = [.loopback]
            
            // ✅ Enable multicast/broadcast
            params.acceptLocalOnly = false

            let listener = try NWListener(using: params)
            self.listener = listener

            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                
                switch state {
                case .ready:
                    self.listenPort = listener.port
                    let portNum = listener.port?.rawValue ?? 0
                    print("🔍 [LIFX Discovery] Listener ready on port \(portNum)")
                    onStatus("Listening on \(portNum)… sending discovery")
                    self.sendGetServiceBroadcast()
                    
                case .failed(let err):
                    print("❌ [LIFX Discovery] Listener failed: \(err)")
                    
                    // ✅ Check for permission errors (macOS Sequoia)
                    if case .posix(let code) = err, code == .EACCES {
                        onStatus("⚠️ Network permission denied. Check System Settings → Privacy & Security → Local Network")
                    } else {
                        onStatus("Listener failed: \(err.localizedDescription)")
                    }
                    
                case .waiting(let err):
                    print("⏳ [LIFX Discovery] Listener waiting: \(err)")
                    onStatus("Waiting: \(err.localizedDescription)")
                    
                case .cancelled:
                    print("🛑 [LIFX Discovery] Listener cancelled")
                    onStatus("Discovery cancelled")
                    
                default:
                    break
                }
            }

            listener.newConnectionHandler = { [weak self] conn in
                guard let self else { return }
                print("📥 [LIFX Discovery] New connection from \(conn.endpoint)")
                conn.start(queue: self.queue)
                self.receiveLoop(on: conn, onLight: onLight)
            }

            listener.start(queue: queue)
            print("🚀 [LIFX Discovery] Starting listener...")
            
        } catch {
            print("❌ [LIFX Discovery] Failed to start listener: \(error)")
            onStatus("Failed to start listener: \(error.localizedDescription)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        listenPort = nil
        print("🛑 [LIFX Discovery] Stopped")
    }

    private func sendGetServiceBroadcast() {
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host("255.255.255.255"), port: lifxPort)
        let packet = makePacket(
            tagged: true,
            target: Data(repeating: 0, count: 8),
            type: 2, // Device.GetService
            payload: Data()
        )
        
        print("📡 [LIFX Discovery] Broadcasting GetService to 255.255.255.255:56700")
        sendPacket(to: endpoint, packet: packet)
    }

    private func sendGetLabel(to ip: String, target: Data) {
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(ip), port: lifxPort)
        let packet = makePacket(
            tagged: false,
            target: target,
            type: 23, // Device.GetLabel
            payload: Data()
        )
        
        print("📝 [LIFX Discovery] Requesting label from \(ip)")
        sendPacket(to: endpoint, packet: packet)
    }

    private func sendPacket(to endpoint: NWEndpoint, packet: Data) {
        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true
        
        // ✅ macOS Sequoia compatibility
        params.requiredInterfaceType = .wifi
        params.prohibitedInterfaceTypes = [.loopback]

        // ✅ Bind to same port as listener if available
        if let port = listenPort, let any = IPv4Address("0.0.0.0") {
            params.requiredLocalEndpoint = .hostPort(host: .ipv4(any), port: port)
        }

        let conn = NWConnection(to: endpoint, using: params)
        
        conn.stateUpdateHandler = { state in
            if case .failed(let err) = state {
                print("❌ [LIFX Discovery] Send connection failed: \(err)")
            }
        }
        
        conn.start(queue: queue)
        conn.send(content: packet, completion: .contentProcessed { error in
            if let error {
                print("❌ [LIFX Discovery] Send failed: \(error)")
            }
            conn.cancel()
        })
    }

    private func receiveLoop(on conn: NWConnection,
                             onLight: @escaping (LIFXLight) -> Void) {
        conn.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }
            
            if let error {
                print("❌ [LIFX Discovery] Receive error: \(error)")
                return
            }
            
            if let data {
                self.handlePacket(data, from: conn, onLight: onLight)
            }
            
            // Continue receiving
            if error == nil {
                self.receiveLoop(on: conn, onLight: onLight)
            }
        }
    }

    private func handlePacket(_ data: Data,
                              from conn: NWConnection,
                              onLight: @escaping (LIFXLight) -> Void) {
        guard data.count >= 36 else {
            print("⚠️ [LIFX Discovery] Packet too short: \(data.count) bytes")
            return
        }

        let type = readUInt16LE(data, offset: 32)
        let target = data.subdata(in: 8..<16)
        let id = target.map { String(format: "%02x", $0) }.joined()
        let ip = remoteIP(from: conn) ?? "Unknown"

        switch type {
        case 3: // Device.StateService
            print("✅ [LIFX Discovery] Found device \(id) at \(ip)")
            
            if labelRequested.insert(id).inserted, ip != "Unknown" {
                var light = devices[id] ?? LIFXLight(id: id, label: "", ip: ip)
                light.ip = ip
                devices[id] = light
                onLight(light)
                sendGetLabel(to: ip, target: target)
            }

        case 25: // Device.StateLabel
            guard data.count >= 68 else {
                print("⚠️ [LIFX Discovery] StateLabel packet too short")
                return
            }
            
            let label = decodeNullTerminatedUTF8(data.subdata(in: 36..<68))
            print("📝 [LIFX Discovery] Device \(id) label: '\(label)'")

            var light = devices[id] ?? LIFXLight(id: id, label: "", ip: ip)
            light.label = label
            if ip != "Unknown" { light.ip = ip }
            devices[id] = light
            onLight(light)

        default:
            print("ℹ️ [LIFX Discovery] Ignoring packet type \(type)")
            break
        }
    }

    private func makePacket(tagged: Bool, target: Data, type: UInt16, payload: Data) -> Data {
        var header = Data(count: 36)
        
        // Size (2 bytes)
        header.replaceSubrange(0..<2, with: withBytes(UInt16(36 + payload.count).littleEndian))

        // Frame (2 bytes): protocol + addressable + tagged + reserved
        let frame: UInt16 = 0x0400 | 0x1000 | (tagged ? 0x2000 : 0x0000)
        header.replaceSubrange(2..<4, with: withBytes(frame.littleEndian))
        
        // Source (4 bytes)
        header.replaceSubrange(4..<8, with: withBytes(source.littleEndian))

        // Target (8 bytes)
        var tgt = target
        if tgt.count < 8 { tgt.append(contentsOf: repeatElement(UInt8(0), count: 8 - tgt.count)) }
        header.replaceSubrange(8..<16, with: tgt.prefix(8))

        // Sequence (1 byte at offset 23)
        seq &+= 1
        header[23] = seq
        
        // Type (2 bytes at offset 32)
        header.replaceSubrange(32..<34, with: withBytes(type.littleEndian))
        
        return header + payload
    }

    private func remoteIP(from conn: NWConnection) -> String? {
        if case .hostPort(let host, _) = conn.endpoint {
            return host.debugDescription.replacingOccurrences(of: "\"", with: "")
        }
        return nil
    }

    private func readUInt16LE(_ data: Data, offset: Int) -> UInt16 {
        guard data.count >= offset + 2 else { return 0 }
        return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private func decodeNullTerminatedUTF8(_ data: Data) -> String {
        String(decoding: data.prefix { $0 != 0 }, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func withBytes<T>(_ value: T) -> Data {
        withUnsafeBytes(of: value) { Data($0) }
    }
}
