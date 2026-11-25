import SwiftUI
import AetherDiskCore

struct SmartCareView: View {
    @ObservedObject var model: AppModel
    @State private var expandedPillarID: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var summary: SmartCareSummary {
        model.smartCareSummary
    }

    private var palette: ModuleStagePalette {
        ModuleStagePalette.forPage("smartcare")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if model.scanning {
                OrbitalScanningBanner(palette: palette, progress: model.progress)
            }

            if model.result == nil && !model.scanning {
                ModuleHeroStage(
                    palette: palette,
                    targetPath: DiskFormat.compactPath(model.root.path),
                    features: [
                        ("sparkles", "系统清理：缓存、日志与窗口状态双栏核验"),
                        ("checkmark.shield.fill", "安全保护：启动代理、凭据防线与下载包只读核查"),
                        ("bolt.heart.fill", "性能优化：内存压力、CPU 散热与实时网速遥测"),
                        ("circle.hexagongrid.fill", "空间透镜：交互式比例气泡星图一屏下钻")
                    ],
                    onChooseFolder: { model.chooseFolder() },
                    onQuickScanHome: { model.start(FileManager.default.homeDirectoryForCurrentUser) }
                )
            } else if model.result != nil {
                scoreHeroCard
            }

            // CleanMyMac 5 Iconic 5-Column Vertical Glass Pillar Cards (Single-Screen No-Scroll Layout)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("五大护理维度")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .accessibilityIdentifier("smartcare-pillars")
                    Spacer()
                    Text("点击立式卡片直达工作台，或点「展开摘要」就地核查")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }

                HStack(alignment: .top, spacing: 10) {
                    ForEach(summary.pillars) { pillar in
                        verticalPillarCard(pillar)
                    }
                }

                if let expandedID = expandedPillarID,
                   let activePillar = summary.pillars.first(where: { $0.id == expandedID }) {
                    pillarQuickDrawer(for: activePillar)
                }
            }

            // Compact 2-Column Smart Assistant Live Insights Strip
            Surface(padding: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    PanelTitle(
                        title: "智能助手诊断建议",
                        caption: "本机只读诊断 · 确认前绝不改动文件"
                    )
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(summary.insights.prefix(4)) { insight in
                            let targetPalette = ModuleStagePalette.forPage(insight.targetPage)
                            HStack(alignment: .center, spacing: 10) {
                                ModuleIconBadge(
                                    symbol: insight.symbol,
                                    primary: insight.severity == .high ? DiskTheme.filledDanger : targetPalette.primary,
                                    secondary: insight.severity == .high ? DiskTheme.danger : targetPalette.secondary,
                                    size: 28
                                )
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(insight.title)
                                        .font(.system(size: 11.5, weight: .semibold))
                                        .lineLimit(1)
                                    Text(insight.detail)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                Spacer(minLength: 6)
                                Button(insight.actionLabel) {
                                    model.page = insight.targetPage
                                }
                                .buttonStyle(DiskButtonStyle(kind: .secondary))
                                .controlSize(.small)
                            }
                            .padding(9)
                            .background(DiskTheme.inset, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                }
            }
            .accessibilityIdentifier("smartcare-insights")
        }
    }

    private var scoreHeroCard: some View {
        Surface(padding: 16) {
            HStack(spacing: 18) {
                ZStack {
                    Circle()
                        .stroke(palette.primary.opacity(0.14), lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: CGFloat(summary.healthScore) / 100.0)
                        .stroke(
                            AngularGradient(
                                colors: [palette.primary, palette.secondary, palette.primary],
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 8, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 1) {
                        Text("\(summary.healthScore)")
                            .font(.system(size: 23, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text("健康指数")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 72, height: 72)
                .accessibilityIdentifier("smartcare-score-ring")

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(summary.statusTitle)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                        Tag(
                            text: model.isExternalVolume ? "外部卷 · 只读" : "全维体检完成",
                            color: model.isExternalVolume ? .orange : palette.primary
                        )
                    }
                    Text(summary.statusSubtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 10)

                HStack(spacing: 8) {
                    if !model.isExternalVolume && !model.eligible.isEmpty {
                        Button {
                            model.page = "suggestions"
                        } label: {
                            Label("审阅缓存 (\(DiskFormat.bytes(model.eligibleBytes)))", systemImage: "sparkles")
                        }
                        .buttonStyle(DiskButtonStyle(kind: .primary))
                        .controlSize(.small)
                    }
                    Button {
                        model.overviewVisualMode = .bubble
                        model.page = "overview"
                    } label: {
                        Label("空间透镜", systemImage: "circle.hexagongrid.fill")
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    private func verticalPillarCard(_ pillar: SmartCarePillar) -> some View {
        let targetPalette = ModuleStagePalette.forPage(pillar.targetPage)
        let disabled = pillar.targetPage == "suggestions" && model.isExternalVolume
        let isExpanded = expandedPillarID == pillar.id
        return Surface(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    guard !disabled else { return }
                    model.page = pillar.targetPage
                } label: {
                    VStack(alignment: .leading, spacing: 11) {
                        HStack {
                            ModuleIconBadge(
                                symbol: pillar.symbol,
                                primary: targetPalette.primary,
                                secondary: targetPalette.secondary,
                                size: 36
                            )
                            Spacer(minLength: 4)
                            Tag(
                                text: pillar.badgeText,
                                color: pillar.severity == .high ? DiskTheme.danger : (pillar.severity == .elevated ? .orange : targetPalette.primary)
                            )
                        }

                        Spacer(minLength: 2)

                        VStack(alignment: .leading, spacing: 5) {
                            Text(pillar.title)
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text(pillar.headlineValue)
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                            Text(pillar.subtitle)
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        HStack {
                            Text(disabled ? "外部卷只读" : "进入工作台")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(disabled ? Color.secondary : targetPalette.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundStyle(disabled ? Color.secondary : targetPalette.primary)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 156, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(disabled)
                .accessibilityIdentifier("pillar-" + pillar.id)

                Divider().opacity(0.45)

                Button {
                    withAnimation(DiskMotion.subtle(reduceMotion: reduceMotion)) {
                        expandedPillarID = isExpanded ? nil : pillar.id
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(isExpanded ? "收起摘要" : "展开摘要")
                            .font(.system(size: 10, weight: .semibold))
                        Spacer()
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(isExpanded ? targetPalette.primary : Color.secondary)
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("pillar-expand-" + pillar.id)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func pillarQuickDrawer(for pillar: SmartCarePillar) -> some View {
        let targetPalette = ModuleStagePalette.forPage(pillar.targetPage)
        return Surface(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    ModuleIconBadge(
                        symbol: pillar.symbol,
                        primary: targetPalette.primary,
                        secondary: targetPalette.secondary,
                        size: 26
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(pillar.title) · 只读快速审阅")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .accessibilityIdentifier("smartcare-pillar-drawer")
                        Text(pillar.subtitle)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !(pillar.targetPage == "suggestions" && model.isExternalVolume) {
                        Button("进入\(pillar.title)工作台") {
                            model.page = pillar.targetPage
                        }
                        .buttonStyle(DiskButtonStyle(kind: .secondary))
                        .controlSize(.small)
                    }
                    Button {
                        withAnimation(DiskMotion.subtle(reduceMotion: reduceMotion)) {
                            expandedPillarID = nil
                        }
                    } label: {
                        Label("收起", systemImage: "xmark")
                    }
                    .buttonStyle(DiskButtonStyle(kind: .quiet))
                    .controlSize(.small)
                    .accessibilityIdentifier("smartcare-drawer-close")
                }

                Divider().opacity(0.55)

                pillarDrawerBody(for: pillar.id, tint: targetPalette.primary)
            }
        }
    }

    @ViewBuilder
    private func pillarDrawerBody(for pillarID: String, tint: Color) -> some View {
        switch pillarID {
        case "cleanup":
            let top = Array(model.recommendations.prefix(5))
            if model.isExternalVolume {
                drawerEmptyText("外部卷仅支持只读空间分析，不提供系统清理建议。")
            } else if top.isEmpty {
                drawerEmptyText(model.result == nil ? "点击底部「智能扫描」后将在这里预览前 5 项缓存与日志建议。" : "当前扫描范围内未发现可清理缓存目录。")
            } else {
                VStack(spacing: 6) {
                    ForEach(top) { rec in
                        drawerRow(
                            title: rec.node.name,
                            subtitle: DiskFormat.compactPath(rec.id),
                            badge: rec.blocked ? "已保护" : rec.category.title,
                            badgeColor: rec.blocked ? DiskTheme.teal : tint,
                            value: DiskFormat.bytes(rec.node.allocated)
                        )
                    }
                }
            }
        case "protection":
            let report = model.protectionReport
            let items = Array((report?.launchItems ?? []).prefix(5))
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Tag(text: "启动代理 \(report?.launchItems.count ?? 0) 项", color: tint)
                    Tag(text: "隐私护盾 \(report?.vaultShields.filter(\.exists).count ?? 0) 项生效", color: DiskTheme.teal)
                    Tag(text: "下载安装包 \(report?.downloadInstallers.count ?? 0) 项", color: .secondary)
                }
                if items.isEmpty {
                    drawerEmptyText("纯元数据安全审计就绪，前往「安全保护」查看启动代理与凭据护盾详情。")
                } else {
                    ForEach(items) { item in
                        drawerRow(
                            title: item.name,
                            subtitle: DiskFormat.compactPath(item.path),
                            badge: item.scope.title,
                            badgeColor: tint,
                            value: item.vendorLabel
                        )
                    }
                }
            }
        case "performance":
            let hist = model.telemetryHistory
            let alert = model.lowSpaceAlert
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("内存实时走势").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.secondary)
                            Spacer()
                            Text("峰值 \(Int((hist.peakMemory * 100).rounded()))%").font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(DiskTheme.teal)
                        }
                        TelemetrySparkline(series: hist.memorySeries, tint: DiskTheme.teal, height: 28)
                    }
                    .padding(9)
                    .background(DiskTheme.inset, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("CPU 实时走势").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.secondary)
                            Spacer()
                            Text("峰值 \(Int((hist.peakCPU * 100).rounded()))%").font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(tint)
                        }
                        TelemetrySparkline(series: hist.cpuSeries, tint: tint, height: 28)
                    }
                    .padding(9)
                    .background(DiskTheme.inset, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                Text(alert.isTriggered ? "只读预警：\(alert.headline)（\(alert.detail)）" : "低空间阈值设为 \(model.lowSpaceThresholdGiB) GiB，当前磁盘可用 \(DiskFormat.bytes(model.volume.free))。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(alert.isTriggered ? .orange : .secondary)
            }
        case "apps":
            let apps = Array(model.filteredInstalledApps.prefix(5))
            if apps.isEmpty {
                drawerEmptyText(model.scanningApps ? "正在只读统计应用目录…" : "暂无可显示的应用统计。")
            } else {
                VStack(spacing: 6) {
                    ForEach(apps) { app in
                        let badgeText = app.unusedDays().map { $0 >= 90 ? "未活跃 ≥ \($0) 天" : ($0 <= 7 ? "近 7 天活跃" : "约 \($0) 天未活跃") } ?? app.source.title
                        drawerRow(
                            title: app.name,
                            subtitle: "本体 \(DiskFormat.bytes(app.bundleAllocated)) · 关联缓存 \(DiskFormat.bytes(app.associatedAllocated))",
                            badge: badgeText,
                            badgeColor: (app.unusedDays() ?? 0) >= 90 ? .orange : DiskTheme.teal,
                            value: DiskFormat.bytes(app.totalFootprint)
                        )
                    }
                }
            }
        default: // spacelens
            let dirs = Array(model.rows.prefix(5))
            let totalBytes = max(Int64(1), model.result?.allocated ?? dirs.reduce(0) { $0 + $1.allocated })
            if dirs.isEmpty {
                drawerEmptyText(model.result == nil ? "开始扫描后，将在此按占比展示前 5 个空间大户目录。" : "当前目录下暂无子项。")
            } else {
                VStack(spacing: 6) {
                    ForEach(dirs) { node in
                        let pct = Int((Double(node.allocated) / Double(totalBytes) * 100).rounded())
                        drawerRow(
                            title: node.name,
                            subtitle: DiskFormat.compactPath(node.path),
                            badge: "\(pct)%",
                            badgeColor: node.protection.isEmpty ? tint : DiskTheme.teal,
                            value: DiskFormat.bytes(node.allocated)
                        )
                    }
                }
            }
        }
    }

    private func drawerRow(title: String, subtitle: String, badge: String, badgeColor: Color, value: String) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title).font(.system(size: 11.5, weight: .semibold)).lineLimit(1)
                    Tag(text: badge, color: badgeColor)
                }
                Text(subtitle)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(DiskTheme.inset, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func drawerEmptyText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.vertical, 8)
    }
}
