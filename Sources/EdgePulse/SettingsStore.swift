import Combine
import Foundation

final class SettingsStore: ObservableObject {
    private enum Key {
        static let enabled = "enabled"
        static let opacity = "opacity"
        static let density = "density"
        static let amplitude = "amplitude"
        static let smoothing = "smoothing"
    }

    private let defaults: UserDefaults

    @Published var enabled: Bool {
        didSet { defaults.set(enabled, forKey: Key.enabled) }
    }

    @Published var opacity: Double {
        didSet { defaults.set(opacity, forKey: Key.opacity) }
    }

    @Published var density: Int {
        didSet { defaults.set(density, forKey: Key.density) }
    }

    @Published var amplitude: Double {
        didSet { defaults.set(amplitude, forKey: Key.amplitude) }
    }

    @Published var smoothing: Double {
        didSet { defaults.set(smoothing, forKey: Key.smoothing) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        enabled = defaults.object(forKey: Key.enabled) as? Bool ?? true
        opacity = defaults.object(forKey: Key.opacity) as? Double ?? 0.82
        density = defaults.object(forKey: Key.density) as? Int ?? 64
        amplitude = defaults.object(forKey: Key.amplitude) as? Double ?? 1.0
        smoothing = defaults.object(forKey: Key.smoothing) as? Double ?? 0.72
    }
}
