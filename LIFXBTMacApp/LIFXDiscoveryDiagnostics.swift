import Foundation
import Network

/// Diagnostic tool for LIFX LAN discovery issues
/// Run this to debug why lights aren't being found
final class LIFXDiscoveryDiagnostics {
    
    static func runDiagnostics(completion: @escaping (String) -> Void) {
        var report = "🔍 LIFX Discovery Diagnostics\n\n"
        
        // 1. Check network interfaces
        report += "1️⃣ Network Interfaces:\n"
        let interfaces = getNetworkInterfaces()
        if interfaces.isEmpty {
            report += "   ❌ No network interfaces found\n"
        } else {
            for iface in interfaces {
                report += "   ✅ \(iface.name): \(iface.address)\n"
            }
        }
        report += "\n"
        
        // 2. Check WiFi connectivity
        report += "2️⃣ Network Path:\n"
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { path in
            if path.status == .satisfied {
                report += "   ✅ Network is reachable\n"
                if path.usesInterfaceType(.wifi) {
                    report += "   ✅ Connected via WiFi\n"
                } else if path.usesInterfaceType(.wiredEthernet) {
                    report += "   ✅ Connected via Ethernet\n"
                } else {
                    report += "   ⚠️ Connected via \(path.availableInterfaces.first?.type.debugDescription ?? "unknown")\n"
                }
            } else {
                report += "   ❌ Network not reachable: \(path.status)\n"
            }
            
            report += "\n3️⃣ UDP Broadcast Test:\n"
            
            // 3. Test UDP broadcast capability
            testUDPBroadcast { success, error in
                if success {
                    report += "   ✅ UDP broadcast successful\n"
                } else {
                    report += "   ❌ UDP broadcast failed: \(error ?? "unknown error")\n"
                }
                
                report += "\n4️⃣ Port 56700 Binding Test:\n"
                
                // 4. Test port binding
                testPortBinding { success, error in
                    if success {
                        report += "   ✅ Can bind to port 56700\n"
                    } else {
                        report += "   ❌ Cannot bind to port 56700: \(error ?? "unknown error")\n"
                    }
                    
                    report += "\n5️⃣ LIFX Discovery Packet Test:\n"
                    
                    // 5. Test actual LIFX discovery
                    testLIFXDiscovery { found, error in
                        if found > 0 {
                            report += "   ✅ Found \(found) LIFX device(s)\n"
                        } else {
                            report += "   ❌ No LIFX devices found\n"
                            if let error {
                                report += "   Error: \(error)\n"
                            }
                        }
                        
                        report += "\n📋 Recommendations:\n"
                        report += getRecommendations(interfaces: interfaces, found: found)
                        
                        completion(report)
                    }
                }
            }
            
            monitor.cancel()
        }
        monitor.start(queue: .main)
    }
    
    private static func getNetworkInterfaces() -> [(name: String, address: String)] {
        var interfaces: [(String, String)] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        
        guard getifaddrs(&ifaddr) == 0 else { return interfaces }
        defer { freeifaddrs(ifaddr) }
        
        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }
            
            guard let interface = ptr?.pointee else { continue }
            let name = String(cString: interface.ifa_name)
            
            // Only IPv4 addresses
            guard interface.ifa_addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            
            var addr = interface.ifa_addr.pointee
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            
            if getnameinfo(&addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                          &hostname, socklen_t(hostname.count),
                          nil, 0, NI_NUMERICHOST) == 0 {
                let address = String(cString: hostname)
                // Skip loopback
                if !address.hasPrefix("127.") {
                    interfaces.append((name, address))
                }
            }
        }
        
        return interfaces
    }
    
    private static func testUDPBroadcast(completion: @escaping (Bool, String?) -> Void) {
        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true
        params.requiredInterfaceType = .wifi
        params.prohibitedInterfaceTypes = [.loopback]
        
        let endpoint = NWEndpoint.hostPort(
            host: "255.255.255.255",
            port: 56700
        )
        
        let connection = NWConnection(to: endpoint, using: params)
        
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                let data = Data([0x00, 0x01, 0x02, 0x03])
                connection.send(content: data, completion: .contentProcessed { error in
                    if let error {
                        completion(false, error.localizedDescription)
                    } else {
                        completion(true, nil)
                    }
                    connection.cancel()
                })
            case .failed(let error):
                completion(false, error.localizedDescription)
                connection.cancel()
            default:
                break
            }
        }
        
        connection.start(queue: .main)
        
        // Timeout after 5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            if connection.state != .ready && connection.state != .failed {
                connection.cancel()
                completion(false, "Timeout")
            }
        }
    }
    
    private static func testPortBinding(completion: @escaping (Bool, String?) -> Void) {
        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true
        params.requiredInterfaceType = .wifi
        
        do {
            let listener = try NWListener(using: params, on: 56700)
            
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    completion(true, nil)
                    listener.cancel()
                case .failed(let error):
                    completion(false, error.localizedDescription)
                    listener.cancel()
                default:
                    break
                }
            }
            
            listener.start(queue: .main)
            
            // Timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                if listener.state != .ready && listener.state != .failed {
                    listener.cancel()
                    completion(false, "Timeout")
                }
            }
        } catch {
            completion(false, error.localizedDescription)
        }
    }
    
    private static func testLIFXDiscovery(completion: @escaping (Int, String?) -> Void) {
        var foundDevices = 0
        let timeout: TimeInterval = 5.0
        
        let discovery = LIFXLanDiscovery()
        
        discovery.startScan(
            onStatus: { status in
                print("Discovery status: \(status)")
            },
            onLight: { light in
                foundDevices += 1
                print("Found light: \(light.label) at \(light.ip)")
            }
        )
        
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
            discovery.stop()
            completion(foundDevices, foundDevices == 0 ? "No devices responded" : nil)
        }
    }
    
    private static func getRecommendations(interfaces: [(String, String)], found: Int) -> String {
        var recommendations = ""
        
        if interfaces.isEmpty {
            recommendations += "• ❌ CRITICAL: No network interfaces found\n"
            recommendations += "  - Check if WiFi/Ethernet is connected\n"
            recommendations += "  - Try restarting network interfaces\n\n"
        }
        
        if found == 0 {
            recommendations += "• No LIFX lights found. Check:\n"
            recommendations += "  1. Lights are powered on and connected to WiFi\n"
            recommendations += "  2. Lights are on the SAME network as this Mac\n"
            recommendations += "  3. Network allows UDP broadcast (some enterprise networks block it)\n"
            recommendations += "  4. Router/firewall allows UDP port 56700\n"
            recommendations += "  5. macOS Local Network permission granted:\n"
            recommendations += "     System Settings → Privacy & Security → Local Network\n"
            recommendations += "  6. Try restarting the LIFX lights (power cycle)\n"
            recommendations += "  7. Use LIFX app to verify lights are online\n\n"
            
            recommendations += "• Network Requirements:\n"
            recommendations += "  - LIFX lights must be on same subnet (e.g., 192.168.1.x)\n"
            recommendations += "  - Broadcast address must be reachable (255.255.255.255)\n"
            recommendations += "  - UDP broadcast must not be filtered by router\n\n"
            
            recommendations += "• Try these commands in Terminal:\n"
            recommendations += "  # Check if lights respond to ping\n"
            recommendations += "  $ ping <light-ip-address>\n\n"
            recommendations += "  # Test UDP broadcast\n"
            recommendations += "  $ echo 'test' | nc -u -b 255.255.255.255 56700\n\n"
        }
        
        return recommendations
    }
}
