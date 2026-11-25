import SwiftUI
import UniformTypeIdentifiers
import AetherDiskCore

struct ContentView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updater: AppUpdater
    @State private var isDropTargeted = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var palette: ModuleStagePalette {
        model.currentStagePalette
    }

    private var effectiveReduceMotion: Bool {
        reduceMotion || ProcessInfo.processInfo.environment["AETHERDISK_QA"] == "1"
    }

    private var primaryOrbLabel: String {
        if model.result != nil { return "重扫" }
        return model.page == "smartcare" ? "智能扫描" : "扫描"
    }

    @ViewBuilder
    private var activeModuleView: some View {
        switch model.page {
        case "smartcare":
            SmartCareView(model: model)
        case "suggestions":
            if model.isExternalVolume {
                externalVolumeReadOnlyCard
            } else {
                SuggestionsPage(model: model)
            }
        case "protection":
            ProtectionView(model: model)
        case "performance":
            PerformanceHealthView(model: model)
        case "applications":
            ApplicationsView(model: model)
        case "large":
            LargeFilesPage(model: model)
        case "overview":
            OverviewView(model: model)
        case "projects":
            ProjectsPage(model: model)
        case "types":
            FileTypesPage(model: model)
        case "changes":
            ChangesPage(model: model)
        case "settings":
            DiskSettings(updater: updater, model: model)
        default:
            SmartCareView(model: model)
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            floatingSidebar
                .frame(width: 234)
                .padding(.leading, 10)
                .padding(.top, 10)
                .padding(.bottom, 10)

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 22)
                    .padding(.top, 20)
                    .padding(.bottom, 10)

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if let message = model.message {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "info.circle.fill")
                                    .foregroundStyle(palette.primary)
                                Text(message)
                                    .font(.system(size: 12))
                                    .textSelection(.enabled)
                                Spacer()
                                Button { model.message = nil } label: {
                                    Image(systemName: "xmark")
                                }
                                .buttonStyle(DiskButtonStyle(kind: .quiet))
                            }
                            .padding(12)
                            .background(palette.primary.opacity(0.11), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(palette.primary.opacity(0.24), lineWidth: 1)
                            )
                        }

                        if model.scanning && model.page != "smartcare" && model.page != "overview" {
                            OrbitalScanningBanner(palette: palette, progress: model.progress)
                        }

                        ZStack(alignment: .topLeading) {
                            activeModuleView
                                .transition(effectiveReduceMotion ? .identity : .opacity)
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .animation(DiskMotion.transition(reduceMotion: effectiveReduceMotion), value: model.page)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                    .padding(.bottom, 12)
                }

                CircularActionOrbBar(
                    palette: palette,
                    scanning: model.scanning,
                    checking: model.checking,
                    hasResult: model.result != nil,
                    cancelled: model.result?.cancelled == true,
                    filesCount: model.result?.files ?? model.progress.files,
                    duration: model.result?.duration ?? 0,
                    unreadableCount: model.result?.unreadable ?? 0,
                    scanProfileTitle: model.scanProfile.title,
                    primaryOrbLabel: primaryOrbLabel,
                    onScan: { model.start() },
                    onCancel: { model.cancel() },
                    onShowIssues: { model.showIssues = true }
                )
            }
        }
        .background(StageBackground(palette: palette))
        .tint(DiskTheme.accent)
        .buttonStyle(DiskButtonStyle())
        .frame(minWidth: 1180, minHeight: 760)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(palette.primary, style: StrokeStyle(lineWidth: 2, dash: [8, 5]))
                    .background(palette.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(alignment: .center) {
                        Label("松开以只读扫描该文件夹", systemImage: "folder.badge.magnifyingglass")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(DiskTheme.surface, in: Capsule())
                            .overlay(Capsule().stroke(palette.primary.opacity(0.35), lineWidth: 1))
                            .shadow(color: .black.opacity(0.14), radius: 12, y: 4)
                    }
                    .padding(12)
                    .allowsHitTesting(false)
            }
        }
        .sheet(item: $model.plan) { plan in confirmation(plan) }
        .sheet(isPresented: $model.showIssues) { ScanIssuesView(model: model) }
        .sheet(isPresented: $model.showSnapshotsSheet) { APFSSnapshotsSheet(model: model) }
        .sheet(isPresented: $model.showAssistant) { SmartAssistantSheet(model: model) }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !model.checking,
              let provider = providers.first,
              provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else {
            return false
        }
        let targetModel = model
        provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
            guard let data,
                  let rawURL = URL(dataRepresentation: data, relativeTo: nil)
                    ?? String(data: data, encoding: .utf8).flatMap({
                        URL(string: $0.trimmingCharacters(in: .whitespacesAndNewlines))
                    }) else {
                return
            }
            let nsURL = rawURL as NSURL
            let resolved = nsURL.isFileReferenceURL() ? (nsURL.filePathURL ?? rawURL) : rawURL
            Task { @MainActor in
                _ = targetModel.handleDroppedURLs([resolved])
            }
        }
        return true
    }

    // MARK: - CleanMyMac 5 Floating Inset Glass Sidebar (1:1 Module Order)

    private var floatingSidebar: some View {
        let summary = model.smartCareSummary
        let sidebarFill: AnyShapeStyle = reduceTransparency
            ? AnyShapeStyle(DiskTheme.sidebarTint)
            : AnyShapeStyle(.ultraThinMaterial)
        let sidebarStroke: AnyShapeStyle = reduceTransparency
            ? AnyShapeStyle(DiskTheme.strongLine)
            : AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color.white.opacity(colorScheme == .dark ? 0.14 : 0.78),
                        DiskTheme.line
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                BrandMark(size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text("AetherDisk")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text("Mac 空间与健康护理")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)

            // CleanMyMac Top Assistant Health Pill
            Button {
                model.showAssistant = true
            } label: {
                HStack(spacing: 7) {
                    Circle()
                        .fill(summary.healthScore >= 85 ? Color.green : Color.orange)
                        .frame(width: 7, height: 7)
                    Text("智能助手")
                        .font(.system(size: 11.5, weight: .semibold))
                    Spacer()
                    Text("\(summary.healthScore) 分 · \(summary.insights.count) 建议")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(palette.primary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    palette.primary.opacity(reduceTransparency ? 0.16 : 0.10),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(palette.primary.opacity(reduceTransparency ? 0.42 : 0.22), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 4)
            .padding(.bottom, 8)
            .accessibilityIdentifier("assistant-button")
            .help("打开智能健康报告与护理建议")

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 1.5) {
                    // CleanMyMac 5 Exact 7 Core Modules
                    sidebarGroupLabel("核心护理", topPadding: 0)
                    nav("smartcare", "智能护理")
                    nav("suggestions", "系统清理", count: model.recommendations.count)
                        .disabled(model.isExternalVolume)
                    nav("protection", "安全保护", count: model.protectionReport?.thirdPartyLaunchCount ?? 0)
                    nav("performance", "性能优化")
                    nav("applications", "应用管理", count: model.appsReport?.apps.count ?? 0)
                    nav("large", "我的杂物", count: model.result?.analysis?.largeFiles.count ?? 0)
                    nav("overview", "空间透镜")

                    // CleanMyMac My Tools Auxiliary Suite
                    sidebarGroupLabel("实用工具", topPadding: 7)
                    nav("projects", "工程洞察", count: model.result?.analysis?.projects.count ?? 0)
                    nav("types", "文件类型")
                    nav("changes", "占用变化")

                    if !model.mountedVolumes.isEmpty {
                        sidebarGroupLabel("挂载卷", topPadding: 7)
                        VStack(spacing: 2.5) {
                            ForEach(Array(model.mountedVolumes.prefix(2))) { vol in
                                volumeRow(vol)
                            }
                        }
                        .accessibilityIdentifier("volume-switcher")
                    }

                    sidebarGroupLabel("快速扫描", topPadding: 7)
                    HStack(spacing: 4) {
                        compactLocation("个人文件夹", "house.fill", FileManager.default.homeDirectoryForCurrentUser)
                        compactLocation("下载", "arrow.down.circle.fill", FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads"))
                    }
                    HStack(spacing: 4) {
                        compactLocation("文稿", "doc.text.fill", FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents"))
                        compactLocation("开发项目", "hammer.fill", FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("IdeaProjects"))
                    }
                    Button { model.chooseFolder() } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "folder.badge.plus").font(.system(size: 10)).frame(width: 15)
                            Text("选择文件夹…")
                            Spacer()
                        }
                        .font(.system(size: 10.5))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(DiskSidebarButtonStyle())
                    .foregroundStyle(.secondary)
                    .disabled(model.checking)
                }
            }

            Spacer(minLength: 4)
            VStack(alignment: .leading, spacing: 5) {
                Divider().opacity(0.5)
                HStack(spacing: 5) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(DiskTheme.teal)
                    Text("只读扫描 · 确认后废纸篓")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                HStack {
                    Text("\(updater.version) · \(updater.releaseLabel)")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button { model.page = "settings" } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 12.5))
                    }
                    .buttonStyle(DiskButtonStyle(kind: .quiet))
                    .help("设置与应用更新")
                    .accessibilityLabel("设置与应用更新")
                }
            }
            .padding(.horizontal, 6)
            .padding(.top, 4)
        }
        .padding(.horizontal, 10)
        .padding(.top, 26)
        .padding(.bottom, 10)
        .background(
            sidebarFill,
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(sidebarStroke, lineWidth: 1)
        )
        .shadow(
            color: Color.black.opacity(colorScheme == .dark ? 0.28 : 0.06),
            radius: 14,
            y: 4
        )
    }

    private func sidebarGroupLabel(_ title: String, topPadding: CGFloat) -> some View {
        Text(title)
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 8)
            .padding(.top, topPadding)
            .padding(.bottom, 2)
    }

    private func nav(_ id: String, _ title: String, count: Int = 0) -> some View {
        let itemPalette = ModuleStagePalette.forPage(id)
        let selected = model.page == id
        return Button { model.page = id } label: {
            HStack(spacing: 8) {
                ModuleIconBadge(
                    symbol: itemPalette.symbol,
                    primary: itemPalette.primary,
                    secondary: itemPalette.secondary,
                    size: 21
                )
                Text(title)
                    .font(.system(size: 12, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
                Spacer(minLength: 4)
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .padding(.horizontal, 5.5)
                        .padding(.vertical, 1.5)
                        .foregroundStyle(selected ? itemPalette.primary : .secondary)
                        .background(
                            (selected ? itemPalette.primary : Color.primary).opacity(0.10),
                            in: Capsule()
                        )
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3.5)
            .background(
                selected ? itemPalette.primary.opacity(reduceTransparency ? 0.20 : 0.14) : .clear,
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(selected ? itemPalette.primary.opacity(reduceTransparency ? 0.45 : 0.28) : .clear, lineWidth: 1)
            )
            .animation(DiskMotion.subtle(reduceMotion: effectiveReduceMotion), value: selected)
        }
        .buttonStyle(DiskSidebarButtonStyle())
        .accessibilityIdentifier("nav-" + id)
    }

    private func volumeRow(_ vol: VolumeDescriptor) -> some View {
        let isActive = model.selectedVolume?.path == vol.path
        let usedFraction = vol.space.total > 0 ? min(1, max(0, Double(vol.space.used) / Double(vol.space.total))) : 0
        return Button {
            if ["settings", "applications", "performance", "protection"].contains(model.page) {
                model.page = "overview"
            }
            model.start(URL(fileURLWithPath: vol.path))
        } label: {
            VStack(alignment: .leading, spacing: 3.5) {
                HStack(spacing: 6) {
                    Image(systemName: vol.isExternal ? "externaldrive.fill" : "internaldrive.fill")
                        .font(.system(size: 10))
                        .frame(width: 14)
                    Text(vol.name)
                        .font(.system(size: 10.5, weight: isActive ? .semibold : .regular))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if vol.isExternal {
                        Text("外置")
                            .font(.system(size: 8, weight: .semibold))
                            .padding(.horizontal, 4.5)
                            .padding(.vertical, 1)
                            .foregroundStyle(.orange)
                            .background(Color.orange.opacity(0.14), in: Capsule())
                    }
                }
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.08))
                        Capsule()
                            .fill(vol.isExternal ? Color.orange.opacity(0.85) : DiskTheme.accent.opacity(0.85))
                            .frame(width: max(2, g.size.width * CGFloat(usedFraction)))
                    }
                }
                .frame(height: 2.5)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4.5)
            .foregroundStyle(isActive ? DiskTheme.accent : Color.secondary)
            .background(isActive ? DiskTheme.accent.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(DiskSidebarButtonStyle())
        .disabled(model.checking)
        .help("\(vol.name) · 剩余 \(DiskFormat.bytes(vol.space.free))")
    }

    private func compactLocation(_ name: String, _ symbol: String, _ url: URL) -> some View {
        Button {
            if ["settings", "applications", "performance", "protection"].contains(model.page) {
                model.page = "overview"
            }
            model.start(url)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 9.5))
                Text(name).lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(.system(size: 10))
            .padding(.horizontal, 6.5)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(DiskSidebarButtonStyle())
        .foregroundStyle(.secondary)
        .disabled(model.checking)
    }

    private var header: some View {
        HStack(spacing: 12) {
            ModuleIconBadge(
                symbol: palette.symbol,
                primary: palette.primary,
                secondary: palette.secondary,
                size: 36
            )
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(palette.title)
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                    Text(palette.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    Image(systemName: model.isExternalVolume ? "externaldrive.fill" : "internaldrive.fill")
                        .font(.system(size: 9.5))
                        .foregroundStyle(palette.primary)
                    Text(DiskFormat.compactPath(model.root.path))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if model.isExternalVolume {
                        Tag(text: "外部卷 · 仅只读分析", color: .orange)
                    }
                }
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .help(model.root.path)
            }

            Spacer(minLength: 12)

            Button { model.exportReport() } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .help("导出扫描报告")
            .accessibilityLabel("导出扫描报告")
            .disabled(model.result == nil || model.scanning || model.exporting)

            Button { model.chooseFolder() } label: {
                Label("选择文件夹", systemImage: "folder")
            }
            .controlSize(.regular)
            .disabled(model.checking)
        }
    }

    private var externalVolumeReadOnlyCard: some View {
        Surface {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "externaldrive.badge.checkmark")
                        .font(.system(size: 24))
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("外部卷 · 仅只读分析").font(.system(size: 16, weight: .semibold, design: .rounded))
                        Text("当前扫描路径位于外部存储卷（\(model.selectedVolume?.name ?? DiskFormat.compactPath(model.root.path))）。")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                Text("为保护外部存储介质中的数据安全，AetherDisk 对外部卷严禁提供清理建议、预览确认或移入废纸篓入口。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
                Button("前往空间透镜") { model.page = "overview" }
                    .buttonStyle(DiskButtonStyle(kind: .primary))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func confirmation(_ plan: CleanupPlan) -> some View {
        DiskDialog(
            title: "确认移入废纸篓？",
            subtitle: "\(plan.targets.count) 项 · 目录占用 \(DiskFormat.bytes(plan.allocated))",
            symbol: "trash.fill",
            destructive: true
        ) {
            Text("已检查源码、安装包、链接及文件占用。执行前会再次校验；检测到目录变化会停止清理。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineSpacing(4)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(plan.targets) { target in
                        HStack(alignment: .top) {
                            Image(systemName: "folder.fill").foregroundStyle(DiskTheme.accent)
                            Text(target.path).font(.system(size: 11)).textSelection(.enabled)
                            Spacer()
                            Text(DiskFormat.bytes(target.allocated)).font(.system(size: 11)).monospacedDigit()
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }
            .frame(maxHeight: 170)
            .background(DiskTheme.inset, in: RoundedRectangle(cornerRadius: DiskTheme.controlRadius, style: .continuous))
            Label("清空废纸篓后才会释放空间。可先从废纸篓还原。", systemImage: "arrow.uturn.backward")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            CleanupRiskNotice()
        } actions: {
            Spacer()
            Button("保留文件", role: .cancel) { model.plan = nil }.keyboardShortcut(.cancelAction)
            Button("确认移入废纸篓", role: .destructive) { model.confirm() }
                .buttonStyle(DiskButtonStyle(kind: .primary))
                .accessibilityIdentifier("confirm-trash")
        }
    }
}
