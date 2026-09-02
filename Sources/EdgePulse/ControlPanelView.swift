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
                Slider(value: $settings.opacity, in: 0.1...1.0)
            }

            controlRow("Density", value: "\(settings.density)") {
                Slider(
                    value: Binding(
                        get: { Double(settings.density) },
                        set: { settings.density = Int($0.rounded()) }
                    ),
                    in: 16...128,
                    step: 8
                )
            }

            controlRow("Amplitude", value: "\(Int(settings.amplitude * 100))%") {
                Slider(value: $settings.amplitude, in: 0.25...2.0)
            }

            controlRow("Smoothing", value: "\(Int(settings.smoothing * 100))%") {
                Slider(value: $settings.smoothing, in: 0...0.95)
            }

            if model.needsPermission {
                Button("Open Privacy Settings") {
                    model.openScreenRecordingSettings()
                }
                .buttonStyle(.borderedProminent)

                Text("Allow EdgePulse under Screen & System Audio Recording, then quit and reopen it.")
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
