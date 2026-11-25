import SwiftUI
import AetherDiskCore

struct SmartCareView: View {
    @ObservedObject var model: AppModel

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
                    Spacer()
                    Text("点击任意立式卡片进入对应模块深度工作台")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }

                HStack(alignment: .top, spacing: 10) {
                    ForEach(summary.pillars) { pillar in
                        verticalPillarCard(pillar)
                    }
                }
            }
            .accessibilityIdentifier("smartcare-pillars")

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
        return Button {
            guard !disabled else { return }
            model.page = pillar.targetPage
        } label: {
            Surface(padding: 14) {
                VStack(alignment: .leading, spacing: 12) {
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

                    Spacer(minLength: 4)

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

                    Divider().opacity(0.5)

                    HStack {
                        Text(disabled ? "外部卷只读" : "查看详情")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(disabled ? Color.secondary : targetPalette.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(disabled ? Color.secondary : targetPalette.primary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 186, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityIdentifier("pillar-" + pillar.id)
    }
}
