import Combine
import Foundation

enum LumenPreset: String, CaseIterable, Identifiable, Sendable {
    case halo
    case glass
    case pulse
    case custom

    static let curated: [LumenPreset] = [.halo, .glass, .pulse]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .halo: "Halo"
        case .glass: "Glass"
        case .pulse: "Pulse"
        case .custom: "Custom"
        }
    }

    var symbol: String {
        switch self {
        case .halo: "circle.hexagongrid.fill"
        case .glass: "sparkles"
        case .pulse: "waveform.path.ecg"
        case .custom: "slider.horizontal.3"
        }
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    private enum Key {
        static let enabled = "enabled"
        static let opacity = "opacity"
        static let density = "density"
        static let amplitude = "amplitude"
        static let smoothing = "smoothing"
        static let glow = "glow"
        static let barWidth = "barWidth"
        static let preset = "lumenPreset"
    }

    private let defaults: UserDefaults

    @Published var enabled: Bool {
        didSet { defaults.set(enabled, forKey: Key.enabled) }
    }

    @Published private(set) var opacity: Double
    @Published private(set) var density: Int
    @Published private(set) var amplitude: Double
    @Published private(set) var smoothing: Double
    @Published private(set) var glow: Double
    @Published private(set) var barWidth: Double
    @Published private(set) var preset: LumenPreset

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        enabled = defaults.object(forKey: Key.enabled) as? Bool ?? true
        opacity = Self.clamp(defaults.object(forKey: Key.opacity) as? Double ?? 0.82, to: 0.1...1.0)
        density = Self.validDensity(defaults.object(forKey: Key.density) as? Int ?? 64)
        amplitude = Self.clamp(defaults.object(forKey: Key.amplitude) as? Double ?? 1.0, to: 0.25...2.0)
        smoothing = Self.clamp(defaults.object(forKey: Key.smoothing) as? Double ?? 0.72, to: 0...0.95)
        glow = Self.clamp(defaults.object(forKey: Key.glow) as? Double ?? 0.85, to: 0...1.0)
        barWidth = Self.clamp(defaults.object(forKey: Key.barWidth) as? Double ?? 0.62, to: 0.3...0.9)
        preset = defaults.string(forKey: Key.preset).flatMap(LumenPreset.init(rawValue:)) ?? .halo
    }

    func setOpacity(_ value: Double) {
        opacity = Self.clamp(value, to: 0.1...1.0)
        defaults.set(opacity, forKey: Key.opacity)
        markCustom()
    }

    func setDensity(_ value: Int) {
        density = Self.validDensity(value)
        defaults.set(density, forKey: Key.density)
        markCustom()
    }

    func setAmplitude(_ value: Double) {
        amplitude = Self.clamp(value, to: 0.25...2.0)
        defaults.set(amplitude, forKey: Key.amplitude)
        markCustom()
    }

    func setSmoothing(_ value: Double) {
        smoothing = Self.clamp(value, to: 0...0.95)
        defaults.set(smoothing, forKey: Key.smoothing)
        markCustom()
    }

    func setGlow(_ value: Double) {
        glow = Self.clamp(value, to: 0...1.0)
        defaults.set(glow, forKey: Key.glow)
        markCustom()
    }

    func setBarWidth(_ value: Double) {
        barWidth = Self.clamp(value, to: 0.3...0.9)
        defaults.set(barWidth, forKey: Key.barWidth)
        markCustom()
    }

    func applyPreset(_ newPreset: LumenPreset) {
        guard newPreset != .custom else {
            markCustom()
            return
        }

        let values: PresetValues = switch newPreset {
        case .halo:
            PresetValues(opacity: 0.82, density: 64, amplitude: 1.0, smoothing: 0.72, glow: 0.85, barWidth: 0.62)
        case .glass:
            PresetValues(opacity: 0.94, density: 96, amplitude: 0.82, smoothing: 0.84, glow: 0.52, barWidth: 0.42)
        case .pulse:
            PresetValues(opacity: 0.9, density: 40, amplitude: 1.35, smoothing: 0.56, glow: 1.0, barWidth: 0.78)
        case .custom:
            preconditionFailure("Custom does not define fixed values")
        }

        opacity = values.opacity
        density = values.density
        amplitude = values.amplitude
        smoothing = values.smoothing
        glow = values.glow
        barWidth = values.barWidth
        preset = newPreset
        persistVisualSettings()
    }

    private func markCustom() {
        guard preset != .custom else { return }
        preset = .custom
        defaults.set(preset.rawValue, forKey: Key.preset)
    }

    private func persistVisualSettings() {
        defaults.set(opacity, forKey: Key.opacity)
        defaults.set(density, forKey: Key.density)
        defaults.set(amplitude, forKey: Key.amplitude)
        defaults.set(smoothing, forKey: Key.smoothing)
        defaults.set(glow, forKey: Key.glow)
        defaults.set(barWidth, forKey: Key.barWidth)
        defaults.set(preset.rawValue, forKey: Key.preset)
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(range.upperBound, max(range.lowerBound, value))
    }

    private static func validDensity(_ value: Int) -> Int {
        let clamped = min(128, max(16, value))
        return Int((Double(clamped) / 8).rounded()) * 8
    }
}

private struct PresetValues {
    let opacity: Double
    let density: Int
    let amplitude: Double
    let smoothing: Double
    let glow: Double
    let barWidth: Double
}
