import SwiftUI
import AetherDiskCore

struct TreemapView: View {
    let rects: [TreemapRect]
    let colorMode: VisualizationColorMode
    let selectedPath: String?
    @Binding var hoveredPath: String?
    let onSelectPath: (String) -> Void
    let onDrillDownPath: (String) -> Void

    @State private var hoveredRectID: String?
    @State private var lastTapInfo: (path: String, time: Date)?

    init(
        rects: [TreemapRect],
        colorMode: VisualizationColorMode,
        selectedPath: String?,
        hoveredPath: Binding<String?>,
        onSelectPath: @escaping (String) -> Void,
        onDrillDownPath: @escaping (String) -> Void
    ) {
        self.rects = rects
        self.colorMode = colorMode
        self.selectedPath = selectedPath
        self._hoveredPath = hoveredPath
        self.onSelectPath = onSelectPath
        self.onDrillDownPath = onDrillDownPath
    }

    private var activeHoveredRect: TreemapRect? {
        if let hoveredRectID, let byID = rects.first(where: { $0.id == hoveredRectID }) {
            return byID
        }
        if let hoveredPath {
            return rects.first(where: { $0.path == hoveredPath })
        }
        return nil
    }

    private var activeSelectedRect: TreemapRect? {
        guard let selectedPath else { return nil }
        return rects.first(where: { $0.path == selectedPath })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                let hovered = activeHoveredRect

                Canvas { context, size in
                    if rects.isEmpty {
                        let box = CGRect(origin: .zero, size: size).insetBy(dx: 2, dy: 2)
                        let path = Path(roundedRect: box, cornerRadius: 10)
                        context.fill(path, with: .color(DiskTheme.inset))
                        context.stroke(path, with: .color(DiskTheme.line), lineWidth: 1)
                        let msg = context.resolve(
                            Text("当前层级暂无可显示的占用块")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        )
                        context.draw(msg, at: CGPoint(x: size.width / 2, y: size.height / 2), anchor: .center)
                        return
                    }

                    // Pass 1: Card fills, protection hatching, and adaptive anti-truncation labels.
                    for rect in rects {
                        let card = insetCardRect(for: rect, in: size)
                        guard card.width > 0.5 && card.height > 0.5 else { continue }
                        let radius = min(7.0, min(card.width, card.height) * 0.22)
                        let cardPath = Path(roundedRect: card, cornerRadius: radius)

                        let isHovered = hovered?.id == rect.id || (hoveredPath != nil && rect.path == hoveredPath)
                        let isSelected = selectedPath != nil && rect.path == selectedPath
                        let baseColor = DiskTheme.color(
                            forMode: colorMode,
                            colorIndex: rect.colorIndex,
                            category: rect.fileCategory,
                            ageBucket: rect.ageBucket,
                            isProtected: rect.isProtected,
                            isTail: rect.isTailGroup
                        )

                        let fillOpacity: Double
                        if hovered != nil {
                            fillOpacity = isHovered ? 0.98 : (isSelected ? 0.85 : 0.62)
                        } else {
                            fillOpacity = isSelected ? 0.98 : 0.88
                        }

                        context.fill(cardPath, with: .color(baseColor.opacity(fillOpacity)))
                        if !rect.isTailGroup {
                            // Subtle dark glaze ensures high contrast for white labels in both Light and Dark mode.
                            context.fill(cardPath, with: .color(Color.black.opacity(0.16)))
                        }

                        if rect.isProtected {
                            drawProtectionHatch(in: &context, clippedTo: cardPath, in: card, isTail: rect.isTailGroup)
                        }

                        if card.width >= 64 && card.height >= 28 {
                            drawLabels(in: &context, rect: rect, card: card, cardPath: cardPath)
                        }
                    }

                    // Pass 2: Selection and hover borders on top so adjacent blocks never clip them.
                    for rect in rects {
                        let isHovered = hovered?.id == rect.id || (hoveredPath != nil && rect.path == hoveredPath)
                        let isSelected = selectedPath != nil && rect.path == selectedPath
                        guard isHovered || isSelected else { continue }

                        let card = insetCardRect(for: rect, in: size)
                        guard card.width > 2 && card.height > 2 else { continue }
                        let radius = min(7.0, min(card.width, card.height) * 0.22)
                        let cardPath = Path(roundedRect: card, cornerRadius: radius)

                        if isSelected {
                            context.stroke(cardPath, with: .color(.primary.opacity(0.9)), lineWidth: 2.6)
                            context.stroke(cardPath, with: .color(.white.opacity(0.95)), lineWidth: 1.2)
                        } else if isHovered {
                            context.stroke(cardPath, with: .color(.white.opacity(0.95)), lineWidth: 2.0)
                        }
                    }
                }
                .accessibilityIdentifier("treemap-canvas")
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        guard geo.size.width > 0, geo.size.height > 0 else { return }
                        let nx = location.x / geo.size.width
                        let ny = location.y / geo.size.height
                        if let hit = TreemapLayout.hitTest(rects: rects, nx: nx, ny: ny) {
                            hoveredRectID = hit.id
                            hoveredPath = hit.path
                        } else {
                            hoveredRectID = nil
                            hoveredPath = nil
                        }
                    case .ended:
                        hoveredRectID = nil
                        hoveredPath = nil
                    }
                }
                .gesture(
                    SpatialTapGesture().onEnded { value in
                        guard geo.size.width > 0, geo.size.height > 0 else { return }
                        let nx = value.location.x / geo.size.width
                        let ny = value.location.y / geo.size.height
                        guard let hit = TreemapLayout.hitTest(rects: rects, nx: nx, ny: ny),
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
            }

            statusBar
        }
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            if let item = activeHoveredRect ?? activeSelectedRect {
                let swatch = DiskTheme.color(
                    forMode: colorMode,
                    colorIndex: item.colorIndex,
                    category: item.fileCategory,
                    ageBucket: item.ageBucket,
                    isProtected: item.isProtected,
                    isTail: item.isTailGroup
                )
                Circle().fill(swatch).frame(width: 8, height: 8)
                Image(systemName: item.isTailGroup ? "square.grid.2x2" : (item.isDirectory ? "folder.fill" : "doc.fill"))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(item.title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if item.isProtected {
                    Tag(text: "受保护", color: .teal)
                }
                Spacer(minLength: 8)
                Text(DiskFormat.bytes(item.allocated))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(String(format: "%.1f%%", item.fraction * 100))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                if item.isDirectory {
                    Text("· 再次点击下钻")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            } else {
                Image(systemName: "cursorarrow.click.2")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Text("点击选中区块，再次点击目录块下钻")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(DiskTheme.inset, in: RoundedRectangle(cornerRadius: DiskTheme.controlRadius))
        .overlay(RoundedRectangle(cornerRadius: DiskTheme.controlRadius).stroke(DiskTheme.line, lineWidth: 1))
    }

    private func insetCardRect(for rect: TreemapRect, in size: CGSize) -> CGRect {
        let raw = CGRect(
            x: rect.x * size.width,
            y: rect.y * size.height,
            width: rect.width * size.width,
            height: rect.height * size.height
        )
        let dx = min(1.5, raw.width * 0.25)
        let dy = min(1.5, raw.height * 0.25)
        return raw.insetBy(dx: dx, dy: dy)
    }

    private func drawProtectionHatch(
        in context: inout GraphicsContext,
        clippedTo cardPath: Path,
        in card: CGRect,
        isTail: Bool
    ) {
        context.drawLayer { layer in
            layer.clip(to: cardPath)
            var hatch = Path()
            let step: Double = 8.0
            let h = card.height
            var x = card.minX - h
            while x <= card.maxX + h {
                hatch.move(to: CGPoint(x: x, y: card.maxY))
                hatch.addLine(to: CGPoint(x: x + h, y: card.minY))
                x += step
            }
            let stripeColor: Color = isTail ? .primary.opacity(0.14) : .white.opacity(0.18)
            layer.stroke(hatch, with: .color(stripeColor), lineWidth: 1.0)
        }
    }

    private func drawLabels(
        in context: inout GraphicsContext,
        rect: TreemapRect,
        card: CGRect,
        cardPath: Path
    ) {
        context.drawLayer { layer in
            layer.clip(to: cardPath)
            let foreground: Color = rect.isTailGroup ? .primary : .white
            let showShield = rect.isProtected && card.width >= 82 && card.height >= 44
            let trailingReserve: Double = showShield ? 20.0 : 12.0
            let maxTextWidth = max(12.0, card.width - 7.0 - trailingReserve)

            if card.height >= 44 {
                let titleFont = Font.system(size: 11, weight: .semibold)
                let fittedTitle = fitText(rect.title, font: titleFont, maxWidth: maxTextWidth, in: &layer)
                let resolvedTitle = layer.resolve(
                    Text(fittedTitle).font(titleFont).foregroundStyle(foreground)
                )
                layer.draw(resolvedTitle, at: CGPoint(x: card.minX + 7, y: card.minY + 6), anchor: .topLeading)

                let bytesStr = DiskFormat.bytes(rect.allocated)
                let subtitleRaw = card.width >= 118
                    ? "\(bytesStr) · \(String(format: "%.1f%%", rect.fraction * 100))"
                    : bytesStr
                let subFont = Font.system(size: 10, weight: .medium, design: .rounded)
                let fittedSub = fitText(subtitleRaw, font: subFont, maxWidth: max(12.0, card.width - 14.0), in: &layer)
                let resolvedSub = layer.resolve(
                    Text(fittedSub).font(subFont).monospacedDigit().foregroundStyle(foreground.opacity(0.88))
                )
                layer.draw(resolvedSub, at: CGPoint(x: card.minX + 7, y: card.minY + 22), anchor: .topLeading)

                if showShield {
                    let icon = layer.resolve(
                        Text("\(Image(systemName: "lock.shield.fill"))")
                            .font(.system(size: 10))
                            .foregroundStyle(rect.isTailGroup ? Color.teal : Color.white.opacity(0.9))
                    )
                    layer.draw(icon, at: CGPoint(x: card.maxX - 7, y: card.minY + 7), anchor: .topTrailing)
                }
            } else {
                let singleRaw = card.width >= 132
                    ? "\(rect.title) · \(DiskFormat.bytes(rect.allocated))"
                    : rect.title
                let compactFont = Font.system(size: 10.5, weight: .semibold)
                let fitted = fitText(singleRaw, font: compactFont, maxWidth: max(12.0, card.width - 14.0), in: &layer)
                let resolved = layer.resolve(
                    Text(fitted).font(compactFont).foregroundStyle(foreground)
                )
                layer.draw(resolved, at: CGPoint(x: card.minX + 7, y: card.midY), anchor: .leading)
            }
        }
    }

    private func fitText(
        _ raw: String,
        font: Font,
        maxWidth: Double,
        in context: inout GraphicsContext
    ) -> String {
        let fullMeasure = context.resolve(Text(raw).font(font))
            .measure(in: CGSize(width: 2000, height: 30))
        if fullMeasure.width <= maxWidth { return raw }

        let chars = Array(raw)
        var low = 0
        var high = chars.count
        var best = "…"
        while low <= high {
            let mid = (low + high) / 2
            let candidate = mid == 0 ? "…" : String(chars.prefix(mid)) + "…"
            let w = context.resolve(Text(candidate).font(font))
                .measure(in: CGSize(width: 2000, height: 30)).width
            if w <= maxWidth {
                best = candidate
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return best
    }
}
