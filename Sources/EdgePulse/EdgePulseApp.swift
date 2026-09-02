import AppKit
import Combine
import OSLog
import SwiftUI

@main
struct EdgePulseApp: App {
    @NSApplicationDelegateAdaptor(EdgePulseAppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            ControlPanelView(model: AppModel.shared)
        } label: {
            MenuBarPulseIcon()
                .accessibilityLabel("EdgePulse")
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

struct DisplayOption: Identifiable, Hashable, Sendable {
    let id: UInt32
    let title: String
}

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    let settings = SettingsStore()
    let analyzer = AudioAnalyzer()

    @Published private(set) var status = "Starting…"
    @Published private(set) var needsPermission = false
    @Published private(set) var availableDisplays: [DisplayOption] = []

    private lazy var overlays = OverlayManager(analyzer: analyzer, settings: settings)
    private lazy var capture = SystemAudioCapture()
    private let logger = Logger(subsystem: "com.cf3i.edgepulse", category: "app")
    private var cancellables = Set<AnyCancellable>()
    private var retryTask: Task<Void, Never>?
    private var retryAttempt = 0
    private var isActive = false
    private var isSleeping = false

    private init() {
        reloadDisplays()

        settings.$smoothing
            .sink { [weak analyzer] value in
                analyzer?.setSmoothing(Float(value))
            }
            .store(in: &cancellables)

        settings.$automaticGain
            .sink { [weak analyzer] enabled in
                analyzer?.setAutomaticGain(enabled)
            }
            .store(in: &cancellables)

        settings.$enabled
            .dropFirst()
            .sink { [weak self] enabled in
                guard self?.isActive == true else { return }
                self?.setEnabled(enabled)
            }
            .store(in: &cancellables)

        settings.$edgePlacement
            .dropFirst()
            .sink { [weak self] _ in
                guard let self, self.isActive, self.settings.enabled else { return }
                self.overlays.rebuild()
            }
            .store(in: &cancellables)

        settings.$selectedDisplayID
            .dropFirst()
            .sink { [weak self] _ in
                guard let self, self.isActive, self.settings.enabled else { return }
                self.overlays.rebuild()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                guard let self else { return }
                self.reloadDisplays()
                self.validateSelectedDisplay()
                guard self.settings.enabled else { return }
                self.overlays.rebuild()
                self.retryTask?.cancel()
                self.capture.restart()
            }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)
            .sink { [weak self] _ in
                guard let self, self.settings.enabled else { return }
                self.isSleeping = true
                self.retryTask?.cancel()
                self.capture.stop()
                self.status = "Sleeping"
            }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in
                guard let self, self.settings.enabled else { return }
                self.isSleeping = false
                self.status = "Reconnecting after wake…"
                self.capture.start()
            }
            .store(in: &cancellables)
    }

    func activate() {
        guard !isActive else { return }
        isActive = true

        capture.onSamples = { [weak analyzer] samples, sampleRate in
            analyzer?.ingest(samples, sampleRate: sampleRate)
        }
        capture.onStateChange = { [weak self] state in
            DispatchQueue.main.async {
                self?.applyCaptureState(state)
            }
        }

        setEnabled(settings.enabled)
    }

    func shutdown() {
        retryTask?.cancel()
        capture.stop()
        overlays.hide()
    }

    func openScreenRecordingSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func retryCaptureAfterPermissionChange() {
        guard settings.enabled else { return }
        retryTask?.cancel()
        retryAttempt = 0
        needsPermission = false
        status = "Checking system audio permission…"
        capture.start()
    }

    var displaySummary: String {
        guard let selectedID = settings.selectedDisplayID else { return "All displays" }
        return availableDisplays.first(where: { $0.id == selectedID })?.title ?? "Main display"
    }

    private func setEnabled(_ enabled: Bool) {
        logger.info("Enabled changed to \(enabled, privacy: .public)")
        if enabled {
            retryTask?.cancel()
            retryAttempt = 0
            overlays.show()
            status = "Connecting to system audio…"
            needsPermission = false
            capture.start()
        } else {
            retryTask?.cancel()
            retryAttempt = 0
            isSleeping = false
            capture.stop()
            analyzer.reset()
            overlays.hide()
            status = "Paused"
            needsPermission = false
        }
    }

    private func reloadDisplays() {
        availableDisplays = NSScreen.screens.compactMap { screen in
            guard let id = screen.edgePulseDisplayID else { return nil }
            return DisplayOption(id: id, title: screen.localizedName)
        }
    }

    private func validateSelectedDisplay() {
        guard let selectedID = settings.selectedDisplayID else { return }
        if !availableDisplays.contains(where: { $0.id == selectedID }) {
            settings.setSelectedDisplayID(nil)
        }
    }

    private func applyCaptureState(_ state: SystemAudioCapture.State) {
        switch state {
        case .idle:
            logger.info("Capture state: idle")
            if settings.enabled {
                status = isSleeping ? "Sleeping" : "Stopped"
            }
        case .starting:
            logger.info("Capture state: starting")
            status = "Connecting to system audio…"
            needsPermission = false
        case .running:
            logger.info("Capture state: running")
            retryTask?.cancel()
            retryAttempt = 0
            status = "Listening to system audio"
            needsPermission = false
        case .permissionRequired:
            logger.notice("Capture state: permission required")
            retryTask?.cancel()
            status = "System audio permission required"
            needsPermission = true
        case .failed(let message):
            logger.error("Capture state: failed — \(message, privacy: .public)")
            needsPermission = false
            scheduleRetry(after: message)
        }
    }

    private func scheduleRetry(after message: String) {
        retryTask?.cancel()
        guard settings.enabled, !isSleeping, retryAttempt < 3 else {
            status = "Audio capture failed: \(message)"
            return
        }

        retryAttempt += 1
        let attempt = retryAttempt
        let delaySeconds = UInt64(1 << (attempt - 1))
        status = "Capture interrupted · retrying in \(delaySeconds)s"

        retryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delaySeconds * 1_000_000_000)
            guard !Task.isCancelled,
                  let self,
                  self.settings.enabled,
                  !self.isSleeping,
                  self.retryAttempt == attempt else {
                return
            }
            self.capture.start()
        }
    }
}
