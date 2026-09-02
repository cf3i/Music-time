import AppKit
import SwiftUI

@MainActor
final class OverlayManager {
    private let analyzer: AudioAnalyzer
    private let settings: SettingsStore
    private var panels: [NSPanel] = []
    private let overlayHeight: CGFloat = 260

    init(analyzer: AudioAnalyzer, settings: SettingsStore) {
        self.analyzer = analyzer
        self.settings = settings
    }

    func show() {
        if panels.isEmpty {
            rebuild()
        } else {
            panels.forEach { $0.orderFrontRegardless() }
        }
    }

    func hide() {
        panels.forEach { $0.orderOut(nil) }
    }

    func rebuild() {
        panels.forEach { $0.close() }
        panels.removeAll()

        for screen in NSScreen.screens {
            let frame = NSRect(
                x: screen.frame.minX,
                y: screen.frame.minY,
                width: screen.frame.width,
                height: overlayHeight
            )
            let panel = makePanel(frame: frame, screen: screen)
            panel.contentView = NSHostingView(
                rootView: SpectrumOverlayView(analyzer: analyzer, settings: settings)
            )
            panel.orderFrontRegardless()
            panels.append(panel)
        }
    }

    private func makePanel(frame: NSRect, screen: NSScreen) -> NSPanel {
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        panel.level = .screenSaver
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        panel.setFrame(frame, display: true)
        return panel
    }
}

private struct SpectrumOverlayView: View {
    @ObservedObject var analyzer: AudioAnalyzer
    @ObservedObject var settings: SettingsStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Canvas(opaque: false, colorMode: .linear, rendersAsynchronously: true) { context, size in
            let levels = resampled(analyzer.spectrum, count: settings.density)
            guard !levels.isEmpty else { return }

            let energy = rootMeanSquare(levels)
            let peak = CGFloat(levels.max() ?? 0)
            let visibility = min(1, max(0, peak * 3.2))
            guard visibility > 0.006 else { return }

            let slotWidth = size.width / CGFloat(levels.count)
            let barWidth = max(1.4, slotWidth * settings.barWidth)
            let motionScale = reduceMotion ? 0.74 : 1.0
            let maxHeight = min(size.height - 8, 126 * settings.amplitude * motionScale)
            let glow = reduceTransparency ? min(settings.glow, 0.28) : settings.glow

            drawAmbientGlow(
                in: &context,
                size: size,
                energy: CGFloat(energy),
                visibility: visibility,
                glow: glow
            )

            var bloomContext = context
            if glow > 0.01 {
                bloomContext.addFilter(
                    .shadow(
                        color: .white.opacity(0.32 + 0.3 * glow),
                        radius: 8 + 14 * glow,
                        x: 0,
                        y: 0
                    )
                )
            }

            var coreContext = context
            if glow > 0.01 {
                coreContext.addFilter(
                    .shadow(
                        color: .white.opacity(0.74),
                        radius: 2 + 6 * glow,
                        x: 0,
                        y: 0
                    )
                )
            }

            for (index, rawLevel) in levels.enumerated() {
                let level = CGFloat(min(1, max(0, rawLevel)))
                guard level > 0.003 else { continue }

                let height = max(1.2, level * maxHeight)
                let x = CGFloat(index) * slotWidth + (slotWidth - barWidth) / 2
                let rect = CGRect(x: x, y: size.height - height, width: barWidth, height: height + 2)
                let cornerRadius = min(barWidth / 2, 6)
                let path = Path(roundedRect: rect, cornerRadius: cornerRadius)

                if glow > 0.01 {
                    bloomContext.fill(path, with: .color(.white.opacity(0.18 * visibility * glow)))
                }

                coreContext.fill(
                    path,
                    with: .linearGradient(
                        Gradient(colors: [
                            .white.opacity(0.96),
                            .white.opacity(0.72 + 0.16 * visibility)
                        ]),
                        startPoint: CGPoint(x: rect.midX, y: rect.minY),
                        endPoint: CGPoint(x: rect.midX, y: rect.maxY)
                    )
                )
            }
        }
        .opacity(settings.opacity)
        .compositingGroup()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func drawAmbientGlow(
        in context: inout GraphicsContext,
        size: CGSize,
        energy: CGFloat,
        visibility: CGFloat,
        glow: Double
    ) {
        guard glow > 0.01 else { return }
        let depth = min(size.height * 0.38, 18 + 72 * energy) * glow
        guard depth > 1 else { return }

        let rect = CGRect(x: 0, y: size.height - depth, width: size.width, height: depth)
        context.fill(
            Path(rect),
            with: .linearGradient(
                Gradient(colors: [
                    .clear,
                    .white.opacity(0.018 * visibility * glow),
                    .white.opacity(0.09 * visibility * glow)
                ]),
                startPoint: CGPoint(x: rect.midX, y: rect.minY),
                endPoint: CGPoint(x: rect.midX, y: rect.maxY)
            )
        )
    }

    private func rootMeanSquare(_ values: [Float]) -> Float {
        guard !values.isEmpty else { return 0 }
        let sum = values.reduce(Float.zero) { $0 + $1 * $1 }
        return sqrt(sum / Float(values.count))
    }

    private func resampled(_ source: [Float], count: Int) -> [Float] {
        guard !source.isEmpty, count > 0 else { return [] }
        guard count > 1 else { return [source[0]] }

        return (0..<count).map { index in
            let position = Double(index) * Double(source.count - 1) / Double(count - 1)
            let lower = Int(position.rounded(.down))
            let upper = min(source.count - 1, lower + 1)
            let fraction = Float(position - Double(lower))
            return source[lower] * (1 - fraction) + source[upper] * fraction
        }
    }
}
