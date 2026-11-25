import SwiftUI
import AppKit
import AetherDiskCore

struct TelemetrySparkline: View {
    let series: [Double]
    let tint: Color
    var height: CGFloat = 38
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var normalized: [Double] {
        series.map { value in
            guard value.isFinite else { return 0 }
            return min(1.0, max(0.0, value))
        }
    }

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            guard w > 4, h > 4 else { return }

            let topPad: CGFloat = 4
            let bottomPad: CGFloat = 4
            let usableH = max(2, h - topPad - bottomPad)

            var baseline = Path()
            baseline.move(to: CGPoint(x: 0, y: h - bottomPad))
            baseline.addLine(to: CGPoint(x: w, y: h - bottomPad))
            context.stroke(baseline, with: .color(tint.opacity(0.18)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

            let values = normalized
            let points: [CGPoint]
            if values.isEmpty {
                let y = h - bottomPad - usableH * 0.08
                points = [CGPoint(x: 0, y: y), CGPoint(x: w, y: y)]
            } else if values.count == 1 {
                let y = topPad + usableH * CGFloat(1.0 - values[0])
                points = [CGPoint(x: 0, y: y), CGPoint(x: w, y: y)]
            } else {
                let step = w / CGFloat(values.count - 1)
                points = values.enumerated().map { idx, val in
                    CGPoint(
                        x: CGFloat(idx) * step,
                        y: topPad + usableH * CGFloat(1.0 - val)
                    )
                }
            }

            var line = Path()
            line.move(to: points[0])
            for i in 1..<points.count {
                let prev = points[i - 1]
                let cur = points[i]
                let midX = (prev.x + cur.x) * 0.5
                line.addCurve(
                    to: cur,
                    control1: CGPoint(x: midX, y: prev.y),
                    control2: CGPoint(x: midX, y: cur.y)
                )
            }

            var area = line
            area.addLine(to: CGPoint(x: points.last?.x ?? w, y: h - bottomPad))
            area.addLine(to: CGPoint(x: points.first?.x ?? 0, y: h - bottomPad))
            area.closeSubpath()

            context.fill(
                area,
                with: .linearGradient(
                    Gradient(colors: [tint.opacity(values.isEmpty ? 0.08 : 0.25), tint.opacity(0.02)]),
                    startPoint: CGPoint(x: 0, y: topPad),
                    endPoint: CGPoint(x: 0, y: h - bottomPad)
                )
            )
            context.stroke(
                line,
                with: .color(values.isEmpty ? tint.opacity(0.42) : tint),
                style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
            )

            if let last = points.last, !values.isEmpty {
                let dotRect = CGRect(x: last.x - 3, y: last.y - 3, width: 6, height: 6)
                context.fill(Path(ellipseIn: dotRect), with: .color(tint))
            }
        }
        .frame(height: height)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: normalized)
    }
}

struct PerformanceHealthView: View {
    @ObservedObject var model: AppModel

    private var palette: ModuleStagePalette {
        ModuleStagePalette.forPage("performance")
    }

    private func formatUptime(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let days = total / 86_400
        let hours = (total % 86_400) / 3600
        let mins = (total % 3600) / 60
        if days > 0 {
            return "\(days) 天 \(hours) 小时"
        }
        return "\(hours) 小时 \(mins) 分钟"
    }

    var body: some View {
        let snap = model.systemHealth
        VStack(alignment: .leading, spacing: 16) {
            Surface(padding: 16) {
                HStack(spacing: 14) {
                    ModuleIconBadge(
                        symbol: "desktopcomputer",
                        primary: palette.primary,
                        secondary: palette.secondary,
                        size: 40
                    )
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(snap?.hostModelLabel ?? "Mac")
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                            Tag(text: snap?.osVersionLabel ?? "macOS", color: palette.primary)
                            if let up = snap?.cpu.uptimeSeconds {
                                Tag(text: "已连续运行 \(formatUptime(up))", color: .secondary)
                            }
                        }
                        Text("纯只读系统内核健康遥测 · 绝不执行伪造内存清理或强行终止用户应用")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        model.refreshSystemTelemetry()
                    } label: {
                        Label("立即采样", systemImage: "arrow.clockwise")
                    }
                    .controlSize(.small)
                    .accessibilityIdentifier("performance-refresh")
                }
            }

            // CleanMyMac 2x3 Interactive Health Telemetry Matrix
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    memoryCard(snap?.memory)
                    cpuCard(snap?.cpu)
                }
                HStack(spacing: 12) {
                    storageHealthCard
                    networkCard(snap?.network)
                }
                HStack(spacing: 12) {
                    powerCard(snap?.power)
                    trashAndPrivacyCard
                }
            }

            // Read-Only Background Launch Items Linkage Card
            launchItemsLinkCard

            // Foreground Running GUI Apps (Read-Only)
            Surface {
                VStack(alignment: .leading, spacing: 10) {
                    PanelTitle(
                        title: "当前活跃桌面应用（只读视图）",
                        caption: "\(model.runningApps.count) 个应用运行中"
                    )
                    if model.runningApps.isEmpty {
                        Text("暂无可列出的桌面应用。")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 16)
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(model.runningApps.prefix(12)) { app in
                                HStack(spacing: 9) {
                                    Circle()
                                        .fill(app.isActive ? palette.primary : Color.secondary.opacity(0.45))
                                        .frame(width: 7, height: 7)
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 5) {
                                            Text(app.name)
                                                .font(.system(size: 11.5, weight: .semibold))
                                                .lineLimit(1)
                                            if app.isActive {
                                                Text("前台")
                                                    .font(.system(size: 8.5, weight: .semibold))
                                                    .padding(.horizontal, 5)
                                                    .padding(.vertical, 1)
                                                    .foregroundStyle(palette.primary)
                                                    .background(palette.primary.opacity(0.14), in: Capsule())
                                            }
                                        }
                                        Text("PID \(app.pid) · \(app.bundleIdentifier)")
                                            .font(.system(size: 9.5))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer(minLength: 4)
                                    if let path = app.bundlePath {
                                        Button {
                                            model.reveal(path)
                                        } label: {
                                            Image(systemName: "arrow.up.forward.app")
                                                .font(.system(size: 10))
                                        }
                                        .buttonStyle(DiskButtonStyle(kind: .quiet))
                                        .help("在 Finder 中显示 \(app.name)")
                                    }
                                }
                                .padding(9)
                                .background(DiskTheme.inset, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            }
                        }
                    }
                }
            }
            .accessibilityIdentifier("running-apps-card")
        }
        .task {
            model.refreshSystemTelemetry()
            guard ProcessInfo.processInfo.environment["AETHERDISK_QA"] != "1" else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                if Task.isCancelled { break }
                model.refreshSystemTelemetry()
            }
        }
    }

    private func memoryCard(_ mem: MemoryTelemetry?) -> some View {
        let frac = mem?.usedFraction ?? 0
        let tint: Color = mem?.pressure == .high ? DiskTheme.danger : (mem?.pressure == .elevated ? .orange : palette.primary)
        let history = model.telemetryHistory
        return Surface {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("内存压力与分布", systemImage: "memorychip.fill")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(tint)
                        .accessibilityIdentifier("performance-telemetry-grid")
                    Spacer()
                    Tag(text: mem?.pressure.title ?? "采样中", color: tint)
                }
                HStack(spacing: 16) {
                    gaugeRing(fraction: frac, label: "\(Int((frac * 100).rounded()))%", sub: "已使用", tint: tint)
                    VStack(alignment: .leading, spacing: 5) {
                        kvRow("可用内存", mem.map { DiskFormat.bytes($0.availableBytes) } ?? "—")
                        kvRow("应用内存", mem.map { DiskFormat.bytes($0.appBytes) } ?? "—")
                        kvRow("联动内存 (Wired)", mem.map { DiskFormat.bytes($0.wiredBytes) } ?? "—")
                        kvRow("已压缩", mem.map { DiskFormat.bytes($0.compressedBytes) } ?? "—")
                        kvRow("物理总计", mem.map { DiskFormat.bytes($0.totalBytes) } ?? "—")
                    }
                }
                telemetrySparklineBlock(
                    sampleCount: history.samples.count,
                    series: history.memorySeries,
                    average: history.averageMemory,
                    peak: history.peakMemory,
                    tint: tint,
                    identifier: "memory-sparkline",
                    label: "内存占用历史趋势图"
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func cpuCard(_ cpu: CPUTelemetry?) -> some View {
        let frac = cpu?.usageFraction ?? 0
        let tint: Color = cpu?.thermalSeverity == .high ? DiskTheme.danger : (cpu?.thermalSeverity == .elevated ? .orange : DiskTheme.accent)
        let history = model.telemetryHistory
        return Surface {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("CPU 负载与散热", systemImage: "cpu.fill")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(tint)
                    Spacer()
                    Tag(text: cpu?.thermalLabel ?? "正常", color: tint)
                }
                HStack(spacing: 16) {
                    gaugeRing(fraction: frac, label: "\(Int((frac * 100).rounded()))%", sub: "总负载", tint: tint)
                    VStack(alignment: .leading, spacing: 5) {
                        kvRow("物理/逻辑核心", cpu.map { "\($0.coreCount) 核" } ?? "—")
                        kvRow("用户态占用", cpu.map { String(format: "%.1f%%", $0.userFraction * 100) } ?? "—")
                        kvRow("内核态占用", cpu.map { String(format: "%.1f%%", $0.systemFraction * 100) } ?? "—")
                        kvRow("1 分钟平均负载", cpu.map { String(format: "%.2f", $0.loadAverage1m) } ?? "—")
                        kvRow("5 分钟平均负载", cpu.map { String(format: "%.2f", $0.loadAverage5m) } ?? "—")
                    }
                }
                telemetrySparklineBlock(
                    sampleCount: history.samples.count,
                    series: history.cpuSeries,
                    average: history.averageCPU,
                    peak: history.peakCPU,
                    tint: tint,
                    identifier: "cpu-sparkline",
                    label: "CPU 负载历史趋势图"
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var storageHealthCard: some View {
        let frac = model.volume.total > 0 ? Double(model.volume.used) / Double(model.volume.total) : 0
        let snapCount = model.apfsSnapshots?.snapshots.count ?? 0
        let alert = model.lowSpaceAlert
        let ringTint: Color = alert.isTriggered ? (alert.severity == .high ? DiskTheme.danger : .orange) : DiskTheme.purple
        return Surface {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("启动盘与快照状态", systemImage: "internaldrive.fill")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(ringTint)
                    Spacer()
                    Tag(
                        text: alert.isTriggered ? "低于 \(model.lowSpaceThresholdGiB) GiB" : "阈值 \(model.lowSpaceThresholdGiB) GiB 正常",
                        color: alert.isTriggered ? ringTint : DiskTheme.teal
                    )
                    Button {
                        model.showSnapshotsSheet = true
                    } label: {
                        Text("APFS 快照 (\(snapCount))")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .buttonStyle(DiskButtonStyle(kind: .quiet))
                }
                HStack(spacing: 16) {
                    gaugeRing(fraction: frac, label: "\(Int((frac * 100).rounded()))%", sub: "磁盘已用", tint: ringTint)
                    VStack(alignment: .leading, spacing: 5) {
                        kvRow("当前卷", model.selectedVolume?.name ?? "Macintosh HD")
                        kvRow("剩余可用", DiskFormat.bytes(model.volume.free))
                        kvRow("弹性可回收差额", DiskFormat.bytes(model.volume.purgeableGap))
                        kvRow("已挂载卷数量", "\(model.mountedVolumes.count) 个")
                    }
                }
                if alert.isTriggered {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(ringTint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(alert.headline)
                                .font(.system(size: 10.5, weight: .semibold))
                            Text("剩余 \(DiskFormat.bytes(alert.freeBytes)) · 差额 \(DiskFormat.bytes(alert.deficitBytes))（只读提醒）")
                                .font(.system(size: 9.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        Button("空间透镜") {
                            model.page = "overview"
                        }
                        .buttonStyle(DiskButtonStyle(kind: .quiet))
                        .controlSize(.small)
                        if !model.isExternalVolume {
                            Button("系统清理") {
                                model.page = "suggestions"
                            }
                            .buttonStyle(DiskButtonStyle(kind: .quiet))
                            .controlSize(.small)
                        }
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
                    .background(ringTint.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(ringTint.opacity(0.24), lineWidth: 1))
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10.5))
                            .foregroundStyle(DiskTheme.teal)
                        Text("低空间提醒阈值 \(model.lowSpaceThresholdGiB) GiB · 当前剩余空间充裕（只读监测）")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DiskTheme.inset, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var launchItemsLinkCard: some View {
        let items = model.protectionReport?.launchItems ?? []
        let thirdPartyCount = model.protectionReport?.thirdPartyLaunchCount ?? 0
        let userAgentsCount = items.filter { $0.scope == .userAgent }.count
        let systemAgentsCount = items.filter { $0.scope == .systemAgent }.count
        let systemDaemonsCount = items.filter { $0.scope == .systemDaemon }.count

        return Surface {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: "gearshape.2.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.primary)
                    Text("后台启动项详情联动")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .accessibilityIdentifier("performance-launch-link")
                    Tag(text: "纯只读元数据审计", color: palette.primary)
                    Spacer()
                    Button {
                        model.openProtectionLaunchItems()
                    } label: {
                        Label("前往安全保护查看启动项", systemImage: "checkmark.shield.fill")
                    }
                    .controlSize(.small)
                    .accessibilityIdentifier("performance-open-launch-items")
                }

                HStack(spacing: 8) {
                    launchCountPill(
                        title: "启动项总计",
                        value: "\(items.count) 项",
                        subtitle: "含第三方 \(thirdPartyCount) 项",
                        tint: palette.primary
                    )
                    launchCountPill(
                        title: "用户 LaunchAgents",
                        value: "\(userAgentsCount) 项",
                        subtitle: "~/Library/LaunchAgents",
                        tint: DiskTheme.accent
                    )
                    launchCountPill(
                        title: "系统 LaunchAgents",
                        value: "\(systemAgentsCount) 项",
                        subtitle: "系统级代理配置",
                        tint: DiskTheme.purple
                    )
                    launchCountPill(
                        title: "系统 LaunchDaemons",
                        value: "\(systemDaemonsCount) 项",
                        subtitle: "后台守护进程清单",
                        tint: DiskTheme.teal
                    )
                }

                Text("仅只读统计 LaunchAgents 与 LaunchDaemons 数量，绝不禁用、改写或删除任何系统启动项配置文件。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func telemetrySparklineBlock(
        sampleCount: Int,
        series: [Double],
        average: Double,
        peak: Double,
        tint: Color,
        identifier: String,
        label: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(sampleCount > 0 ? "近期走势 · \(sampleCount) 次采样" : "近期走势 · 等待采样")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("均值 \(Int((average * 100).rounded()))% · 峰值 \(Int((peak * 100).rounded()))%")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint)
            }
            TelemetrySparkline(series: series, tint: tint)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label)
                .accessibilityIdentifier(identifier)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(DiskTheme.inset, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func launchCountPill(title: String, value: String, subtitle: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
            Text(subtitle)
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DiskTheme.inset, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func networkCard(_ net: NetworkTelemetry?) -> some View {
        let tint = Color(light: 0x0284C7, dark: 0x38BDF8)
        return Surface {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("网络实时吞吐", systemImage: "network")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(tint)
                    Spacer()
                    Tag(text: "\(net?.activeInterfaces ?? 0) 个活跃接口", color: tint)
                }
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("↓ \(DiskFormat.bytes(net?.downloadBytesPerSec ?? 0))/s", systemImage: "arrow.down.circle.fill")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(tint)
                        Label("↑ \(DiskFormat.bytes(net?.uploadBytesPerSec ?? 0))/s", systemImage: "arrow.up.circle.fill")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .leading, spacing: 5) {
                        kvRow("累计接收", DiskFormat.bytes(Int64(clamping: net?.totalReceivedBytes ?? 0)))
                        kvRow("累计发送", DiskFormat.bytes(Int64(clamping: net?.totalSentBytes ?? 0)))
                    }
                    .frame(width: 155)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func powerCard(_ power: PowerTelemetry?) -> some View {
        let tint = Color(light: 0x16A34A, dark: 0x4ADE80)
        return Surface {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("电源与电池健康", systemImage: power?.hasBattery == true ? "battery.100percent.bolt" : "powerplug.fill")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(tint)
                    Spacer()
                    Tag(text: power?.statusLabel ?? "交流电源直连", color: tint)
                }
                Text(power?.hasBattery == true
                     ? "内置电池电量 \(power?.percentage ?? 100)%，实时通过 IOKit 只读检测供电状态。"
                     : "当前设备采用交流桌面电源直连供电，供电状态稳定。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var trashAndPrivacyCard: some View {
        let trashBytes = model.trashSummary?.allocated ?? 0
        let trashCount = model.trashSummary?.itemCount ?? 0
        return Surface {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("废纸篓与访问权限", systemImage: "trash.circle.fill")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.orange)
                    Spacer()
                    Tag(
                        text: model.fullDiskAccessGranted ? "完整磁盘访问已授权" : "隐私目录受限",
                        color: model.fullDiskAccessGranted ? DiskTheme.teal : .orange
                    )
                }
                Text(model.trashSummary?.readable == true
                     ? "个人废纸篓当前占 \(DiskFormat.bytes(trashBytes))（\(trashCount) 项）。AetherDisk 绝不会自动清空废纸篓。"
                     : "个人废纸篓受隐私权限保护暂未读取；可在系统设置中授权完整磁盘访问。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func gaugeRing(fraction: Double, label: String, sub: String, tint: Color) -> some View {
        let clamped = min(1.0, max(0.0, fraction))
        return ZStack {
            Circle().stroke(tint.opacity(0.14), lineWidth: 7)
            Circle()
                .trim(from: 0, to: CGFloat(clamped))
                .stroke(tint, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 1) {
                Text(label)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(sub)
                    .font(.system(size: 8.5))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 62, height: 62)
    }

    private func kvRow(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).foregroundStyle(.secondary)
            Spacer()
            Text(v).monospacedDigit().fontWeight(.medium)
        }
        .font(.system(size: 10.5))
    }
}

// MARK: - Smart Assistant Sheet

struct SmartAssistantSheet: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let summary = model.smartCareSummary
        DiskDialog(
            title: "AetherDisk 智能助手",
            subtitle: "健康指数 \(summary.healthScore) 分 · \(summary.statusTitle)",
            symbol: "sparkles.rectangle.stack"
        ) {
            Text("智能助手依据当前只读扫描与系统内核指标生成透明诊断，所有操作均需你亲自审阅确认。")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(summary.insights) { item in
                        let pal = ModuleStagePalette.forPage(item.targetPage)
                        HStack(alignment: .center, spacing: 12) {
                            ModuleIconBadge(
                                symbol: item.symbol,
                                primary: item.severity == .high ? DiskTheme.filledDanger : pal.primary,
                                secondary: item.severity == .high ? DiskTheme.danger : pal.secondary,
                                size: 30
                            )
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title)
                                    .font(.system(size: 12, weight: .semibold))
                                Text(item.detail)
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.secondary)
                                    .lineSpacing(2)
                            }
                            Spacer(minLength: 8)
                            Button(item.actionLabel) {
                                model.showAssistant = false
                                model.page = item.targetPage
                            }
                            .controlSize(.small)
                        }
                        .padding(10)
                        .background(DiskTheme.inset, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }
            .frame(maxHeight: 260)
        } actions: {
            Button("刷新诊断") {
                model.refreshSystemTelemetry()
                model.refreshApplications()
            }
            Spacer()
            Button("完成") {
                model.showAssistant = false
            }
            .buttonStyle(DiskButtonStyle(kind: .primary))
            .keyboardShortcut(.defaultAction)
        }
        .accessibilityIdentifier("smart-assistant-sheet")
    }
}

// MARK: - CleanMyMac Style MenuBarExtra Health Popover

struct MenuBarHealthPopoverView: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    private func bringMainWindowToFront() {
        NSApp.activate(ignoringOtherApps: true)
        if let win = NSApp.windows.first(where: { $0.frame.width >= 600 }) {
            win.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "main")
        }
    }

    var body: some View {
        let snap = model.systemHealth
        let summary = model.smartCareSummary
        let alert = model.lowSpaceAlert
        let alertTint: Color = alert.severity == .high ? DiskTheme.danger : .orange
        let memPct = snap.map { Int(($0.memory.usedFraction * 100).rounded()) } ?? 0
        let cpuPct = snap.map { Int(($0.cpu.usageFraction * 100).rounded()) } ?? 0
        let diskUsedPct = model.volume.total > 0 ? Int((Double(model.volume.used) / Double(model.volume.total) * 100).rounded()) : 0

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                BrandMark(size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text("AetherDisk 健康中心")
                        .font(.system(size: 13.5, weight: .bold, design: .rounded))
                    Text("\(snap?.hostModelLabel ?? "Mac") · 评分 \(summary.healthScore)")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    model.refreshSystemTelemetry()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(DiskButtonStyle(kind: .quiet))
                .controlSize(.small)
                .help("刷新实时状态")
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                menuTile(
                    title: "Macintosh HD",
                    value: "剩余 \(DiskFormat.bytes(model.volume.free))",
                    caption: alert.isTriggered ? "低于 \(model.lowSpaceThresholdGiB) GiB · 已用 \(diskUsedPct)%" : "已用 \(diskUsedPct)%",
                    symbol: alert.isTriggered ? "externaldrive.badge.exclamationmark" : "internaldrive.fill",
                    tint: alert.isTriggered ? alertTint : DiskTheme.accent
                ) {
                    model.page = "overview"
                    bringMainWindowToFront()
                }

                menuTile(
                    title: "内存压力",
                    value: "\(memPct)% 已用",
                    caption: snap.map { "可用 \(DiskFormat.bytes($0.memory.availableBytes))" } ?? "采样中",
                    symbol: "memorychip.fill",
                    tint: DiskTheme.teal
                ) {
                    model.page = "performance"
                    bringMainWindowToFront()
                }

                menuTile(
                    title: "CPU 与散热",
                    value: "负载 \(cpuPct)%",
                    caption: snap?.cpu.thermalLabel ?? "散热正常",
                    symbol: "cpu.fill",
                    tint: DiskTheme.purple
                ) {
                    model.page = "performance"
                    bringMainWindowToFront()
                }

                menuTile(
                    title: "电源状态",
                    value: snap?.power.percentage.map { "\($0)%" } ?? "AC 直连",
                    caption: snap?.power.statusLabel ?? "供电正常",
                    symbol: snap?.power.hasBattery == true ? "battery.100percent" : "powerplug.fill",
                    tint: .green
                ) {
                    model.page = "performance"
                    bringMainWindowToFront()
                }

                menuTile(
                    title: "实时网络",
                    value: "↓ \(DiskFormat.bytes(snap?.network.downloadBytesPerSec ?? 0))/s",
                    caption: "↑ \(DiskFormat.bytes(snap?.network.uploadBytesPerSec ?? 0))/s",
                    symbol: "network",
                    tint: .cyan
                ) {
                    model.page = "performance"
                    bringMainWindowToFront()
                }

                menuTile(
                    title: "可检缓存",
                    value: model.result == nil ? "待扫描" : DiskFormat.bytes(model.eligibleBytes),
                    caption: model.trashSummary?.readable == true ? "废纸篓 \(DiskFormat.bytes(model.trashSummary?.allocated ?? 0))" : "点击打开智能护理",
                    symbol: "sparkles",
                    tint: .pink
                ) {
                    model.page = "suggestions"
                    bringMainWindowToFront()
                }
            }

            if alert.isTriggered {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(alertTint)
                        Text(alert.headline)
                            .font(.system(size: 11, weight: .semibold))
                        Spacer()
                    }
                    Text("当前剩余 \(DiskFormat.bytes(alert.freeBytes))（低于阈值 \(DiskFormat.bytes(alert.deficitBytes))），仅作只读提醒。")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        Button("空间透镜") {
                            model.page = "overview"
                            bringMainWindowToFront()
                        }
                        .controlSize(.small)
                        if !model.isExternalVolume {
                            Button("系统清理") {
                                model.page = "suggestions"
                                bringMainWindowToFront()
                            }
                            .controlSize(.small)
                        }
                    }
                }
                .padding(9)
                .background(alertTint.opacity(0.10), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(alertTint.opacity(0.24), lineWidth: 1))
            }

            Divider().opacity(0.6)

            HStack(spacing: 8) {
                Button {
                    bringMainWindowToFront()
                } label: {
                    Label("打开 AetherDisk", systemImage: "macwindow")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.small)

                Button {
                    model.page = "smartcare"
                    bringMainWindowToFront()
                    if !model.scanning {
                        model.start()
                    }
                } label: {
                    Label("智能扫描", systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(DiskButtonStyle(kind: .primary))
                .controlSize(.small)
            }
        }
        .padding(14)
        .frame(width: 344)
        .background(DiskTheme.surface)
        .buttonStyle(DiskButtonStyle())
        .onAppear {
            model.refreshSystemTelemetry()
        }
    }

    private func menuTile(
        title: String,
        value: String,
        caption: String,
        symbol: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(tint)
                    Text(title)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                Text(value)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(caption)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DiskTheme.inset, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
