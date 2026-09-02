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
        VStack(alignment: .leading, spacing: 16) {
            header
            enabledCard
            presetSection
            controlsCard

            if model.needsPermission {
                permissionCard
            }

            footer
        }
        .padding(18)
        .frame(width: 360)
        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.07),
                        Color.clear,
                        Color.accentColor.opacity(0.045)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            LumenMark()

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text("EdgePulse")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                    Text("LUMEN")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .tracking(1.1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.primary.opacity(0.075), in: Capsule())
                }

                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 6, height: 6)
                        .shadow(color: statusColor.opacity(0.6), radius: 3)
                    Text(model.status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .accessibilityElement(children: .combine)
    }

    private var enabledCard: some View {
        HStack(spacing: 12) {
            Image(systemName: settings.enabled ? "waveform.badge.checkmark" : "waveform")
                .font(.system(size: 17, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(settings.enabled ? "Visualizer active" : "Visualizer paused")
                    .font(.subheadline.weight(.medium))
                Text(settings.enabled ? "System audio stays on this Mac" : "Audio capture and overlays are stopped")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()
            Toggle("Enabled", isOn: $settings.enabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .accessibilityLabel("Enable visualizer")
        }
        .padding(12)
        .background(.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private var presetSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("LOOK", trailing: settings.preset.title)

            HStack(spacing: 7) {
                ForEach(LumenPreset.curated) { preset in
                    Button {
                        settings.applyPreset(preset)
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: preset.symbol)
                                .font(.system(size: 13, weight: .medium))
                            Text(preset.title)
                                .font(.caption2.weight(.medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .foregroundStyle(settings.preset == preset ? .primary : .secondary)
                        .background(
                            settings.preset == preset ? Color.primary.opacity(0.105) : Color.primary.opacity(0.035),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(.primary.opacity(settings.preset == preset ? 0.14 : 0.055), lineWidth: 0.5)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Apply \(preset.title) visual preset")
                }
            }
        }
    }

    private var controlsCard: some View {
        VStack(spacing: 12) {
            LumenSlider(
                title: "Opacity",
                symbol: "circle.lefthalf.filled",
                valueText: "\(Int(settings.opacity * 100))%",
                value: Binding(get: { settings.opacity }, set: { settings.setOpacity($0) }),
                range: 0.1...1.0
            )

            LumenSlider(
                title: "Density",
                symbol: "circle.grid.cross",
                valueText: "\(settings.density)",
                value: Binding(
                    get: { Double(settings.density) },
                    set: { settings.setDensity(Int($0.rounded())) }
                ),
                range: 16...128,
                step: 8
            )

            LumenSlider(
                title: "Amplitude",
                symbol: "arrow.up.and.down",
                valueText: "\(Int(settings.amplitude * 100))%",
                value: Binding(get: { settings.amplitude }, set: { settings.setAmplitude($0) }),
                range: 0.25...2.0
            )

            LumenSlider(
                title: "Smoothing",
                symbol: "waveform.path",
                valueText: "\(Int(settings.smoothing * 100))%",
                value: Binding(get: { settings.smoothing }, set: { settings.setSmoothing($0) }),
                range: 0...0.95
            )

            Divider().opacity(0.6)

            LumenSlider(
                title: "Glow",
                symbol: "sun.max.fill",
                valueText: "\(Int(settings.glow * 100))%",
                value: Binding(get: { settings.glow }, set: { settings.setGlow($0) }),
                range: 0...1.0
            )

            LumenSlider(
                title: "Bar width",
                symbol: "rectangle.split.3x1",
                valueText: "\(Int(settings.barWidth * 100))%",
                value: Binding(get: { settings.barWidth }, set: { settings.setBarWidth($0) }),
                range: 0.3...0.9
            )
        }
        .padding(13)
        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.primary.opacity(0.055), lineWidth: 0.5)
        }
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("System audio access needed", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.orange)

            Text("Under System Audio Recording Only, use + to add this EdgePulse app if it is missing, or turn it on.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Open Settings") {
                    model.openScreenRecordingSettings()
                }
                .buttonStyle(.borderedProminent)

                Button("Try Again") {
                    model.retryCaptureAfterPermissionChange()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private var footer: some View {
        HStack {
            Label("Bars · Bottom · All displays", systemImage: "rectangle.bottomthird.inset.filled")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
            Button("Quit") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var statusColor: Color {
        if model.needsPermission { return .orange }
        if !settings.enabled { return .secondary }
        return model.status == "Listening to system audio" ? .green : .yellow
    }

    private func sectionLabel(_ title: String, trailing: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .tracking(1.1)
                .foregroundStyle(.tertiary)
            Spacer()
            Text(trailing)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

struct MenuBarPulseIcon: View {
    private let heights: [CGFloat] = [5, 10, 7, 13, 8]

    var body: some View {
        HStack(alignment: .center, spacing: 1.5) {
            ForEach(Array(heights.enumerated()), id: \.offset) { _, height in
                Capsule(style: .continuous)
                    .fill(.primary)
                    .frame(width: 2, height: height)
            }
        }
        .frame(width: 18, height: 15)
        .accessibilityHidden(true)
    }
}

private struct LumenMark: View {
    private let heights: [CGFloat] = [8, 15, 11, 20, 13]

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.2), Color.accentColor.opacity(0.3)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(.white.opacity(0.2), lineWidth: 0.6)

            HStack(alignment: .center, spacing: 2) {
                ForEach(Array(heights.enumerated()), id: \.offset) { _, height in
                    Capsule(style: .continuous)
                        .fill(.white.opacity(0.92))
                        .frame(width: 2.5, height: height)
                }
            }
        }
        .frame(width: 42, height: 42)
        .shadow(color: Color.accentColor.opacity(0.22), radius: 12)
        .accessibilityHidden(true)
    }
}

private struct LumenSlider: View {
    let title: String
    let symbol: String
    let valueText: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double?

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 13)
                Text(title)
                    .font(.caption)
                Spacer()
                Text(valueText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if let step {
                Slider(value: $value, in: range, step: step)
                    .controlSize(.small)
            } else {
                Slider(value: $value, in: range)
                    .controlSize(.small)
            }
        }
        .accessibilityElement(children: .contain)
    }
}
