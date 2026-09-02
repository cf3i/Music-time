import AppKit
import SwiftUI

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
            panel.contentView = NSHostingView(
                rootView: SpectrumOverlayView(analyzer: analyzer, settings: settings)
            )
            panel.setFrame(frame, display: true)
            panel.orderFrontRegardless()
            panels.append(panel)
        }
    }
}

private struct SpectrumOverlayView: View {
    @ObservedObject var analyzer: AudioAnalyzer
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Canvas(opaque: false, colorMode: .linear, rendersAsynchronously: true) { context, size in
            let levels = resampled(analyzer.spectrum, count: settings.density)
            guard !levels.isEmpty else { return }

            let slotWidth = size.width / CGFloat(levels.count)
            let barWidth = max(1.5, slotWidth * 0.62)
            let maxHeight = min(size.height - 10, 120 * settings.amplitude)

            context.addFilter(
                .shadow(
                    color: .white.opacity(0.88),
                    radius: 8,
                    x: 0,
                    y: 0
                )
            )

            for (index, rawLevel) in levels.enumerated() {
                let level = CGFloat(min(1, max(0, rawLevel)))
                guard level > 0.004 else { continue }

                let height = max(1, level * maxHeight)
                let x = CGFloat(index) * slotWidth + (slotWidth - barWidth) / 2
                let rect = CGRect(x: x, y: size.height - height, width: barWidth, height: height + 2)
                let path = Path(roundedRect: rect, cornerRadius: min(barWidth / 2, 5))
                context.fill(path, with: .color(.white.opacity(0.94)))
            }
        }
        .opacity(settings.opacity)
        .allowsHitTesting(false)
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
