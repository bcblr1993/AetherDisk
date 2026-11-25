import SwiftUI
import AetherDiskCore

struct LargeFilesPage: View {
    @ObservedObject var model: AppModel

    private var palette: ModuleStagePalette {
        ModuleStagePalette.forPage("large")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Surface {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        PanelTitle(title: "我的杂物筛查台", caption: "只读定位与预览 · 不提供批量删除")
                        Picker(
                            "杂物视图",
                            selection: Binding(
                                get: { model.clutterTab },
                                set: { nextTab in
                                    model.clutterTab = nextTab
                                    model.showDuplicateSuspects = (nextTab == .duplicates)
                                }
                            )
                        ) {
                            ForEach(ClutterSubTab.allCases) { tab in
                                Text(tab.title).tag(tab)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 288)
                        .accessibilityIdentifier("clutter-subtabs")
                    }

                    HStack(spacing: 10) {
                        DiskSearchField(placeholder: "搜索文件名或路径", text: $model.largeQuery, identifier: "large-search")
                        Picker("大小", selection: $model.largeBasis) {
                            ForEach(SizeBasis.allCases) { basis in Text(basis.title).tag(basis) }
                        }.frame(width: 146).accessibilityIdentifier("large-basis")
                        Picker("至少", selection: $model.largeMinimum) {
                            Text("1 MiB").tag(Int64(1024 * 1024))
                            Text("10 MiB").tag(Int64(10 * 1024 * 1024))
                            Text("100 MiB").tag(Int64(100 * 1024 * 1024))
                            Text("1 GiB").tag(Int64(1024 * 1024 * 1024))
                        }.frame(width: 118).accessibilityIdentifier("large-minimum")
                        Picker("时间维度", selection: $model.largeTimeAxis) {
                            ForEach(TimeAxis.allCases) { axis in Text(axis.title).tag(axis) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 172)
                        .accessibilityIdentifier("clutter-time-axis")
                        Picker(model.largeTimeAxis == .modified ? "修改" : "访问", selection: $model.largeStaleDays) {
                            Text("不限时间").tag(0)
                            Text(model.largeTimeAxis == .modified ? "30 天未改" : "30 天未访问").tag(30)
                            Text(model.largeTimeAxis == .modified ? "90 天未改" : "90 天未访问").tag(90)
                            Text(model.largeTimeAxis == .modified ? "1 年未改" : "1 年未访问").tag(365)
                        }.frame(width: 132).accessibilityIdentifier("large-stale")
                    }.font(.system(size: 11)).controlSize(.large)

                    if model.clutterTab != .downloadsAndArchives {
                        Picker("文件类型", selection: $model.largeCategory) {
                            Text("全部类型").tag(nil as FileCategory?)
                            ForEach(FileCategory.allCases) { Text($0.title).tag(Optional($0)) }
                        }
                        .pickerStyle(.segmented)
                        .font(.system(size: 11))
                        .accessibilityIdentifier("large-category")
                    }

                    HStack(spacing: 12) {
                        Toggle("疑似重复大文件线索（仅元数据）", isOn: $model.showDuplicateSuspects)
                            .toggleStyle(.checkbox)
                            .font(.system(size: 11))
                            .accessibilityIdentifier("large-duplicates-toggle")
                        Spacer()
                        Text("硬链接自动去重 · 稀疏文件区分实际块占用与逻辑体积")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            if let result = model.result, !result.complete {
                Label("当前为部分扫描结果，排行与类型统计可能不完整。", systemImage: "exclamationmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }

            if model.result == nil && !model.scanning {
                ModuleHeroStage(
                    palette: palette,
                    targetPath: DiskFormat.compactPath(model.root.path),
                    features: [
                        ("doc.text.magnifyingglass", "跨目录巨型文件排行"),
                        ("clock.arrow.circlepath", "修改与访问双时间轴陈旧筛查"),
                        ("doc.on.doc.fill", "纯元数据疑似重复快速对比"),
                        ("eye", "一键 Quick Look 预览")
                    ],
                    onChooseFolder: { model.chooseFolder() },
                    onQuickScanHome: { model.start(FileManager.default.homeDirectoryForCurrentUser) }
                )
            } else if model.showDuplicateSuspects || model.clutterTab == .duplicates {
                duplicateSuspectsSection
            } else {
                clutterMetadataStrip
                largeFilesListSection
            }
        }
    }

    private func categorySymbol(for category: FileCategory) -> String {
        switch category {
        case .video: return "film.fill"
        case .audio: return "waveform"
        case .image: return "photo.fill"
        case .archive: return "shippingbox.fill"
        case .document: return "doc.text.fill"
        case .source: return "chevron.left.forwardslash.chevron.right"
        case .other: return "doc.fill"
        }
    }

    private func categoryColor(for category: FileCategory) -> Color {
        DiskTheme.color(
            forMode: .fileType,
            colorIndex: 0,
            category: category,
            ageBucket: .recent30d,
            isProtected: false,
            isTail: false
        )
    }

    private func formattedShortDate(_ timestamp: Int64?) -> String {
        guard let timestamp, timestamp > 0 else { return "未知" }
        return Date(timeIntervalSince1970: TimeInterval(timestamp))
            .formatted(date: .abbreviated, time: .omitted)
    }

    private func formattedDateTime(_ timestamp: Int64?) -> String {
        guard let timestamp, timestamp > 0 else { return "未知" }
        return Date(timeIntervalSince1970: TimeInterval(timestamp))
            .formatted(date: .abbreviated, time: .shortened)
    }

    private func ageTagTitle(for bucket: AgeBucket) -> String {
        if model.largeTimeAxis == .accessed && bucket == .over1y {
            return "1 年以上未访问"
        }
        return bucket.title
    }

    private func sizeTierTag(for bytes: Int64) -> (String, Color)? {
        if bytes >= 1024 * 1024 * 1024 {
            return ("巨型 ≥ 1 GiB", DiskTheme.danger)
        } else if bytes >= 100 * 1024 * 1024 {
            return ("大型 ≥ 100 MiB", .orange)
        }
        return nil
    }

    private var clutterMetadataStrip: some View {
        let summary = model.clutterHighlight
        let isMediaActive = model.clutterTab == .largeAndOld
            && (model.largeCategory == .video || model.largeCategory == .audio || model.largeCategory == .image)
        let isArchiveActive = model.clutterTab == .downloadsAndArchives
        let isStaleActive = model.clutterTab == .largeAndOld && model.largeStaleDays >= 90

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("杂物资产分布概览（≥ 1 MiB 独立文件）")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("clutter-meta-cards")
                Spacer()
                Text(model.largeTimeAxis == .modified ? "陈旧度统计口径：最后修改时间" : "陈旧度统计口径：最后访问时间")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 12) {
                clutterMetaCard(
                    title: "媒体资产",
                    value: DiskFormat.bytes(summary.mediaAllocated),
                    caption: "\(summary.mediaCount) 个文件 · 视频 / 音频 / 图片",
                    actionTitle: "筛选媒体",
                    symbol: "film.fill",
                    tint: palette.primary,
                    active: isMediaActive,
                    accessibilityLabel: "快速筛选媒体资产"
                ) {
                    model.applyClutterMediaFilter()
                }

                clutterMetaCard(
                    title: "安装包与归档",
                    value: DiskFormat.bytes(summary.archiveAllocated),
                    caption: "\(summary.archiveCount) 个文件 · .dmg / .pkg / .zip 等",
                    actionTitle: "查看归档",
                    symbol: "shippingbox.fill",
                    tint: palette.secondary,
                    active: isArchiveActive,
                    accessibilityLabel: "快速查看安装包与归档清单"
                ) {
                    model.applyClutterArchiveFilter()
                }

                clutterMetaCard(
                    title: "陈旧大文件",
                    value: DiskFormat.bytes(summary.stale90Allocated),
                    caption: "\(summary.stale90Count) 个文件 · \(model.largeTimeAxis == .modified ? "90 天以上未修改" : "90 天以上未访问")",
                    actionTitle: "筛选 90 天",
                    symbol: "clock.arrow.circlepath",
                    tint: DiskTheme.teal,
                    active: isStaleActive,
                    accessibilityLabel: "快速筛选 90 天陈旧大文件"
                ) {
                    model.applyClutterStaleFilter()
                }
            }
        }
    }

    private func clutterMetaCard(
        title: String,
        value: String,
        caption: String,
        actionTitle: String,
        symbol: String,
        tint: Color,
        active: Bool,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Surface(padding: 13) {
                HStack(alignment: .top, spacing: 11) {
                    ModuleIconBadge(symbol: symbol, primary: tint, secondary: tint.opacity(0.75), size: 30)
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 6) {
                            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
                            Spacer(minLength: 4)
                            Text(actionTitle)
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(tint)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(tint.opacity(0.11), in: Capsule())
                        }
                        Text(value)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Text(caption)
                            .font(.system(size: 9.5))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .overlay(
                RoundedRectangle(cornerRadius: DiskTheme.cardRadius, style: .continuous)
                    .stroke(active ? tint.opacity(0.55) : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .help("只读切换至\(title)视图")
    }

    private var largeFilesListSection: some View {
        Surface {
            VStack(alignment: .leading, spacing: 10) {
                PanelTitle(
                    title: model.clutterTab == .downloadsAndArchives ? "安装包与归档文件清单" : "跨目录大文件与旧文件清单",
                    caption: "\(model.largeFiles.count) 项 · \(model.largeTimeAxis.title)"
                )
                if model.result?.analysis == nil {
                    Text(model.scanning ? "扫描完成后显示全目录排行。" : "开始一次新扫描，获取大文件排行。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 28)
                } else if model.largeFiles.isEmpty {
                    Text("没有符合当前大小、类型和搜索条件的文件。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 28)
                }
                ForEach(model.largeFiles) { node in
                    let basisSize = model.largeBasis.size(node)
                    let category = FileCategory.classify(node.name, allocated: node.allocated)
                    let tint = categoryColor(for: category)
                    let activeTimestamp = model.largeTimeAxis.timestamp(for: node)
                    let ageBucket = AgeBucket.classify(modifiedAt: activeTimestamp)
                    let isSelected = model.selectedPath == node.path
                    DiskInteractiveRow(selected: isSelected, horizontalPadding: 8, verticalPadding: 10) {
                        HStack(alignment: .top, spacing: 12) {
                            ModuleIconBadge(
                                symbol: categorySymbol(for: category),
                                primary: tint,
                                secondary: tint.opacity(0.75),
                                size: 32
                            )
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(spacing: 6) {
                                    Text(node.name).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                                    Tag(text: category.title, color: tint)
                                    if let tier = sizeTierTag(for: basisSize) {
                                        Tag(text: tier.0, color: tier.1)
                                    }
                                    if ageBucket == .over1y || ageBucket == .days90to365 {
                                        Tag(text: ageTagTitle(for: ageBucket), color: .secondary)
                                    }
                                }
                                Text(DiskFormat.compactPath(node.path))
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .help(node.path)
                                HStack(spacing: 8) {
                                    HStack(spacing: 5) {
                                        Image(systemName: "clock")
                                            .font(.system(size: 9))
                                            .foregroundStyle(.tertiary)
                                        Text("修改 \(formattedShortDate(node.modifiedAt)) · 访问 \(formattedShortDate(node.accessedAt))")
                                            .font(.system(size: 10))
                                            .foregroundStyle(.secondary)
                                            .monospacedDigit()
                                    }
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2.5)
                                    .background(DiskTheme.inset, in: Capsule())

                                    if !node.protection.isEmpty {
                                        Text(node.protection.map(\.title).sorted().joined(separator: " · "))
                                            .font(.system(size: 10))
                                            .foregroundStyle(DiskTheme.teal)
                                    }
                                }
                            }
                            Spacer(minLength: 12)
                            VStack(alignment: .trailing, spacing: 5) {
                                Text(DiskFormat.bytes(basisSize))
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                                Text(model.largeBasis == .allocated ? "逻辑 " + DiskFormat.bytes(node.logical) : "占用 " + DiskFormat.bytes(node.allocated))
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                HStack(spacing: 6) {
                                    Button("快速预览") {
                                        model.selectedPath = node.path
                                        model.quickLook(node.path)
                                    }
                                    .buttonStyle(DiskButtonStyle(kind: .quiet))
                                    .controlSize(.small)
                                    .accessibilityLabel("预览 " + node.name)
                                    Button("在 Finder 中显示") {
                                        model.selectedPath = node.path
                                        model.reveal(node.path)
                                    }
                                    .buttonStyle(DiskButtonStyle(kind: .quiet))
                                    .controlSize(.small)
                                    .accessibilityLabel("定位 " + node.name)
                                }
                            }
                        }
                    }
                    .onTapGesture {
                        model.selectedPath = node.path
                    }
                    .contextMenu {
                        Button("快速预览") { model.quickLook(node.path) }
                        Button("在 Finder 中显示") { model.reveal(node.path) }
                        Button("复制路径") { model.copyPath(node.path) }
                    }
                    Divider().opacity(0.6)
                }
            }
        }
    }

    private var duplicateSuspectsSection: some View {
        Surface {
            VStack(alignment: .leading, spacing: 14) {
                PanelTitle(title: "疑似重复大文件线索", caption: "\(model.duplicateGroups.count) 组 · \(model.largeTimeAxis.title)")
                HStack(spacing: 8) {
                    Image(systemName: "doc.on.doc.fill").foregroundStyle(palette.primary)
                    Text("仅按逻辑大小与扩展名归组，绝不读取文件内容 · 仅提供快速预览与定位")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DiskTheme.inset, in: RoundedRectangle(cornerRadius: DiskTheme.controlRadius))

                if model.result?.analysis == nil {
                    Text(model.scanning ? "扫描完成后生成疑似重复线索。" : "开始一次新扫描，获取纯元数据重复线索。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 28)
                } else if model.duplicateGroups.isEmpty {
                    Text("未发现 1 MiB 以上同逻辑大小且同扩展名的独立文件组。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 28)
                } else {
                    if let selectedGroup = model.selectedDuplicateGroup {
                        duplicateComparisonPanel(for: selectedGroup)
                    }

                    ForEach(model.duplicateGroups) { group in
                        let isGroupSelected = model.selectedDuplicateGroup?.id == group.id
                        let groupComparison = group.comparisonSummary(timeAxis: model.largeTimeAxis)
                        let catTint = categoryColor(for: group.category)

                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: categorySymbol(for: group.category))
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(catTint)
                                Text(group.ext == "(无扩展名)" ? "无扩展名" : ".\(group.ext)")
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                Tag(text: group.category.title, color: catTint)
                                Text("逻辑大小 \(DiskFormat.bytes(group.logicalSize)) · \(group.files.count) 份独立文件")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                if isGroupSelected {
                                    Tag(text: "正在对比", color: palette.primary)
                                }
                                Spacer()
                                if group.potentialRedundantAllocated > 0 {
                                    Tag(text: "疑似冗余约 \(DiskFormat.bytes(group.potentialRedundantAllocated))", color: .orange)
                                }
                                Text("总占用 \(DiskFormat.bytes(group.totalAllocated))")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                                if !isGroupSelected {
                                    Button("对比详情") {
                                        model.selectedDuplicateGroupID = group.id
                                        model.selectedPath = group.files.first?.path
                                    }
                                    .buttonStyle(DiskButtonStyle(kind: .quiet))
                                    .controlSize(.small)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                model.selectedDuplicateGroupID = group.id
                                model.selectedPath = group.files.first?.path
                            }

                            ForEach(group.files) { file in
                                let isNewest = groupComparison.newestPath == file.path
                                let isOldest = groupComparison.oldestPath == file.path
                                DiskInteractiveRow(selected: model.selectedPath == file.path, horizontalPadding: 8, verticalPadding: 6) {
                                    HStack(spacing: 10) {
                                        Image(systemName: categorySymbol(for: group.category))
                                            .font(.system(size: 14))
                                            .foregroundStyle(catTint)
                                        VStack(alignment: .leading, spacing: 3) {
                                            HStack(spacing: 6) {
                                                Text(file.name).font(.system(size: 11, weight: .medium)).lineLimit(1)
                                                if isNewest {
                                                    Tag(text: "最新副本", color: DiskTheme.accent)
                                                } else if isOldest {
                                                    Tag(text: "较旧副本", color: .orange)
                                                }
                                                if !file.protection.isEmpty {
                                                    Text(file.protection.map(\.title).sorted().joined(separator: " · "))
                                                        .font(.system(size: 9))
                                                        .foregroundStyle(DiskTheme.teal)
                                                }
                                            }
                                            Text(DiskFormat.compactPath(file.path))
                                                .font(.system(size: 10))
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                                .help(file.path)
                                            Text("修改 \(formattedShortDate(file.modifiedAt)) · 访问 \(formattedShortDate(file.accessedAt))")
                                                .font(.system(size: 9.5))
                                                .foregroundStyle(.tertiary)
                                                .monospacedDigit()
                                        }
                                        Spacer(minLength: 8)
                                        VStack(alignment: .trailing, spacing: 2) {
                                            Text(DiskFormat.bytes(file.allocated))
                                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                                .monospacedDigit()
                                            if file.logical != file.allocated {
                                                Text("逻辑 \(DiskFormat.bytes(file.logical))")
                                                    .font(.system(size: 9))
                                                    .foregroundStyle(.tertiary)
                                                    .monospacedDigit()
                                            }
                                        }
                                        Button("快速预览") {
                                            model.selectedDuplicateGroupID = group.id
                                            model.selectedPath = file.path
                                            model.quickLook(file.path)
                                        }
                                        .buttonStyle(DiskButtonStyle(kind: .quiet))
                                        .controlSize(.small)
                                        Button("在 Finder 中显示") {
                                            model.selectedDuplicateGroupID = group.id
                                            model.selectedPath = file.path
                                            model.reveal(file.path)
                                        }
                                        .buttonStyle(DiskButtonStyle(kind: .quiet))
                                        .controlSize(.small)
                                    }
                                }
                                .onTapGesture {
                                    model.selectedDuplicateGroupID = group.id
                                    model.selectedPath = file.path
                                }
                                .contextMenu {
                                    Button("快速预览") { model.quickLook(file.path) }
                                    Button("在 Finder 中显示") { model.reveal(file.path) }
                                    Button("复制路径") { model.copyPath(file.path) }
                                }
                            }
                        }
                        .padding(12)
                        .background(
                            isGroupSelected ? palette.primary.opacity(0.06) : DiskTheme.inset,
                            in: RoundedRectangle(cornerRadius: DiskTheme.controlRadius)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: DiskTheme.controlRadius)
                                .stroke(isGroupSelected ? palette.primary.opacity(0.35) : .clear, lineWidth: 1.2)
                        )
                    }
                }
            }
        }
        .onAppear {
            model.syncSelectedDuplicateGroup()
        }
        .onChange(of: model.duplicateGroups) { _, _ in
            model.syncSelectedDuplicateGroup()
        }
    }

    private func duplicateComparisonPanel(for group: DuplicateSizeGroup) -> some View {
        let comparison = group.comparisonSummary(timeAxis: model.largeTimeAxis)
        let newestFile = comparison.newestPath.flatMap { path in group.files.first { $0.path == path } }
        let oldestFile = comparison.oldestPath.flatMap { path in group.files.first { $0.path == path } }
        let extLabel = group.ext == "(无扩展名)" ? "无扩展名" : ".\(group.ext)"

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.split.2x1.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.primary)
                Text("疑似重复快速对比面板")
                    .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                    .accessibilityIdentifier("duplicate-compare-panel")
                Tag(text: "\(extLabel) · \(group.files.count) 份副本", color: palette.primary)
                Spacer()
                Tag(text: "纯只读核验 · 无删除入口", color: DiskTheme.teal)
            }

            HStack(spacing: 10) {
                comparisonMetricTile(
                    title: "物理 / 单份逻辑",
                    value: "\(DiskFormat.bytes(group.totalAllocated)) / \(DiskFormat.bytes(group.logicalSize))",
                    caption: "疑似冗余约 \(DiskFormat.bytes(group.potentialRedundantAllocated))"
                )
                comparisonMetricTile(
                    title: "时间跨度",
                    value: "\(comparison.spanDays) 天",
                    caption: model.largeTimeAxis == .modified ? "按修改时间计算" : "按访问时间计算"
                )
                comparisonMetricTile(
                    title: "受保护副本",
                    value: "\(comparison.protectedCount) / \(group.files.count) 份",
                    caption: comparison.protectedCount > 0 ? "含保护防线标记" : "暂无保护标记"
                )
                comparisonMetricTile(
                    title: "对比时间轴",
                    value: model.largeTimeAxis.title,
                    caption: "支持点击下方分组切换对比"
                )
            }

            HStack(alignment: .top, spacing: 12) {
                duplicateComparisonFileCard(
                    roleTitle: "最新副本",
                    roleColor: DiskTheme.accent,
                    file: newestFile,
                    groupCategory: group.category
                )
                duplicateComparisonFileCard(
                    roleTitle: "较旧副本",
                    roleColor: .orange,
                    file: oldestFile,
                    groupCategory: group.category
                )
            }
        }
        .padding(14)
        .background(DiskTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: DiskTheme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DiskTheme.cardRadius, style: .continuous)
                .stroke(palette.primary.opacity(0.26), lineWidth: 1)
        )
    }

    private func comparisonMetricTile(title: String, value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(caption)
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DiskTheme.inset, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func duplicateComparisonFileCard(
        roleTitle: String,
        roleColor: Color,
        file: DiskNode?,
        groupCategory: FileCategory
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Tag(text: roleTitle, color: roleColor)
                if let file, !file.protection.isEmpty {
                    Tag(text: file.protection.map(\.title).sorted().joined(separator: " · "), color: DiskTheme.teal)
                }
                Spacer(minLength: 4)
            }

            if let file {
                HStack(spacing: 8) {
                    ModuleIconBadge(
                        symbol: categorySymbol(for: groupCategory),
                        primary: roleColor,
                        secondary: roleColor.opacity(0.75),
                        size: 26
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(file.name)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                        Text(DiskFormat.compactPath(file.path))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(file.path)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("物理占用 \(DiskFormat.bytes(file.allocated)) · 逻辑大小 \(DiskFormat.bytes(file.logical))")
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .monospacedDigit()
                    Text("修改时间 \(formattedDateTime(file.modifiedAt))")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Text("访问时间 \(formattedDateTime(file.accessedAt))")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                HStack(spacing: 8) {
                    Button {
                        model.selectedPath = file.path
                        model.quickLook(file.path)
                    } label: {
                        Label("快速预览 (⌘Y)", systemImage: "eye")
                    }
                    .buttonStyle(DiskButtonStyle(kind: .secondary))
                    .controlSize(.small)
                    .help("使用系统 Quick Look 只读预览 \(file.name) (⌘Y)")

                    Button {
                        model.selectedPath = file.path
                        model.reveal(file.path)
                    } label: {
                        Label("在 Finder 中显示", systemImage: "arrow.up.forward.app")
                    }
                    .buttonStyle(DiskButtonStyle(kind: .quiet))
                    .controlSize(.small)
                }
            } else {
                Text("当前分组缺少时间戳元数据，请在下方清单核对副本。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DiskTheme.surface.opacity(0.85), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(DiskTheme.line, lineWidth: 1)
        )
    }
}

struct FileTypesPage: View {
    @ObservedObject var model: AppModel
    var types: [FileTypeUsage] { model.result?.analysis?.fileTypes ?? [] }
    var ageBuckets: [AgeBucketUsage] { (model.result?.analysis?.ageBuckets ?? []).filter { $0.files > 0 } }
    var total: Int64 { max(1, types.reduce(0) { $0 + $1.allocated }) }

    var body: some View {
        let positiveTypes = types.filter { $0.allocated > 0 }
        VStack(alignment: .leading, spacing: 16) {
            Surface {
                VStack(alignment: .leading, spacing: 18) {
                    PanelTitle(title: "文件类型占用", caption: "按已分配大小")
                    Text("按扩展名归类，不读取文件内容。统计扫描到的唯一文件，含目录列表未保留的深层文件；目录自身元数据不计入以下占比。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineSpacing(4)
                    if !positiveTypes.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            GeometryReader { geo in
                                let available = max(0, geo.size.width - CGFloat(max(0, positiveTypes.count - 1)) * 2)
                                HStack(spacing: 2) {
                                    ForEach(Array(positiveTypes.enumerated()), id: \.element.id) { index, usage in
                                        let frac = Double(usage.allocated) / Double(total)
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(DiskTheme.colors[index % DiskTheme.colors.count])
                                            .frame(width: max(3, available * CGFloat(frac)))
                                            .help("\(usage.category.title) · \(DiskFormat.bytes(usage.allocated)) (\(String(format: "%.1f%%", frac * 100)))")
                                    }
                                }
                            }
                            .frame(height: 12)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .accessibilityIdentifier("filetypes-distribution-bar")

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(Array(positiveTypes.enumerated()), id: \.element.id) { index, usage in
                                        HStack(spacing: 4) {
                                            Circle().fill(DiskTheme.colors[index % DiskTheme.colors.count]).frame(width: 6, height: 6)
                                            Text("\(usage.category.title) \(String(format: "%.0f%%", Double(usage.allocated) / Double(total) * 100))")
                                                .font(.system(size: 10))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    if types.isEmpty {
                        Text("开始一次新扫描，获取文件类型统计。")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 28)
                    }
                    ForEach(Array(types.enumerated()), id: \.element.id) { index, usage in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Circle().fill(DiskTheme.colors[index % DiskTheme.colors.count]).frame(width: 8, height: 8)
                                Text(usage.category.title).font(.system(size: 13, weight: .semibold))
                                Text("\(usage.files.formatted()) 个文件").font(.system(size: 10)).foregroundStyle(.secondary)
                                Spacer()
                                Text(DiskFormat.bytes(usage.allocated)).font(.system(size: 14, weight: .bold, design: .rounded))
                                Text(String(format: "%.1f%%", Double(usage.allocated) / Double(total) * 100))
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 48, alignment: .trailing)
                            }
                            GeometryReader { g in
                                Capsule().fill(DiskTheme.colors[index % DiskTheme.colors.count].opacity(0.12))
                                    .overlay(alignment: .leading) {
                                        Capsule()
                                            .fill(DiskTheme.colors[index % DiskTheme.colors.count])
                                            .frame(width: max(2, g.size.width * CGFloat(usage.allocated) / CGFloat(total)))
                                    }
                            }.frame(height: 5)
                            if !usage.extensions.isEmpty {
                                HStack(spacing: 6) {
                                    ForEach(usage.extensions.prefix(6)) { ext in
                                        Button {
                                            model.clutterTab = .largeAndOld
                                            model.showDuplicateSuspects = false
                                            model.largeCategory = usage.category
                                            model.largeQuery = ext.ext == "(无扩展名)" ? "" : "." + ext.ext
                                            model.page = "large"
                                        } label: {
                                            Text("\(ext.ext == "(无扩展名)" ? ext.ext : "." + ext.ext) \(DiskFormat.bytes(ext.allocated))")
                                                .font(.system(size: 10))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(DiskTheme.inset, in: Capsule())
                                        }.buttonStyle(DiskButtonStyle(kind: .quiet))
                                    }
                                }
                            }
                            HStack {
                                Text("逻辑大小 " + DiskFormat.bytes(usage.logical)).font(.system(size: 10)).foregroundStyle(.secondary)
                                Spacer()
                                Button("查看此类大文件") {
                                    model.clutterTab = .largeAndOld
                                    model.showDuplicateSuspects = false
                                    model.largeCategory = usage.category
                                    model.page = "large"
                                }
                                .buttonStyle(DiskButtonStyle(kind: .quiet))
                                .font(.system(size: 11))
                                .foregroundStyle(DiskTheme.accent)
                                .accessibilityLabel("查看大文件 " + usage.category.title)
                            }
                        }.padding(.vertical, 9)
                    }
                    if let r = model.result, !r.complete {
                        Text("扫描不完整，统计仅包含已读取的文件。").font(.system(size: 11)).foregroundStyle(.orange)
                    }
                }
            }
            if !ageBuckets.isEmpty {
                Surface {
                    VStack(alignment: .leading, spacing: 14) {
                        PanelTitle(title: "文件活跃度与陈旧分布", caption: "按最后修改时间统计")
                        HStack(spacing: 12) {
                            ForEach(ageBuckets) { item in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(item.bucket.title).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                                    Text(DiskFormat.bytes(item.allocated)).font(.system(size: 15, weight: .bold, design: .rounded)).monospacedDigit()
                                    Text("\(item.files.formatted()) 个文件 · \(String(format: "%.1f%%", Double(item.allocated) / Double(total) * 100))")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.tertiary)
                                    Button("筛选大文件 →") {
                                        model.clutterTab = .largeAndOld
                                        model.showDuplicateSuspects = false
                                        model.largeCategory = nil
                                        model.largeStaleDays = item.bucket.staleDaysFilter
                                        model.page = "large"
                                    }
                                    .buttonStyle(DiskButtonStyle(kind: .quiet))
                                    .font(.system(size: 10))
                                    .foregroundStyle(DiskTheme.accent)
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(DiskTheme.inset, in: RoundedRectangle(cornerRadius: DiskTheme.controlRadius))
                            }
                        }
                    }
                }
            }
        }
    }
}

struct ProjectsPage: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Surface {
                VStack(alignment: .leading, spacing: 12) {
                    PanelTitle(title: "开发工程工作区洞察", caption: "\(model.projects.count) 个工程 · 按工程汇总构建缓存与陈旧度")
                    HStack(spacing: 10) {
                        DiskSearchField(placeholder: "搜索工程名称或路径", text: $model.projectQuery, identifier: "project-search")
                        Picker("排序", selection: $model.projectSort) {
                            ForEach(ProjectSort.allCases) { item in Text(item.title).tag(item) }
                        }.pickerStyle(.segmented).labelsHidden().frame(width: 264).accessibilityIdentifier("project-sort")
                    }.font(.system(size: 11))
                    Text("自动识别包含 Git 或语言工程清单的项目根目录，汇总其总占用与可识别构建缓存占用。勾选缓存后仍需在系统清理页确认才移入废纸篓。")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            Surface {
                VStack(alignment: .leading, spacing: 10) {
                    if model.result == nil {
                        Text(model.scanning ? "正在扫描识别工程目录…" : "开始一次扫描，识别工作区内的开发工程。")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 28)
                    } else if model.projects.isEmpty {
                        Text("当前扫描范围内未发现符合筛选条件的开发工程。")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 28)
                    }
                    ForEach(model.projects) { project in
                        DiskInteractiveRow(horizontalPadding: 8, verticalPadding: 10) {
                            HStack(alignment: .top, spacing: 12) {
                                ModuleIconBadge(
                                    symbol: "hammer.fill",
                                    primary: DiskTheme.teal,
                                    secondary: DiskTheme.accent,
                                    size: 32
                                )
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack(spacing: 6) {
                                        Text(project.name).font(.system(size: 13, weight: .semibold))
                                        Tag(text: project.markers.prefix(2).joined(separator: " · "), color: DiskTheme.teal)
                                        if let ts = project.modifiedAt, ts <= Int64(Date().timeIntervalSince1970) - 90 * 86_400 {
                                            Tag(text: "久未活跃", color: .orange)
                                        }
                                    }
                                    Text(DiskFormat.compactPath(project.path))
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .help(project.path)
                                    if project.allocated > 0 {
                                        GeometryReader { g in
                                            let cacheFrac = max(0, min(1, project.cacheRatio))
                                            let nonCacheFrac = max(0, 1 - cacheFrac)
                                            let hasBoth = project.nonCacheAllocated > 0 && project.cacheAllocated > 0
                                            let available = max(0, g.size.width - (hasBoth ? 2 : 0))
                                            HStack(spacing: hasBoth ? 2 : 0) {
                                                if project.nonCacheAllocated > 0 {
                                                    Capsule()
                                                        .fill(DiskTheme.accent.opacity(0.72))
                                                        .frame(width: max(2, available * CGFloat(nonCacheFrac)))
                                                }
                                                if project.cacheAllocated > 0 {
                                                    Capsule()
                                                        .fill(DiskTheme.purple)
                                                        .frame(width: max(3, available * CGFloat(cacheFrac)))
                                                }
                                            }
                                        }
                                        .frame(height: 4)
                                        .padding(.vertical, 2)
                                    }
                                    HStack(spacing: 12) {
                                        Text("\(project.fileCount.formatted()) 文件")
                                        Text("源码与资产 \(DiskFormat.bytes(project.nonCacheAllocated))")
                                        if project.cacheAllocated > 0 {
                                            Text("构建缓存 \(DiskFormat.bytes(project.cacheAllocated)) (\(Int((project.cacheRatio * 100).rounded()))%)")
                                                .foregroundStyle(DiskTheme.purple)
                                        }
                                        if let ts = project.modifiedAt {
                                            Text("最近活跃 \(Date(timeIntervalSince1970: TimeInterval(ts)).formatted(date: .abbreviated, time: .omitted))")
                                        }
                                    }.font(.system(size: 10)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 6) {
                                    Text(DiskFormat.bytes(project.allocated))
                                        .font(.system(size: 14, weight: .bold, design: .rounded))
                                        .monospacedDigit()
                                    HStack(spacing: 8) {
                                        if !project.cachePaths.isEmpty && !model.isExternalVolume {
                                            Button("前往系统清理") { model.selectProjectCaches(project) }
                                                .buttonStyle(DiskButtonStyle(kind: .quiet))
                                                .font(.system(size: 10))
                                                .foregroundStyle(DiskTheme.purple)
                                        }
                                        Button("空间透镜查看") { model.browseProject(project) }
                                            .buttonStyle(DiskButtonStyle(kind: .quiet))
                                            .font(.system(size: 10))
                                            .foregroundStyle(DiskTheme.accent)
                                        Button("在 Finder 中显示") { model.reveal(project.path) }
                                            .buttonStyle(DiskButtonStyle(kind: .quiet))
                                            .font(.system(size: 10))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .onTapGesture { model.browseProject(project) }
                        .contextMenu {
                            Button("空间透镜查看") { model.browseProject(project) }
                            Button("在 Finder 中显示") { model.reveal(project.path) }
                            Button("复制路径") { model.copyPath(project.path) }
                        }
                        if project.id != model.projects.last?.id { Divider().opacity(0.6) }
                    }
                }
            }
        }
    }
}

struct ScanIssuesView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        DiskDialog(title: "未读取的路径", subtitle: "保留前 50 条路径 · 当前统计可能不完整", symbol: "folder.badge.questionmark") {
            Text("这些位置未计入完整占用。可能受 macOS 隐私权限、文件夹权限或扫描期间的目录变化影响。")
                .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(model.result?.issues ?? [], id: \.self) { path in
                        Label(path, systemImage: "folder").font(.system(size: 11)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.padding(12)
            }.frame(height: 220).background(DiskTheme.inset, in: RoundedRectangle(cornerRadius: DiskTheme.controlRadius))
            Text("开启权限后需重新扫描。扫描不会读取文件内容。").font(.system(size: 11)).foregroundStyle(.secondary)
        } actions: {
            Button("打开完整磁盘访问设置") { model.permissions() }
            Spacer()
            Button("完成") { model.showIssues = false }.buttonStyle(DiskButtonStyle(kind: .primary)).keyboardShortcut(.defaultAction)
        }
    }
}

struct APFSSnapshotsSheet: View {
    @ObservedObject var model: AppModel
    var body: some View {
        let report = model.apfsSnapshots
        let count = report?.snapshots.count ?? 0
        DiskDialog(
            title: "APFS 本地快照（只读）",
            subtitle: report.map { "卷 \($0.volumePath) · \(count) 个快照" } ?? "正在读取快照清单…",
            symbol: "camera.aperture"
        ) {
            Text("AetherDisk 仅只读展示快照清单，绝不删除或干预系统时间机器快照。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineSpacing(4)
            if let report {
                Text(report.note)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(count > 0 ? .orange : .secondary)
                if report.snapshots.isEmpty {
                    Text("未检测到可列出的 APFS 本地快照，或当前卷未启用本地时间机器快照。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(DiskTheme.inset, in: RoundedRectangle(cornerRadius: DiskTheme.controlRadius))
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(report.snapshots) { snap in
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "clock.arrow.circlepath")
                                        .foregroundStyle(.orange)
                                        .padding(.top, 2)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(snap.dateLabel).font(.system(size: 12, weight: .medium))
                                        Text(snap.name).font(.system(size: 10)).foregroundStyle(.secondary).textSelection(.enabled)
                                    }
                                    Spacer(minLength: 0)
                                }
                                if snap.id != report.snapshots.last?.id {
                                    Divider().opacity(0.6)
                                }
                            }
                        }
                        .padding(12)
                    }
                    .frame(height: 220)
                    .background(DiskTheme.inset, in: RoundedRectangle(cornerRadius: DiskTheme.controlRadius))
                }
            } else {
                ProgressView("正在只读检测 APFS 本地快照…")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
            Text("系统可在存储空间紧张时自动按需回收弹性可回收空间。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        } actions: {
            Button("刷新") { model.refreshSystemTelemetry() }
            Spacer()
            Button("完成") { model.showSnapshotsSheet = false }
                .buttonStyle(DiskButtonStyle(kind: .primary))
                .keyboardShortcut(.defaultAction)
        }
        .accessibilityIdentifier("apfs-snapshots-sheet")
    }
}
