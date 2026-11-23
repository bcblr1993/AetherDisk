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
        VStack(spacing: 14) {
            storageCard
            HStack(spacing: 12) {
                metric(
                    "扫描占用",
                    model.result.map { DiskFormat.bytes($0.allocated) } ?? (model.scanning ? DiskFormat.bytes(model.progress.allocated) : "尚未扫描"),
                    "已分配大小",
                    "square.stack.3d.up",
                    DiskTheme.accent
                )
                if model.isExternalVolume {
                    metric(
                        "卷访问模式",
                        "仅只读分析",
                        "外部卷不提供清理入口",
                        "externaldrive.badge.checkmark",
                        .orange
                    )
                } else {
                    metric(
                        "可检查缓存",
                        DiskFormat.bytes(model.eligibleBytes),
                        "\(model.eligible.count) 项 · 确认后处理",
                        "sparkles",
                        DiskTheme.purple
                    )
                }
                metric(
                    "默认保护",
                    "\(model.recommendations.filter(\.blocked).count) 项",
                    "源码、安装包与个人数据",
                    "lock.shield",
                    .teal
                )
            }
            if model.scanning { scanStatus }
            if model.result == nil && !model.scanning {
                emptyScan
            } else {
                visualizationCard
                HStack(alignment: .top, spacing: 16) {
                    rankingCard.frame(maxWidth: .infinity)
                    VStack(spacing: 16) {
                        inspector
                        recommendationSummary
                    }.frame(width: 260)
                }
            }
        }
    }

    private var storageCard: some View {
        let snapCount = model.apfsSnapshots?.snapshots.count ?? 0
        return Surface {
            HStack(spacing: 20) {
                ZStack {
                    Circle().stroke(DiskTheme.accent.opacity(0.09), lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: model.volume.total > 0 ? CGFloat(model.volume.used) / CGFloat(model.volume.total) : 0)
                        .stroke(
                            AngularGradient(colors: [DiskTheme.accent, DiskTheme.purple], center: .center, startAngle: .degrees(0), endAngle: .degrees(360)),
                            style: StrokeStyle(lineWidth: 8, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 1) {
                        Text(model.volume.total > 0 ? "\(Int(Double(model.volume.used) / Double(model.volume.total) * 100))%" : "—")
                            .font(.system(size: 19, weight: .semibold, design: .rounded))
                        Text("已使用").font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                }.frame(width: 64, height: 64).padding(4)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 8) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("所选位置所在磁盘").font(.system(size: 11)).foregroundStyle(.secondary)
                            Text("还有 \(DiskFormat.bytes(model.volume.free)) 可用")
                                .font(.system(size: 22, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                        }
                        Spacer()
                        Button {
                            model.showSnapshotsSheet = true
                        } label: {
                            Label(snapCount > 0 ? "APFS 本地快照 (\(snapCount))" : "快照透视", systemImage: "camera.aperture")
                        }
                        .buttonStyle(DiskButtonStyle(kind: snapCount > 0 ? .secondary : .quiet))
                        .controlSize(.small)
                        .foregroundStyle(snapCount > 0 ? Color.orange : Color.secondary)
                        .accessibilityIdentifier("apfs-snapshots-button")

                        if model.isExternalVolume {
                            Tag(text: "外部卷 · 仅只读分析", color: .orange)
                        } else {
                            Tag(text: "本机实时容量", color: .teal)
                        }
                    }

                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(DiskTheme.accent.opacity(0.09))
                            Capsule()
                                .fill(LinearGradient(colors: [DiskTheme.accent, DiskTheme.purple], startPoint: .leading, endPoint: .trailing))
                                .frame(width: model.volume.total > 0 ? g.size.width * CGFloat(model.volume.used) / CGFloat(model.volume.total) : 0)
                        }
                    }.frame(height: 6)

                    HStack {
                        Text("已用 \(DiskFormat.bytes(model.volume.used))")
                        Spacer()
                        Text("总容量 \(DiskFormat.bytes(model.volume.total))")
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                    if model.volume.purgeableNote != nil || (model.trashSummary?.readable == true && (model.trashSummary?.allocated ?? 0) > 0) {
                        HStack(spacing: 12) {
                            if let purgeable = model.volume.purgeableNote {
                                Text(purgeable).font(.system(size: 10)).foregroundStyle(.teal)
                            }
                            Spacer(minLength: 0)
                            if let trash = model.trashSummary, trash.readable, trash.allocated > 0 {
                                Label("废纸篓占 \(DiskFormat.bytes(trash.allocated))（\(trash.itemCount) 项）", systemImage: "trash")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private func metric(_ title: String, _ value: String, _ caption: String, _ icon: String, _ tint: Color) -> some View {
        Surface(padding: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(value)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text(caption).font(.system(size: 9)).foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var scanStatus: some View {
        HStack(spacing: 12) {
            ProgressView().controlSize(.small)
            VStack(alignment: .leading, spacing: 4) {
                Text("正在扫描 · \(model.progress.files.formatted()) 个文件").font(.system(size: 12, weight: .medium))
                Text(DiskFormat.compactPath(model.progress.currentPath)).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Text("可随时停止").font(.system(size: 10)).foregroundStyle(.secondary)
        }.padding(14).background(DiskTheme.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    private var emptyScan: some View {
        Surface {
            VStack(spacing: 16) {
                Image(systemName: "folder.badge.magnifyingglass")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(DiskTheme.accent)
                    .padding(.top, 20)
                Text("从一个文件夹开始").font(.system(size: 18, weight: .semibold))
                Text("包含隐藏目录，逐层看清占用。\n扫描不读取文件内容，也不会修改你的文件；支持将文件夹直接拖入窗口分析。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
                Button("扫描个人文件夹") { model.start(FileManager.default.homeDirectoryForCurrentUser) }
                    .buttonStyle(DiskButtonStyle(kind: .primary))
                HStack(spacing: 24) {
                    Label("源码保护", systemImage: "chevron.left.forwardslash.chevron.right")
                    Label("确认后清理", systemImage: "checkmark.shield")
                    Label("本地处理", systemImage: "lock")
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .padding(.vertical, 20)
            }.frame(maxWidth: .infinity)
        }
    }

    private var visualizationCard: some View {
        let topArcs = model.sunburstArcs.filter { $0.depth == 1 }
        return Surface {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    PanelTitle(title: "空间分布视图", caption: DiskFormat.compactPath(model.activeScope))
                    Picker("配色", selection: $model.visualColorMode) {
                        ForEach(VisualizationColorMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 112)
                    .disabled(model.overviewVisualMode == .columns)
                    .accessibilityIdentifier("visual-color-mode")

                    Picker("视图模式", selection: $model.overviewVisualMode) {
                        ForEach(OverviewVisualMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 248)
                    .accessibilityIdentifier("overview-visual-mode")
                }

                switch model.overviewVisualMode {
                case .sunburst:
                    VStack(alignment: .leading, spacing: 10) {
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
                        .frame(height: 265)

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
                                                    Image(systemName: "lock.shield.fill").font(.system(size: 8)).foregroundStyle(.teal)
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
                    .frame(height: 265)

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
                    .frame(height: 275)

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
                                .fill(color.opacity(0.85))
                                .frame(width: max(4, available * CGFloat(block.fraction)))
                                .contentShape(Rectangle())
                                .help("\(block.title) · \(DiskFormat.bytes(block.allocated)) (\(String(format: "%.1f%%", block.fraction * 100)))")
                                .onTapGesture { model.handleSpaceMapTap(block) }
                        }
                    }
                }.frame(height: 14)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(blocks.enumerated()), id: \.element.id) { idx, block in
                            let color = spaceMapColor(block: block, index: idx)
                            Button {
                                model.handleSpaceMapTap(block)
                            } label: {
                                HStack(spacing: 4) {
                                    Circle().fill(color).frame(width: 6, height: 6)
                                    if block.isProtected { Image(systemName: "lock.shield.fill").font(.system(size: 8)).foregroundStyle(.teal) }
                                    Text("\(block.title) \(String(format: "%.0f%%", block.fraction * 100))").font(.system(size: 10))
                                }.padding(.horizontal, 6).padding(.vertical, 2).background(DiskTheme.inset, in: Capsule())
                            }.buttonStyle(DiskButtonStyle(kind: .quiet))
                        }
                    }
                }
            }
            .padding(.vertical, 2)
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
        Surface {
            VStack(alignment: .leading, spacing: 10) {
                PanelTitle(title: "占用排行", caption: model.rankingSort.title)
                HStack(spacing: 8) {
                    DiskSearchField(placeholder: "搜索当前层级", text: $model.query)
                    Picker("排序", selection: $model.rankingSort) {
                        ForEach(RankingSort.allCases) { item in Text(item.title).tag(item) }
                    }.pickerStyle(.segmented).labelsHidden().frame(width: 168).accessibilityIdentifier("ranking-sort")
                    if !model.isBrowsingSubfolder && model.root.path != "/" && model.root != FileManager.default.homeDirectoryForCurrentUser {
                        Button { model.start(model.root.deletingLastPathComponent()) } label: { Image(systemName: "arrow.up") }.help("扫描上一级")
                    }
                }
                if model.isBrowsingSubfolder {
                    HStack(spacing: 6) {
                        Button { model.navigateUp() } label: { Image(systemName: "chevron.left") }
                            .buttonStyle(DiskButtonStyle(kind: .quiet))
                            .help("返回上一层浏览")
                            .accessibilityLabel("返回上一层浏览")
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 4) {
                                ForEach(Array(model.breadcrumbs.enumerated()), id: \.element.path) { idx, crumb in
                                    if idx > 0 { Image(systemName: "chevron.right").font(.system(size: 8)).foregroundStyle(.tertiary) }
                                    Button(crumb.name) { model.browse(crumb.path) }.buttonStyle(DiskButtonStyle(kind: .quiet)).font(.system(size: 11))
                                }
                            }
                        }
                        Spacer(minLength: 0)
                        Button("回到扫描根目录") { model.browse(nil) }.buttonStyle(DiskButtonStyle(kind: .quiet)).font(.system(size: 10))
                    }.padding(.horizontal, 8).padding(.vertical, 4).background(DiskTheme.inset, in: RoundedRectangle(cornerRadius: DiskTheme.controlRadius))
                }
                HStack { Text("文件夹 / 文件"); Spacer(); Text("占用 / 比例") }.font(.system(size: 10)).foregroundStyle(.tertiary)
                if model.rows.isEmpty {
                    Text(model.scanning ? "正在收集目录…" : "此目录没有可列出的文件，或访问受到限制。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 28)
                }
                VStack(spacing: 2) {
                    ForEach(Array(model.rows.prefix(model.rankingLimit).enumerated()), id: \.element.id) { index, node in
                        diskRow(node, index: index)
                    }
                }
                if model.rows.count > model.rankingLimit {
                    Button("显示更多（已显示 \(model.rankingLimit) / \(model.rows.count) 项）") { model.rankingLimit += 60 }
                        .buttonStyle(DiskButtonStyle(kind: .quiet))
                        .font(.system(size: 11))
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
        return DiskInteractiveRow(selected: model.selectedPath == node.path, horizontalPadding: 8, verticalPadding: 5) {
            HStack(spacing: 10) {
                Image(systemName: node.kind == .directory ? "folder.fill" : "doc.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 5) {
                        Text(node.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                        if node.restricted { Image(systemName: "lock").font(.system(size: 9)).foregroundStyle(.orange) }
                        if !node.protection.isEmpty { Image(systemName: "lock.shield").font(.system(size: 9)).foregroundStyle(.teal) }
                    }
                    GeometryReader { g in
                        Capsule().fill(tint.opacity(0.65)).frame(width: max(2, g.size.width * fraction))
                    }.frame(height: 3)
                }.frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(primaryText).font(.system(size: 12, weight: .medium, design: .rounded)).monospacedDigit()
                    Text(secondaryText).font(.system(size: 9)).foregroundStyle(.tertiary)
                }.frame(width: 75, alignment: .trailing)
                if model.canBrowse(node) {
                    Button { model.browse(node.path) } label: {
                        Image(systemName: "arrow.turn.down.right").font(.system(size: 10)).foregroundStyle(.secondary)
                    }.buttonStyle(DiskButtonStyle(kind: .quiet)).help("展开 \(node.name)").accessibilityLabel("展开 \(node.name)")
                }
                if node.kind == .directory {
                    Button { model.start(URL(fileURLWithPath: node.path)) } label: {
                        Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(.tertiary)
                    }.buttonStyle(DiskButtonStyle(kind: .quiet)).help("扫描 \(node.name)").accessibilityLabel("扫描 \(node.name)")
                } else {
                    Color.clear.frame(width: 6)
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
        Surface {
            VStack(alignment: .leading, spacing: 14) {
                PanelTitle(title: "所选项目")
                if let node = model.selectedNode {
                    Image(systemName: node.kind == .directory ? "folder.fill" : "doc.fill").font(.system(size: 25)).foregroundStyle(DiskTheme.accent)
                    Text(node.name).font(.system(size: 15, weight: .semibold)).lineLimit(2)
                    Text(DiskFormat.compactPath(node.path)).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(3).truncationMode(.middle).textSelection(.enabled)
                    Divider()
                    detail("已分配", DiskFormat.bytes(node.allocated))
                    detail("逻辑大小", DiskFormat.bytes(node.logical))
                    detail("文件数", node.fileCount.formatted())
                    if let sparse = DiskFormat.sparsityNote(allocated: node.allocated, logical: node.logical) { Tag(text: sparse, color: .orange) }
                    if let ts = node.modifiedAt { detail("最近修改", Date(timeIntervalSince1970: TimeInterval(ts)).formatted(date: .abbreviated, time: .omitted)) }
                    if let delta = model.delta(node) { detail("较上次", (delta >= 0 ? "+" : "−") + DiskFormat.bytes(delta)) }
                    if !node.protection.isEmpty {
                        Text(node.protection.map(\.title).sorted().joined(separator: " · "))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineSpacing(4)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            if model.canBrowse(node) {
                                Button { model.browse(node.path) } label: { Label("展开此目录", systemImage: "arrow.turn.down.right") }
                                    .font(.system(size: 11))
                                    .controlSize(.small)
                            } else if node.kind == .file {
                                Button { model.quickLook(node.path) } label: { Label("快速预览", systemImage: "eye") }
                                    .font(.system(size: 11))
                                    .controlSize(.small)
                                    .accessibilityIdentifier("inspector-quicklook")
                            }
                            Button { model.reveal(node.path) } label: { Label("在 Finder 中显示", systemImage: "arrow.up.forward.app") }
                                .font(.system(size: 11))
                                .controlSize(.small)
                        }
                        if node.kind == .directory {
                            let isProtected = model.isUserProtected(node.path)
                            Button { model.toggleProtection(for: node.path) } label: {
                                Label(isProtected ? "取消保护" : "保护此目录", systemImage: isProtected ? "lock.slash" : "lock.shield")
                            }
                            .font(.system(size: 11))
                            .controlSize(.small)
                            .disabled(model.checking)
                            .accessibilityIdentifier("inspector-toggle-protection")
                        }
                    }
                } else {
                    Text("选择一项，查看大小和保护状态。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 20)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func detail(_ label: String, _ value: String) -> some View {
        HStack { Text(label).foregroundStyle(.secondary); Spacer(); Text(value).monospacedDigit() }.font(.system(size: 11))
    }

    private var recommendationSummary: some View {
        Surface {
            VStack(alignment: .leading, spacing: 12) {
                if model.isExternalVolume {
                    HStack {
                        Image(systemName: "externaldrive.badge.checkmark").foregroundStyle(.orange)
                        Text("外部卷 · 仅只读分析").font(.system(size: 12, weight: .semibold))
                    }
                    Text("当前所选位置位于外部存储卷，仅提供只读空间统计，不开放清理建议或移入废纸篓操作。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineSpacing(4)
                } else {
                    HStack { Image(systemName: "sparkles").foregroundStyle(DiskTheme.purple); Text("留一点呼吸空间").font(.system(size: 12, weight: .semibold)) }
                    Text(model.eligible.isEmpty ? "暂无明确可处理的缓存。重要文件会默认保留。" : "发现 \(model.eligible.count) 项缓存可进一步检查，目录占用约 \(DiskFormat.bytes(model.eligibleBytes))。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineSpacing(4)
                    Button("查看清理建议 →") { model.page = "suggestions" }
                        .buttonStyle(DiskButtonStyle(kind: .quiet))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DiskTheme.accent)
                    Text("目录占用不等于可释放空间。").font(.system(size: 9)).foregroundStyle(.tertiary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
