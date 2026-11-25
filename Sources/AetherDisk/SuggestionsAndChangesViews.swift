import SwiftUI
import AetherDiskCore

struct SuggestionsPage: View {
    @ObservedObject var model: AppModel
    @State private var collapsedGroupIDs: Set<String> = []

    private var palette: ModuleStagePalette {
        ModuleStagePalette.forPage("suggestions")
    }

    private var selectedAllocatedBytes: Int64 {
        model.recommendations
            .filter { model.selectedCaches.contains($0.id) }
            .reduce(0) { $0 + $1.node.allocated }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            cleanupSubTabSwitcher

            if model.cleanupSubTab == .cloudStorage {
                CloudStorageView(model: model)
            } else {
                systemJunkContent
            }
        }
    }

    private var cleanupSubTabSwitcher: some View {
        Surface(padding: 10) {
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.primary)
                    Text("审阅模式")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 4)
                .accessibilityIdentifier("cleanup-subtabs")

                HStack(spacing: 6) {
                    ForEach(CleanupSubTab.allCases) { tab in
                        let selected = model.cleanupSubTab == tab
                        let icon = tab == .systemJunk ? "sparkles" : "icloud.fill"
                        Button {
                            model.cleanupSubTab = tab
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: icon)
                                    .font(.system(size: 11, weight: .semibold))
                                Text(tab.title)
                                    .font(.system(size: 11.5, weight: selected ? .semibold : .medium))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .foregroundStyle(selected ? .white : .primary)
                            .background(
                                selected
                                    ? AnyShapeStyle(LinearGradient(colors: [palette.primary, palette.secondary], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    : AnyShapeStyle(DiskTheme.inset),
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(selected ? .white.opacity(0.22) : DiskTheme.line, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("cleanup-tab-" + tab.rawValue)
                    }
                }

                Spacer()

                if model.cleanupSubTab == .cloudStorage {
                    Tag(text: "纯只读透视 · 绝不下载或删除", color: DiskTheme.teal)
                } else {
                    Text("默认不勾选 · 移入废纸篓需二次确认")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    @ViewBuilder
    private var systemJunkContent: some View {
        HStack(spacing: 12) {
            SuggestionMetricCard(
                title: "可进一步检查",
                value: DiskFormat.bytes(model.eligibleBytes),
                caption: "\(model.eligible.count) 个可检目录",
                icon: "sparkles",
                tint: palette.primary
            )
            SuggestionMetricCard(
                title: "当前已勾选",
                value: model.selectedCaches.isEmpty ? "0 B" : DiskFormat.bytes(selectedAllocatedBytes),
                caption: "\(model.selectedCaches.count) 项待预览确认",
                icon: "checkmark.circle.fill",
                tint: palette.secondary
            )
            SuggestionMetricCard(
                title: "已保护项目",
                value: "\(model.recommendations.filter(\.blocked).count) 项",
                caption: "源码、安装包或个人数据",
                icon: "lock.shield.fill",
                tint: DiskTheme.teal
            )
        }

        HStack(spacing: 9) {
            Image(systemName: "checkmark.shield.fill").foregroundStyle(DiskTheme.teal)
            Text("先检查，后确认。清理只移入系统废纸篓，绝不直接永久删除，也绝不清空废纸篓。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            if !model.eligible.isEmpty {
                Button("勾选当前可见可检项") { model.selectAllVisibleEligibleCaches() }
                    .buttonStyle(DiskButtonStyle(kind: .quiet))
                    .font(.system(size: 11, weight: .medium))
                    .disabled(!model.fresh || model.scanning || model.checking)
                if !model.selectedCaches.isEmpty {
                    Button("清空勾选") { model.clearCacheSelection() }
                        .buttonStyle(DiskButtonStyle(kind: .quiet))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }

        if model.result == nil && !model.scanning {
            ModuleHeroStage(
                palette: palette,
                targetPath: DiskFormat.compactPath(model.root.path),
                features: [
                    ("safari.fill", "网页与应用缓存"),
                    ("doc.text.below.ecg.fill", "应用历史日志与窗口状态"),
                    ("hammer.fill", "Xcode 与工程构建缓存"),
                    ("lock.shield.fill", "Git 与源码自动防误删")
                ],
                onChooseFolder: { model.chooseFolder() },
                onQuickScanHome: { model.start(FileManager.default.homeDirectoryForCurrentUser) }
            )
        } else {
            // CleanMyMac Two-Pane Master-Detail Junk Reviewer
            HStack(alignment: .top, spacing: 14) {
                categoryMasterPane
                    .frame(width: 216)
                detailListPane
                    .frame(maxWidth: .infinity)
            }
        }

        // Action & Confirmation Trigger Bar
        Surface(padding: 14) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("已选择 \(model.selectedCaches.count) 项 · 目录占用 \(DiskFormat.bytes(selectedAllocatedBytes))")
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text("检查会重新校验 inode 指纹、进程占用与 Git 状态；移入废纸篓不代表立即释放可用空间。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if model.checking { ProgressView().controlSize(.small) }
                Button {
                    model.preview()
                } label: {
                    Label("检查并预览", systemImage: "checkmark.shield.fill")
                }
                .buttonStyle(DiskButtonStyle(kind: .primary))
                .disabled(model.selectedCaches.isEmpty || !model.fresh || model.checking || model.scanning)
                .accessibilityIdentifier("preview-cleanup")
            }
        }

        if !model.auditEntries.isEmpty {
            Surface {
                VStack(alignment: .leading, spacing: 10) {
                    PanelTitle(title: "最近移入废纸篓记录", caption: "本机审计账本 · 共 \(model.auditEntries.count) 次操作")
                    ForEach(model.auditEntries.prefix(5)) { entry in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(entry.movedPaths.map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: "、"))
                                    .font(.system(size: 11, weight: .medium))
                                    .lineLimit(1)
                                Text("\(entry.timestamp.formatted(date: .abbreviated, time: .shortened)) · \(entry.movedPaths.count) 项")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(DiskFormat.bytes(entry.planAllocated))
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    private var categoryMasterPane: some View {
        let totalAllocated = model.recommendations.reduce(Int64(0)) { $0 + $1.node.allocated }
        return Surface(padding: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("清理分类")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.bottom, 2)

                Button {
                    model.suggestionCategory = nil
                } label: {
                    HStack(spacing: 8) {
                        ModuleIconBadge(
                            symbol: "sparkles",
                            primary: palette.primary,
                            secondary: palette.secondary,
                            size: 24
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            Text("全部建议项")
                                .font(.system(size: 11.5, weight: model.suggestionCategory == nil ? .semibold : .regular))
                            Text("\(model.recommendations.count) 项")
                                .font(.system(size: 9.5))
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 4)
                        Text(DiskFormat.bytes(totalAllocated))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        model.suggestionCategory == nil ? palette.primary.opacity(0.12) : .clear,
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )
                }
                .buttonStyle(.plain)

                if !model.recommendationCategoryTotals.isEmpty {
                    Divider().opacity(0.55)
                }

                ForEach(model.recommendationCategoryTotals, id: \.category) { item in
                    let isSelected = model.suggestionCategory == item.category
                    Button {
                        model.suggestionCategory = isSelected ? nil : item.category
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: item.category.symbol)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(isSelected ? palette.primary : .secondary)
                                .frame(width: 24, height: 24)
                                .background(
                                    (isSelected ? palette.primary : Color.primary).opacity(0.08),
                                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                                )
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.category.title)
                                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                                    .lineLimit(1)
                                Text("\(item.count) 项")
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 4)
                            Text(DiskFormat.bytes(item.allocated))
                                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(isSelected ? palette.primary : .primary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            isSelected ? palette.primary.opacity(0.12) : .clear,
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .accessibilityIdentifier("cleanup-category-sidebar")
    }

    private var detailListPane: some View {
        Surface {
            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.suggestionCategory?.title ?? "建议清单明细")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                        Text(
                            model.suggestionGroupByApp
                                ? "按应用/工具链分组 · 共 \(model.groupedVisibleRecommendations.count) 组 · \(model.filteredRecommendations.count) 项"
                                : "默认不勾选 · 共 \(model.filteredRecommendations.count) 项"
                        )
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        model.suggestionGroupByApp.toggle()
                    } label: {
                        Label("按应用分组", systemImage: model.suggestionGroupByApp ? "rectangle.3.group.fill" : "rectangle.3.group")
                    }
                    .buttonStyle(DiskButtonStyle(kind: model.suggestionGroupByApp ? .primary : .secondary))
                    .controlSize(.small)
                    .accessibilityIdentifier("cleanup-group-toggle")
                    .accessibilityValue(model.suggestionGroupByApp ? "已开启" : "未开启")
                }
                .padding(.bottom, 12)

                if !model.recommendations.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            DiskSearchField(
                                placeholder: "搜索缓存名称或路径",
                                text: $model.suggestionQuery,
                                identifier: "suggestion-search"
                            )
                            Picker("状态", selection: $model.suggestionFilter) {
                                ForEach(SuggestionFilter.allCases) { item in Text(item.title).tag(item) }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: 164)
                            .accessibilityIdentifier("suggestion-filter")

                            Picker("类别", selection: $model.suggestionCategory) {
                                Text("全部类别").tag(nil as CacheCategory?)
                                ForEach(CacheCategory.allCases) { item in Text(item.title).tag(Optional(item)) }
                            }
                            .labelsHidden()
                            .frame(width: 136)
                            .accessibilityIdentifier("suggestion-category")
                        }

                        HStack(spacing: 10) {
                            Toggle("仅看 90 天未改", isOn: $model.suggestionStaleOnly)
                                .toggleStyle(.checkbox)
                                .font(.system(size: 11))
                                .accessibilityIdentifier("suggestion-stale-only")

                            if !model.staleEligibleCacheIDs.isEmpty {
                                Button("勾选 90 天未改可检项") { model.selectStaleEligibleCaches() }
                                    .buttonStyle(DiskButtonStyle(kind: .quiet))
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(palette.primary)
                                    .disabled(!model.fresh || model.scanning || model.checking)
                                    .accessibilityIdentifier("select-stale-caches")
                            }
                            Spacer()
                        }
                    }
                    .font(.system(size: 11))
                    .padding(.bottom, 10)
                }

                if model.recommendations.isEmpty {
                    Text(model.scanning ? "正在扫描识别可清理缓存目录…" : "此次扫描未发现符合规则的缓存或日志目录。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 44)
                } else if model.filteredRecommendations.isEmpty {
                    Text("没有符合当前筛选条件的缓存目录。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                } else if model.suggestionGroupByApp {
                    VStack(spacing: 10) {
                        ForEach(model.groupedVisibleRecommendations) { group in
                            recommendationGroupCard(group)
                        }
                    }
                } else {
                    ForEach(model.filteredRecommendations) { r in
                        recommendationRow(r)
                        if r.id != model.filteredRecommendations.last?.id {
                            Divider().opacity(0.6)
                        }
                    }
                }
            }
        }
    }

    private func recommendationGroupCard(_ group: RecommendationAppGroup) -> some View {
        DisclosureGroup(
            isExpanded: Binding(
                get: { !collapsedGroupIDs.contains(group.id) },
                set: { expanded in
                    if expanded {
                        collapsedGroupIDs.remove(group.id)
                    } else {
                        collapsedGroupIDs.insert(group.id)
                    }
                }
            )
        ) {
            VStack(spacing: 0) {
                ForEach(group.items) { r in
                    recommendationRow(r)
                    if r.id != group.items.last?.id {
                        Divider().opacity(0.6)
                    }
                }
            }
            .padding(.top, 6)
        } label: {
            HStack(spacing: 10) {
                ModuleIconBadge(
                    symbol: group.symbol,
                    primary: palette.primary,
                    secondary: palette.secondary,
                    size: 26
                )
                Text(group.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text("\(group.items.count) 项")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                if group.eligibleCount > 0 {
                    Tag(text: "\(group.eligibleCount) 可检", color: palette.primary)
                }
                if group.blockedCount > 0 {
                    Tag(text: "\(group.blockedCount) 已保护", color: DiskTheme.teal)
                }
                Spacer(minLength: 8)
                Text(DiskFormat.bytes(group.allocated))
                    .font(.system(size: 13.5, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
            .padding(.vertical, 4)
        }
        .padding(10)
        .background(DiskTheme.inset, in: RoundedRectangle(cornerRadius: DiskTheme.controlRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DiskTheme.controlRadius, style: .continuous)
                .stroke(DiskTheme.line, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func recommendationRow(_ r: Recommendation) -> some View {
        DiskInteractiveRow(
            selected: model.selectedCaches.contains(r.id),
            horizontalPadding: 8,
            verticalPadding: 11
        ) {
            HStack(alignment: .top, spacing: 12) {
                Toggle(
                    "选择 \(r.node.name)",
                    isOn: Binding(
                        get: { model.selectedCaches.contains(r.id) },
                        set: {
                            if $0 { model.selectedCaches.insert(r.id) }
                            else { model.selectedCaches.remove(r.id) }
                        }
                    )
                )
                .labelsHidden()
                .toggleStyle(.checkbox)
                .disabled(r.blocked || !model.fresh || model.scanning || model.checking)
                .padding(.top, 4)

                Image(systemName: r.blocked ? "lock.shield.fill" : r.category.symbol)
                    .font(.system(size: 17))
                    .foregroundStyle(r.blocked ? DiskTheme.teal : palette.primary)
                    .frame(width: 30, height: 30)
                    .background(
                        (r.blocked ? DiskTheme.teal : palette.primary).opacity(0.10),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(r.node.name).font(.system(size: 13, weight: .semibold))
                        Tag(text: r.category.title, color: .secondary)
                        Tag(text: r.blocked ? "已保护" : "需要确认", color: r.blocked ? DiskTheme.teal : DiskTheme.accent)
                        if r.isStale(days: 90) { Tag(text: "90 天未改", color: .orange) }
                    }
                    Text(DiskFormat.compactPath(r.id))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(r.id)
                    Text(r.blocked ? r.node.protection.map(\.title).sorted().joined(separator: " · ") : r.reason)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 8) {
                    Text(DiskFormat.bytes(r.node.allocated))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Button("查看位置") { model.reveal(r.id) }
                        .buttonStyle(DiskButtonStyle(kind: .quiet))
                        .font(.system(size: 10))
                        .foregroundStyle(DiskTheme.accent)
                }
            }
        }
        .onTapGesture {
            guard !r.blocked && model.fresh && !model.scanning && !model.checking else { return }
            if model.selectedCaches.contains(r.id) { model.selectedCaches.remove(r.id) }
            else { model.selectedCaches.insert(r.id) }
        }
        .contextMenu {
            Button("在 Finder 中显示") { model.reveal(r.id) }
            Button("复制路径") { model.copyPath(r.id) }
        }
    }
}

struct ChangesPage: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    PanelTitle(
                        title: "与上次扫描对比",
                        caption: model.previous.map { "基线 \($0.scannedAt.formatted(date: .abbreviated, time: .shortened)) · 共 \(model.history.count) 份快照" } ?? "相同目录 · 已分配大小"
                    )
                    if model.previous != nil && model.previous?.root == model.result?.root {
                        Picker("对比层级", selection: $model.comparisonDepth) {
                            ForEach(ComparisonDepth.allCases) { item in Text(item.title).tag(item) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 168)
                        .accessibilityIdentifier("comparison-depth")
                    }
                }

                if (model.previous?.unreadable ?? 0) > 0 || (model.result?.unreadable ?? 0) > 0 {
                    Text("扫描存在权限遗漏；差异可能受到统计范围影响。")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }

                if model.previous == nil || model.previous?.root != model.result?.root {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(DiskTheme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 36)
                    Text("再扫描一次，就能看见变化")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                    Text("本次结果只保存在本机。下次扫描同一目录时，比较各项目的占用变化。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 40)
                } else {
                    HStack(spacing: 10) {
                        DiskSearchField(
                            placeholder: "搜索变化目录或路径",
                            text: $model.comparisonQuery,
                            identifier: "comparison-search"
                        )
                        Picker("方向", selection: $model.comparisonDirection) {
                            ForEach(ChangeDirection.allCases) { item in Text(item.title).tag(item) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 168)
                        .accessibilityIdentifier("comparison-direction")

                        if model.baselineOptions.count > 1 {
                            Picker(
                                "基线",
                                selection: Binding(
                                    get: { model.previous?.scannedAt ?? Date.distantPast },
                                    set: { target in
                                        if let match = model.baselineOptions.first(where: { abs($0.scannedAt.timeIntervalSince(target)) < 0.001 }) {
                                            model.previous = match
                                        }
                                    }
                                )
                            ) {
                                ForEach(model.baselineOptions, id: \.scannedAt) { snap in
                                    Text(snap.scannedAt.formatted(date: .abbreviated, time: .shortened)).tag(snap.scannedAt)
                                }
                            }
                            .frame(width: 160)
                            .accessibilityIdentifier("comparison-baseline")
                        }
                    }
                    .font(.system(size: 11))

                    if let summary = model.comparisonSummary {
                        HStack(spacing: 14) {
                            Text("总变化 \((summary.allocatedDelta >= 0 ? "+" : "−") + DiskFormat.bytes(summary.allocatedDelta))")
                                .fontWeight(.semibold)
                            Text("增长 \(summary.grownCount) 项 · 减少 \(summary.shrunkCount) 项")
                            Text("文件数 \((summary.filesDelta >= 0 ? "+" : "") + summary.filesDelta.formatted())")
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    }

                    if model.trendPoints.count >= 2 {
                        SnapshotTrendChart(
                            points: model.trendPoints,
                            selectedBaselineDate: model.previous?.scannedAt,
                            currentDate: model.result?.scannedAt
                        ) { tappedDate in
                            if let match = model.baselineOptions.first(where: { abs($0.scannedAt.timeIntervalSince(tappedDate)) < 0.001 }) {
                                model.previous = match
                            }
                        }
                    }

                    if !model.growthHotspots.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                Text("持续增长热点：")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.orange)
                                ForEach(model.growthHotspots.prefix(5)) { spot in
                                    Button {
                                        model.navigateToOverview(path: spot.path)
                                    } label: {
                                        Tag(text: "\(spot.name) +\(DiskFormat.bytes(spot.totalGrowth))（连涨 \(spot.consecutiveGrows) 次）", color: .orange)
                                    }
                                    .buttonStyle(DiskButtonStyle(kind: .quiet))
                                    .help("点击在空间透镜中查看 \(spot.path)")
                                }
                            }
                        }
                        .accessibilityIdentifier("growth-hotspots")
                    }

                    if model.changes.isEmpty {
                        Text("没有符合当前筛选条件的变化目录。")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 28)
                    }

                    ForEach(model.changes, id: \.0.id) { node, delta in
                        DiskInteractiveRow(horizontalPadding: 8, verticalPadding: 8) {
                            HStack {
                                Image(systemName: node.kind == .directory ? "folder.fill" : "doc.fill")
                                    .foregroundStyle(DiskTheme.accent)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(node.name).font(.system(size: 12, weight: .medium))
                                    if model.comparisonDepth == .deep {
                                        Text(DiskFormat.compactPath(node.path))
                                            .font(.system(size: 10))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                            .help(node.path)
                                    }
                                }
                                Spacer()
                                Text((delta > 0 ? "+" : delta < 0 ? "−" : "") + DiskFormat.bytes(delta))
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(delta > 0 ? Color.orange : delta < 0 ? DiskTheme.teal : .secondary)
                                Button("空间透镜查看") { model.navigateToOverview(path: node.path) }
                                    .buttonStyle(DiskButtonStyle(kind: .quiet))
                                    .font(.system(size: 10))
                                    .foregroundStyle(DiskTheme.accent)
                                Button("在 Finder 中显示") { model.reveal(node.path) }
                                    .buttonStyle(DiskButtonStyle(kind: .quiet))
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .onTapGesture { model.navigateToOverview(path: node.path) }
                        .contextMenu {
                            Button("空间透镜查看") { model.navigateToOverview(path: node.path) }
                            Button("在 Finder 中显示") { model.reveal(node.path) }
                            Button("复制路径") { model.copyPath(node.path) }
                        }
                        Divider()
                    }
                }
            }
        }
    }
}

private struct SnapshotTrendChart: View {
    let points: [TrendPoint]
    let selectedBaselineDate: Date?
    let currentDate: Date?
    let onSelectBaseline: (Date) -> Void

    private var maxAllocated: Int64 {
        max(1, points.map(\.allocated).max() ?? 1)
    }

    private var minAllocated: Int64 {
        points.map(\.allocated).min() ?? 0
    }

    private func isSameMoment(_ a: Date?, _ b: Date) -> Bool {
        guard let a else { return false }
        return abs(a.timeIntervalSince(b)) < 0.001
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("多快照占用走势", systemImage: "chart.bar.xaxis")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Text("共 \(points.count) 次快照 · 区间 \(DiskFormat.bytes(minAllocated)) – \(DiskFormat.bytes(maxAllocated))")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            HStack(alignment: .bottom, spacing: 10) {
                ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                    let isCurrent = isSameMoment(currentDate, point.scannedAt) || (currentDate == nil && index == points.count - 1)
                    let isBaseline = !isCurrent && isSameMoment(selectedBaselineDate, point.scannedAt)
                    let ratio = max(0.0, min(1.0, Double(point.allocated) / Double(maxAllocated)))
                    let barHeight = max(10.0, 68.0 * CGFloat(ratio))

                    Button {
                        if !isCurrent {
                            onSelectBaseline(point.scannedAt)
                        }
                    } label: {
                        VStack(spacing: 5) {
                            Text(DiskFormat.bytes(point.allocated))
                                .font(.system(size: 9.5, weight: isCurrent || isBaseline ? .semibold : .medium, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(isCurrent ? DiskTheme.accent : isBaseline ? DiskTheme.purple : .secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)

                            ZStack(alignment: .bottom) {
                                Capsule()
                                    .fill(DiskTheme.line)
                                    .frame(width: 20, height: 68)
                                Capsule()
                                    .fill(
                                        isCurrent
                                            ? AnyShapeStyle(LinearGradient(colors: [DiskTheme.accent, DiskTheme.purple], startPoint: .bottom, endPoint: .top))
                                            : isBaseline
                                                ? AnyShapeStyle(DiskTheme.purple.opacity(0.75))
                                                : AnyShapeStyle(DiskTheme.accent.opacity(0.36))
                                    )
                                    .frame(width: 20, height: barHeight)
                                    .overlay(
                                        Capsule()
                                            .stroke(isBaseline ? DiskTheme.purple : .clear, lineWidth: 1.5)
                                    )
                            }

                            VStack(spacing: 1) {
                                Text(point.scannedAt.formatted(.dateTime.month(.twoDigits).day(.twoDigits).hour().minute()))
                                    .font(.system(size: 9))
                                    .foregroundStyle(isCurrent || isBaseline ? .primary : .secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                                if isCurrent {
                                    Text("当前")
                                        .font(.system(size: 8.5, weight: .semibold))
                                        .foregroundStyle(DiskTheme.accent)
                                } else if isBaseline {
                                    Text("基线")
                                        .font(.system(size: 8.5, weight: .semibold))
                                        .foregroundStyle(DiskTheme.purple)
                                } else {
                                    Text("\(point.files.formatted()) 文件")
                                        .font(.system(size: 8.5))
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(DiskButtonStyle(kind: .quiet))
                    .disabled(isCurrent)
                    .help("\(point.scannedAt.formatted(date: .abbreviated, time: .shortened)) · \(DiskFormat.bytes(point.allocated)) · \(point.files.formatted()) 个文件")
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(12)
        .background(DiskTheme.inset, in: RoundedRectangle(cornerRadius: DiskTheme.controlRadius))
        .overlay(RoundedRectangle(cornerRadius: DiskTheme.controlRadius).stroke(DiskTheme.line, lineWidth: 1))
        .accessibilityIdentifier("snapshot-trend-chart")
    }
}

struct SuggestionMetricCard: View {
    let title: String
    let value: String
    let caption: String
    let icon: String
    let tint: Color

    var body: some View {
        Surface(padding: 13) {
            HStack(alignment: .top, spacing: 11) {
                ModuleIconBadge(symbol: icon, primary: tint, secondary: tint.opacity(0.75), size: 30)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(value)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text(caption).font(.system(size: 9.5)).foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
