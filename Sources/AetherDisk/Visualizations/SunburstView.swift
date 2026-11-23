import SwiftUI
import AetherDiskCore

struct SunburstView: View {
    let arcs: [SunburstArc]
    let scopeTitle: String
    let scopeAllocated: Int64
    let canNavigateUp: Bool
    let colorMode: VisualizationColorMode
    let selectedPath: String?
    @Binding var hoveredPath: String?
    let onSelectPath: (String) -> Void
    let onDrillDownPath: (String) -> Void
    let onNavigateUp: () -> Void

    @State private var hoveredArcID: String?
    @State private var hoveringCenter = false
    @State private var lastTapInfo: (path: String, time: Date)?

    init(
        arcs: [SunburstArc],
        scopeTitle: String,
        scopeAllocated: Int64,
        canNavigateUp: Bool,
        colorMode: VisualizationColorMode,
        selectedPath: String?,
        hoveredPath: Binding<String?>,
        onSelectPath: @escaping (String) -> Void,
        onDrillDownPath: @escaping (String) -> Void,
        onNavigateUp: @escaping () -> Void
    ) {
        self.arcs = arcs
        self.scopeTitle = scopeTitle
        self.scopeAllocated = scopeAllocated
        self.canNavigateUp = canNavigateUp
        self.colorMode = colorMode
        self.selectedPath = selectedPath
        self._hoveredPath = hoveredPath
        self.onSelectPath = onSelectPath
        self.onDrillDownPath = onDrillDownPath
        self.onNavigateUp = onNavigateUp
    }

    private struct Metrics {
        let center: CGPoint
        let innerRadius: Double
        let ringWidth: Double
        let ringCount: Int
    }

    private func metrics(for size: CGSize) -> Metrics {
        let ringCount = max(1, arcs.map(\.depth).max() ?? 1)
        let side = max(96.0, min(size.width, size.height))
        let maxRadius = max(42.0, (side - 16.0) / 2.0)
        let innerRadius = max(34.0, min(58.0, maxRadius * 0.41))
        let availableRingSpace = max(18.0, maxRadius - innerRadius)
        let ringWidth = min(42.0, availableRingSpace / Double(ringCount))
        return Metrics(
            center: CGPoint(x: size.width / 2.0, y: size.height / 2.0),
            innerRadius: innerRadius,
            ringWidth: ringWidth,
            ringCount: ringCount
        )
    }

    private var activeHoveredArc: SunburstArc? {
        if let hoveredArcID, let byID = arcs.first(where: { $0.id == hoveredArcID }) {
            return byID
        }
        if let hoveredPath {
            return arcs.first(where: { $0.path == hoveredPath })
        }
        return nil
    }

    var body: some View {
        GeometryReader { geo in
            let m = metrics(for: geo.size)
            let hovered = activeHoveredArc

            ZStack {
                Canvas { context, size in
                    let canvasMetrics = metrics(for: size)
                    let center = canvasMetrics.center
                    let innerR = canvasMetrics.innerRadius
                    let ringW = canvasMetrics.ringWidth

                    if arcs.isEmpty {
                        let placeholderRect = CGRect(
                            x: center.x - innerR - ringW * 0.5,
                            y: center.y - innerR - ringW * 0.5,
                            width: (innerR + ringW * 0.5) * 2,
                            height: (innerR + ringW * 0.5) * 2
                        )
                        context.stroke(
                            Path(ellipseIn: placeholderRect),
                            with: .color(DiskTheme.line),
                            lineWidth: ringW * 0.8
                        )
                    } else {
                        // Pass 1: Fills, protection hatching, and crisp sector separators.
                        for arc in arcs {
                            let r0 = innerR + Double(arc.depth - 1) * ringW
                            let r1 = r0 + ringW
                            let wedge = wedgePath(
                                center: center,
                                innerRadius: r0,
                                outerRadius: r1,
                                startAngle: arc.startAngle,
                                endAngle: arc.endAngle
                            )

                            let isHovered = hovered?.id == arc.id || (hoveredPath != nil && arc.path == hoveredPath)
                            let isSelected = selectedPath != nil && arc.path == selectedPath
                            let baseColor = DiskTheme.color(
                                forMode: colorMode,
                                colorIndex: arc.colorIndex,
                                category: arc.fileCategory,
                                ageBucket: arc.ageBucket,
                                isProtected: arc.isProtected,
                                isTail: arc.isTailGroup
                            )

                            let depthBaseOpacity = max(0.68, 0.90 - Double(arc.depth - 1) * 0.08)
                            let fillOpacity: Double
                            if hovered != nil {
                                fillOpacity = isHovered ? 1.0 : (isSelected ? depthBaseOpacity * 0.85 : depthBaseOpacity * 0.58)
                            } else {
                                fillOpacity = isSelected ? 0.98 : depthBaseOpacity
                            }

                            context.fill(wedge, with: .color(baseColor.opacity(fillOpacity)))

                            if arc.isProtected {
                                drawProtectionHatch(
                                    in: &context,
                                    clippedTo: wedge,
                                    center: center,
                                    outerRadius: r1,
                                    isTail: arc.isTailGroup
                                )
                            }

                            let isFullCircle = abs((arc.endAngle - arc.startAngle) - 2.0 * Double.pi) < 1e-4
                            if isFullCircle {
                                let outerRect = CGRect(x: center.x - r1, y: center.y - r1, width: r1 * 2, height: r1 * 2)
                                let innerRect = CGRect(x: center.x - r0, y: center.y - r0, width: r0 * 2, height: r0 * 2)
                                context.stroke(Path(ellipseIn: outerRect), with: .color(DiskTheme.surface), lineWidth: 1.5)
                                context.stroke(Path(ellipseIn: innerRect), with: .color(DiskTheme.surface), lineWidth: 1.5)
                            } else {
                                context.stroke(wedge, with: .color(DiskTheme.surface), lineWidth: 1.5)
                            }
                        }

                        // Pass 2: Selection and hover emphasis rings above neighbor edges.
                        for arc in arcs {
                            let isHovered = hovered?.id == arc.id || (hoveredPath != nil && arc.path == hoveredPath)
                            let isSelected = selectedPath != nil && arc.path == selectedPath
                            guard isHovered || isSelected else { continue }

                            let r0 = innerR + Double(arc.depth - 1) * ringW + 0.75
                            let r1 = innerR + Double(arc.depth) * ringW - 0.75
                            guard r1 > r0 else { continue }

                            let highlightWedge = wedgePath(
                                center: center,
                                innerRadius: r0,
                                outerRadius: r1,
                                startAngle: arc.startAngle,
                                endAngle: arc.endAngle
                            )
                            if isSelected {
                                context.stroke(highlightWedge, with: .color(.primary.opacity(0.88)), lineWidth: 2.6)
                                context.stroke(highlightWedge, with: .color(.white.opacity(0.92)), lineWidth: 1.2)
                            } else if isHovered {
                                context.stroke(highlightWedge, with: .color(.white.opacity(0.95)), lineWidth: 2.0)
                            }
                        }
                    }

                    // Center disk surface & interactive ring.
                    let centerRadius = max(12.0, innerR - 2.0)
                    let centerRect = CGRect(
                        x: center.x - centerRadius,
                        y: center.y - centerRadius,
                        width: centerRadius * 2,
                        height: centerRadius * 2
                    )
                    let centerCircle = Path(ellipseIn: centerRect)
                    context.fill(centerCircle, with: .color(DiskTheme.surface))
                    if hoveringCenter && canNavigateUp {
                        context.fill(centerCircle, with: .color(DiskTheme.accent.opacity(0.08)))
                        context.stroke(centerCircle, with: .color(DiskTheme.accent.opacity(0.75)), lineWidth: 1.8)
                    } else {
                        context.stroke(centerCircle, with: .color(DiskTheme.line), lineWidth: 1.0)
                    }
                }
                .accessibilityIdentifier("sunburst-canvas")
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        let dx = location.x - m.center.x
                        let dy = location.y - m.center.y
                        let r = hypot(dx, dy)
                        hoveringCenter = r < m.innerRadius
                        if let hit = SunburstLayout.hitTest(
                            arcs: arcs,
                            dx: dx,
                            dy: dy,
                            innerRadius: m.innerRadius,
                            ringWidth: m.ringWidth
                        ) {
                            hoveredArcID = hit.id
                            hoveredPath = hit.path
                        } else {
                            hoveredArcID = nil
                            hoveredPath = nil
                        }
                    case .ended:
                        hoveringCenter = false
                        hoveredArcID = nil
                        hoveredPath = nil
                    }
                }
                .gesture(
                    SpatialTapGesture().onEnded { value in
                        let dx = value.location.x - m.center.x
                        let dy = value.location.y - m.center.y
                        if hypot(dx, dy) < m.innerRadius {
                            if canNavigateUp {
                                onNavigateUp()
                            }
                            return
                        }
                        guard let hit = SunburstLayout.hitTest(
                            arcs: arcs,
                            dx: dx,
                            dy: dy,
                            innerRadius: m.innerRadius,
                            ringWidth: m.ringWidth
                        ),
                        !hit.isTailGroup,
                        let path = hit.path else {
                            return
                        }
                        let now = Date()
                        let isDoubleTap = lastTapInfo.map {
                            $0.path == path && now.timeIntervalSince($0.time) < 0.38
                        } ?? false
                        if hit.isDirectory && (path == selectedPath || isDoubleTap) {
                            lastTapInfo = nil
                            onDrillDownPath(path)
                        } else {
                            lastTapInfo = (path, now)
                            onSelectPath(path)
                        }
                    }
                )

                centerOverlay(metrics: m, hovered: hovered)
                    .position(m.center)
                    .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private func centerOverlay(metrics m: Metrics, hovered: SunburstArc?) -> some View {
        let box = max(56.0, m.innerRadius * 1.56)
        VStack(spacing: 3) {
            if let arc = hovered {
                Text(arc.title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .multilineTextAlignment(.center)
                Text(DiskFormat.bytes(arc.allocated))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                HStack(spacing: 3) {
                    if arc.isProtected {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 8.5))
                            .foregroundStyle(.teal)
                    }
                    Text(String(format: "%.1f%%", arc.fraction * 100))
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            } else if arcs.isEmpty {
                Text("暂无占用")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(DiskFormat.bytes(scopeAllocated))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            } else {
                Text(scopeTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .multilineTextAlignment(.center)
                Text(DiskFormat.bytes(scopeAllocated))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if canNavigateUp {
                    Label("点击中心返回上级", systemImage: "arrow.up.circle")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(DiskTheme.accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
        .frame(width: box, height: box)
    }

    private func wedgePath(
        center: CGPoint,
        innerRadius: Double,
        outerRadius: Double,
        startAngle: Double,
        endAngle: Double
    ) -> Path {
        var path = Path()
        path.addArc(
            center: center,
            radius: outerRadius,
            startAngle: .radians(startAngle),
            endAngle: .radians(endAngle),
            clockwise: false
        )
        path.addArc(
            center: center,
            radius: innerRadius,
            startAngle: .radians(endAngle),
            endAngle: .radians(startAngle),
            clockwise: true
        )
        path.closeSubpath()
        return path
    }

    private func drawProtectionHatch(
        in context: inout GraphicsContext,
        clippedTo wedge: Path,
        center: CGPoint,
        outerRadius: Double,
        isTail: Bool
    ) {
        context.drawLayer { layer in
            layer.clip(to: wedge)
            var hatch = Path()
            let step: Double = 7.0
            let span = outerRadius * 2.0
            var offset = -span
            while offset <= span {
                hatch.move(to: CGPoint(x: center.x + offset, y: center.y - outerRadius))
                hatch.addLine(to: CGPoint(x: center.x + offset - outerRadius, y: center.y + outerRadius))
                offset += step
            }
            let stripeColor: Color = isTail ? .primary.opacity(0.16) : .white.opacity(0.24)
            layer.stroke(hatch, with: .color(stripeColor), lineWidth: 1.0)
        }
    }
}
