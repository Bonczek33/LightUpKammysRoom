//
//  ANTPlusSensorViewModel.swift
//  LIFXBTMacApp
//
//  Created by Tomasz Bak on 2/17/26.
//

import Foundation
import IOKit
import IOKit.usb

private enum ANT {
    static let syncByte: UInt8 = 0xA4

    // Message IDs (Host → Device)
    static let msgUnassignChannel:    UInt8 = 0x41
    static let msgAssignChannel:      UInt8 = 0x42
    static let msgSetChannelPeriod:   UInt8 = 0x43
    static let msgSetSearchTimeout:   UInt8 = 0x44
    static let msgSetRFFrequency:     UInt8 = 0x45
    static let msgSetNetworkKey:      UInt8 = 0x46
    static let msgResetSystem:        UInt8 = 0x4A
    static let msgOpenChannel:        UInt8 = 0x4B
    static let msgCloseChannel:       UInt8 = 0x4C
    static let msgSetChannelID:       UInt8 = 0x51

    // Message IDs (Device → Host)
    static let msgBroadcastData:      UInt8 = 0x4E
    static let msgChannelResponse:    UInt8 = 0x40
    static let msgStartup:            UInt8 = 0x6F

    // Channel response codes
    static let eventRxSearchTimeout:  UInt8 = 0x01

    // Channel types
    static let channelTypeSlaveRX:    UInt8 = 0x00

    // ANT+ RF settings
    static let rfFrequency:           UInt8 = 57  // 2457 MHz

    // Public ANT+ key
    static let networkKey: [UInt8] = [0xB9, 0xA5, 0x21, 0xFB, 0xBD, 0x72, 0xC3, 0x45]

    enum Profile {
        case heartRate
        case power

        var deviceType: UInt8 {
            switch self {
            case .heartRate: return 120
            case .power:     return 11
            }
        }

        var channelPeriod: UInt16 {
            switch self {
            case .heartRate: return 8070
            case .power:     return 8182
            }
        }
    }

    // Vendor IDs
    static let dynastreamVendorID: Int = 0x0FCF
    static let garminVendorID: Int     = 0x091E

    // Product IDs
    static let knownProductIDs: [Int] = [
        0x1004, 0x1006, 0x1008, 0x1009
    ]

    // Tuning
    static let resetDelayNs: UInt64 = 150_000_000       // 150ms
    static let initNoPacketNoticeNs: UInt64 = 3_000_000_000 // 3s
    static let readBufferSize = 64
}

@MainActor
final class ANTPlusSensorViewModel: NSObject, ObservableObject, @unchecked Sendable {

    // MARK: - Background parsing

    /// Parsed events emitted by the background ANT parser.
    private enum ParsedEvent {
        case heartRate(bpm: Int, firstPacket: Bool)
        case power(watts: Int, cadence: Int?, firstPacket: Bool)
        case cadence(rpm: Int)
        case channelSearchTimeout(channel: UInt8)
        case channelID(channel: UInt8, deviceNumber: UInt16)
    }

    /// Stateful parser that runs on the USB read-loop task (off the MainActor).
    /// Keeps buffering + checksum validation + page parsing out of the UI thread.
    private final class BackgroundParser {
        private let hrChannel: UInt8
        private let powerChannel: UInt8

        private var rxBuffer: [UInt8] = []

        // cadence from crank torque page (page 0x12)
        private var lastCrankEventTime: UInt16 = 0
        private var lastCrankRevolutions: UInt16 = 0
        private var crankDataInitialized = false

        private(set) var hrDeviceFound = false
        private(set) var powerDeviceFound = false

        init(hrChannel: UInt8, powerChannel: UInt8) {
            self.hrChannel = hrChannel
            self.powerChannel = powerChannel
        }

        func reset() {
            rxBuffer.removeAll(keepingCapacity: true)
            lastCrankEventTime = 0
            lastCrankRevolutions = 0
            crankDataInitialized = false
            hrDeviceFound = false
            powerDeviceFound = false
        }

        func ingest(_ bytes: [UInt8]) -> [ParsedEvent] {
            if !bytes.isEmpty {
                rxBuffer.append(contentsOf: bytes)
            }
            return drainRXBuffer()
        }

        private func drainRXBuffer() -> [ParsedEvent] {
            var events: [ParsedEvent] = []
            var offset = 0

            while rxBuffer.count - offset >= 4 {
                if rxBuffer[offset] != ANT.syncByte {
                    offset += 1
                    continue
                }

                let length = Int(rxBuffer[offset + 1])
                let totalLen = 4 + length
                if rxBuffer.count - offset < totalLen { break }

                var c: UInt8 = 0
                for i in offset..<(offset + totalLen) { c ^= rxBuffer[i] }
                if c != 0 {
                    offset += 1
                    continue
                }

                let msgID = rxBuffer[offset + 2]
                let payload = Array(rxBuffer[(offset + 3)..<(offset + 3 + length)])

                switch msgID {
                case ANT.msgBroadcastData:
                    events.append(contentsOf: handleBroadcastData(payload))
                case ANT.msgChannelResponse:
                    if let ev = handleChannelResponse(payload) { events.append(ev) }
                case ANT.msgSetChannelID:
                    if let ev = handleChannelIDResponse(payload) { events.append(ev) }
                case ANT.msgStartup:
                    break
                default:
                    break
                }

                offset += totalLen
            }

            if offset > 0 { rxBuffer.removeFirst(offset) }
            return events
        }

        private func handleBroadcastData(_ payload: [UInt8]) -> [ParsedEvent] {
            guard payload.count >= 9 else { return [] }
            let channel = payload[0]
            let dataPage = payload[1]
            let data = Array(payload[1..<9])

            if channel == hrChannel {
                return parseHeartRate(data: data).map { [$0] } ?? []
            } else if channel == powerChannel {
                return parsePower(data: data, dataPage: dataPage)
            }
            return []
        }

        private func handleChannelResponse(_ payload: [UInt8]) -> ParsedEvent? {
            guard payload.count >= 3 else { return nil }
            let channel = payload[0]
            let msgID = payload[1]
            let eventCode = payload[2]

            if msgID == 0x01, eventCode == ANT.eventRxSearchTimeout {
                return .channelSearchTimeout(channel: channel)
            }
            return nil
        }

        private func handleChannelIDResponse(_ payload: [UInt8]) -> ParsedEvent? {
            guard payload.count >= 5 else { return nil }
            let channel = payload[0]
            let deviceNumber = UInt16(payload[1]) | (UInt16(payload[2]) << 8)
            guard deviceNumber != 0 else { return nil }
            return .channelID(channel: channel, deviceNumber: deviceNumber)
        }

        private func parseHeartRate(data: [UInt8]) -> ParsedEvent? {
            guard data.count >= 8 else { return nil }
            let instantHR = Int(data[7])
            guard instantHR > 0, instantHR < 255 else { return nil }

            let first = !hrDeviceFound
            if first { hrDeviceFound = true }
            return .heartRate(bpm: instantHR, firstPacket: first)
        }

        private func parsePower(data: [UInt8], dataPage: UInt8) -> [ParsedEvent] {
            guard data.count >= 8 else { return [] }

            switch dataPage {
            case 0x10:
                let instantCadence = Int(data[3])
                let instantPower = Int(data[6]) | (Int(data[7]) << 8)

                let cadence: Int?
                if instantCadence < 255 && instantCadence > 0 {
                    cadence = instantCadence
                } else {
                    cadence = nil
                }

                let first = !powerDeviceFound
                if first { powerDeviceFound = true }

                return [.power(watts: instantPower, cadence: cadence, firstPacket: first)]

            case 0x12:
                let crankEventTime = UInt16(data[4]) | (UInt16(data[5]) << 8)
                let crankRevolutions = UInt16(data[6]) | (UInt16(data[7]) << 8)

                defer {
                    lastCrankEventTime = crankEventTime
                    lastCrankRevolutions = crankRevolutions
                    crankDataInitialized = true
                }

                guard crankDataInitialized else { return [] }

                let timeDiff = crankEventTime &- lastCrankEventTime
                let revDiff = crankRevolutions &- lastCrankRevolutions
                guard timeDiff > 0, revDiff > 0, revDiff < 10 else { return [] }

                let timeSeconds = Double(timeDiff) / 2048.0
                guard timeSeconds > 0 else { return [] }

                let rpm = Int((Double(revDiff) / timeSeconds * 60.0).rounded())
                guard rpm > 0, rpm < 300 else { return [] }
                return [.cadence(rpm: rpm)]

            default:
                return []
            }
        }
    }

    enum ConnectionState: String {
        case disconnected = "No ANT+ stick"
        case searching = "Searching for sensors…"
        case connected = "ANT+ connected"
        case error = "ANT+ error"
    }

    @Published private(set) var heartRateBPM: Int? = nil
    @Published private(set) var powerWatts: Int? = nil
    @Published private(set) var cadenceRPM: Int? = nil

    @Published private(set) var state: ConnectionState = .disconnected
    @Published private(set) var status: String = "ANT+: idle"
    @Published private(set) var connectedHRName: String? = nil
    @Published private(set) var connectedPowerName: String? = nil
    @Published private(set) var donglesAvailable: Int = 0

    @Published private(set) var connectedHRDeviceNumber: UInt16? = nil
    @Published private(set) var connectedPowerDeviceNumber: UInt16? = nil

    var onDeviceConnected: ((UInt16, String, Bool, Bool) -> Void)?

    override init() {
        self.parser = BackgroundParser(hrChannel: 0, powerChannel: 1)
        super.init()
    }

    private var readTask: Task<Void, Never>? = nil
    private var isOpen = false

    private let hrChannel: UInt8 = 0
    private let powerChannel: UInt8 = 1

    private var targetHRDeviceNumber: UInt16 = 0
    private var targetPowerDeviceNumber: UInt16 = 0

    private var hrDeviceFound = false
    private var powerDeviceFound = false

    // ✅ Background parser (buffering + parsing off the MainActor)
    nonisolated(unsafe) private let parser: BackgroundParser

    // IOKit pointers
    private var deviceInterfacePtr: UnsafeMutablePointer<UnsafeMutablePointer<IOUSBDeviceInterface182>>? = nil
    private var interfaceInterfacePtr: UnsafeMutablePointer<UnsafeMutablePointer<IOUSBInterfaceInterface182>>? = nil
    private var inPipeRef: UInt8 = 0
    private var outPipeRef: UInt8 = 0

    // CFUUID constants not bridged to Swift
    private static let kIOUSBDeviceUserClientTypeUUID = CFUUIDGetConstantUUIDWithBytes(nil,
        0x9d, 0xc7, 0xb7, 0x80, 0x9e, 0xc0, 0x11, 0xD4,
        0xa5, 0x4f, 0x00, 0x0a, 0x27, 0x05, 0x28, 0x61)!
    private static let kIOUSBInterfaceUserClientTypeUUID = CFUUIDGetConstantUUIDWithBytes(nil,
        0x2d, 0x97, 0x86, 0xc6, 0x9e, 0xf3, 0x11, 0xD4,
        0xad, 0x51, 0x00, 0x0a, 0x27, 0x05, 0x28, 0x61)!
    private static let kIOCFPlugInInterfaceUUID = CFUUIDGetConstantUUIDWithBytes(nil,
        0xC2, 0x44, 0xE8, 0x58, 0x10, 0x9C, 0x11, 0xD4,
        0x91, 0xD4, 0x00, 0x50, 0xE4, 0xC6, 0x42, 0x6F)!
    private static let kIOUSBDeviceInterfaceUUID = CFUUIDGetConstantUUIDWithBytes(nil,
        0x5c, 0x81, 0x87, 0xd0, 0x9e, 0xf3, 0x11, 0xD4,
        0x8b, 0x45, 0x00, 0x0a, 0x27, 0x05, 0x28, 0x61)!
    private static let kIOUSBInterfaceInterfaceUUID = CFUUIDGetConstantUUIDWithBytes(nil,
        0x73, 0xc9, 0x7a, 0xe8, 0x9e, 0xf3, 0x11, 0xD4,
        0xb1, 0xd0, 0x00, 0x0a, 0x27, 0x05, 0x28, 0x61)!

    // MARK: - Public API

    func start() {
        // ✅ prevent restart races
        guard !isOpen else { return }
        guard readTask == nil else { return }

        state = .disconnected
        status = "ANT+: scanning for USB stick…"

        Task.detached(priority: .userInitiated) { [weak self] in
            await self?.openDongle()
        }
    }


    /// Configure target device numbers (0 = wildcard) and start the dongle.
    /// Used by ContentView for "auto-reconnect" behavior.
    func autoReconnect(hrDeviceNumber: UInt16?, powerDeviceNumber: UInt16?) {
        targetHRDeviceNumber = hrDeviceNumber ?? 0
        targetPowerDeviceNumber = powerDeviceNumber ?? 0

        // If we're already running, restart channels so the new targets take effect.
        if isOpen {
            stop()
        }
        start()
    }

    func stop() {
        // Abort any blocking ReadPipe first, then cancel the read task.
        abortUSBPipes()

        let task = readTask
        task?.cancel()
        readTask = nil

        // Release USB resources only after the read loop has fully exited
        // to avoid use-after-free on interface pointers.
        if let task {
            Task { @MainActor [weak self] in
                _ = await task.result
                self?.closeUSB()
            }
        } else {
            closeUSB()
        }

        isOpen = false

        heartRateBPM = nil
        powerWatts = nil
        cadenceRPM = nil
        connectedHRName = nil
        connectedPowerName = nil
        connectedHRDeviceNumber = nil
        connectedPowerDeviceNumber = nil
        hrDeviceFound = false
        powerDeviceFound = false
        targetHRDeviceNumber = 0
        targetPowerDeviceNumber = 0
        parser.reset()

        state = .disconnected
        status = "ANT+: idle"
    }

    // MARK: - Init

    private func openDongle() async {
        await MainActor.run {
            self.status = "ANT+: scanning USB devices…"
            self.state = .disconnected
        }

        guard let service = findANTDevice() else {
            await MainActor.run {
                self.state = .disconnected
                self.status = "ANT+: no USB dongle found. Plug in an ANT+ stick."
                self.donglesAvailable = 0
            }
            return
        }

        // ✅ always release the retained service
        defer { IOObjectRelease(service) }

        await MainActor.run {
            self.donglesAvailable = 1
            self.status = "ANT+: opening USB interface…"
        }

        guard openUSBDevice(service) else {
            await MainActor.run {
                self.state = .error
                self.status = "ANT+: failed to open USB device"
            }
            return
        }

        await MainActor.run {
            self.isOpen = true
            self.state = .searching
            self.status = "ANT+: resetting radio…"
        }

        sendMessage(id: ANT.msgResetSystem, data: [0x00])
        try? await Task.sleep(nanoseconds: ANT.resetDelayNs)

        await MainActor.run { self.status = "ANT+: configuring channels…" }

        sendMessage(id: ANT.msgSetNetworkKey, data: [0x00] + ANT.networkKey)

        configureChannel(channel: hrChannel, profile: .heartRate)
        configureChannel(channel: powerChannel, profile: .power)

        await MainActor.run { self.status = "ANT+: waiting for sensor packets…" }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: ANT.initNoPacketNoticeNs)
            if self.isOpen && !self.hrDeviceFound && !self.powerDeviceFound {
                self.status = "ANT+: still searching… (no packets yet)"
            }
        }

        if let ifPtr = self.interfaceInterfacePtr, self.inPipeRef != 0 {
            let interfacePtr = ifPtr
            let inPipe = self.inPipeRef
            readTask = Task.detached(priority: .userInitiated) { [weak self] in
                guard let self else { return }
                await self.readLoop(interfacePtr: interfacePtr, inPipe: inPipe)
            }
        }
    }

    private func configureChannel(channel: UInt8, profile: ANT.Profile) {
        sendMessage(id: ANT.msgCloseChannel, data: [channel])
        sendMessage(id: ANT.msgUnassignChannel, data: [channel])

        sendMessage(id: ANT.msgAssignChannel, data: [channel, ANT.channelTypeSlaveRX, 0x00])

        let devNum: UInt16 = (profile == .heartRate) ? targetHRDeviceNumber : targetPowerDeviceNumber
        sendMessage(id: ANT.msgSetChannelID, data: [
            channel,
            UInt8(devNum & 0xFF), UInt8(devNum >> 8),
            profile.deviceType,
            0x00
        ])

        let period = profile.channelPeriod
        sendMessage(id: ANT.msgSetChannelPeriod, data: [channel, UInt8(period & 0xFF), UInt8(period >> 8)])

        sendMessage(id: ANT.msgSetRFFrequency, data: [channel, ANT.rfFrequency])

        sendMessage(id: ANT.msgSetSearchTimeout, data: [channel, 0xFF])

        sendMessage(id: ANT.msgOpenChannel, data: [channel])
    }

    // MARK: - ANT framing + RX parsing

    private func sendMessage(id: UInt8, data: [UInt8]) {
        var msg: [UInt8] = [ANT.syncByte, UInt8(data.count), id] + data
        var checksum: UInt8 = 0
        for b in msg { checksum ^= b }
        msg.append(checksum)
        writeToUSB(Data(msg))
    }

    private func requestChannelID(channel: UInt8) {
        sendMessage(id: 0x4D, data: [channel, ANT.msgSetChannelID])
    }

    // Applies a batch of parsed updates on the MainActor.
    private func applyParsedEvents(_ events: [ParsedEvent]) {
        var shouldUpdateStatus = false

        for ev in events {
            switch ev {
            case let .heartRate(bpm, firstPacket):
                heartRateBPM = bpm
                if firstPacket {
                    hrDeviceFound = true
                    connectedHRName = "ANT+ HR Sensor"
                    state = .connected
                    shouldUpdateStatus = true
                    requestChannelID(channel: hrChannel)
                }

            case let .power(watts, cadence, firstPacket):
                powerWatts = watts
                if let cadence { cadenceRPM = cadence }
                if firstPacket {
                    powerDeviceFound = true
                    connectedPowerName = "ANT+ Power Meter"
                    state = .connected
                    shouldUpdateStatus = true
                    requestChannelID(channel: powerChannel)
                }

            case let .cadence(rpm):
                cadenceRPM = rpm

            case let .channelSearchTimeout(channel):
                if channel == hrChannel {
                    connectedHRName = nil
                    heartRateBPM = nil
                    connectedHRDeviceNumber = nil
                    hrDeviceFound = false
                }
                if channel == powerChannel {
                    connectedPowerName = nil
                    powerWatts = nil
                    cadenceRPM = nil
                    connectedPowerDeviceNumber = nil
                    powerDeviceFound = false
                }
                status = "ANT+: search timeout on ch \(channel), reopening…"
                shouldUpdateStatus = true

                let profile: ANT.Profile = (channel == hrChannel) ? .heartRate : .power
                configureChannel(channel: channel, profile: profile)

            case let .channelID(channel, deviceNumber):
                if channel == hrChannel {
                    connectedHRDeviceNumber = deviceNumber
                    connectedHRName = "ANT+ HR #\(deviceNumber)"
                    onDeviceConnected?(deviceNumber, connectedHRName ?? "", true, false)
                } else if channel == powerChannel {
                    connectedPowerDeviceNumber = deviceNumber
                    connectedPowerName = "ANT+ Power #\(deviceNumber)"
                    onDeviceConnected?(deviceNumber, connectedPowerName ?? "", false, true)
                }
                shouldUpdateStatus = true
            }
        }

        if shouldUpdateStatus {
            updateStatus()
        }
    }

    private func updateStatus() {
        var parts: [String] = []
        if hrDeviceFound { parts.append("HR") }
        if powerDeviceFound { parts.append("Power") }

        if parts.isEmpty {
            status = "ANT+: waiting for sensor packets…"
        } else {
            status = "ANT+: \(parts.joined(separator: " + ")) connected"
        }
    }

    // MARK: - Device discovery (✅ retain returned service)

    private func findANTDevice() -> io_service_t? {
        let classNames: [String] = ["IOUSBHostDevice", kIOUSBDeviceClassName as String]

        for className in classNames {
            guard let matching = IOServiceMatching(className) else { continue }

            var iterator: io_iterator_t = 0
            let result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
            guard result == KERN_SUCCESS else { continue }
            defer { IOObjectRelease(iterator) }

            var service = IOIteratorNext(iterator)
            while service != 0 {
                func readIntProp(_ key: String) -> Int? {
                    let cf = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)
                    if let num = cf?.takeRetainedValue() as? NSNumber { return num.intValue }
                    return nil
                }

                let vid = readIntProp("idVendor") ?? readIntProp(kUSBVendorID as String)
                let pid = readIntProp("idProduct") ?? readIntProp(kUSBProductID as String)

                if let vid, let pid {
                    let vendorOK = (vid == ANT.dynastreamVendorID) || (vid == ANT.garminVendorID)
                    if vendorOK && ANT.knownProductIDs.contains(pid) {
                        IOObjectRetain(service)     // ✅ keep valid after iterator is released
                        return service
                    }
                }

                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
        }

        return nil
    }

    // MARK: - Open device + interface selection

    private func openUSBDevice(_ service: io_service_t) -> Bool {
        var score: Int32 = 0
        var plugInInterface: UnsafeMutablePointer<UnsafeMutablePointer<IOCFPlugInInterface>?>? = nil

        let kr = IOCreatePlugInInterfaceForService(
            service,
            Self.kIOUSBDeviceUserClientTypeUUID,
            Self.kIOCFPlugInInterfaceUUID,
            &plugInInterface,
            &score
        )
        guard kr == KERN_SUCCESS, let plugIn = plugInInterface else { return false }

        var deviceInterfaceRaw: LPVOID? = nil
        var usbDeviceUUID = CFUUIDGetUUIDBytes(Self.kIOUSBDeviceInterfaceUUID)

        withUnsafeMutablePointer(to: &usbDeviceUUID) { uuidPtr in
            _ = plugIn.pointee?.pointee.QueryInterface(
                plugIn,
                uuidPtr.withMemoryRebound(to: REFIID.self, capacity: 1) { $0.pointee },
                &deviceInterfaceRaw
            )
        }
        _ = plugIn.pointee?.pointee.Release(plugIn)

        guard let devRaw = deviceInterfaceRaw else { return false }

        deviceInterfacePtr = devRaw.assumingMemoryBound(to: UnsafeMutablePointer<IOUSBDeviceInterface182>.self)
        guard let dev = deviceInterfacePtr?.pointee.pointee else { return false }

        var openResult = dev.USBDeviceOpen(deviceInterfacePtr)
        if openResult == kIOReturnExclusiveAccess {
            openResult = dev.USBDeviceOpenSeize(deviceInterfacePtr)
        }
        guard openResult == kIOReturnSuccess else { return false }

        var configDesc: IOUSBConfigurationDescriptorPtr? = nil
        if dev.GetConfigurationDescriptorPtr(deviceInterfacePtr, 0, &configDesc) == kIOReturnSuccess {
            if let configValue = configDesc?.pointee.bConfigurationValue {
                _ = dev.SetConfiguration(deviceInterfacePtr, configValue)
            }
        }

        var request = IOUSBFindInterfaceRequest(
            bInterfaceClass: UInt16(kIOUSBFindInterfaceDontCare),
            bInterfaceSubClass: UInt16(kIOUSBFindInterfaceDontCare),
            bInterfaceProtocol: UInt16(kIOUSBFindInterfaceDontCare),
            bAlternateSetting: UInt16(kIOUSBFindInterfaceDontCare)
        )

        var interfaceIterator: io_iterator_t = 0
        guard dev.CreateInterfaceIterator(deviceInterfacePtr, &request, &interfaceIterator) == kIOReturnSuccess else {
            return false
        }
        defer { IOObjectRelease(interfaceIterator) }

        var candidate = IOIteratorNext(interfaceIterator)
        while candidate != 0 {
            if openUSBInterfaceAndFindPipes(candidate) {
                return true
            }
            IOObjectRelease(candidate)
            candidate = IOIteratorNext(interfaceIterator)
        }

        return false
    }

    private func openUSBInterfaceAndFindPipes(_ usbInterface: io_service_t) -> Bool {
        inPipeRef = 0
        outPipeRef = 0

        var ifacePlugIn: UnsafeMutablePointer<UnsafeMutablePointer<IOCFPlugInInterface>?>? = nil
        var ifaceScore: Int32 = 0

        guard IOCreatePlugInInterfaceForService(
            usbInterface,
            Self.kIOUSBInterfaceUserClientTypeUUID,
            Self.kIOCFPlugInInterfaceUUID,
            &ifacePlugIn,
            &ifaceScore
        ) == KERN_SUCCESS, let ifPlug = ifacePlugIn else {
            return false
        }

        var ifaceRaw: LPVOID? = nil
        var usbInterfaceUUID = CFUUIDGetUUIDBytes(Self.kIOUSBInterfaceInterfaceUUID)

        withUnsafeMutablePointer(to: &usbInterfaceUUID) { uuidPtr in
            _ = ifPlug.pointee?.pointee.QueryInterface(
                ifPlug,
                uuidPtr.withMemoryRebound(to: REFIID.self, capacity: 1) { $0.pointee },
                &ifaceRaw
            )
        }
        _ = ifPlug.pointee?.pointee.Release(ifPlug)

        guard let ifRawPtr = ifaceRaw else { return false }

        if interfaceInterfacePtr != nil {
            closeUSBInterfaceOnly()
        }

        interfaceInterfacePtr = ifRawPtr.assumingMemoryBound(to: UnsafeMutablePointer<IOUSBInterfaceInterface182>.self)
        guard let iface = interfaceInterfacePtr?.pointee.pointee else {
            closeUSBInterfaceOnly()
            return false
        }

        guard iface.USBInterfaceOpen(interfaceInterfacePtr) == kIOReturnSuccess else {
            closeUSBInterfaceOnly()
            return false
        }

        var numEndpoints: UInt8 = 0
        _ = iface.GetNumEndpoints(interfaceInterfacePtr, &numEndpoints)
        guard numEndpoints > 0 else {
            closeUSBInterfaceOnly()
            return false
        }

        for pipeIndex in UInt8(1)...numEndpoints {
            var direction: UInt8 = 0
            var number: UInt8 = 0
            var transferType: UInt8 = 0
            var maxPacketSize: UInt16 = 0
            var interval: UInt8 = 0

            let pipeResult = iface.GetPipeProperties(
                interfaceInterfacePtr,
                pipeIndex,
                &direction,
                &number,
                &transferType,
                &maxPacketSize,
                &interval
            )
            guard pipeResult == kIOReturnSuccess else { continue }

            if transferType == 2 { // bulk
                if direction == 1 { inPipeRef = pipeIndex }
                if direction == 0 { outPipeRef = pipeIndex }
            }
        }

        guard inPipeRef != 0, outPipeRef != 0 else {
            closeUSBInterfaceOnly()
            return false
        }

        return true
    }

    /// Abort any blocking pipe I/O without releasing the interface pointers.
    /// Safe to call before cancelling the read task.
    private func abortUSBPipes() {
        guard let iface = interfaceInterfacePtr?.pointee.pointee else { return }
        if inPipeRef != 0 {
            _ = iface.AbortPipe(interfaceInterfacePtr, inPipeRef)
        }
        if outPipeRef != 0 {
            _ = iface.AbortPipe(interfaceInterfacePtr, outPipeRef)
        }
    }

func closeUSBInterfaceOnly() {
        if let iface = interfaceInterfacePtr?.pointee.pointee {
            _ = iface.USBInterfaceClose(interfaceInterfacePtr)
        }
        if let ifPtr = interfaceInterfacePtr {
            _ = ifPtr.pointee.pointee.Release(interfaceInterfacePtr)
        }
        interfaceInterfacePtr = nil
        inPipeRef = 0
        outPipeRef = 0
    }

    private func closeUSB() {
        closeUSBInterfaceOnly()

        if let dev = deviceInterfacePtr?.pointee.pointee {
            _ = dev.USBDeviceClose(deviceInterfacePtr)
        }
        if let devPtr = deviceInterfacePtr {
            _ = devPtr.pointee.pointee.Release(deviceInterfacePtr)
        }
        deviceInterfacePtr = nil
    }

    // MARK: - USB Read / Write (correct pointers)

    private func writeToUSB(_ data: Data) {
        guard let iface = interfaceInterfacePtr?.pointee.pointee, outPipeRef != 0 else { return }

        let bytes = [UInt8](data)

        let result: IOReturn = bytes.withUnsafeBytes { rawBuf in
            guard let base = rawBuf.baseAddress else { return kIOReturnBadArgument }
            let ptr = UnsafeMutableRawPointer(mutating: base)
            return iface.WritePipe(interfaceInterfacePtr, outPipeRef, ptr, UInt32(bytes.count))
        }

        if result != kIOReturnSuccess {
            print("❌ [ANT+] WritePipe failed: 0x\(String(format: "%08X", result))")
        }
    }

    nonisolated private func readLoop(
        interfacePtr: UnsafeMutablePointer<UnsafeMutablePointer<IOUSBInterfaceInterface182>>,
        inPipe: UInt8
    ) async {
        var buffer = [UInt8](repeating: 0, count: ANT.readBufferSize)
        let iface = interfacePtr.pointee.pointee

        while !Task.isCancelled {
            var bytesRead: UInt32 = UInt32(buffer.count)
            let result: IOReturn = buffer.withUnsafeMutableBytes { rawBuf in
                guard let base = rawBuf.baseAddress else { return kIOReturnBadArgument }
                return iface.ReadPipe(interfacePtr, inPipe, base, &bytesRead)
            }

            if result == kIOReturnSuccess, bytesRead > 0 {
                let received = Array(buffer[0..<Int(bytesRead)])

                // Parse + buffer off-main, then publish changes on the MainActor.
                let events = parser.ingest(received)
                if !events.isEmpty {
                    await MainActor.run { [weak self] in
                        self?.applyParsedEvents(events)
                    }
                }

            } else if result == kIOReturnAborted || result == kIOReturnNotOpen {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.state = .disconnected
                    self.status = "ANT+: dongle disconnected"
                    self.heartRateBPM = nil
                    self.powerWatts = nil
                    self.cadenceRPM = nil
                    self.parser.reset()
                }
                break
            } else if result != kIOReturnSuccess {
                try? await Task.sleep(nanoseconds: 5_000_000)
            }
        }
    }

}

