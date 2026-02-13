import SwiftUI

struct ContentView: View {
    @ObservedObject var bt: BluetoothSensorsViewModel
    @StateObject private var lifx = LIFXDiscoveryViewModel()
    @StateObject private var auto = AutoColorController()
    @StateObject private var store = UserConfigStore()
    @StateObject private var charts = ChartsViewModel()  // NEW: Charts view model

    private let intFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .none
        return f
    }()

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {

                // Compact BT status bar (config moved to Settings)
                BluetoothStatusBar(bt: bt)

                LIFXPanel(vm: lifx, store: store)
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                Divider()

                AutoColorPanel(
                    auto: auto,
                    store: store,
                    formatter: intFormatter,
                    onSave: saveAll,
                    onReset: resetAll
                )
                
                Divider()
                
                // NEW: Charts panel
                ChartsPanel(charts: charts)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .environmentObject(bt)
        .task {
            store.load()
            auto.bind(lifx: lifx, bt: bt)
            charts.bind(bt: bt)  // NEW: Bind charts to BT data
            applyStore()
            
            // Remember connected devices for auto-reconnect
            bt.onDeviceConnected = { [weak store] id, name, isHR, isPower in
                guard let store else { return }
                if isHR {
                    store.lastHRPeripheralID = id
                    store.lastHRPeripheralName = name
                }
                if isPower {
                    store.lastPowerPeripheralID = id
                    store.lastPowerPeripheralName = name
                }
                store.save()
            }
            
            // Auto-reconnect to last known devices
            if store.btAutoReconnect {
                bt.autoReconnect(
                    hrUUID: store.lastHRPeripheralID,
                    powerUUID: store.lastPowerPeripheralID
                )
            }
            
            // Listen for settings changes from Settings window
            NotificationCenter.default.addObserver(
                forName: .settingsDidChange,
                object: nil,
                queue: .main
            ) { _ in
                Task { @MainActor in
                    store.load()
                    applyStore()
                }
            }
        }
        .onChange(of: lifx.aliasByID) { _, newValue in
            store.aliasesByID = newValue
        }
        .onChange(of: store.weightKg) { _, newValue in
            charts.weightKg = newValue  // NEW: Update charts when weight changes
        }
        .onDisappear {
            saveAll()
            lifx.stop()
            bt.stopScan()
            bt.disconnectAll()
            auto.stop()
            charts.stop()  // NEW: Stop charts sampling
        }
    }

    private func applyStore() {
        auto.dateOfBirth = store.dateOfBirth
        auto.ftp = store.ftp
        auto.weightKg = store.weightKg
        auto.source = AutoColorController.Source(rawValue: store.autoSourceRaw) ?? .off
        auto.powerMovingAverageSeconds = store.powerMovingAverageSeconds
        auto.modulateIntensityWithHR = store.modulateIntensityWithHR
        auto.minIntensityPercent = store.minIntensityPercent
        auto.maxIntensityPercent = store.maxIntensityPercent
        lifx.aliasByID = store.aliasesByID
        
        // NEW: Update charts weight
        charts.weightKg = store.weightKg
    }

    private func saveAll() {
        store.dateOfBirth = auto.dateOfBirth
        store.ftp = auto.ftp
        store.weightKg = auto.weightKg
        store.autoSourceRaw = auto.source.rawValue
        store.powerMovingAverageSeconds = auto.powerMovingAverageSeconds
        store.modulateIntensityWithHR = auto.modulateIntensityWithHR
        store.minIntensityPercent = auto.minIntensityPercent
        store.maxIntensityPercent = auto.maxIntensityPercent
        store.aliasesByID = lifx.aliasByID
        store.save()
    }

    private func resetAll() {
        store.resetToDefaults()
        applyStore()
    }
}
