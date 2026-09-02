# EdgePulse

EdgePulse is a menu-bar-only macOS audio visualizer. It listens to system audio and draws a click-through, always-on-top white spectrum along the bottom edge of every display. On macOS 14.2 and later it uses a Core Audio process tap, with ScreenCaptureKit retained as the macOS 13–14.1 fallback. Audio is analyzed locally and is never recorded or uploaded.

## Requirements

- macOS 13 or later
- Xcode Command Line Tools

## Build and run

```bash
cd ~/Pjs/EdgePulse
./scripts/setup-local-signing.sh
./scripts/build-app.sh
open build/EdgePulse.app
```

On macOS 14.2 and later, allow EdgePulse under **System Audio Recording Only**. If it is not listed, use the `+` button in that section and select `build/EdgePulse.app`. On macOS 13–14.1, approve **Screen & System Audio Recording** instead. The app has no Dock icon; use the waveform icon in the menu bar.

## Controls

- **Enabled** starts or stops capture and shows or hides the overlay.
- **Look** applies the Halo, Glass, or Pulse visual preset.
- **Opacity** changes the brightness/transparency of the whole overlay.
- **Density** changes the number of frequency bars (16–128).
- **Amplitude** changes their maximum height.
- **Smoothing** changes how quickly bars decay.
- **Glow** changes the ambient halo and bloom strength.
- **Bar width** changes the geometry and spacing of the spectrum.

Settings persist automatically in `UserDefaults`.

## Development

Open `EdgePulse.xcodeproj` for the native macOS app target, Run, Profile, and Archive workflows. The Swift package remains the fast path for core builds and tests.

Run the full unit test suite:

```bash
swift test
```

Create an optimized local build:

```bash
./scripts/build-app.sh release
```

For a fast compile check without packaging:

```bash
swift build
```

Run `setup-local-signing.sh` once to create a self-signed development identity in the ignored `.local-signing` directory. macOS asks for one administrator confirmation to trust that certificate for code signing only. This gives the app a stable cryptographic identity so its privacy permission survives local rebuilds. The identity is only for development on this Mac and is not trusted for distribution. Production builds must use Apple Development or Developer ID signing; set `EDGEPULSE_SIGNING_IDENTITY` and optionally `EDGEPULSE_SIGNING_KEYCHAIN` when invoking the build script.

On macOS 26, System Settings separates **System Audio Recording Only** from broader screen recording access. EdgePulse uses the narrower audio-only permission. It does not need microphone access.

See [ROADMAP.md](ROADMAP.md) for the path from the current core-stability work to the public beta.
