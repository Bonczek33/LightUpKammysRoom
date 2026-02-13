import SwiftUI

struct ContentView: View {
    @StateObject private var lifx = LIFXDiscoveryViewModel()
    @StateObject private var bt = BluetoothSensorsViewModel()
    @StateObject private var auto = AutoColorController()
    @StateObject private var store = UserConfigStore()

    private let intFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .none
        return f
    }()

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {

                // Layout: left BT panel, right wider LIFX panel (Option 2)
                HStack(alignment: .top, spacing: 16) {
                    BluetoothPanel(bt: bt)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    LIFXPanel(vm: lifx, store: store)
                        .frame(
                            minWidth: 900,
                            idealWidth: 1040,
                            maxWidth: 1200,
                            alignment: .topTrailing
                        )
                }
                .frame(maxWidth: .infinity)

                Divider()

                AutoColorPanel(
                    auto: auto,
                    store: store,
                    formatter: intFormatter,
                    onSave: saveAll,
                    onReset: resetAll
                )
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .task {
            store.load()
            auto.bind(lifx: lifx, bt: bt)
            applyStore()
            
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
        .onDisappear {
            saveAll()
            lifx.stop()
            bt.stopScan()
            bt.disconnectAll()
            auto.stop()
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
