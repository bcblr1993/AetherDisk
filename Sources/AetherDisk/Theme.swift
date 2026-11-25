import SwiftUI
import AppKit
import AetherDiskCore

struct ModuleStagePalette: Sendable {
    let id: String
    let title: String
    let subtitle: String
    let heroTitle: String
    let heroDescription: String
    let symbol: String
    let primary: Color
    let secondary: Color

    static func forPage(_ page: String) -> ModuleStagePalette {
        switch page {
        case "smartcare":
            return ModuleStagePalette(
                id: "smartcare",
                title: "智能护理",
                subtitle: "一键全维只读体检 · 空间、缓存与系统健康",
                heroTitle: "欢迎使用 AetherDisk 智能护理",
                heroDescription: "一次本机只读扫描，串联系统垃圾审阅、空间气泡透镜、大旧杂物筛查、应用残留透视与实时硬件健康诊断。",
                symbol: "wand.and.stars",
                primary: Color(light: 0x0D9488, dark: 0x2DD4BF),
                secondary: Color(light: 0x4F46E5, dark: 0x818CF8)
            )
        case "suggestions":
            return ModuleStagePalette(
                id: "suggestions",
                title: "系统清理",
                subtitle: "左分类 · 右明细审阅 · 仅移入废纸篓",
                heroTitle: "让 Mac 卸下冗余缓存负担",
                heroDescription: "精准识别应用缓存、历史日志、窗口状态、Xcode 设备支持与工程构建产物。源码与安装包全程自动保护。",
                symbol: "sparkles",
                primary: Color(light: 0xDB2777, dark: 0xF472B6),
                secondary: Color(light: 0x7C3AED, dark: 0xA78BFA)
            )
        case "protection":
            return ModuleStagePalette(
                id: "protection",
                title: "安全保护",
                subtitle: "启动代理透视 · 凭据防线 · 下载安装包只读核查",
                heroTitle: "守护系统边界与核心资产安全",
                heroDescription: "纯元数据只读审计用户与系统后台启动代理、SSH/GPG/钥匙串保护锁及下载目录待核验安装包，绝不篡改系统配置。",
                symbol: "checkmark.shield.fill",
                primary: Color(light: 0x059669, dark: 0x34D399),
                secondary: Color(light: 0x0284C7, dark: 0x38BDF8)
            )
        case "large":
            return ModuleStagePalette(
                id: "large",
                title: "我的杂物",
                subtitle: "跨目录大文件 · 陈旧归档 · 纯元数据重复线索",
                heroTitle: "揪出潜伏在深处的大文件与旧杂物",
                heroDescription: "不读取任何文件内容，按已分配块与逻辑体积双重透视大文件、久未修改文件与疑似重复文件组。",
                symbol: "shippingbox.and.arrow.backward.fill",
                primary: Color(light: 0xD97706, dark: 0xFBBF24),
                secondary: Color(light: 0xEA580C, dark: 0xFB7185)
            )
        case "overview":
            return ModuleStagePalette(
                id: "overview",
                title: "空间透镜",
                subtitle: "气泡地图 · 旭日图 · 树状图 · 分栏树 · 占比条",
                heroTitle: "构建磁盘空间的视觉星图",
                heroDescription: "以交互式比例气泡图与多维空间拓扑逐层展开文件夹大小，一眼定位真正的空间大户。",
                symbol: "circle.hexagongrid.fill",
                primary: Color(light: 0x0284C7, dark: 0x38BDF8),
                secondary: Color(light: 0x3A5BD9, dark: 0x6F8CFF)
            )
        case "applications":
            return ModuleStagePalette(
                id: "applications",
                title: "应用管理",
                subtitle: "应用体积透视 · 关联缓存 · 卸载残留线索",
                heroTitle: "清晰掌控每一款应用的真实足迹",
                heroDescription: "只读统计已安装应用本体与关联缓存、日志、窗口状态占用，识别无匹配应用的孤立缓存线索；应用本体严格受保护。",
                symbol: "square.stack.3d.up.fill",
                primary: Color(light: 0x0284C7, dark: 0x38BDF8),
                secondary: Color(light: 0x2563EB, dark: 0x60A5FA)
            )
        case "projects":
            return ModuleStagePalette(
                id: "projects",
                title: "工程洞察",
                subtitle: "Git 与多语言工作区 · 构建缓存占比分析",
                heroTitle: "专为开发者打造的工程空间透视",
                heroDescription: "自动识别 Swift、Rust、Node、Python、Java、Go、Zig 等工程目录，量化源码资产与可再生构建缓存比例。",
                symbol: "hammer.fill",
                primary: Color(light: 0x059669, dark: 0x34D399),
                secondary: Color(light: 0x0D9488, dark: 0x2DD4BF)
            )
        case "performance":
            return ModuleStagePalette(
                id: "performance",
                title: "性能优化",
                subtitle: "内存压力 · CPU 与散热 · 电源 · 网络 · 快照",
                heroTitle: "实时洞悉 Mac 运行脉搏",
                heroDescription: "基于原生内核接口只读展示内存分布、CPU 负载、散热状态、电源健康、网络速率与活跃桌面应用。",
                symbol: "bolt.heart.fill",
                primary: Color(light: 0x16A34A, dark: 0x4ADE80),
                secondary: Color(light: 0x0D9488, dark: 0x2DD4BF)
            )
        case "types":
            return ModuleStagePalette(
                id: "types",
                title: "文件类型",
                subtitle: "全量扩展名谱系 · 修改时间陈旧度分桶",
                heroTitle: "空间都去哪了，按类型一清二楚",
                heroDescription: "穿透展示视频、归档、源码、文档、图片与音频的真实占用比例及活跃时间分布。",
                symbol: "chart.bar.xaxis",
                primary: Color(light: 0x7C3AED, dark: 0xA78BFA),
                secondary: Color(light: 0x4F46E5, dark: 0x818CF8)
            )
        case "changes":
            return ModuleStagePalette(
                id: "changes",
                title: "占用变化",
                subtitle: "多快照历史趋势 · 连续增长热点追踪",
                heroTitle: "每一次空间涨落，皆有迹可循",
                heroDescription: "对比本机历史完整扫描快照，定位悄然膨胀的目录与连续增长热点。",
                symbol: "chart.line.uptrend.xyaxis",
                primary: Color(light: 0x4F46E5, dark: 0x818CF8),
                secondary: Color(light: 0x9333EA, dark: 0xC084FC)
            )
        default:
            return ModuleStagePalette(
                id: "settings",
                title: "设置与更新",
                subtitle: "并发策略 · 隐私权限 · 自定义保护 · Sparkle 更新",
                heroTitle: "设置与安全偏好",
                heroDescription: "配置磁盘友好扫描档位、保护目录清单与签名应用内更新。",
                symbol: "gearshape.fill",
                primary: DiskTheme.accent,
                secondary: DiskTheme.purple
            )
        }
    }
}

enum DiskTheme {
    static let filledAccent = Color(light: 0x3A5BD9, dark: 0x506AE0)
    static let filledDanger = Color(light: 0xC13D45, dark: 0xB9424C)
    static let controlRadius: CGFloat = 9
    static let cardRadius: CGFloat = 16
    static let danger = Color(light: 0xC94449, dark: 0xF06A72)
    static let accent = Color(light: 0x3A5BD9, dark: 0x6F8CFF)
    static let purple = Color(light: 0x7253CF, dark: 0xA58BFF)
    static let teal = Color(light: 0x0D9488, dark: 0x2DD4BF)
    static let background = Color(light: 0xF2F4FA, dark: 0x0E1017)
    static let sidebarTint = Color(light: 0xE9ECF6, dark: 0x12151F)
    static let surface = Color(light: 0xFFFFFF, dark: 0x171B26)
    static let elevatedSurface = Color(light: 0xF9FAFE, dark: 0x1E2331)
    static let inset = Color(light: 0xF3F5FB, dark: 0x222736)
    static let line = Color.primary.opacity(0.08)
    static let strongLine = Color.primary.opacity(0.13)
    static let colors: [Color] = [
        Color(light: 0x2563EB, dark: 0x60A5FA),
        Color(light: 0x7C3AED, dark: 0xA78BFA),
        Color(light: 0x0D9488, dark: 0x2DD4BF),
        Color(light: 0xEA580C, dark: 0xFB923C),
        Color(light: 0xDB2777, dark: 0xF472B6),
        Color(light: 0x0284C7, dark: 0x38BDF8),
        Color(light: 0x4F46E5, dark: 0x818CF8)
    ]

    static func color(
        forMode mode: VisualizationColorMode,
        colorIndex: Int,
        category: FileCategory,
        ageBucket: AgeBucket,
        isProtected: Bool,
        isTail: Bool
    ) -> Color {
        if isTail { return Color.secondary.opacity(0.38) }
        switch mode {
        case .hierarchy:
            let safeIndex = colorIndex == Int.min ? 0 : abs(colorIndex)
            return colors[safeIndex % colors.count]
        case .fileType:
            switch category {
            case .video: return purple
            case .audio: return Color(light: 0xDB2777, dark: 0xF472B6)
            case .image: return teal
            case .archive: return Color(light: 0xEA580C, dark: 0xFB923C)
            case .source: return accent
            case .document: return Color(light: 0x0284C7, dark: 0x38BDF8)
            case .other: return Color(light: 0x4F46E5, dark: 0x818CF8)
            }
        case .age:
            switch ageBucket {
            case .recent30d: return accent
            case .days30to90: return teal
            case .days90to365: return Color(light: 0xEA580C, dark: 0xFB923C)
            case .over1y: return danger
            }
        case .protection:
            return isProtected ? teal : purple
        }
    }
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(
                srgbRed: CGFloat((hex >> 16) & 255) / 255,
                green: CGFloat((hex >> 8) & 255) / 255,
                blue: CGFloat(hex & 255) / 255,
                alpha: 1
            )
        })
    }
}

enum DiskMotion {
    static func transition(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.86)
    }

    static func subtle(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.22)
    }

    static func hover(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.12)
    }
}

struct StageBackground: View {
    let palette: ModuleStagePalette
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let topAlpha = colorScheme == .dark ? 0.20 : 0.11
        let bottomAlpha = colorScheme == .dark ? 0.16 : 0.08
        ZStack {
            DiskTheme.background
            if !reduceTransparency {
                RadialGradient(
                    colors: [palette.primary.opacity(topAlpha), .clear],
                    center: .topTrailing,
                    startRadius: 20,
                    endRadius: 560
                )
                RadialGradient(
                    colors: [palette.secondary.opacity(bottomAlpha), .clear],
                    center: .bottomLeading,
                    startRadius: 30,
                    endRadius: 520
                )
            }
        }
        .ignoresSafeArea()
        .animation(DiskMotion.subtle(reduceMotion: reduceMotion), value: palette.id)
    }
}

struct BrandMark: View {
    var size: CGFloat = 36
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(light: 0x0EA5E9, dark: 0x38BDF8),
                            DiskTheme.accent,
                            DiskTheme.purple
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.55), .white.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: DiskTheme.accent.opacity(0.28), radius: size * 0.18, y: size * 0.08)

            Circle()
                .trim(from: 0.04, to: 0.76)
                .stroke(.white.opacity(0.95), style: StrokeStyle(lineWidth: size * 0.09, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(size * 0.22)
            Circle()
                .trim(from: 0.81, to: 0.96)
                .stroke(.white.opacity(0.52), style: StrokeStyle(lineWidth: size * 0.09, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(size * 0.22)
            Circle()
                .fill(.white)
                .frame(width: size * 0.13, height: size * 0.13)
        }
        .frame(width: size, height: size)
    }
}

struct ModuleIconBadge: View {
    let symbol: String
    let primary: Color
    let secondary: Color
    var size: CGFloat = 24

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [primary, secondary],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.52), .white.opacity(0.08)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.9
                        )
                )
                .shadow(color: primary.opacity(0.25), radius: size * 0.16, y: size * 0.06)

            Image(systemName: symbol)
                .font(.system(size: size * 0.48, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}

struct Surface<Content: View>: View {
    let content: Content
    let padding: CGFloat
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(padding: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        let fill = reduceTransparency
            ? DiskTheme.surface
            : DiskTheme.surface.opacity(colorScheme == .dark ? 0.88 : 0.93)
        let borderStyle: AnyShapeStyle = reduceTransparency
            ? AnyShapeStyle(DiskTheme.strongLine)
            : AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color.white.opacity(colorScheme == .dark ? 0.11 : 0.75),
                        DiskTheme.line
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        content
            .padding(padding)
            .background(
                fill,
                in: RoundedRectangle(cornerRadius: DiskTheme.cardRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DiskTheme.cardRadius, style: .continuous)
                    .stroke(borderStyle, lineWidth: 1)
            )
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.22 : 0.045),
                radius: 12,
                y: 4
            )
    }
}

struct Tag: View {
    let text: String
    var color: Color = DiskTheme.accent
    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3.5)
            .foregroundStyle(color)
            .background(color.opacity(0.11), in: Capsule())
    }
}

struct PanelTitle: View {
    let title: String
    var caption: String = ""
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 14, weight: .semibold, design: .rounded))
            Spacer()
            if !caption.isEmpty {
                Text(caption).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }
}

struct CleanupRiskNotice: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("清理风险提示", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.orange)
            Text("软件及清理建议可能存在问题或误判，请谨慎操作。重要文件请先备份，并逐项核对清理目录。误删或数据丢失由用户自行承担，开发者概不负责。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(Color.orange.opacity(0.18), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("cleanup-risk-notice")
    }
}

// MARK: - CleanMyMac Hero Welcome & Orbital Scanning Stages

struct ModuleHeroStage: View {
    let palette: ModuleStagePalette
    let targetPath: String
    let features: [(icon: String, text: String)]
    let onChooseFolder: () -> Void
    let onQuickScanHome: () -> Void

    var body: some View {
        Surface(padding: 32) {
            HStack(spacing: 32) {
                // Left Column: CleanMyMac Editorial Manifesto & Feature Bullets
                VStack(alignment: .leading, spacing: 18) {
                    Tag(text: palette.title + " · 纯只读安全引擎", color: palette.primary)
                    Text(palette.heroTitle)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(palette.heroDescription)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(features.enumerated()), id: \.offset) { _, feat in
                            HStack(spacing: 10) {
                                Image(systemName: feat.icon)
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundStyle(palette.primary)
                                    .frame(width: 26, height: 26)
                                    .background(palette.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                                Text(feat.text)
                                    .font(.system(size: 12.5, weight: .medium))
                            }
                        }
                    }
                    .padding(.vertical, 4)

                    HStack(spacing: 10) {
                        HStack(spacing: 6) {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(palette.primary)
                            Text(targetPath)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .font(.system(size: 11.5, weight: .medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(DiskTheme.inset, in: Capsule())

                        Button("切换文件夹…", action: onChooseFolder)
                            .controlSize(.small)

                        Button("扫描个人文件夹", action: onQuickScanHome)
                            .buttonStyle(DiskButtonStyle(kind: .primary))
                            .controlSize(.small)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Right Column: CleanMyMac Layered 3D Glass Stage Emblem
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [palette.primary.opacity(0.28), palette.secondary.opacity(0.08), .clear],
                                center: .center,
                                startRadius: 12,
                                endRadius: 115
                            )
                        )
                        .frame(width: 230, height: 230)

                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [palette.primary.opacity(0.14), palette.secondary.opacity(0.06)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 176, height: 176)
                        .rotationEffect(.degrees(-8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 26, style: .continuous)
                                .stroke(.white.opacity(0.22), lineWidth: 1)
                                .rotationEffect(.degrees(-8))
                        )

                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [palette.primary.opacity(0.48), palette.secondary.opacity(0.16)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])
                        )
                        .frame(width: 148, height: 148)

                    ModuleIconBadge(
                        symbol: palette.symbol,
                        primary: palette.primary,
                        secondary: palette.secondary,
                        size: 84
                    )
                }
                .frame(width: 240)
            }
        }
    }
}

struct OrbitalScanningBanner: View {
    let palette: ModuleStagePalette
    let progress: ScanProgress

    @State private var spinning = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let isSpinning = spinning && !reduceMotion
        Surface(padding: 16) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(palette.primary.opacity(0.16), lineWidth: 4)
                        .frame(width: 44, height: 44)
                    Circle()
                        .trim(from: 0.08, to: 0.72)
                        .stroke(
                            LinearGradient(colors: [palette.primary, palette.secondary], startPoint: .topLeading, endPoint: .bottomTrailing),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round)
                        )
                        .frame(width: 44, height: 44)
                        .rotationEffect(.degrees(isSpinning ? 360 : 0))
                        .animation(
                            reduceMotion ? nil : .linear(duration: 1.15).repeatForever(autoreverses: false),
                            value: isSpinning
                        )
                    Image(systemName: palette.symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.primary)
                }
                .transaction { if reduceMotion { $0.animation = nil } }
                .onAppear { spinning = !reduceMotion }
                .onChange(of: reduceMotion) { _, reduced in
                    spinning = !reduced
                }

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text("正在深度只读扫描 · \(progress.files.formatted()) 个文件")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Tag(text: "已累计 \(DiskFormat.bytes(progress.allocated))", color: palette.primary)
                    }
                    Text(progress.currentPath.isEmpty ? "正在读取目录元数据…" : DiskFormat.compactPath(progress.currentPath))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Text("不读取文件内容 · 可随时停止")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - CleanMyMac Bottom Floating Circular Action Orb Dock

private struct OrbWingCapsuleModifier: ViewModifier {
    let reduceTransparency: Bool

    func body(content: Content) -> some View {
        let fill: AnyShapeStyle = reduceTransparency
            ? AnyShapeStyle(DiskTheme.elevatedSurface)
            : AnyShapeStyle(.ultraThinMaterial)
        let border = reduceTransparency ? DiskTheme.strongLine : DiskTheme.line
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(fill, in: Capsule())
            .overlay(Capsule().stroke(border, lineWidth: 1))
    }
}

struct CircularActionOrbBar: View {
    let palette: ModuleStagePalette
    let scanning: Bool
    let checking: Bool
    let hasResult: Bool
    let cancelled: Bool
    let filesCount: Int
    let duration: Double
    let unreadableCount: Int
    let scanProfileTitle: String
    let primaryOrbLabel: String
    let onScan: () -> Void
    let onCancel: () -> Void
    let onShowIssues: () -> Void

    @State private var hoveringOrb = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let orbHover = hoveringOrb && !reduceMotion
        HStack(alignment: .center, spacing: 14) {
            // Left telemetry status floating frosted capsule
            HStack(spacing: 7) {
                Image(systemName: unreadableCount > 0 ? "exclamationmark.circle.fill" : "checkmark.shield.fill")
                    .foregroundStyle(unreadableCount > 0 ? .orange : palette.primary)
                if hasResult {
                    Text(cancelled ? "扫描已停止 · 部分结果" : "\(filesCount.formatted()) 个文件 · \(String(format: "%.1f", duration)) 秒")
                        .monospacedDigit()
                    if unreadableCount > 0 {
                        Button("\(unreadableCount) 个路径未能读取", action: onShowIssues)
                            .buttonStyle(DiskButtonStyle(kind: .quiet))
                            .foregroundStyle(.orange)
                            .help("查看未读取路径与权限说明")
                    }
                } else if scanning {
                    Text("正在扫描元数据 · \(filesCount.formatted()) 个文件")
                        .monospacedDigit()
                } else {
                    Text("只读扫描 · 不读取文件内容")
                }
                Text("· \(scanProfileTitle)")
                    .foregroundStyle(.tertiary)
            }
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
            .modifier(OrbWingCapsuleModifier(reduceTransparency: reduceTransparency))
            .frame(maxWidth: .infinity, alignment: .leading)

            // Center CleanMyMac Iconic Circular Glowing Action Orb
            if scanning {
                Button(role: .cancel, action: onCancel) {
                    ZStack {
                        Circle()
                            .fill(DiskTheme.danger.opacity(reduceTransparency ? 0.22 : (orbHover ? 0.24 : 0.15)))
                            .frame(width: 66, height: 66)
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [DiskTheme.filledDanger, Color(light: 0xE11D48, dark: 0xFB7185)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 54, height: 54)
                            .overlay(
                                Circle().stroke(.white.opacity(0.45), lineWidth: 1.2)
                            )
                            .shadow(color: DiskTheme.danger.opacity(0.35), radius: 10, y: 3)
                        VStack(spacing: 1) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 13, weight: .bold))
                            Text("停止扫描")
                                .font(.system(size: 8.5, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                    }
                    .animation(DiskMotion.hover(reduceMotion: reduceMotion), value: hoveringOrb)
                }
                .buttonStyle(.plain)
                .onHover { hoveringOrb = $0 }
                .accessibilityLabel("停止扫描")
                .help("立即停止当前扫描并保留已读部分结果")
            } else {
                Button(action: onScan) {
                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [palette.primary.opacity(reduceTransparency ? 0.0 : (orbHover ? 0.40 : 0.24)), .clear],
                                    center: .center,
                                    startRadius: 16,
                                    endRadius: 40
                                )
                            )
                            .frame(width: 78, height: 78)
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [palette.primary.opacity(0.60), palette.secondary.opacity(0.28)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                            .frame(width: 68, height: 68)
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [palette.primary, palette.secondary],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 58, height: 58)
                            .overlay(
                                Circle()
                                    .stroke(
                                        LinearGradient(
                                            colors: [.white.opacity(0.70), .white.opacity(0.14)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        ),
                                        lineWidth: 1.3
                                    )
                            )
                            .shadow(color: palette.primary.opacity(orbHover ? 0.50 : 0.34), radius: orbHover ? 16 : 11, y: 4)
                        VStack(spacing: 1.5) {
                            Image(systemName: hasResult ? "arrow.clockwise" : "play.fill")
                                .font(.system(size: 13, weight: .bold))
                            Text(primaryOrbLabel)
                                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(.white)
                    }
                    .scaleEffect(orbHover ? 1.04 : 1.0)
                    .animation(DiskMotion.hover(reduceMotion: reduceMotion), value: hoveringOrb)
                }
                .buttonStyle(.plain)
                .disabled(checking)
                .opacity(checking ? 0.45 : 1)
                .animation(DiskMotion.subtle(reduceMotion: reduceMotion), value: checking)
                .onHover { hoveringOrb = $0 }
                .keyboardShortcut("r", modifiers: .command)
                .accessibilityIdentifier("scan")
                .accessibilityLabel(hasResult ? "重新扫描" : "开始扫描")
                .help("\(hasResult ? "重新扫描" : "开始只读扫描") (⌘R)")
            }

            // Right APFS honesty notice wing (floating frosted capsule)
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.tertiary)
                Text("APFS 共享数据可能使目录占用高于实际可释放空间")
                    .lineLimit(1)
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .modifier(OrbWingCapsuleModifier(reduceTransparency: reduceTransparency))
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 22)
        .padding(.top, 4)
        .padding(.bottom, 10)
    }
}

// MARK: - Shared Controls & Dialogs

enum DiskButtonKind { case primary, secondary, quiet }

struct DiskButtonStyle: ButtonStyle {
    var kind: DiskButtonKind = .secondary
    func makeBody(configuration: Configuration) -> some View {
        DiskButtonChrome(configuration: configuration, kind: kind)
    }
}

private struct DiskButtonChrome: View {
    let configuration: ButtonStyleConfiguration
    let kind: DiskButtonKind
    @Environment(\.isEnabled) private var enabled
    @Environment(\.controlSize) private var size
    @Environment(\.isFocused) private var focused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    private var tint: Color { configuration.role == .destructive ? DiskTheme.danger : DiskTheme.accent }
    private var small: Bool { size == .small || size == .mini }
    private var foreground: Color { kind == .primary ? .white : kind == .quiet ? tint : .primary }
    private var fill: AnyShapeStyle {
        if kind == .primary {
            let base = configuration.role == .destructive
                ? LinearGradient(colors: [DiskTheme.filledDanger, DiskTheme.danger], startPoint: .topLeading, endPoint: .bottomTrailing)
                : LinearGradient(colors: [DiskTheme.filledAccent, DiskTheme.purple], startPoint: .topLeading, endPoint: .bottomTrailing)
            return AnyShapeStyle(base.opacity(configuration.isPressed ? 0.82 : hovering ? 0.93 : 1))
        }
        if hovering || configuration.isPressed {
            return AnyShapeStyle(tint.opacity(configuration.isPressed ? 0.13 : 0.075))
        }
        return AnyShapeStyle(kind == .secondary ? DiskTheme.surface : .clear)
    }

    var body: some View {
        configuration.label
            .font(.system(size: small ? 11 : 12, weight: .medium))
            .padding(.horizontal, small ? 10 : 13)
            .frame(minHeight: small ? 26 : 32)
            .foregroundStyle(foreground)
            .background(fill, in: RoundedRectangle(cornerRadius: DiskTheme.controlRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DiskTheme.controlRadius, style: .continuous)
                    .stroke(kind == .secondary ? DiskTheme.strongLine : (kind == .primary ? .white.opacity(0.22) : .clear), lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DiskTheme.controlRadius + 2, style: .continuous)
                    .stroke(focused ? DiskTheme.accent.opacity(0.6) : .clear, lineWidth: 2)
                    .padding(-3)
            )
            .contentShape(RoundedRectangle(cornerRadius: DiskTheme.controlRadius, style: .continuous))
            .opacity(enabled ? 1 : 0.42)
            .onHover { hovering = $0 }
            .animation(DiskMotion.hover(reduceMotion: reduceMotion), value: hovering)
    }
}

struct DiskSidebarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        DiskSidebarButtonChrome(configuration: configuration)
    }
}

private struct DiskSidebarButtonChrome: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    var body: some View {
        configuration.label
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color.primary.opacity(configuration.isPressed ? 0.09 : hovering ? 0.05 : 0),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .opacity(enabled ? 1 : 0.45)
            .onHover { hovering = $0 }
            .animation(DiskMotion.hover(reduceMotion: reduceMotion), value: hovering)
    }
}

struct DiskInteractiveRow<Content: View>: View {
    var selected = false
    var horizontalPadding: CGFloat = 8
    var verticalPadding: CGFloat = 6
    let content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    init(selected: Bool = false, horizontalPadding: CGFloat = 8, verticalPadding: CGFloat = 6, @ViewBuilder content: () -> Content) {
        self.selected = selected
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                DiskTheme.accent.opacity(selected ? 0.10 : hovering ? 0.052 : 0),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(selected ? DiskTheme.accent.opacity(0.24) : .clear, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .onHover { hovering = $0 }
            .animation(DiskMotion.hover(reduceMotion: reduceMotion), value: hovering)
    }
}

struct DiskDialog<Content: View, Actions: View>: View {
    let title: String
    let subtitle: String
    let symbol: String
    var destructive = false
    @ViewBuilder let content: Content
    @ViewBuilder let actions: Actions
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let dividerColor = reduceTransparency ? DiskTheme.strongLine : DiskTheme.line
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ModuleIconBadge(
                    symbol: symbol,
                    primary: destructive ? DiskTheme.filledDanger : DiskTheme.accent,
                    secondary: destructive ? DiskTheme.danger : DiskTheme.purple,
                    size: 42
                )
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.system(size: 19, weight: .semibold, design: .rounded))
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(22)
            Divider().overlay(dividerColor)
            VStack(alignment: .leading, spacing: 16) { content }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
            Divider().overlay(dividerColor)
            HStack(spacing: 10) { actions }
                .padding(.horizontal, 22)
                .padding(.vertical, 16)
                .background(DiskTheme.inset)
        }
        .frame(width: 600)
        .background(DiskTheme.surface)
        .tint(DiskTheme.accent)
        .buttonStyle(DiskButtonStyle())
    }
}

struct DiskSearchField: View {
    let placeholder: String
    @Binding var text: String
    var identifier = ""
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let idleBorder = reduceTransparency ? DiskTheme.strongLine : DiskTheme.line
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .focused($focused)
                .accessibilityIdentifier(identifier)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .font(.system(size: 12))
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(DiskTheme.inset, in: RoundedRectangle(cornerRadius: DiskTheme.controlRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DiskTheme.controlRadius, style: .continuous)
                .stroke(focused ? DiskTheme.accent.opacity(0.65) : idleBorder, lineWidth: 1)
        )
    }
}
