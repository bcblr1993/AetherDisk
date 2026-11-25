import SwiftUI
import AetherDiskCore

struct OverviewView: View {
    @ObservedObject var model: AppModel

    private var scopeTitle: String {
        let scope = model.activeScope
        return scope == "/" ? "/" : URL(fileURLWithPath: scope).lastPathComponent
    }

    private var scopeAllocated: Int64 {
        if model.isBrowsingSubfolder {
            return model.currentNodes.first(where: { $0.path == model.activeScope })?.allocated
                ?? model.rows.reduce(0) { $0 + $1.allocated }
        }
        return model.result?.allocated ?? model.progress.allocated
    }

    var body: some View {
        VStack(spacing: 12) {
            compactStorageStrip

            if model.scanning {
                OrbitalScanningBanner(palette: ModuleStagePalette.forPage("overview"), progress: model.progress)
            }

            if model.result == nil && !model.scanning {
                ModuleHeroStage(
                    palette: ModuleStagePalette.forPage("overview"),
                    targetPath: DiskFormat.compactPath(model.root.path),
                    features: [
                        ("circle.hexagongrid.fill", "左目录树 · 右大幅比例气泡星图双栏同屏联动"),
                        ("chevron.left.forwardslash.chevron.right", "源码、工程与安装包斜纹光圈自动保护"),
                        ("eye", "⌘Y 原生 Quick Look 快速预览文件"),
                        ("lock.fill", "纯元数据读取，零文件内容触碰")
                    ],
                    onChooseFolder: { model.chooseFolder() },
                    onQuickScanHome: { model.start(FileManager.default.homeDirectoryForCurrentUser) }
                )
            } else {
                // CleanMyMac Space Lens Signature Side-by-Side Split Layout
                HStack(alignment: .top, spacing: 14) {
                    rankingCard
                        .frame(width: 344)

                    VStack(spacing: 12) {
                        visualizationCard
                        HStack(alignment: .top, spacing: 12) {
                            inspector
                                .frame(maxWidth: .infinity)
                            recommendationSummary
                                .frame(width: 228)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var compactStorageStrip: some View {
        let snapCount = model.apfsSnapshots?.snapshots.count ?? 0
        let palette = ModuleStagePalette.forPage("overview")
        let usedRatio = model.volume.total > 0 ? CGFloat(model.volume.used) / CGFloat(model.volume.total) : 0
        let scanValue = model.result.map { DiskFormat.bytes($0.allocated) } ?? (model.scanning ? DiskFormat.bytes(model.progress.allocated) : "待扫描")

        return Surface(padding: 13) {
            HStack(spacing: 16) {
                ZStack {
                    Circle().stroke(palette.primary.opacity(0.14), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: usedRatio)
                        .stroke(
                            AngularGradient(colors: [palette.primary, palette.secondary, palette.primary], center: .center),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                    Text(model.volume.total > 0 ? "\(Int(Double(usedRatio) * 100))%" : "—")
                        .font(.system(size: 12.5, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
                .frame(width: 46, height: 46)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text("\(model.selectedVolume?.name ?? "Macintosh HD") · 还有 \(DiskFormat.bytes(model.volume.free)) 可用")
                            .font(.system(size: 15.5, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text("已用 \(DiskFormat.bytes(model.volume.used)) / 总计 \(DiskFormat.bytes(model.volume.total))")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(palette.primary.opacity(0.11))
                            Capsule()
                                .fill(LinearGradient(colors: [palette.primary, palette.secondary], startPoint: .leading, endPoint: .trailing))
                                .frame(width: g.size.width * usedRatio)
                        }
                    }
                    .frame(height: 5)
                }

                Spacer(minLength: 8)

                // Inline KPI pills
                HStack(spacing: 8) {
                    inlineMetricChip(title: "扫描占用", value: scanValue, tint: DiskTheme.accent)
                    if model.isExternalVolume {
                        inlineMetricChip(title: "访问模式", value: "仅只读分析", tint: .orange)
                    } else {
                        inlineMetricChip(title: "可检查缓存", value: DiskFormat.bytes(model.eligibleBytes), tint: DiskTheme.purple)
                    }
                    inlineMetricChip(title: "默认保护", value: "\(model.recommendations.filter(\.blocked).count) 项", tint: DiskTheme.teal)
                }

                Button {
                    model.showSnapshotsSheet = true
                } label: {
                    Label(snapCount > 0 ? "快照 (\(snapCount))" : "快照透视", systemImage: "camera.aperture")
                }
                .buttonStyle(DiskButtonStyle(kind: .secondary))
                .controlSize(.small)
                .accessibilityIdentifier("apfs-snapshots-button")
            }
        }
    }

    private func inlineMetricChip(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var visualizationCard: some View {
        let topArcs = model.sunburstArcs.filter { $0.depth == 1 }
        return Surface(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    PanelTitle(title: "空间透镜视图", caption: DiskFormat.compactPath(model.activeScope))
                    Picker("配色", selection: $model.visualColorMode) {
                        ForEach(VisualizationColorMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 104)
                    .disabled(model.overviewVisualMode == .columns)
                    .accessibilityIdentifier("visual-color-mode")

                    Picker("视图模式", selection: $model.overviewVisualMode) {
                        ForEach(OverviewVisualMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 276)
                    .accessibilityIdentifier("overview-visual-mode")
                }

                switch model.overviewVisualMode {
                case .bubble:
                    BubbleLensView(
                        bubbles: model.bubbleNodes,
                        canNavigateUp: model.isBrowsingSubfolder,
                        colorMode: model.visualColorMode,
                        selectedPath: model.selectedPath,
                        hoveredPath: $model.hoveredPath,
                        onSelectPath: { path in model.selectedPath = path },
                        onDrillDownPath: { path in model.drillDownPath(path) },
                        onNavigateUp: { model.navigateUp() }
                    )
                    .frame(height: 318)

                case .sunburst:
                    VStack(alignment: .leading, spacing: 8) {
                        SunburstView(
                            arcs: model.sunburstArcs,
                            scopeTitle: scopeTitle,
                            scopeAllocated: scopeAllocated,
                            canNavigateUp: model.isBrowsingSubfolder,
                            colorMode: model.visualColorMode,
                            selectedPath: model.selectedPath,
                            hoveredPath: $model.hoveredPath,
                            onSelectPath: { path in model.selectedPath = path },
                            onDrillDownPath: { path in model.drillDownPath(path) },
                            onNavigateUp: { model.navigateUp() }
                        )
                        .frame(height: 286)

                        if !topArcs.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(topArcs.prefix(10)) { arc in
                                        let color = DiskTheme.color(
                                            forMode: model.visualColorMode,
                                            colorIndex: arc.colorIndex,
                                            category: arc.fileCategory,
                                            ageBucket: arc.ageBucket,
                                            isProtected: arc.isProtected,
                                            isTail: arc.isTailGroup
                                        )
                                        Button {
                                            guard !arc.isTailGroup, let path = arc.path else { return }
                                            if model.selectedPath == path && arc.isDirectory {
                                                model.drillDownPath(path)
                                            } else {
                                                model.selectedPath = path
                                            }
                                        } label: {
                                            HStack(spacing: 4) {
                                                Circle().fill(color).frame(width: 6, height: 6)
                                                if arc.isProtected {
                                                    Image(systemName: "lock.shield.fill").font(.system(size: 8)).foregroundStyle(DiskTheme.teal)
                                                }
                                                Text("\(arc.title) \(String(format: "%.0f%%", arc.fraction * 100))")
                                                    .font(.system(size: 10))
                                            }
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 3)
                                            .background(
                                                (arc.path != nil && model.selectedPath == arc.path) ? color.opacity(0.14) : DiskTheme.inset,
                                                in: Capsule()
                                            )
                                        }
                                        .buttonStyle(DiskButtonStyle(kind: .quiet))
                                        .disabled(arc.isTailGroup)
                                    }
                                }
                            }
                        }
                    }

                case .treemap:
                    TreemapView(
                        rects: model.treemapRects,
                        colorMode: model.visualColorMode,
                        selectedPath: model.selectedPath,
                        hoveredPath: $model.hoveredPath,
                        onSelectPath: { path in model.selectedPath = path },
                        onDrillDownPath: { path in model.drillDownPath(path) }
                    )
                    .frame(height: 318)

                case .columns:
                    MillerColumnsView(
                        columns: model.millerColumns,
                        selectedPath: model.selectedPath,
                        onSelectNode: { node, columnPath in
                            let stdCol = URL(fileURLWithPath: columnPath).standardizedFileURL.path
                            let stdScope = URL(fileURLWithPath: model.activeScope).standardizedFileURL.path
                            if stdCol != stdScope {
                                model.browse(stdCol)
                            }
                            model.selectedPath = node.path
                        },
                        onDrillDownNode: { node in
                            model.drillDownPath(node.path)
                        },
                        onRescanNode: { node in
                            if node.kind == .directory {
                                model.start(URL(fileURLWithPath: node.path))
                            }
                        }
                    )
                    .frame(height: 318)

                case .bar:
                    classicSpaceMapBar
                }
            }
        }
    }

    @ViewBuilder
    private var classicSpaceMapBar: some View {
        let blocks = model.spaceMapBlocks
        if blocks.isEmpty {
            Text(model.scanning ? "正在统计当前层级空间分布…" : "当前层级暂无可显示的占比分块。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 16)
                .accessibilityIdentifier("space-map")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                GeometryReader { geo in
                    let available = max(0, geo.size.width - CGFloat(max(0, blocks.count - 1)) * 2)
                    HStack(spacing: 2) {
                        ForEach(Array(blocks.enumerated()), id: \.element.id) { idx, block in
                            let color = spaceMapColor(block: block, index: idx)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(color.opacity(0.88))
                                .frame(width: max(4, available * CGFloat(block.fraction)))
                                .contentShape(Rectangle())
                                .help("\(block.title) · \(DiskFormat.bytes(block.allocated)) (\(String(format: "%.1f%%", block.fraction * 100)))")
                                .onTapGesture { model.handleSpaceMapTap(block) }
                        }
                    }
                }.frame(height: 18)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(blocks.enumerated()), id: \.element.id) { idx, block in
                            let color = spaceMapColor(block: block, index: idx)
                            Button {
                                model.handleSpaceMapTap(block)
                            } label: {
                                HStack(spacing: 4) {
                                    Circle().fill(color).frame(width: 6, height: 6)
                                    if block.isProtected { Image(systemName: "lock.shield.fill").font(.system(size: 8)).foregroundStyle(DiskTheme.teal) }
                                    Text("\(block.title) \(String(format: "%.0f%%", block.fraction * 100))").font(.system(size: 10))
                                }.padding(.horizontal, 6).padding(.vertical, 2).background(DiskTheme.inset, in: Capsule())
                            }.buttonStyle(DiskButtonStyle(kind: .quiet))
                        }
                    }
                }
            }
            .padding(.vertical, 8)
            .accessibilityIdentifier("space-map")
        }
    }

    private func spaceMapColor(block: SpaceMapBlock, index: Int) -> Color {
        if let path = block.path, let node = model.rows.first(where: { $0.path == path }) {
            let category: FileCategory = node.kind == .directory ? .other : FileCategory.classify(node.name, allocated: node.allocated)
            let age = AgeBucket.classify(modifiedAt: node.modifiedAt)
            return DiskTheme.color(
                forMode: model.visualColorMode,
                colorIndex: index,
                category: category,
                ageBucket: age,
                isProtected: block.isProtected,
                isTail: block.isTailGroup
            )
        }
        return DiskTheme.color(
            forMode: model.visualColorMode,
            colorIndex: index,
            category: .other,
            ageBucket: .recent30d,
            isProtected: block.isProtected,
            isTail: block.isTailGroup
        )
    }

    private var rankingCard: some View {
        Surface(padding: 13) {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    PanelTitle(title: "目录透镜树", caption: model.rankingSort.title)
                    if !model.isBrowsingSubfolder && model.root.path != "/" && model.root != FileManager.default.homeDirectoryForCurrentUser {
                        Button { model.start(model.root.deletingLastPathComponent()) } label: { Image(systemName: "arrow.up") }
                            .controlSize(.small)
                            .help("扫描上一级")
                            .accessibilityLabel("扫描上一级")
                    }
                }

                DiskSearchField(placeholder: "搜索当前层级", text: $model.query)

                Picker("排序", selection: $model.rankingSort) {
                    ForEach(RankingSort.allCases) { item in Text(item.title).tag(item) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityIdentifier("ranking-sort")

                if model.isBrowsingSubfolder {
                    HStack(spacing: 5) {
                        Button { model.navigateUp() } label: { Image(systemName: "chevron.left") }
                            .buttonStyle(DiskButtonStyle(kind: .quiet))
                            .help("返回上一层浏览")
                            .accessibilityLabel("返回上一层浏览")
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 4) {
                                ForEach(Array(model.breadcrumbs.enumerated()), id: \.element.path) { idx, crumb in
                                    if idx > 0 { Image(systemName: "chevron.right").font(.system(size: 8)).foregroundStyle(.tertiary) }
                                    Button(crumb.name) { model.browse(crumb.path) }.buttonStyle(DiskButtonStyle(kind: .quiet)).font(.system(size: 10.5))
                                }
                            }
                        }
                        Spacer(minLength: 0)
                        Button("回到扫描根目录") { model.browse(nil) }
                            .buttonStyle(DiskButtonStyle(kind: .quiet))
                            .font(.system(size: 10))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3.5)
                    .background(DiskTheme.inset, in: RoundedRectangle(cornerRadius: DiskTheme.controlRadius))
                }

                HStack { Text("文件夹 / 文件"); Spacer(); Text("占用 / 比例") }
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)

                if model.rows.isEmpty {
                    Text(model.scanning ? "正在收集目录…" : "此目录没有可列出的文件，或访问受到限制。")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 24)
                }

                VStack(spacing: 2) {
                    ForEach(Array(model.rows.prefix(model.rankingLimit).enumerated()), id: \.element.id) { index, node in
                        diskRow(node, index: index)
                    }
                }
                if model.rows.count > model.rankingLimit {
                    Button("显示更多（已显示 \(model.rankingLimit) / \(model.rows.count) 项）") { model.rankingLimit += 60 }
                        .buttonStyle(DiskButtonStyle(kind: .quiet))
                        .font(.system(size: 10.5))
                        .padding(.top, 4)
                        .accessibilityIdentifier("ranking-show-more")
                }
            }
        }
    }

    private func diskRow(_ node: DiskNode, index: Int) -> some View {
        let fraction = min(1, Double(node.allocated) / Double(max(1, model.result?.allocated ?? model.progress.allocated)))
        let primaryText = model.rankingSort == .logical ? DiskFormat.bytes(node.logical) : DiskFormat.bytes(node.allocated)
        let secondaryText = model.rankingSort == .files ? "\(node.fileCount.formatted()) 文件" : String(format: "%.1f%%", fraction * 100)
        let tint = DiskTheme.colors[index % DiskTheme.colors.count]
        return DiskInteractiveRow(selected: model.selectedPath == node.path, horizontalPadding: 7, verticalPadding: 4.5) {
            HStack(spacing: 8) {
                Image(systemName: node.kind == .directory ? "folder.fill" : "doc.fill")
                    .font(.system(size: 13.5))
                    .foregroundStyle(tint)
                    .frame(width: 24, height: 24)
                    .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text(node.name).font(.system(size: 11.5, weight: .medium)).lineLimit(1)
                        if node.restricted { Image(systemName: "lock.fill").font(.system(size: 8.5)).foregroundStyle(.orange) }
                        if !node.protection.isEmpty { Image(systemName: "lock.shield.fill").font(.system(size: 8.5)).foregroundStyle(DiskTheme.teal) }
                    }
                    GeometryReader { g in
                        Capsule().fill(tint.opacity(0.68)).frame(width: max(2, g.size.width * fraction))
                    }.frame(height: 2.5)
                }.frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(primaryText).font(.system(size: 11.5, weight: .semibold, design: .rounded)).monospacedDigit()
                    Text(secondaryText).font(.system(size: 8.5)).foregroundStyle(.tertiary)
                }.frame(width: 68, alignment: .trailing)
                if model.canBrowse(node) {
                    Button { model.browse(node.path) } label: {
                        Image(systemName: "arrow.turn.down.right").font(.system(size: 9.5)).foregroundStyle(.secondary)
                    }.buttonStyle(DiskButtonStyle(kind: .quiet)).help("展开 \(node.name)").accessibilityLabel("展开 \(node.name)")
                }
                if node.kind == .directory {
                    Button { model.start(URL(fileURLWithPath: node.path)) } label: {
                        Image(systemName: "chevron.right").font(.system(size: 9.5)).foregroundStyle(.tertiary)
                    }.buttonStyle(DiskButtonStyle(kind: .quiet)).help("扫描 \(node.name)").accessibilityLabel("扫描 \(node.name)")
                } else {
                    Color.clear.frame(width: 4)
                }
            }
        }
        .onTapGesture { model.handleNodeTap(node) }
        .contextMenu {
            if node.kind == .file {
                Button("快速预览") { model.quickLook(node.path) }
            }
            Button("在 Finder 中显示") { model.reveal(node.path) }
            Button("复制路径") { model.copyPath(node.path) }
            if model.canBrowse(node) { Button("展开此层级") { model.browse(node.path) } }
            if node.kind == .directory {
                Button(model.isUserProtected(node.path) ? "取消保护此目录" : "保护此目录") {
                    model.toggleProtection(for: node.path)
                }.disabled(model.checking)
                Button("扫描此文件夹") { model.start(URL(fileURLWithPath: node.path)) }
            }
        }
    }

    private var inspector: some View {
        Surface(padding: 13) {
            VStack(alignment: .leading, spacing: 10) {
                PanelTitle(title: "所选项目")
                if let node = model.selectedNode {
                    HStack(spacing: 10) {
                        ModuleIconBadge(
                            symbol: node.kind == .directory ? "folder.fill" : "doc.fill",
                            primary: DiskTheme.accent,
                            secondary: DiskTheme.purple,
                            size: 32
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(node.name).font(.system(size: 13.5, weight: .bold, design: .rounded)).lineLimit(1)
                                if let sparse = DiskFormat.sparsityNote(allocated: node.allocated, logical: node.logical) {
                                    Tag(text: sparse, color: .orange)
                                }
                            }
                            Text(DiskFormat.compactPath(node.path))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                        }
                        Spacer(minLength: 4)
                    }

                    HStack(spacing: 16) {
                        detailPill("已分配", DiskFormat.bytes(node.allocated))
                        detailPill("逻辑大小", DiskFormat.bytes(node.logical))
                        detailPill("文件数", node.fileCount.formatted())
                        if let ts = node.modifiedAt {
                            detailPill("最近修改", Date(timeIntervalSince1970: TimeInterval(ts)).formatted(date: .abbreviated, time: .omitted))
                        }
                    }

                    if !node.protection.isEmpty {
                        Text("保护标识：" + node.protection.map(\.title).sorted().joined(separator: " · "))
                            .font(.system(size: 10))
                            .foregroundStyle(DiskTheme.teal)
                    }

                    HStack(spacing: 8) {
                        if model.canBrowse(node) {
                            Button { model.browse(node.path) } label: { Label("展开此目录", systemImage: "arrow.turn.down.right") }
                                .controlSize(.small)
                        } else if node.kind == .file {
                            Button { model.quickLook(node.path) } label: { Label("快速预览", systemImage: "eye") }
                                .controlSize(.small)
                                .accessibilityIdentifier("inspector-quicklook")
                        }
                        Button { model.reveal(node.path) } label: { Label("在 Finder 中显示", systemImage: "arrow.up.forward.app") }
                            .controlSize(.small)
                        if node.kind == .directory {
                            let isProtected = model.isUserProtected(node.path)
                            Button { model.toggleProtection(for: node.path) } label: {
                                Label(isProtected ? "取消保护" : "保护此目录", systemImage: isProtected ? "lock.slash" : "lock.shield")
                            }
                            .controlSize(.small)
                            .disabled(model.checking)
                            .accessibilityIdentifier("inspector-toggle-protection")
                        }
                    }
                } else {
                    Text("点击任意气泡、扇区或左侧目录项，查看大小和保护状态。")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 14)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func detailPill(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 9.5)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 11.5, weight: .semibold, design: .rounded)).monospacedDigit()
        }
    }

    private var recommendationSummary: some View {
        Surface(padding: 13) {
            VStack(alignment: .leading, spacing: 8) {
                if model.isExternalVolume {
                    HStack {
                        Image(systemName: "externaldrive.badge.checkmark").foregroundStyle(.orange)
                        Text("外部卷 · 只读").font(.system(size: 12, weight: .semibold))
                    }
                    Text("外部存储卷严格只读分析，不开放任何清理操作。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                } else {
                    HStack {
                        Image(systemName: "sparkles").foregroundStyle(DiskTheme.purple)
                        Text("系统清理快览").font(.system(size: 12, weight: .semibold))
                    }
                    Text(model.eligible.isEmpty ? "暂无可处理缓存，核心资产默认保留。" : "发现 \(model.eligible.count) 项可检缓存，约 \(DiskFormat.bytes(model.eligibleBytes))。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                    Button("前往系统清理 →") { model.page = "suggestions" }
                        .buttonStyle(DiskButtonStyle(kind: .quiet))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DiskTheme.accent)
                    Text("目录占用不等于可释放空间。").font(.system(size: 9)).foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
