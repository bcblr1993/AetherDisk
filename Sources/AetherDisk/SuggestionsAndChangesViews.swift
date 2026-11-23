import SwiftUI
import AetherDiskCore

struct SuggestionsPage: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                SuggestionMetricCard(
                    title: "可进一步检查",
                    value: DiskFormat.bytes(model.eligibleBytes),
                    caption: "\(model.eligible.count) 个候选目录",
                    icon: "sparkles",
                    tint: DiskTheme.purple
                )
                SuggestionMetricCard(
                    title: "已保护项目",
                    value: "\(model.recommendations.filter(\.blocked).count) 项",
                    caption: "包含源码、安装包或个人数据",
                    icon: "lock.shield",
                    tint: .teal
                )
            }

            HStack(spacing: 9) {
                Image(systemName: "checkmark.shield").foregroundStyle(.teal)
                Text("先检查，后确认。清理只移入废纸篓，不会直接永久删除。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Surface {
                VStack(spacing: 0) {
                    PanelTitle(title: "建议清单", caption: "默认不勾选")
                        .padding(.bottom, 12)

                    if !model.recommendations.isEmpty {
                        if !model.recommendationCategoryTotals.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(model.recommendationCategoryTotals, id: \.category) { item in
                                        Button {
                                            model.suggestionCategory = (model.suggestionCategory == item.category) ? nil : item.category
                                        } label: {
                                            Text("\(item.category.title) \(DiskFormat.bytes(item.allocated)) (\(item.count))")
                                                .font(.system(size: 10, weight: model.suggestionCategory == item.category ? .semibold : .regular))
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 3)
                                                .background(
                                                    model.suggestionCategory == item.category ? DiskTheme.accent.opacity(0.16) : DiskTheme.inset,
                                                    in: Capsule()
                                                )
                                        }
                                        .buttonStyle(DiskButtonStyle(kind: .quiet))
                                    }
                                }
                            }
                            .padding(.bottom, 8)
                        }

                        HStack(spacing: 10) {
                            DiskSearchField(
                                placeholder: "搜索缓存名称或路径",
                                text: $model.suggestionQuery,
                                identifier: "suggestion-search"
                            )
                            Toggle("仅看 90 天未改", isOn: $model.suggestionStaleOnly)
                                .toggleStyle(.checkbox)
                                .font(.system(size: 11))
                                .accessibilityIdentifier("suggestion-stale-only")

                            if !model.staleEligibleCacheIDs.isEmpty {
                                Button("勾选 90 天未改可检项") { model.selectStaleEligibleCaches() }
                                    .buttonStyle(DiskButtonStyle(kind: .quiet))
                                    .font(.system(size: 10))
                                    .foregroundStyle(DiskTheme.purple)
                                    .disabled(!model.fresh || model.scanning || model.checking)
                                    .accessibilityIdentifier("select-stale-caches")
                            }

                            Picker("状态", selection: $model.suggestionFilter) {
                                ForEach(SuggestionFilter.allCases) { item in Text(item.title).tag(item) }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: 168)
                            .accessibilityIdentifier("suggestion-filter")

                            Picker("类别", selection: $model.suggestionCategory) {
                                Text("全部类别").tag(nil as CacheCategory?)
                                ForEach(CacheCategory.allCases) { item in Text(item.title).tag(Optional(item)) }
                            }
                            .frame(width: 150)
                            .accessibilityIdentifier("suggestion-category")
                        }
                        .font(.system(size: 11))
                        .padding(.bottom, 10)
                    }

                    if model.recommendations.isEmpty {
                        Text(model.result == nil ? "先扫描一个文件夹，建议会在这里出现。" : "此次扫描未发现符合规则的缓存目录。")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 48)
                    } else if model.filteredRecommendations.isEmpty {
                        Text("没有符合当前筛选条件的缓存目录。")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 32)
                    }

                    ForEach(model.filteredRecommendations) { r in
                        DiskInteractiveRow(
                            selected: model.selectedCaches.contains(r.id),
                            horizontalPadding: 8,
                            verticalPadding: 12
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

                                Image(systemName: r.blocked ? "lock.shield.fill" : "shippingbox")
                                    .font(.system(size: 18))
                                    .foregroundStyle(r.blocked ? Color.teal : DiskTheme.purple)
                                    .frame(width: 30)
                                    .padding(.top, 3)

                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(r.node.name).font(.system(size: 13, weight: .semibold))
                                        Tag(text: r.blocked ? "已保护" : "需要确认", color: r.blocked ? .teal : DiskTheme.accent)
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

                                VStack(alignment: .trailing, spacing: 9) {
                                    Text(DiskFormat.bytes(r.node.allocated))
                                        .font(.system(size: 14, weight: .semibold, design: .rounded))
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

                        if r.id != model.filteredRecommendations.last?.id {
                            Divider().opacity(0.65)
                        }
                    }
                }
            }

            HStack {
                Text("已选择 \(model.selectedCaches.count) 项")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                if model.checking { ProgressView().controlSize(.small) }
                Button { model.preview() } label: { Label("检查并预览", systemImage: "checkmark.shield") }
                    .buttonStyle(DiskButtonStyle(kind: .primary))
                    .disabled(model.selectedCaches.isEmpty || !model.fresh || model.checking || model.scanning)
                    .accessibilityIdentifier("preview-cleanup")
            }

            Text("检查会重新确认文件占用与目录内容。新发现的源码、Git 跟踪文件、安装包或符号链接会阻止清理。移入废纸篓不代表已释放空间。")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineSpacing(4)

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
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .monospacedDigit()
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
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
                        .font(.system(size: 17, weight: .semibold))
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
                                .fontWeight(.medium)
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
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.orange)
                                ForEach(model.growthHotspots.prefix(5)) { spot in
                                    Button {
                                        model.navigateToOverview(path: spot.path)
                                    } label: {
                                        Tag(text: "\(spot.name) +\(DiskFormat.bytes(spot.totalGrowth))（连涨 \(spot.consecutiveGrows) 次）", color: .orange)
                                    }
                                    .buttonStyle(DiskButtonStyle(kind: .quiet))
                                    .help("点击在概览中查看 \(spot.path)")
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
                                Image(systemName: node.kind == .directory ? "folder" : "doc")
                                    .foregroundStyle(DiskTheme.accent)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(node.name).font(.system(size: 12))
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
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(delta > 0 ? Color.orange : delta < 0 ? .teal : .secondary)
                                Button("概览中查看") { model.navigateToOverview(path: node.path) }
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
                            Button("概览中查看") { model.navigateToOverview(path: node.path) }
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

private struct SuggestionMetricCard: View {
    let title: String
    let value: String
    let caption: String
    let icon: String
    let tint: Color

    var body: some View {
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
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
