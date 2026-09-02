import Combine
import Foundation

@MainActor
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

    @Published private(set) var opacity: Double

    @Published private(set) var density: Int

    @Published private(set) var amplitude: Double

    @Published private(set) var smoothing: Double

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        enabled = defaults.object(forKey: Key.enabled) as? Bool ?? true
        opacity = Self.clamp(defaults.object(forKey: Key.opacity) as? Double ?? 0.82, to: 0.1...1.0)
        density = Self.validDensity(defaults.object(forKey: Key.density) as? Int ?? 64)
        amplitude = Self.clamp(defaults.object(forKey: Key.amplitude) as? Double ?? 1.0, to: 0.25...2.0)
        smoothing = Self.clamp(defaults.object(forKey: Key.smoothing) as? Double ?? 0.72, to: 0...0.95)
    }

    func setOpacity(_ value: Double) {
        opacity = Self.clamp(value, to: 0.1...1.0)
        defaults.set(opacity, forKey: Key.opacity)
    }

    func setDensity(_ value: Int) {
        density = Self.validDensity(value)
        defaults.set(density, forKey: Key.density)
    }

    func setAmplitude(_ value: Double) {
        amplitude = Self.clamp(value, to: 0.25...2.0)
        defaults.set(amplitude, forKey: Key.amplitude)
    }

    func setSmoothing(_ value: Double) {
        smoothing = Self.clamp(value, to: 0...0.95)
        defaults.set(smoothing, forKey: Key.smoothing)
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(range.upperBound, max(range.lowerBound, value))
    }

    private static func validDensity(_ value: Int) -> Int {
        let clamped = min(128, max(16, value))
        return Int((Double(clamped) / 8).rounded()) * 8
    }
}
