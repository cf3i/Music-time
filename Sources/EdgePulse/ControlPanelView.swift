import AppKit
import SwiftUI

struct ControlPanelView: View {
    @ObservedObject private var model: AppModel
    @ObservedObject private var settings: SettingsStore

    init(model: AppModel) {
        self.model = model
        settings = model.settings
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                Image(systemName: "waveform.path.ecg")
                    .font(.title2)
                VStack(alignment: .leading, spacing: 1) {
                    Text("EdgePulse")
                        .font(.headline)
                    Text(model.status)
                        .font(.caption)
                        .foregroundStyle(model.needsPermission ? .orange : .secondary)
                        .lineLimit(2)
                }
                Spacer()
            }

            Divider()

            Toggle("Enabled", isOn: $settings.enabled)
                .toggleStyle(.switch)

            controlRow("Opacity", value: "\(Int(settings.opacity * 100))%") {
                Slider(
                    value: Binding(
                        get: { settings.opacity },
                        set: { settings.setOpacity($0) }
                    ),
                    in: 0.1...1.0
                )
            }

            controlRow("Density", value: "\(settings.density)") {
                Slider(
                    value: Binding(
                        get: { Double(settings.density) },
                        set: { settings.setDensity(Int($0.rounded())) }
                    ),
                    in: 16...128,
                    step: 8
                )
            }

            controlRow("Amplitude", value: "\(Int(settings.amplitude * 100))%") {
                Slider(
                    value: Binding(
                        get: { settings.amplitude },
                        set: { settings.setAmplitude($0) }
                    ),
                    in: 0.25...2.0
                )
            }

            controlRow("Smoothing", value: "\(Int(settings.smoothing * 100))%") {
                Slider(
                    value: Binding(
                        get: { settings.smoothing },
                        set: { settings.setSmoothing($0) }
                    ),
                    in: 0...0.95
                )
            }

            if model.needsPermission {
                HStack {
                    Button("Open Privacy Settings") {
                        model.openScreenRecordingSettings()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Try Again") {
                        model.retryCaptureAfterPermissionChange()
                    }
                }

                Text("In Privacy Settings, turn on EdgePulse under System Audio Recording Only, then return here and choose Try Again.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack {
                Text("Bars · Bottom · All displays")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Quit") {
                    NSApp.terminate(nil)
                }
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    private func controlRow<Content: View>(
        _ title: String,
        value: String,
        @ViewBuilder control: () -> Content
    ) -> some View {
        VStack(spacing: 5) {
            HStack {
                Text(title)
                Spacer()
                Text(value)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            control()
        }
    }
}
