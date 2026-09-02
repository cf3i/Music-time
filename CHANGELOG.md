# Changelog

## 0.2.0 — Unreleased

### Added

- Generation-based capture lifecycle that rejects stale asynchronous starts and stream callbacks
- Automatic capture retries plus sleep, wake, and display-change recovery
- Sample-rate-aware 4,096-point FFT processor with a 1,024-sample hop
- Unit tests for lifecycle behavior, generated audio signals, smoothing, reset, and settings validation
- Swift 6 concurrency checking

### Changed

- Replaced the shifting pending-sample array with a fixed-size ring buffer
- Reused FFT working buffers and improved logarithmic band uniqueness
- Moved to the stable `com.cf3i.edgepulse` bundle identifier

## 0.1.0 — MVP

- ScreenCaptureKit system-audio capture
- Bottom-edge glowing bar spectrum on all displays
- Menu-bar controls for enabled state, opacity, density, amplitude, and smoothing
- Local ad-hoc app packaging
