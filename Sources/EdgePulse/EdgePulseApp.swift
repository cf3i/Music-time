import AppKit
import Combine
import SwiftUI

@main
struct EdgePulseApp: App {
    @NSApplicationDelegateAdaptor(EdgePulseAppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            ControlPanelView(model: AppModel.shared)
        } label: {
            Label("EdgePulse", systemImage: "waveform.path.ecg")
        }
        .menuBarExtraStyle(.window)
    }
}

final class EdgePulseAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppModel.shared.activate()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.shutdown()
    }
}

final class AppModel: ObservableObject {
    static let shared = AppModel()

    let settings = SettingsStore()
    let analyzer = AudioAnalyzer()

    @Published private(set) var status = "Starting…"
    @Published private(set) var needsPermission = false

    private lazy var overlays = OverlayManager(analyzer: analyzer, settings: settings)
    private lazy var capture = SystemAudioCapture()
    private var cancellables = Set<AnyCancellable>()
    private var isActive = false

    private init() {
        settings.$smoothing
            .sink { [weak analyzer] value in
                analyzer?.smoothing = Float(value)
            }
            .store(in: &cancellables)

        settings.$enabled
            .dropFirst()
            .sink { [weak self] enabled in
                guard self?.isActive == true else { return }
                self?.setEnabled(enabled)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                guard let self, self.settings.enabled else { return }
                self.overlays.rebuild()
            }
            .store(in: &cancellables)
    }

    func activate() {
        guard !isActive else { return }
        isActive = true

        capture.onSamples = { [weak analyzer] samples in
            analyzer?.ingest(samples)
        }
        capture.onStateChange = { [weak self] state in
            DispatchQueue.main.async {
                self?.applyCaptureState(state)
            }
        }

        setEnabled(settings.enabled)
    }

    func shutdown() {
        capture.stop()
        overlays.hide()
    }

    func openScreenRecordingSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func setEnabled(_ enabled: Bool) {
        if enabled {
            overlays.show()
            status = "Connecting to system audio…"
            needsPermission = false
            capture.start()
        } else {
            capture.stop()
            analyzer.reset()
            overlays.hide()
            status = "Paused"
            needsPermission = false
        }
    }

    private func applyCaptureState(_ state: SystemAudioCapture.State) {
        switch state {
        case .idle:
            if settings.enabled {
                status = "Stopped"
            }
        case .starting:
            status = "Connecting to system audio…"
            needsPermission = false
        case .running:
            status = "Listening to system audio"
            needsPermission = false
        case .permissionRequired:
            status = "Screen & System Audio permission required"
            needsPermission = true
        case .failed(let message):
            status = "Audio capture failed: \(message)"
            needsPermission = false
        }
    }
}
