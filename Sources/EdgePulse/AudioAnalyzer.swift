import Combine
import Foundation

@MainActor
final class AudioAnalyzer: ObservableObject {
    @Published private(set) var spectrum = [Float](repeating: 0, count: 128)

    nonisolated private let worker = SpectrumWorker()

    func setSmoothing(_ value: Float) {
        worker.setSmoothing(value)
    }

    nonisolated func ingest(_ samples: [Float], sampleRate: Float) {
        worker.ingest(samples, sampleRate: sampleRate) { [weak self] output in
            Task { @MainActor [weak self] in
                self?.spectrum = output
            }
        }
    }

    func reset() {
        worker.reset { [weak self] in
            Task { @MainActor [weak self] in
                self?.spectrum = [Float](repeating: 0, count: 128)
            }
        }
    }
}

/// Owns all mutable DSP state and confines it to a dedicated serial queue.
private final class SpectrumWorker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.cf3i.edgepulse.analysis", qos: .userInteractive)
    private let processor = SpectrumProcessor()
    private var smoothing: Float = 0.72

    func setSmoothing(_ value: Float) {
        queue.async { [weak self] in
            self?.smoothing = min(0.95, max(0, value))
        }
    }

    func ingest(
        _ samples: [Float],
        sampleRate: Float,
        onOutput: @escaping @Sendable ([Float]) -> Void
    ) {
        guard !samples.isEmpty else { return }
        queue.async { [weak self] in
            guard let self,
                  let output = self.processor.process(
                    samples: samples,
                    sampleRate: sampleRate,
                    smoothing: self.smoothing
                  ) else {
                return
            }
            onOutput(output)
        }
    }

    func reset(onReset: @escaping @Sendable () -> Void) {
        queue.async { [weak self] in
            self?.processor.reset()
            onReset()
        }
    }
}
