import SwiftUI
import AetherDiskCore

struct BubbleLensView: View {
    let bubbles: [BubbleNode]
    let canNavigateUp: Bool
    let colorMode: VisualizationColorMode
    let selectedPath: String?
    @Binding var hoveredPath: String?
    let onSelectPath: (String) -> Void
    let onDrillDownPath: (String) -> Void
    let onNavigateUp: () -> Void

    @State private var hoveredBubbleID: String?
    @State private var lastTapInfo: (path: String, time: Date)?
    @State private var zoomScale: Double = 1.0
    @GestureState private var pinchFactor: CGFloat = 1.0
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var effectiveZoom: Double {
        min(1.80, max(0.85, zoomScale * Double(pinchFactor)))
    }

    private func normalizedPoint(location: CGPoint, in size: CGSize) -> (nx: Double, ny: Double, side: Double, ox: Double, oy: Double) {
        let side = max(80.0, min(size.width, size.height)) * effectiveZoom
        let ox = (size.width - side) / 2.0
        let oy = (size.height - side) / 2.0
        let nx = (location.x - ox) / side
        let ny = (location.y - oy) / side
        return (nx, ny, side, ox, oy)
    }

    private var activeHoveredBubble: BubbleNode? {
        if let hoveredBubbleID, let match = bubbles.first(where: { $0.id == hoveredBubbleID }) {
            return match
        }
        if let hoveredPath {
            return bubbles.first(where: { !$0.isHub && $0.path == hoveredPath })
        }
        return nil
    }

    var body: some View {
        GeometryReader { geo in
            let scale = effectiveZoom
            let side = max(80.0, min(geo.size.width, geo.size.height)) * scale
            let ox = (geo.size.width - side) / 2.0
            let oy = (geo.size.height - side) / 2.0
            let hovered = activeHoveredBubble
            let zoomBindingAnim = DiskMotion.subtle(reduceMotion: reduceMotion)

            ZStack(alignment: .topTrailing) {
                Canvas { context, size in
                    let s = max(80.0, min(size.width, size.height)) * scale
                    let originX = (size.width - s) / 2.0
                    let originY = (size.height - s) / 2.0
                    let center = CGPoint(x: size.width / 2.0, y: size.height / 2.0)

                    // Space Lens subtle orbital backdrop rings
                    for factor in [0.22, 0.35, 0.47] {
                        let r = s * factor
                        let ringRect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
                        context.stroke(
                            Path(ellipseIn: ringRect),
                            with: .color(DiskTheme.line.opacity(0.65)),
                            style: StrokeStyle(lineWidth: 1, dash: [4, 5])
                        )
                    }

                    // Connector spokes from hub to primary bubbles (highlighted on hover)
                    if let hub = bubbles.first(where: \.isHub) {
                        let hubPt = CGPoint(x: originX + hub.cx * s, y: originY + hub.cy * s)
                        for b in bubbles where !b.isHub {
                            let bPt = CGPoint(x: originX + b.cx * s, y: originY + b.cy * s)
                            let isSpokeHovered = hovered?.id == b.id || (hoveredPath != nil && b.path == hoveredPath)
                            var line = Path()
                            line.move(to: hubPt)
                            line.addLine(to: bPt)
                            context.stroke(
                                line,
                                with: .color(isSpokeHovered ? DiskTheme.accent.opacity(0.9) : DiskTheme.line.opacity(0.55)),
                                lineWidth: isSpokeHovered ? 2.2 : 1.0
                            )
                        }
                    }

                    // Draw each sphere bubble
                    for bubble in bubbles {
                        let cx = originX + bubble.cx * s
                        let cy = originY + bubble.cy * s
                        let isHovered = hovered?.id == bubble.id || (!bubble.isHub && hoveredPath != nil && bubble.path == hoveredPath)
                        let isSelected = !bubble.isHub && selectedPath != nil && bubble.path == selectedPath
                        let baseR = max(6.0, bubble.radius * s)
                        let drawR = isHovered ? baseR * 1.035 : baseR
                        let rect = CGRect(x: cx - drawR, y: cy - drawR, width: drawR * 2, height: drawR * 2)
                        let circlePath = Path(ellipseIn: rect)

                        if bubble.isHub {
                            let hubFill = RadialGradient(
                                colors: [
                                    DiskTheme.elevatedSurface,
                                    DiskTheme.surface
                                ],
                                center: .topLeading,
                                startRadius: 2,
                                endRadius: drawR * 2
                            )
                            context.fill(circlePath, with: .style(hubFill))
                            context.stroke(
                                circlePath,
                                with: .color(isHovered && canNavigateUp ? DiskTheme.accent : DiskTheme.accent.opacity(0.45)),
                                lineWidth: isHovered && canNavigateUp ? 2.4 : 1.6
                            )
                        } else {
                            let baseColor = DiskTheme.color(
                                forMode: colorMode,
                                colorIndex: bubble.colorIndex,
                                category: bubble.fileCategory,
                                ageBucket: bubble.ageBucket,
                                isProtected: bubble.isProtected,
                                isTail: bubble.isTailGroup
                            )
                            let dimmed = hovered != nil && !isHovered && !isSelected
                            let alpha = dimmed ? 0.56 : (isSelected || isHovered ? 0.96 : 0.86)

                            let sphereGradient = RadialGradient(
                                colors: [
                                    baseColor.opacity(min(1.0, alpha * 0.78)),
                                    baseColor.opacity(alpha)
                                ],
                                center: UnitPoint(x: 0.32, y: 0.28),
                                startRadius: drawR * 0.08,
                                endRadius: drawR * 1.15
                            )
                            context.fill(circlePath, with: .style(sphereGradient))

                            // Specular top-left highlight sheen
                            let sheenRect = rect.insetBy(dx: drawR * 0.08, dy: drawR * 0.08)
                            context.stroke(
                                Path(ellipseIn: sheenRect),
                                with: .color(.white.opacity(dimmed ? 0.12 : 0.28)),
                                lineWidth: 1.0
                            )

                            if bubble.isProtected {
                                drawProtectionStripes(in: &context, clippedTo: circlePath, rect: rect)
                            }

                            if isSelected {
                                context.stroke(circlePath, with: .color(.primary.opacity(0.88)), lineWidth: 2.5)
                                context.stroke(Path(ellipseIn: rect.insetBy(dx: 1.5, dy: 1.5)), with: .color(.white.opacity(0.92)), lineWidth: 1.2)
                            } else if isHovered {
                                context.stroke(circlePath, with: .color(.white.opacity(0.95)), lineWidth: 2.0)
                            } else {
                                context.stroke(circlePath, with: .color(DiskTheme.surface.opacity(0.85)), lineWidth: 1.2)
                            }
                        }
                    }
                }
                .accessibilityIdentifier("bubble-lens-canvas")
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let loc):
                        let mapped = normalizedPoint(location: loc, in: geo.size)
                        if let hit = BubbleLensLayout.hitTest(bubbles: bubbles, nx: mapped.nx, ny: mapped.ny) {
                            hoveredBubbleID = hit.id
                            hoveredPath = hit.isHub ? nil : hit.path
                        } else {
                            hoveredBubbleID = nil
                            hoveredPath = nil
                        }
                    case .ended:
                        hoveredBubbleID = nil
                        hoveredPath = nil
                    }
                }
                .gesture(
                    SpatialTapGesture().onEnded { value in
                        let mapped = normalizedPoint(location: value.location, in: geo.size)
                        guard let hit = BubbleLensLayout.hitTest(bubbles: bubbles, nx: mapped.nx, ny: mapped.ny) else {
                            return
                        }
                        if hit.isHub {
                            if canNavigateUp {
                                onNavigateUp()
                            }
                            return
                        }
                        guard !hit.isTailGroup, let path = hit.path else { return }
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

                .gesture(
                    MagnificationGesture()
                        .updating($pinchFactor) { value, state, _ in
                            state = value
                        }
                        .onEnded { value in
                            zoomScale = min(1.80, max(0.85, zoomScale * Double(value)))
                        }
                )

                // Crisp SwiftUI text overlays centered on sufficiently large bubbles
                ZStack {
                    ForEach(bubbles) { bubble in
                        let rPx = bubble.radius * side
                        if bubble.isHub || rPx >= 24 {
                            bubbleLabel(bubble: bubble, radiusPx: rPx)
                                .position(
                                    x: ox + bubble.cx * side,
                                    y: oy + bubble.cy * side
                                )
                        }
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .allowsHitTesting(false)

                if let hovered, !hovered.isHub {
                    VStack(alignment: .trailing, spacing: 3) {
                        HStack(spacing: 7) {
                            if hovered.isProtected {
                                Image(systemName: "lock.shield.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(DiskTheme.teal)
                            }
                            Text(hovered.title)
                                .font(.system(size: 11, weight: .semibold))
                                .lineLimit(1)
                            Text(DiskFormat.bytes(hovered.allocated))
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(DiskTheme.accent)
                            Text(String(format: "%.1f%%", hovered.fraction * 100))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        HStack(spacing: 6) {
                            Tag(text: hovered.isTailGroup ? "长尾归并" : hovered.fileCategory.title, color: DiskTheme.accent)
                            Text(hovered.isTailGroup ? "已归并尾部小项" : (hovered.isDirectory ? "单击选中 · 双击下钻" : "只读元数据文件"))
                                .font(.system(size: 9.5))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(
                        reduceTransparency ? DiskTheme.elevatedSurface : DiskTheme.surface.opacity(colorScheme == .dark ? 0.92 : 0.95),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(reduceTransparency ? DiskTheme.strongLine : DiskTheme.line, lineWidth: 1)
                    )
                    .padding(8)
                    .allowsHitTesting(false)
                }

                // Bottom-left floating Bubble Lens zoom control strip
                HStack(spacing: 5) {
                    Text("缩放")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("bubble-zoom-controls")
                    Button {
                        withAnimation(zoomBindingAnim) {
                            zoomScale = max(0.85, zoomScale - 0.20)
                        }
                    } label: {
                        Image(systemName: "minus.magnifyingglass")
                            .font(.system(size: 10.5, weight: .semibold))
                    }
                    .buttonStyle(DiskButtonStyle(kind: .quiet))
                    .disabled(zoomScale <= 0.86)
                    .accessibilityLabel("缩小气泡图")
                    .accessibilityIdentifier("bubble-zoom-out")

                    Button("\(Int((zoomScale * 100).rounded()))%") {
                        withAnimation(zoomBindingAnim) {
                            zoomScale = 1.0
                        }
                    }
                    .buttonStyle(DiskButtonStyle(kind: .quiet))
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .accessibilityLabel("重置气泡图缩放 \(Int((zoomScale * 100).rounded()))%")
                    .accessibilityValue("\(Int((zoomScale * 100).rounded()))%")
                    .help("重置气泡图缩放")
                    .accessibilityIdentifier("bubble-zoom-reset")

                    Button {
                        withAnimation(zoomBindingAnim) {
                            zoomScale = min(1.80, zoomScale + 0.20)
                        }
                    } label: {
                        Image(systemName: "plus.magnifyingglass")
                            .font(.system(size: 10.5, weight: .semibold))
                    }
                    .buttonStyle(DiskButtonStyle(kind: .quiet))
                    .disabled(zoomScale >= 1.79)
                    .accessibilityLabel("放大气泡图")
                    .accessibilityIdentifier("bubble-zoom-in")
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    reduceTransparency
                        ? AnyShapeStyle(DiskTheme.elevatedSurface)
                        : AnyShapeStyle(.ultraThinMaterial),
                    in: Capsule()
                )
                .overlay(Capsule().stroke(reduceTransparency ? DiskTheme.strongLine : DiskTheme.line, lineWidth: 1))
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
            .clipped()
        }
    }

    @ViewBuilder
    private func bubbleLabel(bubble: BubbleNode, radiusPx: Double) -> some View {
        let maxW = max(36.0, radiusPx * 1.68)
        if bubble.isHub {
            VStack(spacing: 2) {
                Text(bubble.title)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(DiskFormat.bytes(bubble.allocated))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(DiskTheme.accent)
                if canNavigateUp {
                    Text("↑ 返回上级")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: maxW)
        } else {
            VStack(spacing: 1) {
                Text(bubble.title)
                    .font(.system(size: radiusPx >= 36 ? 10.5 : 9, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if radiusPx >= 30 {
                    Text(DiskFormat.bytes(bubble.allocated))
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .opacity(0.92)
                }
            }
            .foregroundStyle(bubble.isTailGroup ? Color.primary : Color.white)
            .shadow(color: bubble.isTailGroup ? .clear : .black.opacity(0.28), radius: 2, y: 1)
            .frame(width: maxW)
        }
    }

    private func drawProtectionStripes(in context: inout GraphicsContext, clippedTo circle: Path, rect: CGRect) {
        context.drawLayer { layer in
            layer.clip(to: circle)
            var hatch = Path()
            let step = 7.0
            let span = max(rect.width, rect.height) * 2.0
            var offset = -span
            while offset <= span {
                hatch.move(to: CGPoint(x: rect.minX + offset, y: rect.minY))
                hatch.addLine(to: CGPoint(x: rect.minX + offset - rect.height, y: rect.maxY))
                offset += step
            }
            layer.stroke(hatch, with: .color(.white.opacity(0.22)), lineWidth: 1.0)
        }
    }
}
