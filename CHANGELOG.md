# Changelog

## 0.4.0 — 2026-09-03

### Added

- A continuous, glow-layered Wave renderer alongside the original Bars renderer
- Bottom, top, left, right, and four-edge placement with live overlay rebuilding
- Per-display targeting for multi-monitor setups
- Renderer-ready bass, mid, high-frequency, overall-energy, and kick-onset features
- Bass-driven halo breathing, kick edge pulses, and animated high-frequency shimmer
- Automatic gain that gently balances quiet and loud source material

### Changed

- Evolved the menu-bar panel into the Flow layout with visualizer, edge, display, and gain controls
- Made all renderer geometry orientation-aware while keeping every overlay click-through and Space-aware
- Paused continuous shimmer rendering during silence and under Reduce Motion

## 0.3.0 — 2026-09-03

### Added

- Lumen control-panel design with adaptive materials, clear capture status, and accessible labels
- Halo, Glass, and Pulse visual presets with automatic Custom-state tracking
- Adjustable layered glow and bar-width controls
- A custom monochrome menu-bar mark and a complete Finder app icon
- Reduced-motion and reduced-transparency treatments for the overlay

### Changed

- Rebuilt the bar renderer with an ambient edge halo, separate bloom and core layers, smoother geometry, and graceful silence fade
- Grouped controls into a compact visual hierarchy while preserving every MVP control

## 0.2.0 — 2026-09-03

### Added

- Generation-based capture lifecycle that rejects stale asynchronous starts and stream callbacks
- Automatic capture retries plus sleep, wake, and display-change recovery
- Sample-rate-aware 4,096-point FFT processor with a 1,024-sample hop
- Unit tests for lifecycle behavior, generated audio signals, smoothing, reset, settings validation, and processing headroom
- Swift 6 concurrency checking
- Native Xcode macOS application target and shared Run/Profile/Archive scheme
- Unified logging for capture lifecycle and permission diagnostics
- Core Audio process-tap capture on macOS 14.2 and later, using the narrower system-audio-only permission
- Project-local self-signed development identity so privacy permission survives rebuilds
- In-app permission retry without requiring repeated Enabled toggles
- macOS 26-specific guidance for the separate System Audio Recording Only permission

### Changed

- Replaced the shifting pending-sample array with a fixed-size ring buffer
- Reused FFT working buffers and improved logarithmic band uniqueness
- Moved to the stable `com.cf3i.edgepulse` bundle identifier
- Moved the system permission prompt onto the main actor and classify ScreenCaptureKit permission errors explicitly
- Retained ScreenCaptureKit only as a compatibility fallback for macOS 13–14.1
- Replaced ad-hoc signing, which macOS intentionally treats as a new identity after every build

## 0.1.0 — MVP

- ScreenCaptureKit system-audio capture
- Bottom-edge glowing bar spectrum on all displays
- Menu-bar controls for enabled state, opacity, density, amplitude, and smoothing
- Local ad-hoc app packaging
