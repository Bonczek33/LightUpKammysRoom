//
//  LIFXLanDiscovery.swift
//  LIFXBTMacApp
//
//  Created by Tomasz Bak on 2/16/26.
//

import Foundation
import Network

final class LIFXLanDiscovery {
    private let lifxPort: NWEndpoint.Port = 56700
    private let queue = DispatchQueue(label: "lifx.lan.discovery")

    private var listener: NWListener?
    private var listenPort: NWEndpoint.Port?

    private var source: UInt32 = .random(in: 1...UInt32.max)
    private var seq: UInt8 = 0

    // Thread-safe access to shared state
    private let stateLock = NSLock()
    private var devices: [String: LIFXLight] = [:]
    private var labelRequested: Set<String> = []
    
    // Track if we've sent initial broadcast
    private var initialBroadcastSent = false
    
    // IMPROVEMENT: Try multiple broadcast methods
    private var broadcastAttempts = 0
    private let maxBroadcastAttempts = 3
    private var broadcastTimer: DispatchSourceTimer?

    func startScan(onStatus: @escaping (String) -> Void,
                   onLight: @escaping (LIFXLight) -> Void) {
        stop()
        
        stateLock.lock()
        devices.removeAll()
        labelRequested.removeAll()
        initialBroadcastSent = false
        broadcastAttempts = 0
        stateLock.unlock()
        
        source = .random(in: 1...UInt32.max)
        seq = 0
        listenPort = nil

        print("🚀 [LIFX Discovery] Starting discovery...")
        
        // IMPROVEMENT: Try binding to any available port first (more reliable)
        do {
            let params = NWParameters.udp
            params.allowLocalEndpointReuse = true
            
            // Try WiFi first, but don't require it (allows Ethernet too)
            params.includePeerToPeer = false
            params.prohibitedInterfaceTypes = [.loopback]
            
            // Enable broadcast
            params.acceptLocalOnly = false

            let listener = try NWListener(using: params)
            self.listener = listener

            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                
                switch state {
                case .ready:
                    self.listenPort = listener.port
                    let portNum = listener.port?.rawValue ?? 0
                    print("🔓 [LIFX Discovery] Listener ready on port \(portNum)")
                    onStatus("Listening on port \(portNum)")
                    
                    // Send initial broadcast
                    self.stateLock.lock()
                    let shouldSend = !self.initialBroadcastSent
                    if shouldSend {
                        self.initialBroadcastSent = true
                    }
                    self.stateLock.unlock()
                    
                    if shouldSend {
                        // IMPROVEMENT: Send multiple broadcasts for reliability
                        self.sendMultipleBroadcasts(onStatus: onStatus)
                    }
                    
                case .failed(let err):
                    print("❌ [LIFX Discovery] Listener failed: \(err)")
                    
                    // Check for permission errors (macOS Sequoia)
                    if case .posix(let code) = err, code == .EACCES {
                        let msg = "⚠️ Network permission denied.\n\nGo to:\nSystem Settings → Privacy & Security → Local Network\n\nEnable permission for this app."
                        onStatus(msg)
                    } else {
                        onStatus("Listener failed: \(err.localizedDescription)")
                    }
                    
                case .waiting(let err):
                    print("⏳ [LIFX Discovery] Listener waiting: \(err)")
                    onStatus("Waiting for network...")
                    
                case .cancelled:
                    print("🛑 [LIFX Discovery] Listener cancelled")
                    onStatus("Discovery cancelled")
                    
                default:
                    print("ℹ️ [LIFX Discovery] Listener state: \(state)")
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
            print("🔄 [LIFX Discovery] Listener starting...")
            
            // Check if already ready (synchronous state check)
            queue.async { [weak self] in
                guard let self else { return }
                if listener.state == .ready {
                    self.stateLock.lock()
                    let shouldSend = !self.initialBroadcastSent
                    if shouldSend {
                        self.initialBroadcastSent = true
                    }
                    self.stateLock.unlock()
                    
                    if shouldSend {
                        print("✅ [LIFX Discovery] Listener was already ready, sending broadcasts")
                        self.sendMultipleBroadcasts(onStatus: onStatus)
                    }
                }
            }
            
        } catch {
            print("❌ [LIFX Discovery] Failed to start listener: \(error)")
            onStatus("Failed to start: \(error.localizedDescription)")
        }
    }

    func stop() {
        broadcastTimer?.cancel()
        broadcastTimer = nil
        
        listener?.cancel()
        listener = nil
        listenPort = nil
        
        stateLock.lock()
        devices.removeAll()
        labelRequested.removeAll()
        initialBroadcastSent = false
        broadcastAttempts = 0
        stateLock.unlock()
        
        print("🛑 [LIFX Discovery] Stopped")
    }

    // IMPROVEMENT: Send multiple broadcasts for better reliability
    private func sendMultipleBroadcasts(onStatus: @escaping (String) -> Void) {
        // Send first broadcast immediately
        sendGetServiceBroadcast()
        
        // Send 2 more broadcasts at 1-second intervals
        broadcastTimer?.cancel()
        broadcastTimer = DispatchSource.makeTimerSource(queue: queue)
        broadcastTimer?.schedule(deadline: .now() + 1.0, repeating: 1.0)
        broadcastTimer?.setEventHandler { [weak self] in
            guard let self else { return }
            
            self.stateLock.lock()
            self.broadcastAttempts += 1
            let attempts = self.broadcastAttempts
            self.stateLock.unlock()
            
            if attempts < self.maxBroadcastAttempts {
                print("🔄 [LIFX Discovery] Sending broadcast attempt \(attempts + 1)/\(self.maxBroadcastAttempts)")
                self.sendGetServiceBroadcast()
                onStatus("Searching... (attempt \(attempts + 1))")
            } else {
                self.broadcastTimer?.cancel()
                self.broadcastTimer = nil
                onStatus("Discovery complete")
            }
        }
        broadcastTimer?.resume()
    }

    private func sendGetServiceBroadcast() {
        // IMPROVEMENT: Try multiple broadcast addresses
        let broadcastAddresses = [
            "255.255.255.255",  // Global broadcast
            getBroadcastAddress() ?? "255.255.255.255"  // Subnet-specific broadcast
        ]
        
        let packet = makePacket(
            tagged: true,
            target: Data(repeating: 0, count: 8),
            type: 2, // Device.GetService
            payload: Data()
        )
        
        for address in Set(broadcastAddresses) {  // Remove duplicates
            let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(address), port: lifxPort)
            print("📡 [LIFX Discovery] Broadcasting GetService to \(address):56700")
            sendPacket(to: endpoint, packet: packet)
        }
    }
    
    // IMPROVEMENT: Calculate subnet broadcast address
    private func getBroadcastAddress() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }
        
        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }
            
            guard let interface = ptr?.pointee else { continue }
            let name = String(cString: interface.ifa_name)
            
            // Look for WiFi or Ethernet, not loopback
            guard name.hasPrefix("en") else { continue }
            
            // Only IPv4
            guard interface.ifa_addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            
            // Get address and netmask
            guard let addr = interface.ifa_addr.pointee.toIPv4(),
                  let mask = interface.ifa_netmask.pointee.toIPv4() else { continue }
            
            // Skip loopback
            guard !addr.hasPrefix("127.") else { continue }
            
            // Calculate broadcast address
            let broadcast = calculateBroadcast(ip: addr, netmask: mask)
            print("ℹ️ [LIFX Discovery] Found interface \(name): \(addr), netmask: \(mask), broadcast: \(broadcast)")
            return broadcast
        }
        
        return nil
    }
    
    private func calculateBroadcast(ip: String, netmask: String) -> String {
        let ipParts = ip.split(separator: ".").compactMap { UInt8($0) }
        let maskParts = netmask.split(separator: ".").compactMap { UInt8($0) }
        
        guard ipParts.count == 4, maskParts.count == 4 else {
            return "255.255.255.255"
        }
        
        let broadcast = zip(ipParts, maskParts).map { ip, mask in
            ip | (~mask)
        }
        
        return broadcast.map(String.init).joined(separator: ".")
    }

    private func sendGetLabel(to ip: String, target: Data) {
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(ip), port: lifxPort)
        let packet = makePacket(
            tagged: false,
            target: target,
            type: 23, // Device.GetLabel
            payload: Data()
        )
        
        print("🏷 [LIFX Discovery] Requesting label from \(ip)")
        sendPacket(to: endpoint, packet: packet)
    }

    private func sendPacket(to endpoint: NWEndpoint, packet: Data) {
//        let params = NWParameters.udp
//        params.allowLocalEndpointReuse = true
//        
//        // Less restrictive interface requirements
//        params.includePeerToPeer = false
//        params.prohibitedInterfaceTypes = [.loopback]
//
//        // Bind to same port as listener if available
//        if let port = listenPort, let any = IPv4Address("0.0.0.0") {
//            params.requiredLocalEndpoint = .hostPort(host: .ipv4(any), port: port)
//        }

        let params = NWParameters.udp
            params.allowLocalEndpointReuse = true
            params.includePeerToPeer = false
            params.prohibitedInterfaceTypes = [.loopback]

            // REMOVE THIS BLOCK (it causes EADDRINUSE when you open multiple connections):
            // if let port = listenPort, let any = IPv4Address("0.0.0.0") {
            //     params.requiredLocalEndpoint = .hostPort(host: .ipv4(any), port: port)
            // }

       //     let conn = NWConnection(to: endpoint, using: params)
        
        
        let conn = NWConnection(to: endpoint, using: params)
        
        var didSend = false
        conn.stateUpdateHandler = { [weak conn] state in
            switch state {
            case .ready:
                if !didSend {
                    didSend = true
                    conn?.send(content: packet, completion: .contentProcessed { error in
                        if let error {
                            print("❌ [LIFX Discovery] Send failed: \(error)")
                        }
                        conn?.cancel()
                    })
                }
            case .failed(let err):
                print("❌ [LIFX Discovery] Send connection failed: \(err)")
                conn?.cancel()
            default:
                break
            }
        }
        
        conn.start(queue: queue)
        
        // Timeout
        queue.asyncAfter(deadline: .now() + 2) { [weak conn] in
            if conn?.state != .cancelled {
                conn?.cancel()
            }
        }
    }

    private func receiveLoop(on conn: NWConnection,
                             onLight: @escaping (LIFXLight) -> Void) {
        conn.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }
            
            if let error {
                // Only log non-cancelled errors
                let nsError = error as NSError
                if nsError.domain != NWError.errorDomain || nsError.code != 89 { // ECANCELED
                    print("⚠️ [LIFX Discovery] Receive error: \(error)")
                }
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
            
            // Thread-safe access to shared state
            stateLock.lock()
            let wasInserted = labelRequested.insert(id).inserted
            if wasInserted, ip != "Unknown" {
                var light = devices[id] ?? LIFXLight(id: id, label: "", ip: ip)
                light.ip = ip
                devices[id] = light
                stateLock.unlock()
                
                // Call onLight outside the lock
                onLight(light)
                sendGetLabel(to: ip, target: target)
            } else {
                stateLock.unlock()
            }

        case 25: // Device.StateLabel
            guard data.count >= 68 else {
                print("⚠️ [LIFX Discovery] StateLabel packet too short")
                return
            }
            
            let label = decodeNullTerminatedUTF8(data.subdata(in: 36..<68))
            print("🏷 [LIFX Discovery] Device \(id) label: '\(label)'")

            // Thread-safe access
            stateLock.lock()
            var light = devices[id] ?? LIFXLight(id: id, label: "", ip: ip)
            light.label = label
            if ip != "Unknown" { light.ip = ip }
            devices[id] = light
            stateLock.unlock()
            
            // Call onLight outside the lock
            onLight(light)

        default:
            // Silently ignore other packet types
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

// MARK: - Helper Extensions

extension sockaddr {
    func toIPv4() -> String? {
        guard sa_family == UInt8(AF_INET) else { return nil }
        
        var addr = self
        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        
        guard getnameinfo(&addr, socklen_t(sa_len),
                         &hostname, socklen_t(hostname.count),
                         nil, 0, NI_NUMERICHOST) == 0 else {
            return nil
        }
        
        return String(cString: hostname)
    }
}

