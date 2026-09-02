import Foundation

/// Pure state reducer used by `SystemAudioCapture` to reject stale asynchronous work.
/// Keeping this logic independent from ScreenCaptureKit makes rapid start/stop behavior testable.
struct CaptureLifecycle {
    enum Phase: Equatable {
        case idle
        case starting
        case running
        case permissionRequired
        case failed
    }

    private(set) var phase: Phase = .idle
    private(set) var wantsCapture = false
    private(set) var generation: UInt64 = 0

    mutating func requestStart() -> UInt64? {
        guard !wantsCapture else { return nil }
        wantsCapture = true
        generation &+= 1
        phase = .starting
        return generation
    }

    @discardableResult
    mutating func requestStop() -> UInt64 {
        wantsCapture = false
        generation &+= 1
        phase = .idle
        return generation
    }

    func accepts(_ token: UInt64) -> Bool {
        wantsCapture && token == generation
    }

    mutating func didStart(token: UInt64) -> Bool {
        guard accepts(token) else { return false }
        phase = .running
        return true
    }

    mutating func permissionWasDenied(token: UInt64) -> Bool {
        guard accepts(token) else { return false }
        wantsCapture = false
        phase = .permissionRequired
        return true
    }

    mutating func didFail(token: UInt64) -> Bool {
        guard accepts(token) else { return false }
        wantsCapture = false
        phase = .failed
        return true
    }

    mutating func activeStreamStopped(token: UInt64) -> Bool {
        guard token == generation else { return false }
        wantsCapture = false
        phase = .failed
        return true
    }
}
