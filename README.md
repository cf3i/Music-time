# EdgePulse

EdgePulse is a menu-bar-only macOS audio visualizer. It listens to system audio with ScreenCaptureKit and draws a click-through, always-on-top white spectrum along the bottom edge of every display.

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

For a fast compile check without packaging:

```bash
swift build
```

The app bundle is ad-hoc signed so macOS can associate privacy permission with a stable bundle identifier. If you move or rebuild the app and macOS asks again, approve the new build in System Settings.
