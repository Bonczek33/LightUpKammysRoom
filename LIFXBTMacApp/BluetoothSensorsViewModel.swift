import Foundation
import CoreBluetooth
import SwiftUI

// MARK: - Bluetooth UUID helpers

extension CBUUID {
    static let heartRateService      = CBUUID(string: "180D")
    static let hrMeasurement         = CBUUID(string: "2A37")

    static let cyclingPowerService   = CBUUID(string: "1818")
    static let cyclingPowerMeasure   = CBUUID(string: "2A63")
}

extension CBPeripheral {
    var nameOrUnknown: String { (name?.isEmpty == false) ? name! : "Unknown" }
}

// MARK: - Bluetooth Sensors (HR + Power)

@MainActor
final class BluetoothSensorsViewModel: NSObject, ObservableObject {
    enum BTState: String { case unknown, resetting, unsupported, unauthorized, poweredOff, poweredOn }

    @Published private(set) var btState: BTState = .unknown
    @Published private(set) var status: String = "Bluetooth: idle"

    @Published private(set) var heartRateBPM: Int? = nil
    @Published private(set) var powerWatts: Int? = nil
    @Published private(set) var cadenceRPM: Int? = nil

    struct PeripheralItem: Identifiable, Hashable {
        let id: UUID
        let name: String
        let rssi: Int
    }

    @Published private(set) var hrCandidates: [PeripheralItem] = []
    @Published private(set) var powerCandidates: [PeripheralItem] = []
    @Published private(set) var connectedHRName: String? = nil
    @Published private(set) var connectedPowerName: String? = nil
    @Published private(set) var connectedHRPeripheralID: String? = nil
    @Published private(set) var connectedPowerPeripheralID: String? = nil

    // Retry state (visible to UI)
    @Published private(set) var hrRetryCount: Int = 0
    @Published private(set) var powerRetryCount: Int = 0
    @Published private(set) var isRetryingHR: Bool = false
    @Published private(set) var isRetryingPower: Bool = false

    private var central: CBCentralManager!
    private var hrPeripheral: CBPeripheral?
    private var powerPeripheral: CBPeripheral?
    private var peripheralsByID: [UUID: CBPeripheral] = [:]
    
    // Retry configuration
    private let maxRetryAttempts = 5
    private let baseRetryDelay: TimeInterval = 1.0  // seconds, doubles each attempt
    private var hrRetryTask: Task<Void, Never>?
    private var powerRetryTask: Task<Void, Never>?
    /// Set to true when user explicitly disconnects — suppresses auto-retry
    private var userRequestedDisconnect = false
    
    // Cadence calculation state
    private var lastCrankRevs: UInt16?
    private var lastCrankTime: UInt16?  // In 1024ths of a second

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    /// Callback fired when a device successfully connects, so the caller can persist the UUID.
    /// Parameters: (peripheralUUID: String, name: String, isHR: Bool, isPower: Bool)
    var onDeviceConnected: ((_ id: String, _ name: String, _ isHR: Bool, _ isPower: Bool) -> Void)?

    /// Attempt to reconnect to previously known peripherals by UUID.
    /// CoreBluetooth can retrieve known peripherals even without scanning.
    func autoReconnect(hrUUID: String?, powerUUID: String?) {
        userRequestedDisconnect = false
        cancelAllRetries()
        guard central.state == .poweredOn else {
            // Defer until powered on
            pendingAutoReconnectHR = hrUUID
            pendingAutoReconnectPower = powerUUID
            return
        }
        performAutoReconnect(hrUUID: hrUUID, powerUUID: powerUUID)
    }

    private var pendingAutoReconnectHR: String? = nil
    private var pendingAutoReconnectPower: String? = nil

    private func performAutoReconnect(hrUUID: String?, powerUUID: String?) {
        var uuids: [UUID] = []
        if let s = hrUUID, let u = UUID(uuidString: s) { uuids.append(u) }
        if let s = powerUUID, let u = UUID(uuidString: s) { uuids.append(u) }
        guard !uuids.isEmpty else { return }

        let known = central.retrievePeripherals(withIdentifiers: uuids)
        print("🔄 [BLE] Auto-reconnect: found \(known.count) known peripheral(s)")

        for p in known {
            peripheralsByID[p.identifier] = p
            p.delegate = self

            if let s = hrUUID, p.identifier.uuidString == s, hrPeripheral == nil {
                status = "Reconnecting HR: \(p.nameOrUnknown)…"
                hrPeripheral = p
                central.connect(p, options: nil)
                print("🔄 [BLE] Auto-reconnecting HR: \(p.nameOrUnknown)")
            }
            if let s = powerUUID, p.identifier.uuidString == s, powerPeripheral == nil {
                status = "Reconnecting Power: \(p.nameOrUnknown)…"
                powerPeripheral = p
                central.connect(p, options: nil)
                print("🔄 [BLE] Auto-reconnecting Power: \(p.nameOrUnknown)")
            }
        }
    }

    func startScan() {
        guard central.state == .poweredOn else {
            status = "Bluetooth not powered on"
            return
        }
        userRequestedDisconnect = false
        cancelAllRetries()
        status = "Scanning for HR + Power devices…"
        hrCandidates.removeAll()
        powerCandidates.removeAll()
        peripheralsByID.removeAll()

        central.scanForPeripherals(
            withServices: [CBUUID.heartRateService, CBUUID.cyclingPowerService],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
    }

    func stopScan() {
        central.stopScan()
        status = "Scan stopped"
    }

    func disconnectAll() {
        userRequestedDisconnect = true
        cancelAllRetries()
        if let p = hrPeripheral { central.cancelPeripheralConnection(p) }
        if let p = powerPeripheral { central.cancelPeripheralConnection(p) }
    }

    private func cancelAllRetries() {
        hrRetryTask?.cancel(); hrRetryTask = nil
        powerRetryTask?.cancel(); powerRetryTask = nil
        hrRetryCount = 0; powerRetryCount = 0
        isRetryingHR = false; isRetryingPower = false
    }

    /// Retry connecting to a peripheral with exponential backoff.
    private func retryConnect(peripheral: CBPeripheral, isHR: Bool) {
        let count = isHR ? hrRetryCount : powerRetryCount
        guard count < maxRetryAttempts else {
            let role = isHR ? "HR" : "Power"
            status = "\(role) reconnect failed after \(maxRetryAttempts) attempts"
            print("❌ [BLE] \(role) retry exhausted (\(maxRetryAttempts) attempts)")
            if isHR { isRetryingHR = false } else { isRetryingPower = false }
            return
        }

        let attempt = count + 1
        let delay = baseRetryDelay * pow(2.0, Double(count))  // 1, 2, 4, 8, 16s
        let role = isHR ? "HR" : "Power"

        if isHR {
            hrRetryCount = attempt; isRetryingHR = true
        } else {
            powerRetryCount = attempt; isRetryingPower = true
        }

        status = "Retrying \(role) (\(attempt)/\(maxRetryAttempts)) in \(Int(delay))s…"
        print("🔄 [BLE] Retry \(role) attempt \(attempt)/\(maxRetryAttempts), delay \(delay)s")

        let task = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch { return } // cancelled

            guard let self, !Task.isCancelled else { return }
            guard self.central.state == .poweredOn else {
                self.status = "Bluetooth not available for \(role) retry"
                if isHR { self.isRetryingHR = false } else { self.isRetryingPower = false }
                return
            }

            self.status = "Reconnecting \(role): \(peripheral.nameOrUnknown)…"
            peripheral.delegate = self
            self.central.connect(peripheral, options: nil)
        }

        if isHR { hrRetryTask = task } else { powerRetryTask = task }
    }

    func connectHR(id: UUID) {
        guard let p = peripheralsByID[id] else { return }
        userRequestedDisconnect = false
        hrRetryTask?.cancel(); hrRetryCount = 0; isRetryingHR = false
        status = "Connecting HR: \(p.nameOrUnknown)…"
        hrPeripheral = p
        hrPeripheral?.delegate = self
        central.connect(p, options: nil)
    }

    func connectPower(id: UUID) {
        guard let p = peripheralsByID[id] else { return }
        userRequestedDisconnect = false
        powerRetryTask?.cancel(); powerRetryCount = 0; isRetryingPower = false
        status = "Connecting Power: \(p.nameOrUnknown)…"
        powerPeripheral = p
        powerPeripheral?.delegate = self
        central.connect(p, options: nil)
    }

    private func parseHeartRate(from data: Data) -> Int? {
        // 0x2A37 Heart Rate Measurement
        guard data.count >= 2 else {
            print("⚠️ [BLE HR] Packet too short: \(data.count) bytes")
            return nil
        }
        let flags = data[0]
        let isUInt16 = (flags & 0x01) != 0
        if !isUInt16 { return Int(data[1]) }
        guard data.count >= 3 else {
            print("⚠️ [BLE HR] UInt16 format but packet too short")
            return nil
        }
        let v = UInt16(data[1]) | (UInt16(data[2]) << 8)
        return Int(v)
    }

    private func parseInstantPower(from data: Data) -> Int? {
        // 0x2A63 Cycling Power Measurement: flags(2) + instantaneous power(sint16)
        guard data.count >= 4 else {
            print("⚠️ [BLE Power] Packet too short: \(data.count) bytes")
            return nil
        }
        let raw = Int16(bitPattern: UInt16(data[2]) | (UInt16(data[3]) << 8))
        return Int(raw)
    }
    
    private func parseCadence(from data: Data) -> Int? {
        // 0x2A63 Cycling Power Measurement
        guard data.count >= 2 else {
            print("⚠️ [BLE Cadence] Packet too short: \(data.count) bytes")
            return nil
        }
        
        let flags = UInt16(data[0]) | (UInt16(data[1]) << 8)
        
        // Bit 5: Crank Revolution Data Present
        let hasCrankData = (flags & 0x0020) != 0
        
        guard hasCrankData else {
            // No crank data in this packet - not an error, just not available
            return nil
        }
        
        // Calculate offset: skip flags(2) + power(2) + optional fields before crank data
        var offset = 4  // flags(2) + power(2)
        
        // Bit 0: Pedal Power Balance Present (adds 1 byte)
        if (flags & 0x0001) != 0 { offset += 1 }
        
        // Bit 2: Accumulated Torque Present (adds 2 bytes)
        if (flags & 0x0004) != 0 { offset += 2 }
        
        // Bit 4: Wheel Revolution Data Present (adds 6 bytes: 4 + 2)
        if (flags & 0x0010) != 0 { offset += 6 }
        
        // Now we should be at Crank Revolution Data
        // Format: Cumulative Crank Revolutions (uint16) + Last Crank Event Time (uint16)
        guard data.count >= offset + 4 else {
            print("⚠️ [BLE Cadence] Packet too short for crank data: \(data.count) bytes, need \(offset + 4)")
            return nil
        }
        
        let crankRevs = UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
        let crankTime = UInt16(data[offset + 2]) | (UInt16(data[offset + 3]) << 8)
        
        // Calculate cadence from deltas
        if let prevRevs = lastCrankRevs, let prevTime = lastCrankTime {
            // Handle wrap-around for UInt16
            let revDelta = crankRevs &- prevRevs  // Wrapping subtraction
            let timeDelta = crankTime &- prevTime  // Time in 1/1024 seconds
            
            // If no revolutions happened, cadence is 0
            if revDelta == 0 {
                lastCrankRevs = crankRevs
                lastCrankTime = crankTime
                return 0
            }
            
            // Only calculate if we have a reasonable time delta (> 0 and < 5 seconds)
            if timeDelta > 0 && timeDelta < 5120 {  // 5 seconds = 5 * 1024
                // Cadence (RPM) = (revolutions / time_in_seconds) * 60
                // Time is in 1/1024 seconds, so time_in_seconds = timeDelta / 1024
                // RPM = (revDelta / (timeDelta / 1024)) * 60
                // RPM = (revDelta * 1024 * 60) / timeDelta
                let cadence = (Double(revDelta) * 1024.0 * 60.0) / Double(timeDelta)
                
                // Store current values for next calculation
                lastCrankRevs = crankRevs
                lastCrankTime = crankTime
                
                // Sanity check: cadence should be 0-250 RPM
                if cadence >= 0 && cadence <= 250 {
                    return Int(cadence.rounded())
                } else {
                    print("⚠️ [BLE Cadence] Calculated cadence out of range: \(cadence) RPM")
                }
            } else {
                print("⚠️ [BLE Cadence] Time delta out of range: \(timeDelta)")
            }
        }
        
        // Store current values for next calculation
        lastCrankRevs = crankRevs
        lastCrankTime = crankTime
        
        return nil  // First reading or invalid delta
    }

    private func upsertCandidate(_ p: CBPeripheral, rssi: Int, isHR: Bool, isPower: Bool) {
        peripheralsByID[p.identifier] = p

        if isHR {
            let item = PeripheralItem(id: p.identifier, name: p.nameOrUnknown, rssi: rssi)
            if let idx = hrCandidates.firstIndex(where: { $0.id == item.id }) { hrCandidates[idx] = item }
            else { hrCandidates.append(item) }
            hrCandidates.sort { $0.rssi > $1.rssi }
        }

        if isPower {
            let item = PeripheralItem(id: p.identifier, name: p.nameOrUnknown, rssi: rssi)
            if let idx = powerCandidates.firstIndex(where: { $0.id == item.id }) { powerCandidates[idx] = item }
            else { powerCandidates.append(item) }
            powerCandidates.sort { $0.rssi > $1.rssi }
        }
    }
}

extension BluetoothSensorsViewModel: @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let mapped: BTState
        switch central.state {
        case .unknown:      mapped = .unknown
        case .resetting:    mapped = .resetting
        case .unsupported:  mapped = .unsupported
        case .unauthorized: mapped = .unauthorized
        case .poweredOff:   mapped = .poweredOff
        case .poweredOn:    mapped = .poweredOn
        @unknown default:   mapped = .unknown
        }
        btState = mapped
        status = "Bluetooth: \(mapped.rawValue)"
        if mapped != .poweredOn { stopScan() }
        
        // Handle deferred auto-reconnect
        if mapped == .poweredOn,
           pendingAutoReconnectHR != nil || pendingAutoReconnectPower != nil {
            let hr = pendingAutoReconnectHR
            let pwr = pendingAutoReconnectPower
            pendingAutoReconnectHR = nil
            pendingAutoReconnectPower = nil
            performAutoReconnect(hrUUID: hr, powerUUID: pwr)
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any],
                        rssi RSSI: NSNumber) {
        let rssi = RSSI.intValue
        let advServices = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
        let isHR = advServices.contains(.heartRateService)
        let isPower = advServices.contains(.cyclingPowerService)
        upsertCandidate(peripheral, rssi: rssi, isHR: isHR, isPower: isPower)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        status = "Connected: \(peripheral.nameOrUnknown). Discovering services…"
        peripheral.delegate = self
        peripheral.discoverServices([.heartRateService, .cyclingPowerService])

        let isHR = peripheral.identifier == hrPeripheral?.identifier
        let isPower = peripheral.identifier == powerPeripheral?.identifier

        if isHR {
            connectedHRName = peripheral.nameOrUnknown
            connectedHRPeripheralID = peripheral.identifier.uuidString
            hrRetryTask?.cancel(); hrRetryCount = 0; isRetryingHR = false
        }
        if isPower {
            connectedPowerName = peripheral.nameOrUnknown
            connectedPowerPeripheralID = peripheral.identifier.uuidString
            powerRetryTask?.cancel(); powerRetryCount = 0; isRetryingPower = false
        }

        // Notify caller so they can persist the device for auto-reconnect
        if isHR || isPower {
            onDeviceConnected?(
                peripheral.identifier.uuidString,
                peripheral.nameOrUnknown,
                isHR,
                isPower
            )
        }
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        let errorMsg = error?.localizedDescription ?? "Unknown error"
        status = "Failed to connect: \(peripheral.nameOrUnknown) - \(errorMsg)"
        print("❌ [BLE] Connection failed: \(peripheral.nameOrUnknown) - \(errorMsg)")

        guard !userRequestedDisconnect else { return }

        // Retry with backoff
        let isHR = peripheral.identifier == hrPeripheral?.identifier
        let isPower = peripheral.identifier == powerPeripheral?.identifier
        if isHR { retryConnect(peripheral: peripheral, isHR: true) }
        if isPower { retryConnect(peripheral: peripheral, isHR: false) }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let isHR = peripheral.identifier == hrPeripheral?.identifier
        let isPower = peripheral.identifier == powerPeripheral?.identifier

        if let error {
            status = "Disconnected: \(peripheral.nameOrUnknown) - \(error.localizedDescription)"
            print("❌ [BLE] Disconnected with error: \(peripheral.nameOrUnknown) - \(error.localizedDescription)")
        } else {
            status = "Disconnected: \(peripheral.nameOrUnknown)"
            print("ℹ️ [BLE] Clean disconnect: \(peripheral.nameOrUnknown)")
        }

        // Clear live data
        if isHR {
            connectedHRName = nil; connectedHRPeripheralID = nil; heartRateBPM = nil
        }
        if isPower {
            connectedPowerName = nil; connectedPowerPeripheralID = nil; powerWatts = nil
            cadenceRPM = nil; lastCrankRevs = nil; lastCrankTime = nil
        }

        // Auto-retry on unexpected disconnect (error present = connection dropped)
        // Skip if user explicitly disconnected
        if error != nil, !userRequestedDisconnect {
            if isHR {
                print("🔄 [BLE] Unexpected HR disconnect, will retry…")
                retryConnect(peripheral: peripheral, isHR: true)
            }
            if isPower {
                print("🔄 [BLE] Unexpected Power disconnect, will retry…")
                retryConnect(peripheral: peripheral, isHR: false)
            }
        } else {
            // Clean disconnect — clear peripheral references
            if isHR { hrPeripheral = nil }
            if isPower { powerPeripheral = nil }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            status = "Service discovery error: \(error.localizedDescription)"
            print("❌ [BLE] Service discovery failed: \(error.localizedDescription)")
            return
        }
        for s in peripheral.services ?? [] {
            if s.uuid == .heartRateService {
                peripheral.discoverCharacteristics([.hrMeasurement], for: s)
            } else if s.uuid == .cyclingPowerService {
                peripheral.discoverCharacteristics([.cyclingPowerMeasure], for: s)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error {
            status = "Char discovery error: \(error.localizedDescription)"
            print("❌ [BLE] Characteristic discovery failed: \(error.localizedDescription)")
            return
        }
        for c in service.characteristics ?? [] {
            if service.uuid == .heartRateService, c.uuid == .hrMeasurement {
                peripheral.setNotifyValue(true, for: c)
                status = "Subscribed HR measurement"
                print("✅ [BLE] Subscribed to HR notifications")
            }
            if service.uuid == .cyclingPowerService, c.uuid == .cyclingPowerMeasure {
                peripheral.setNotifyValue(true, for: c)
                status = "Subscribed power measurement"
                print("✅ [BLE] Subscribed to power notifications")
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            status = "Notify error: \(error.localizedDescription)"
            print("❌ [BLE] Notification error: \(error.localizedDescription)")
            return
        }
        guard let data = characteristic.value else {
            print("⚠️ [BLE] No data in characteristic update")
            return
        }
        
        // FIXED: Proper cadence calculation flow
        if characteristic.uuid == .hrMeasurement {
            if let bpm = parseHeartRate(from: data) {
                heartRateBPM = bpm
            }
        } else if characteristic.uuid == .cyclingPowerMeasure {
            // Always try to parse both power and cadence from the same packet
            if let w = parseInstantPower(from: data) {
                powerWatts = w
            }
            
            // Try to parse cadence independently
            // This will return nil if crank data isn't present or first reading
            if let rpm = parseCadence(from: data) {
                cadenceRPM = rpm
            } else if powerWatts == 0 {
                // Only set cadence to 0 if power is 0 AND parsing returned nil
                // This handles the case where the rider stops pedaling
                cadenceRPM = 0
            }
            // Otherwise, keep the last cadence value (don't set to nil)
        }
    }
}
