import SwiftUI
import AetherDiskCore

struct ApplicationsView: View {
    @ObservedObject var model: AppModel

    private var palette: ModuleStagePalette {
        ModuleStagePalette.forPage("applications")
    }

    var body: some View {
        let report = model.appsReport
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                appMetricCard(
                    title: "已安装应用",
                    value: report.map { "\($0.apps.count) 款" } ?? (model.scanningApps ? "正在读取…" : "0 款"),
                    caption: report.map { "本体合计 \(DiskFormat.bytes($0.totalAppsBundleAllocated))" } ?? "纯元数据只读统计",
                    symbol: "square.stack.3d.up.fill",
                    tint: palette.primary
                )
                appMetricCard(
                    title: "关联缓存与状态",
                    value: report.map { DiskFormat.bytes($0.totalAssociatedAllocated) } ?? "—",
                    caption: "~/Library 缓存 · 日志 · 窗口状态",
                    symbol: "sparkles",
                    tint: DiskTheme.purple
                )
                appMetricCard(
                    title: "疑似卸载残留线索",
                    value: report.map { "\($0.orphanedData.count) 项" } ?? "—",
                    caption: report.map { "共 \(DiskFormat.bytes($0.totalOrphanedAllocated)) · 可定位核对" } ?? "无对应已装应用的缓存",
                    symbol: "archivebox.fill",
                    tint: .orange
                )
            }

            HStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(DiskTheme.teal)
                Text("安全边界：所有 .app 应用本体均受严格保护（绝不卸载或删除应用包）；关联缓存与孤立残留线索仅支持在 Finder 查看或跳转「系统清理」经二次校验移入废纸篓。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    model.refreshApplications()
                } label: {
                    Label(model.scanningApps ? "正在刷新…" : "刷新应用列表", systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
                .disabled(model.scanningApps)
                .accessibilityIdentifier("apps-refresh")
            }

            HStack(alignment: .top, spacing: 14) {
                filterSidebar
                    .frame(width: 194)

                if model.appFilterMode == .orphans {
                    orphansPane
                        .frame(maxWidth: .infinity)
                } else {
                    appsMainPane
                        .frame(maxWidth: .infinity)
                    appDetailInspector
                        .frame(width: 266)
                }
            }
        }
    }

    private func appMetricCard(title: String, value: String, caption: String, symbol: String, tint: Color) -> some View {
        Surface(padding: 13) {
            HStack(alignment: .top, spacing: 11) {
                ModuleIconBadge(symbol: symbol, primary: tint, secondary: tint.opacity(0.75), size: 30)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(value)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                    Text(caption).font(.system(size: 9.5)).foregroundStyle(.tertiary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var filterSidebar: some View {
        let allApps = model.appsReport?.apps ?? []
        let orphansCount = model.appsReport?.orphanedData.count ?? 0
        return Surface(padding: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("应用透视筛选")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.bottom, 2)
                    .accessibilityIdentifier("apps-filter-rail")

                ForEach(AppFilterMode.allCases) { mode in
                    let isSelected = model.appFilterMode == mode
                    let count: Int = {
                        switch mode {
                        case .all: return allApps.count
                        case .large: return allApps.filter { $0.totalFootprint >= 250 * 1024 * 1024 }.count
                        case .unused: return allApps.filter { $0.isStale(days: 90) }.count
                        case .withCaches: return allApps.filter { !$0.associatedItems.isEmpty }.count
                        case .orphans: return orphansCount
                        }
                    }()
                    let icon: String = {
                        switch mode {
                        case .all: return "square.grid.2x2.fill"
                        case .large: return "arrow.up.right.square.fill"
                        case .unused: return "clock.fill"
                        case .withCaches: return "sparkles"
                        case .orphans: return "archivebox.fill"
                        }
                    }()

                    Button {
                        model.appFilterMode = mode
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: icon)
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(isSelected ? palette.primary : .secondary)
                                .frame(width: 22, height: 22)
                                .background(
                                    (isSelected ? palette.primary : Color.primary).opacity(0.08),
                                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                                )
                            Text(mode.title)
                                .font(.system(size: 11.5, weight: isSelected ? .semibold : .regular))
                            Spacer(minLength: 4)
                            Text("\(count)")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(isSelected ? palette.primary : .secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            isSelected ? palette.primary.opacity(0.12) : .clear,
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("app-filter-" + mode.rawValue)
                }
            }
        }
    }

    private var appsMainPane: some View {
        let items = model.filteredInstalledApps
        return Surface {
            VStack(alignment: .leading, spacing: 12) {
                PanelTitle(title: model.appFilterMode.title, caption: "\(items.count) 款")
                HStack(spacing: 8) {
                    DiskSearchField(placeholder: "搜索应用名称或路径", text: $model.appQuery, identifier: "app-search")
                    Picker("排序", selection: $model.appSortMode) {
                        ForEach(AppSortMode.allCases) { item in Text(item.title).tag(item) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 240)
                    .accessibilityIdentifier("app-sort")
                }

                if model.scanningApps && items.isEmpty {
                    ProgressView("正在只读统计应用目录元数据…")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 36)
                } else if items.isEmpty {
                    Text("没有符合当前筛选条件的应用。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 36)
                }

                VStack(spacing: 4) {
                    ForEach(items.prefix(80)) { app in
                        let selected = model.selectedInstalledApp?.path == app.path
                        DiskInteractiveRow(selected: selected, horizontalPadding: 8, verticalPadding: 8) {
                            HStack(spacing: 11) {
                                ModuleIconBadge(
                                    symbol: app.source == .appStore ? "apple.logo" : "app.fill",
                                    primary: palette.primary,
                                    secondary: palette.secondary,
                                    size: 32
                                )
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 6) {
                                        Text(app.name)
                                            .font(.system(size: 12.5, weight: .semibold))
                                            .lineLimit(1)
                                        Tag(text: app.source.title, color: app.source == .appStore ? palette.primary : .secondary)
                                        Tag(text: "本体受保护", color: DiskTheme.teal)
                                        if let badge = unusedBadge(for: app) {
                                            Tag(text: badge.0, color: badge.1)
                                        }
                                    }
                                    HStack(spacing: 10) {
                                        Text("本体 \(DiskFormat.bytes(app.bundleAllocated))")
                                        if app.associatedAllocated > 0 {
                                            Text("关联缓存 \(DiskFormat.bytes(app.associatedAllocated))")
                                                .foregroundStyle(DiskTheme.purple)
                                        }
                                    }
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 8)
                                VStack(alignment: .trailing, spacing: 3) {
                                    Text(DiskFormat.bytes(app.totalFootprint))
                                        .font(.system(size: 13.5, weight: .bold, design: .rounded))
                                        .monospacedDigit()
                                    Text("\(app.fileCount.formatted()) 文件")
                                        .font(.system(size: 9.5))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .onTapGesture {
                            model.selectedAppPath = app.path
                        }
                        .contextMenu {
                            Button("在 Finder 中显示应用本体") { model.reveal(app.path) }
                            Button("复制路径") { model.copyPath(app.path) }
                        }
                    }
                }
            }
        }
    }

    private var appDetailInspector: some View {
        Surface {
            VStack(alignment: .leading, spacing: 12) {
                PanelTitle(title: "应用足迹详情")
                if let app = model.selectedInstalledApp {
                    HStack(spacing: 10) {
                        ModuleIconBadge(
                            symbol: app.source == .appStore ? "apple.logo" : "app.fill",
                            primary: palette.primary,
                            secondary: palette.secondary,
                            size: 38
                        )
                        VStack(alignment: .leading, spacing: 3) {
                            Text(app.name)
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .lineLimit(2)
                            Text("\(app.source.title) · 本体只读保护")
                                .font(.system(size: 10.5))
                                .foregroundStyle(DiskTheme.teal)
                        }
                    }
                    Text(DiskFormat.compactPath(app.path))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .textSelection(.enabled)

                    Divider()
                    metricLine("总足迹占用", DiskFormat.bytes(app.totalFootprint))
                    metricLine("应用本体已分配", DiskFormat.bytes(app.bundleAllocated))
                    metricLine("应用逻辑大小", DiskFormat.bytes(app.bundleLogical))
                    metricLine("关联缓存与日志", DiskFormat.bytes(app.associatedAllocated))
                    if let days = app.unusedDays() {
                        metricLine("元数据估算活跃", days == 0 ? "今日活跃" : "约 \(days) 天未活跃")
                    }
                    if let ts = app.modifiedAt {
                        metricLine("本体最近修改", Date(timeIntervalSince1970: TimeInterval(ts)).formatted(date: .abbreviated, time: .omitted))
                    }
                    Text("基于文件系统元数据估算，本体严格只读保护。")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)

                    if !app.associatedItems.isEmpty {
                        Divider()
                        Text("关联数据目录 (\(app.associatedItems.count))")
                            .font(.system(size: 11, weight: .semibold))
                        VStack(spacing: 6) {
                            ForEach(app.associatedItems.prefix(6)) { item in
                                HStack(spacing: 6) {
                                    Image(systemName: item.blocked ? "lock.shield.fill" : item.category.symbol)
                                        .font(.system(size: 10))
                                        .foregroundStyle(item.blocked ? DiskTheme.teal : DiskTheme.purple)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(item.name).font(.system(size: 10.5, weight: .medium)).lineLimit(1)
                                        Text(item.category.title).font(.system(size: 9)).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(DiskFormat.bytes(item.allocated))
                                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                                        .monospacedDigit()
                                    Button {
                                        model.reveal(item.path)
                                    } label: {
                                        Image(systemName: "arrow.up.forward.app").font(.system(size: 9.5))
                                    }
                                    .buttonStyle(DiskButtonStyle(kind: .quiet))
                                }
                                .padding(7)
                                .background(DiskTheme.inset, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            model.reveal(app.path)
                        } label: {
                            Label("在 Finder 中显示本体", systemImage: "arrow.up.forward.app")
                        }
                        .controlSize(.small)

                        if !app.eligibleCachePaths.isEmpty && !model.isExternalVolume {
                            Button {
                                model.jumpToAppCaches(app.eligibleCachePaths)
                            } label: {
                                Label("前往系统清理审阅缓存", systemImage: "sparkles")
                            }
                            .buttonStyle(DiskButtonStyle(kind: .primary))
                            .controlSize(.small)
                        }
                    }
                    .padding(.top, 4)
                } else {
                    Text("选择左侧任一应用，查看其本体大小与关联缓存明细。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 24)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var orphansPane: some View {
        let items = model.filteredOrphanedData
        return Surface {
            VStack(alignment: .leading, spacing: 12) {
                PanelTitle(title: "疑似卸载残留缓存与窗口状态线索", caption: "\(items.count) 项")
                DiskSearchField(placeholder: "搜索残留目录名称或 Bundle 标识", text: $model.appQuery, identifier: "orphan-search")

                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill").foregroundStyle(palette.primary)
                    Text("以下用户缓存或窗口状态目录在 /Applications 与 ~/Applications 中未匹配到同名已安装应用。可能来自已卸载软件、命令行工具或自定义路径安装应用，请核对后再处理。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                }
                .padding(10)
                .background(DiskTheme.inset, in: RoundedRectangle(cornerRadius: DiskTheme.controlRadius))

                if items.isEmpty {
                    Text("未检测到明显的孤立应用缓存或状态残留线索。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 36)
                }

                ForEach(items.prefix(80)) { orphan in
                    DiskInteractiveRow(horizontalPadding: 8, verticalPadding: 9) {
                        HStack(spacing: 12) {
                            Image(systemName: orphan.blocked ? "lock.shield.fill" : orphan.category.symbol)
                                .font(.system(size: 16))
                                .foregroundStyle(orphan.blocked ? DiskTheme.teal : .orange)
                                .frame(width: 28, height: 28)
                                .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(orphan.name)
                                        .font(.system(size: 12.5, weight: .semibold))
                                        .lineLimit(1)
                                    Tag(text: orphan.category.title, color: .secondary)
                                    if orphan.blocked {
                                        Tag(text: "已保护", color: DiskTheme.teal)
                                    }
                                }
                                Text(DiskFormat.compactPath(orphan.path))
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            Text(DiskFormat.bytes(orphan.allocated))
                                .font(.system(size: 13.5, weight: .bold, design: .rounded))
                                .monospacedDigit()
                            if !orphan.blocked && !model.isExternalVolume {
                                Button("去系统清理") {
                                    model.jumpToAppCaches([orphan.path])
                                }
                                .buttonStyle(DiskButtonStyle(kind: .quiet))
                                .controlSize(.small)
                            }
                            Button("查看位置") {
                                model.reveal(orphan.path)
                            }
                            .buttonStyle(DiskButtonStyle(kind: .quiet))
                            .controlSize(.small)
                        }
                    }
                    Divider().opacity(0.55)
                }
            }
        }
    }

    private func unusedBadge(for app: InstalledAppItem) -> (String, Color)? {
        guard let days = app.unusedDays() else { return nil }
        if days >= 90 {
            return ("未活跃 ≥ \(days) 天", .orange)
        } else if days <= 7 {
            return ("近 7 天活跃", DiskTheme.teal)
        } else {
            return ("约 \(days) 天未活跃", .secondary)
        }
    }

    private func metricLine(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit().fontWeight(.medium)
        }
        .font(.system(size: 11))
    }
}
