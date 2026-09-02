import Foundation
import XCTest
@testable import EdgePulse

@MainActor
final class SettingsStoreTests: XCTestCase {
    func testPersistedValuesAreClampedAndAligned() {
        let suite = "com.cf3i.edgepulse.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(-4.0, forKey: "opacity")
        defaults.set(133, forKey: "density")
        defaults.set(9.0, forKey: "amplitude")
        defaults.set(4.0, forKey: "smoothing")
        defaults.set(-2.0, forKey: "glow")
        defaults.set(4.0, forKey: "barWidth")

        let settings = SettingsStore(defaults: defaults)

        XCTAssertEqual(settings.opacity, 0.1)
        XCTAssertEqual(settings.density, 128)
        XCTAssertEqual(settings.amplitude, 2.0)
        XCTAssertEqual(settings.smoothing, 0.95)
        XCTAssertEqual(settings.glow, 0)
        XCTAssertEqual(settings.barWidth, 0.9)
    }

    func testRuntimeAssignmentsRemainInSupportedRanges() {
        let suite = "com.cf3i.edgepulse.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)

        settings.setOpacity(2)
        settings.setDensity(21)
        settings.setAmplitude(-1)
        settings.setSmoothing(-2)
        settings.setGlow(4)
        settings.setBarWidth(0)

        XCTAssertEqual(settings.opacity, 1)
        XCTAssertEqual(settings.density, 24)
        XCTAssertEqual(settings.amplitude, 0.25)
        XCTAssertEqual(settings.smoothing, 0)
        XCTAssertEqual(settings.glow, 1)
        XCTAssertEqual(settings.barWidth, 0.3)
        XCTAssertEqual(settings.preset, .custom)
        XCTAssertEqual(defaults.double(forKey: "opacity"), 1)
        XCTAssertEqual(defaults.integer(forKey: "density"), 24)
    }

    func testCuratedPresetAppliesAndPersistsEveryVisualValue() {
        let suite = "com.cf3i.edgepulse.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)

        settings.applyPreset(.pulse)

        XCTAssertEqual(settings.preset, .pulse)
        XCTAssertEqual(settings.opacity, 0.9)
        XCTAssertEqual(settings.density, 40)
        XCTAssertEqual(settings.amplitude, 1.35)
        XCTAssertEqual(settings.smoothing, 0.56)
        XCTAssertEqual(settings.glow, 1)
        XCTAssertEqual(settings.barWidth, 0.78)

        let restored = SettingsStore(defaults: defaults)
        XCTAssertEqual(restored.preset, .pulse)
        XCTAssertEqual(restored.density, 40)
        XCTAssertEqual(restored.glow, 1)
    }
}
