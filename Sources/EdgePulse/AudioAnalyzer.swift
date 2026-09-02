import Combine
import Foundation

struct AudioVisualState: Equatable, Sendable {
    var spectrum: [Float]
    var energy: Float
    var bass: Float
    var mid: Float
    var high: Float
    var kick: Float

    static let silent = AudioVisualState(
        spectrum: [Float](repeating: 0, count: 128),
        energy: 0,
        bass: 0,
        mid: 0,
        high: 0,
        kick: 0
    )
}

/// Converts a smoothed logarithmic spectrum into renderer-friendly musical features.
/// Calls must remain on one serial queue because onset detection has a short memory.
final class AudioFeatureExtractor {
    private var bassFloor: Float = 0
    private var kickEnvelope: Float = 0

    func process(_ spectrum: [Float]) -> AudioVisualState {
        guard !spectrum.isEmpty else { return .silent }

        let bassEnd = max(1, Int(Float(spectrum.count) * 0.28))
        let midEnd = max(bassEnd + 1, Int(Float(spectrum.count) * 0.70))
        let bass = average(spectrum[0..<min(bassEnd, spectrum.count)])
        let mid = average(spectrum[min(bassEnd, spectrum.count)..<min(midEnd, spectrum.count)])
        let high = average(spectrum[min(midEnd, spectrum.count)..<spectrum.count])
        let energy = rootMeanSquare(spectrum)

        let onset = max(0, bass - bassFloor * 1.22)
        let kickTarget = min(1, onset * 5.6)
        kickEnvelope = max(kickTarget, kickEnvelope * 0.68)
        bassFloor = bassFloor * 0.92 + bass * 0.08

        return AudioVisualState(
            spectrum: spectrum,
            energy: energy,
            bass: bass,
            mid: mid,
            high: high,
            kick: kickEnvelope
        )
    }

    func reset() {
        bassFloor = 0
        kickEnvelope = 0
    }

    private func average(_ values: ArraySlice<Float>) -> Float {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Float(values.count)
    }

    private func rootMeanSquare(_ values: [Float]) -> Float {
        let squared = values.reduce(Float.zero) { $0 + $1 * $1 }
        return sqrt(squared / Float(values.count))
    }
}

@MainActor
final class AudioAnalyzer: ObservableObject {
    @Published private(set) var visualState = AudioVisualState.silent

    var spectrum: [Float] { visualState.spectrum }

    nonisolated private let worker = SpectrumWorker()

    func setSmoothing(_ value: Float) {
        worker.setSmoothing(value)
    }

    func setAutomaticGain(_ enabled: Bool) {
        worker.setAutomaticGain(enabled)
    }

    nonisolated func ingest(_ samples: [Float], sampleRate: Float) {
        worker.ingest(samples, sampleRate: sampleRate) { [weak self] output in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if output.energy < 0.001, self.visualState.energy < 0.001 {
                    return
                }
                self.visualState = output
            }
        }
    }

    func reset() {
        worker.reset { [weak self] in
            Task { @MainActor [weak self] in
                self?.visualState = .silent
            }
        }
    }
}

/// Owns all mutable DSP state and confines it to a dedicated serial queue.
private final class SpectrumWorker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.cf3i.edgepulse.analysis", qos: .userInteractive)
    private let processor = SpectrumProcessor()
    private let features = AudioFeatureExtractor()
    private var smoothing: Float = 0.72
    private var automaticGain = true
    private var analysisFrame = 0

    func setSmoothing(_ value: Float) {
        queue.async { [weak self] in
            self?.smoothing = min(0.95, max(0, value))
        }
    }

    func setAutomaticGain(_ enabled: Bool) {
        queue.async { [weak self] in
            self?.automaticGain = enabled
        }
    }

    func ingest(
        _ samples: [Float],
        sampleRate: Float,
        onOutput: @escaping @Sendable (AudioVisualState) -> Void
    ) {
        guard !samples.isEmpty else { return }
        queue.async { [weak self] in
            guard let self,
                  let output = self.processor.process(
                    samples: samples,
                    sampleRate: sampleRate,
                    smoothing: self.smoothing,
                    automaticGain: self.automaticGain
                  ) else {
                return
            }
            let visualState = self.features.process(output)
            self.analysisFrame += 1
            guard self.analysisFrame.isMultiple(of: 2) else { return }
            onOutput(visualState)
        }
    }

    func reset(onReset: @escaping @Sendable () -> Void) {
        queue.async { [weak self] in
            self?.processor.reset()
            self?.features.reset()
            self?.analysisFrame = 0
            onReset()
        }
    }
}
