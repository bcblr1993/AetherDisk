import SwiftUI
import UniformTypeIdentifiers
import AetherDiskCore

struct ContentView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updater: AppUpdater
    @State private var isDropTargeted = false

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 204)
            Rectangle().fill(DiskTheme.line).frame(width: 1)
            VStack(spacing: 0) {
                header.padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 14)
                Divider().opacity(0.6)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if let message = model.message {
                            HStack(alignment: .top) {
                                Image(systemName: "info.circle.fill").foregroundStyle(DiskTheme.accent)
                                Text(message).font(.system(size: 12)).textSelection(.enabled)
                                Spacer()
                                Button { model.message = nil } label: { Image(systemName: "xmark") }
                                    .buttonStyle(DiskButtonStyle(kind: .quiet))
                            }
                            .padding(12)
                            .background(DiskTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        }
                        switch model.page {
                        case "large": LargeFilesPage(model: model)
                        case "types": FileTypesPage(model: model)
                        case "projects": ProjectsPage(model: model)
                        case "suggestions":
                            if model.isExternalVolume {
                                externalVolumeReadOnlyCard
                            } else {
                                SuggestionsPage(model: model)
                            }
                        case "changes": ChangesPage(model: model)
                        case "settings": DiskSettings(updater: updater, model: model)
                        default: OverviewView(model: model)
                        }
                    }.padding(20)
                }
                footer.padding(.horizontal, 24).padding(.vertical, 11)
            }
        }
        .background(DiskTheme.background).tint(DiskTheme.accent).buttonStyle(DiskButtonStyle())
        .frame(minWidth: 1100, minHeight: 720)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(DiskTheme.accent, style: StrokeStyle(lineWidth: 2, dash: [8, 5]))
                    .background(DiskTheme.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(alignment: .center) {
                        Label("松开以只读扫描该文件夹", systemImage: "folder.badge.magnifyingglass")
                            .font(.system(size: 14, weight: .semibold))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(DiskTheme.surface, in: Capsule())
                            .overlay(Capsule().stroke(DiskTheme.accent.opacity(0.35), lineWidth: 1))
                            .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
                    }
                    .padding(10)
                    .allowsHitTesting(false)
            }
        }
        .sheet(item: $model.plan) { plan in confirmation(plan) }
        .sheet(isPresented: $model.showIssues) { ScanIssuesView(model: model) }
        .sheet(isPresented: $model.showSnapshotsSheet) { APFSSnapshotsSheet(model: model) }
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

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                BrandMark(size: 35)
                VStack(alignment: .leading, spacing: 3) {
                    Text("AetherDisk").font(.system(size: 17, weight: .semibold))
                    Text("看清每一寸空间").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }.padding(.bottom, 16)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("工作空间")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 6)
                    nav("overview", "磁盘概览", "square.grid.2x2")
                    nav("large", "大文件", "doc.text.magnifyingglass")
                    nav("types", "文件类型", "chart.bar.xaxis")
                    nav("projects", "工程洞察", "hammer.circle", count: model.result?.analysis?.projects.count ?? 0)
                    nav("suggestions", "清理建议", "sparkles", count: model.recommendations.count)
                        .disabled(model.isExternalVolume)
                    nav("changes", "占用变化", "chart.line.uptrend.xyaxis")

                    if !model.mountedVolumes.isEmpty {
                        Text("挂载卷")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 10)
                            .padding(.top, 14)
                            .padding(.bottom, 6)
                        VStack(spacing: 3) {
                            ForEach(Array(model.mountedVolumes.prefix(4))) { vol in
                                volumeRow(vol)
                            }
                        }
                        .accessibilityIdentifier("volume-switcher")
                    }

                    Text("快速扫描")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 10)
                        .padding(.top, 14)
                        .padding(.bottom, 6)
                    location("个人文件夹", "house", FileManager.default.homeDirectoryForCurrentUser)
                    location("下载", "arrow.down.circle", FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads"))
                    location("文稿", "doc.text", FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents"))
                    location("开发项目", "hammer", FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("IdeaProjects"))
                    Button { model.chooseFolder() } label: {
                        HStack(spacing: 10) { Image(systemName: "folder.badge.plus").frame(width: 17); Text("选择文件夹…"); Spacer() }
                            .font(.system(size: 12))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(RoundedRectangle(cornerRadius: 9))
                    }
                    .buttonStyle(DiskSidebarButtonStyle())
                    .foregroundStyle(.secondary)
                    .disabled(model.checking)
                }
            }

            Spacer(minLength: 10)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    Image(systemName: "lock.shield").foregroundStyle(DiskTheme.accent)
                    Text("文件留在你的 Mac").font(.system(size: 11, weight: .medium))
                }
                Text("本机分析 · 确认后清理\n源码与安装包默认保护")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
                Divider().padding(.vertical, 3)
                HStack {
                    Text("\(updater.version) · \(updater.releaseLabel)")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button { model.page = "settings" } label: {
                        Image(systemName: "gearshape").font(.system(size: 13))
                    }
                    .buttonStyle(DiskButtonStyle(kind: .quiet))
                    .help("设置与应用更新")
                }
            }.padding(.horizontal, 10)
        }
        .padding(.horizontal, 14)
        .padding(.top, 34)
        .padding(.bottom, 16)
        .background(.regularMaterial)
    }

    private func volumeRow(_ vol: VolumeDescriptor) -> some View {
        let isActive = model.selectedVolume?.path == vol.path
        let usedFraction = vol.space.total > 0 ? min(1, max(0, Double(vol.space.used) / Double(vol.space.total))) : 0
        return Button {
            model.page = "overview"
            model.start(URL(fileURLWithPath: vol.path))
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Image(systemName: vol.isExternal ? "externaldrive" : "internaldrive")
                        .font(.system(size: 11))
                        .frame(width: 15)
                    Text(vol.name)
                        .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if vol.isExternal {
                        Text("外置")
                            .font(.system(size: 8, weight: .medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .foregroundStyle(.orange)
                            .background(Color.orange.opacity(0.12), in: Capsule())
                    }
                }
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.08))
                        Capsule()
                            .fill(vol.isExternal ? Color.orange.opacity(0.8) : DiskTheme.accent.opacity(0.8))
                            .frame(width: max(2, g.size.width * CGFloat(usedFraction)))
                    }
                }
                .frame(height: 3)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(isActive ? DiskTheme.accent : Color.secondary)
            .background(isActive ? DiskTheme.accent.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 9))
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(DiskSidebarButtonStyle())
        .disabled(model.checking)
        .help("\(vol.name) · 剩余 \(DiskFormat.bytes(vol.space.free))")
    }

    private func nav(_ id: String, _ title: String, _ icon: String, count: Int = 0) -> some View {
        Button { model.page = id } label: {
            HStack(spacing: 10) {
                Image(systemName: icon).frame(width: 17)
                Text(title)
                Spacer()
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(DiskTheme.accent.opacity(0.1), in: Capsule())
                }
            }
            .font(.system(size: 12, weight: model.page == id ? .semibold : .regular))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(model.page == id ? DiskTheme.accent : Color.secondary)
            .background(model.page == id ? DiskTheme.accent.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 9))
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(DiskSidebarButtonStyle()).accessibilityIdentifier("nav-" + id)
    }

    private func location(_ name: String, _ symbol: String, _ url: URL) -> some View {
        Button { model.page = "overview"; model.start(url) } label: {
            HStack(spacing: 10) { Image(systemName: symbol).frame(width: 17); Text(name); Spacer() }
                .font(.system(size: 12))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(DiskSidebarButtonStyle()).foregroundStyle(.secondary).disabled(model.checking)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text(
                    model.page == "large" ? "大文件，直接找到。" :
                    model.page == "types" ? "空间，都用在哪。" :
                    model.page == "projects" ? "工程占用，一眼看透。" :
                    model.page == "settings" ? "设置与更新" :
                    model.page == "suggestions" ? "让空间，轻一点。" :
                    model.page == "changes" ? "变化，有迹可循。" :
                    "磁盘空间，一目了然。"
                ).font(.system(size: 24, weight: .semibold))
                HStack(spacing: 6) {
                    Image(systemName: model.isExternalVolume ? "externaldrive" : "internaldrive")
                    Text(DiskFormat.compactPath(model.root.path)).lineLimit(1).truncationMode(.middle)
                    if model.isExternalVolume {
                        Tag(text: "外部卷 · 仅只读分析", color: .orange)
                    }
                }.font(.system(size: 11)).foregroundStyle(.secondary).help(model.root.path)
            }
            Spacer(minLength: 16)
            Button { model.exportReport() } label: { Image(systemName: "square.and.arrow.up") }
                .help("导出扫描报告")
                .accessibilityLabel("导出扫描报告")
                .disabled(model.result == nil || model.scanning || model.exporting)
            Button { model.chooseFolder() } label: { Label("选择文件夹", systemImage: "folder") }
                .controlSize(.regular)
                .disabled(model.checking)
            if model.scanning {
                Button("停止扫描", role: .cancel) { model.cancel() }.controlSize(.regular)
            } else {
                Button { model.start() } label: { Label(model.result == nil ? "开始扫描" : "重新扫描", systemImage: "arrow.clockwise") }
                    .buttonStyle(DiskButtonStyle(kind: .primary))
                    .controlSize(.regular)
                    .disabled(model.checking)
                    .keyboardShortcut("r", modifiers: .command)
                    .accessibilityIdentifier("scan")
            }
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
                        Text("外部卷 · 仅只读分析").font(.system(size: 16, weight: .semibold))
                        Text("当前扫描路径位于外部存储卷（\(model.selectedVolume?.name ?? DiskFormat.compactPath(model.root.path))）。")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                Text("为保护外部存储介质中的数据安全，AetherDisk 对外部卷严禁提供清理建议、预览确认或移入废纸篓入口。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
                Button("返回磁盘概览") { model.page = "overview" }
                    .buttonStyle(DiskButtonStyle(kind: .primary))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: model.result?.unreadable ?? 0 > 0 ? "exclamationmark.circle" : "checkmark.shield")
            if let r = model.result {
                Text(r.cancelled ? "扫描已停止 · 部分结果" : "\(r.files.formatted()) 个文件 · \(String(format: "%.1f", r.duration)) 秒")
                if r.unreadable > 0 {
                    Button("\(r.unreadable) 个路径未能读取") { model.showIssues = true }
                        .buttonStyle(DiskButtonStyle(kind: .quiet))
                        .foregroundStyle(.orange)
                        .help("查看未读取路径与权限说明")
                }
            } else {
                Text("只读扫描 · 不读取文件内容")
            }
            Text("· \(model.scanProfile.title)").foregroundStyle(.tertiary)
            Spacer()
            Text("APFS 共享数据可能使目录占用高于实际可释放空间").lineLimit(1)
        }.font(.system(size: 9)).foregroundStyle(.secondary)
    }

    private func confirmation(_ plan: CleanupPlan) -> some View {
        DiskDialog(title: "确认移入废纸篓？", subtitle: "\(plan.targets.count) 项 · 目录占用 \(DiskFormat.bytes(plan.allocated))", symbol: "trash", destructive: true) {
            Text("已检查源码、安装包、链接及文件占用。执行前会再次校验；检测到目录变化会停止清理。")
                .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(plan.targets) { target in
                        HStack(alignment: .top) {
                            Image(systemName: "folder").foregroundStyle(DiskTheme.accent)
                            Text(target.path).font(.system(size: 11)).textSelection(.enabled)
                            Spacer()
                            Text(DiskFormat.bytes(target.allocated)).font(.system(size: 11)).monospacedDigit()
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
            }.frame(maxHeight: 170).background(DiskTheme.inset, in: RoundedRectangle(cornerRadius: DiskTheme.controlRadius))
            Label("清空废纸篓后才会释放空间。可先从废纸篓还原。", systemImage: "arrow.uturn.backward").font(.system(size: 11)).foregroundStyle(.secondary)
            CleanupRiskNotice()
        } actions: {
            Spacer()
            Button("保留文件", role: .cancel) { model.plan = nil }.keyboardShortcut(.cancelAction)
            Button("确认移入废纸篓", role: .destructive) { model.confirm() }
                .buttonStyle(DiskButtonStyle(kind: .primary)).accessibilityIdentifier("confirm-trash")
        }
    }
}
