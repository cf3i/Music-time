# EdgePulse roadmap

The runnable MVP is tagged `v0.1.0-mvp`. The next five milestones intentionally stabilize the core before expanding the visual surface.

## v0.2.0 — Pulse Core ✅

- Race-free, cancellable ScreenCaptureKit lifecycle
- Recovery after stream interruption, display changes, sleep, and wake
- Allocation-conscious FFT ring buffer and sample-rate-aware band mapping
- Swift 6 concurrency checks
- Native Xcode app target with shared Run, Profile, and Archive scheme
- Unit tests for lifecycle, spectrum behavior, and settings validation
- CPU, memory, and long-running reliability baselines

## v0.3.0 — Lumen ✅

- Refined menu-bar control panel and visual design system
- Layered glow, bar geometry, spacing, and graceful silence transitions
- Theme presets and polished app/menu-bar icons
- Light, dark, accessibility, and reduced-motion treatments

## v0.4.0 — Flow

- Wave renderer
- Top, bottom, left, right, and all-edge placement
- Bass breathing, kick pulses, high-frequency shimmer, and automatic gain
- Per-display visual configuration

## v0.5.0 — Studio

- First-run permission onboarding
- Launch at login and global pause shortcut
- Preset management and import/export
- Battery-aware rendering, diagnostics, localization, and accessibility

## v0.6.0 — Public Beta

- Developer ID signing, hardened runtime, and notarization
- Release archive and installer pipeline
- Safe updates, crash diagnostics, privacy documentation, and beta feedback
- Clean-install and upgrade testing on supported macOS versions
