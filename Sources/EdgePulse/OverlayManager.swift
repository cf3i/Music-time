import AppKit
import SwiftUI

enum OverlayEdge: CaseIterable, Sendable {
    case bottom
    case top
    case left
    case right

    var isHorizontal: Bool {
        self == .bottom || self == .top
    }
}

extension EdgePlacement {
    var overlayEdges: [OverlayEdge] {
        switch self {
        case .bottom: [.bottom]
        case .top: [.top]
        case .left: [.left]
        case .right: [.right]
        case .all: OverlayEdge.allCases
        }
    }
}

extension NSScreen {
    var edgePulseDisplayID: UInt32? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}

@MainActor
final class OverlayManager {
    private let analyzer: AudioAnalyzer
    private let settings: SettingsStore
    private var panels: [NSPanel] = []
    private let overlayDepth: CGFloat = 260

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

        for screen in targetScreens() {
            for edge in settings.edgePlacement.overlayEdges {
                let frame = panelFrame(for: edge, screen: screen)
                let panel = makePanel(frame: frame, screen: screen)
                panel.contentView = NSHostingView(
                    rootView: EdgeSpectrumOverlayView(
                        analyzer: analyzer,
                        settings: settings,
                        edge: edge
                    )
                )
                panel.orderFrontRegardless()
                panels.append(panel)
            }
        }
    }

    private func targetScreens() -> [NSScreen] {
        guard let selectedID = settings.selectedDisplayID else {
            return NSScreen.screens
        }
        let matches = NSScreen.screens.filter { $0.edgePulseDisplayID == selectedID }
        return matches.isEmpty ? [NSScreen.main].compactMap { $0 } : matches
    }

    private func panelFrame(for edge: OverlayEdge, screen: NSScreen) -> NSRect {
        switch edge {
        case .bottom:
            NSRect(
                x: screen.frame.minX,
                y: screen.frame.minY,
                width: screen.frame.width,
                height: overlayDepth
            )
        case .top:
            NSRect(
                x: screen.frame.minX,
                y: screen.frame.maxY - overlayDepth,
                width: screen.frame.width,
                height: overlayDepth
            )
        case .left:
            NSRect(
                x: screen.frame.minX,
                y: screen.frame.minY,
                width: overlayDepth,
                height: screen.frame.height
            )
        case .right:
            NSRect(
                x: screen.frame.maxX - overlayDepth,
                y: screen.frame.minY,
                width: overlayDepth,
                height: screen.frame.height
            )
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

private struct EdgeSpectrumOverlayView: View {
    @ObservedObject var analyzer: AudioAnalyzer
    @ObservedObject var settings: SettingsStore
    let edge: OverlayEdge

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Canvas(opaque: false, colorMode: .linear, rendersAsynchronously: true) { context, size in
            draw(
                context: &context,
                size: size,
                phase: reduceMotion ? 0 : ProcessInfo.processInfo.systemUptime
            )
        }
        .opacity(settings.opacity)
        .compositingGroup()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func draw(context: inout GraphicsContext, size: CGSize, phase: TimeInterval) {
        let state = analyzer.visualState
        let levels = resampled(state.spectrum, count: settings.density)
        guard !levels.isEmpty else { return }

        let peak = CGFloat(levels.max() ?? 0)
        let visibility = min(1, max(0, peak * 3.2))
        guard visibility > 0.004 else { return }

        let glow = reduceTransparency ? min(settings.glow, 0.28) : settings.glow
        let bass = CGFloat(state.bass)
        let kick = reduceMotion ? 0 : CGFloat(state.kick)
        let availableDepth = (edge.isHorizontal ? size.height : size.width) - 8
        let motionScale = reduceMotion ? 0.78 : 1.0
        let reactiveScale = 0.88 + bass * 0.34 + kick * 0.24
        let maxDepth = min(availableDepth, 126 * settings.amplitude * motionScale * reactiveScale)

        drawAmbientGlow(
            context: &context,
            size: size,
            energy: CGFloat(state.energy),
            bass: bass,
            kick: kick,
            visibility: visibility,
            glow: glow
        )

        switch settings.visualizerStyle {
        case .bars:
            drawBars(
                context: &context,
                size: size,
                levels: levels,
                maxDepth: maxDepth,
                visibility: visibility,
                glow: glow
            )
        case .wave:
            drawWave(
                context: &context,
                size: size,
                levels: levels,
                maxDepth: maxDepth,
                visibility: visibility,
                glow: glow
            )
        }

        drawKickPulse(
            context: &context,
            size: size,
            kick: kick,
            visibility: visibility,
            glow: glow
        )
        drawShimmer(
            context: &context,
            size: size,
            high: CGFloat(state.high),
            visibility: visibility,
            glow: glow,
            phase: phase
        )
    }

    private func drawBars(
        context: inout GraphicsContext,
        size: CGSize,
        levels: [Float],
        maxDepth: CGFloat,
        visibility: CGFloat,
        glow: Double
    ) {
        let majorLength = edge.isHorizontal ? size.width : size.height
        let slotLength = majorLength / CGFloat(levels.count)
        let elementWidth = max(1.4, slotLength * settings.barWidth)

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

            let depth = max(1.2, level * maxDepth)
            let along = CGFloat(index) * slotLength + (slotLength - elementWidth) / 2
            let rect = elementRect(
                along: along,
                length: elementWidth,
                depth: depth + 2,
                inset: 0,
                size: size
            )
            let cornerRadius = min(elementWidth / 2, 6)
            let path = Path(roundedRect: rect, cornerRadius: cornerRadius)

            if glow > 0.01 {
                bloomContext.fill(path, with: .color(.white.opacity(0.18 * visibility * glow)))
            }

            let gradient = inwardGradientPoints(size: size, depth: depth)
            coreContext.fill(
                path,
                with: .linearGradient(
                    Gradient(colors: [
                        .white.opacity(0.96),
                        .white.opacity(0.72 + 0.16 * visibility)
                    ]),
                    startPoint: gradient.inner,
                    endPoint: gradient.edge
                )
            )
        }
    }

    private func drawWave(
        context: inout GraphicsContext,
        size: CGSize,
        levels: [Float],
        maxDepth: CGFloat,
        visibility: CGFloat,
        glow: Double
    ) {
        let paddedLevels = [Float.zero] + levels + [Float.zero]
        let majorLength = edge.isHorizontal ? size.width : size.height
        let points = paddedLevels.enumerated().map { index, rawLevel in
            let along = majorLength * CGFloat(index) / CGFloat(max(1, paddedLevels.count - 1))
            let depth = CGFloat(min(1, max(0, rawLevel))) * maxDepth
            return point(along: along, inset: depth, size: size)
        }
        guard points.count > 2 else { return }

        var line = Path()
        line.move(to: points[0])
        for index in 1..<(points.count - 1) {
            let current = points[index]
            let next = points[index + 1]
            let midpoint = CGPoint(x: (current.x + next.x) / 2, y: (current.y + next.y) / 2)
            line.addQuadCurve(to: midpoint, control: current)
        }
        if let final = points.last, points.count >= 2 {
            line.addQuadCurve(to: final, control: points[points.count - 2])
        }

        var fill = line
        fill.addLine(to: point(along: majorLength, inset: 0, size: size))
        fill.addLine(to: point(along: 0, inset: 0, size: size))
        fill.closeSubpath()

        let gradient = inwardGradientPoints(size: size, depth: maxDepth)
        context.fill(
            fill,
            with: .linearGradient(
                Gradient(colors: [
                    .white.opacity(0.015 * visibility),
                    .white.opacity(0.15 * visibility)
                ]),
                startPoint: gradient.inner,
                endPoint: gradient.edge
            )
        )

        var bloomContext = context
        if glow > 0.01 {
            bloomContext.addFilter(
                .shadow(
                    color: .white.opacity(0.44 * glow),
                    radius: 10 + 16 * glow,
                    x: 0,
                    y: 0
                )
            )
            bloomContext.stroke(
                line,
                with: .color(.white.opacity(0.22 * visibility * glow)),
                lineWidth: 3.2 + 3.4 * glow
            )
        }

        var coreContext = context
        coreContext.addFilter(
            .shadow(
                color: .white.opacity(0.72),
                radius: 2 + 6 * glow,
                x: 0,
                y: 0
            )
        )
        coreContext.stroke(
            line,
            with: .color(.white.opacity(0.9)),
            lineWidth: 1.1 + 2.4 * settings.barWidth
        )
    }

    private func drawAmbientGlow(
        context: inout GraphicsContext,
        size: CGSize,
        energy: CGFloat,
        bass: CGFloat,
        kick: CGFloat,
        visibility: CGFloat,
        glow: Double
    ) {
        guard glow > 0.01 else { return }
        let availableDepth = edge.isHorizontal ? size.height : size.width
        let depth = min(availableDepth * 0.48, 16 + 58 * energy + 54 * bass + 26 * kick) * glow
        guard depth > 1 else { return }

        let rect = elementRect(
            along: 0,
            length: edge.isHorizontal ? size.width : size.height,
            depth: depth,
            inset: 0,
            size: size
        )
        let gradient = inwardGradientPoints(size: size, depth: depth)
        context.fill(
            Path(rect),
            with: .linearGradient(
                Gradient(colors: [
                    .clear,
                    .white.opacity(0.02 * visibility * glow),
                    .white.opacity((0.085 + 0.1 * bass) * visibility * glow)
                ]),
                startPoint: gradient.inner,
                endPoint: gradient.edge
            )
        )
    }

    private func drawKickPulse(
        context: inout GraphicsContext,
        size: CGSize,
        kick: CGFloat,
        visibility: CGFloat,
        glow: Double
    ) {
        guard kick > 0.015 else { return }
        let majorLength = edge.isHorizontal ? size.width : size.height
        let rect = elementRect(
            along: 0,
            length: majorLength,
            depth: 1.2 + kick * 3.4,
            inset: 0,
            size: size
        )
        var pulseContext = context
        pulseContext.addFilter(
            .shadow(
                color: .white.opacity(0.8),
                radius: 5 + 18 * kick * glow,
                x: 0,
                y: 0
            )
        )
        pulseContext.fill(
            Path(rect),
            with: .color(.white.opacity((0.18 + 0.56 * kick) * visibility))
        )
    }

    private func drawShimmer(
        context: inout GraphicsContext,
        size: CGSize,
        high: CGFloat,
        visibility: CGFloat,
        glow: Double,
        phase: TimeInterval
    ) {
        guard high > 0.025 else { return }
        let majorLength = edge.isHorizontal ? size.width : size.height
        let count = min(28, max(8, Int(majorLength / 72)))
        var shimmerContext = context
        shimmerContext.addFilter(
            .shadow(
                color: .white.opacity(0.55),
                radius: 2 + 5 * glow,
                x: 0,
                y: 0
            )
        )

        for index in 0..<count {
            let seed = Double(index) * 0.61803398875
            let travel = phase * (26 + Double(index % 5) * 5)
            let along = CGFloat((seed * Double(majorLength) + travel).truncatingRemainder(dividingBy: Double(majorLength)))
            let flicker = 0.45 + 0.55 * abs(sin(phase * 7.4 + Double(index) * 2.17))
            let length = CGFloat(2.4 + Double(index % 4) * 1.2)
            let inset = CGFloat(2 + (index % 3))
            let rect = elementRect(
                along: along,
                length: length,
                depth: 1.1,
                inset: inset,
                size: size
            )
            shimmerContext.fill(
                Path(roundedRect: rect, cornerRadius: 0.6),
                with: .color(.white.opacity(high * flicker * visibility * 0.9))
            )
        }
    }

    private func point(along: CGFloat, inset: CGFloat, size: CGSize) -> CGPoint {
        switch edge {
        case .bottom: CGPoint(x: along, y: size.height - inset)
        case .top: CGPoint(x: along, y: inset)
        case .left: CGPoint(x: inset, y: along)
        case .right: CGPoint(x: size.width - inset, y: along)
        }
    }

    private func elementRect(
        along: CGFloat,
        length: CGFloat,
        depth: CGFloat,
        inset: CGFloat,
        size: CGSize
    ) -> CGRect {
        switch edge {
        case .bottom:
            CGRect(x: along, y: size.height - inset - depth, width: length, height: depth)
        case .top:
            CGRect(x: along, y: inset, width: length, height: depth)
        case .left:
            CGRect(x: inset, y: along, width: depth, height: length)
        case .right:
            CGRect(x: size.width - inset - depth, y: along, width: depth, height: length)
        }
    }

    private func inwardGradientPoints(size: CGSize, depth: CGFloat) -> (inner: CGPoint, edge: CGPoint) {
        let majorLength = edge.isHorizontal ? size.width : size.height
        return (
            point(along: majorLength / 2, inset: depth, size: size),
            point(along: majorLength / 2, inset: 0, size: size)
        )
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
