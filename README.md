# EdgePulse

EdgePulse is a menu-bar-only macOS audio visualizer. It listens to system audio with ScreenCaptureKit and draws a click-through, always-on-top white spectrum along the bottom edge of every display. Audio is analyzed locally and is never recorded or uploaded.

## Requirements

- macOS 13 or later
- Xcode Command Line Tools

## Build and run

```bash
cd ~/Pjs/EdgePulse
./scripts/build-app.sh
open build/EdgePulse.app
```

On first launch, macOS asks for **Screen & System Audio Recording** access. Approve EdgePulse, quit it, and open it again. The app has no Dock icon; use the waveform icon in the menu bar.

## MVP controls

- **Enabled** starts or stops capture and shows or hides the overlay.
- **Opacity** changes the brightness/transparency of the whole overlay.
- **Density** changes the number of frequency bars (16–128).
- **Amplitude** changes their maximum height.
- **Smoothing** changes how quickly bars decay.

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

The local app bundle is ad-hoc signed as `com.cf3i.edgepulse` so macOS can associate privacy permission with a stable bundle identifier. If you move or rebuild the app and macOS asks again, approve the new build in System Settings.

See [ROADMAP.md](ROADMAP.md) for the path from the current core-stability work to the public beta.
