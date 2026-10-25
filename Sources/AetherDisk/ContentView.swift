import SwiftUI
import AetherDiskCore

struct ContentView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updater: AppUpdater
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 196)
            Rectangle().fill(DiskTheme.line).frame(width: 1)
            VStack(spacing: 0) {
                header.padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 14)
                Divider().opacity(0.6)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if let message = model.message {
                            HStack(alignment: .top) { Image(systemName: "info.circle.fill").foregroundStyle(DiskTheme.accent); Text(message).font(.system(size: 12)).textSelection(.enabled); Spacer(); Button { model.message = nil } label: { Image(systemName: "xmark") }.buttonStyle(DiskButtonStyle(kind: .quiet)) }
                                .padding(12).background(DiskTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        }
                        switch model.page {
                        case "large": LargeFilesPage(model: model)
                        case "types": FileTypesPage(model: model)
                        case "suggestions": suggestionsPage
                        case "changes": changesPage
                        case "settings": DiskSettings(updater: updater, model: model)
                        default: overview
                        }
                    }.padding(20)
                }
                footer.padding(.horizontal, 24).padding(.vertical, 11)
            }
        }
        .background(DiskTheme.background).tint(DiskTheme.accent).buttonStyle(DiskButtonStyle())
        .frame(minWidth: 1080, minHeight: 700)
        .sheet(item: $model.plan) { plan in confirmation(plan) }
        .sheet(isPresented: $model.showIssues) { ScanIssuesView(model: model) }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) { BrandMark(size: 35); VStack(alignment: .leading, spacing: 3) { Text("AetherDisk").font(.system(size: 17, weight: .semibold)); Text("看清每一寸空间").font(.system(size: 10)).foregroundStyle(.secondary) } }.padding(.bottom, 20)
            Text("工作空间").font(.system(size: 10, weight: .medium)).foregroundStyle(.tertiary).padding(.horizontal, 10).padding(.bottom, 8)
            nav("overview", "磁盘概览", "square.grid.2x2")
            nav("large", "大文件", "doc.text.magnifyingglass")
            nav("types", "文件类型", "chart.bar.xaxis")
            nav("suggestions", "清理建议", "sparkles", count: model.recommendations.count)
            nav("changes", "占用变化", "chart.line.uptrend.xyaxis")
            Text("快速扫描").font(.system(size: 10, weight: .medium)).foregroundStyle(.tertiary).padding(.horizontal, 10).padding(.top, 18).padding(.bottom, 8)
            location("个人文件夹", "house", FileManager.default.homeDirectoryForCurrentUser)
            location("下载", "arrow.down.circle", FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads"))
            location("文稿", "doc.text", FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents"))
            location("开发项目", "hammer", FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("IdeaProjects"))
            Button { model.chooseFolder() } label: { Label("选择文件夹…", systemImage: "folder.badge.plus").font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading).padding(10) }.buttonStyle(DiskSidebarButtonStyle()).foregroundStyle(.secondary).disabled(model.checking)
            Spacer()
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) { Image(systemName: "lock.shield").foregroundStyle(DiskTheme.accent); Text("文件留在你的 Mac").font(.system(size: 11, weight: .medium)) }
                Text("本机分析 · 确认后清理\n源码与安装包默认保护").font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(4)
                Divider().padding(.vertical, 3)
                HStack { Text("\(updater.version) · \(updater.releaseLabel)").font(.system(size: 10)).foregroundStyle(.tertiary); Spacer(); Button { model.page = "settings" } label: { Image(systemName: "gearshape").font(.system(size: 13)) }.buttonStyle(DiskButtonStyle(kind: .quiet)).help("设置与应用更新") }
            }.padding(.horizontal, 10)
        }.padding(.horizontal, 14).padding(.top, 34).padding(.bottom, 16).background(.regularMaterial)
    }
    private func nav(_ id: String, _ title: String, _ icon: String, count: Int = 0) -> some View {
        Button { model.page = id } label: {
            HStack(spacing: 10) { Image(systemName: icon).frame(width: 17); Text(title); Spacer(); if count > 0 { Text("\(count)").font(.system(size: 10, weight: .medium)).padding(.horizontal, 6).padding(.vertical, 2).background(DiskTheme.accent.opacity(0.1), in: Capsule()) } }
                .font(.system(size: 12, weight: model.page == id ? .semibold : .regular)).padding(.horizontal, 10).padding(.vertical, 8)
                .foregroundStyle(model.page == id ? DiskTheme.accent : Color.secondary)
                .background(model.page == id ? DiskTheme.accent.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(DiskSidebarButtonStyle()).accessibilityIdentifier("nav-" + id)
    }
    private func location(_ name: String, _ symbol: String, _ url: URL) -> some View {
        Button { model.page = "overview"; model.start(url) } label: { Label(name, systemImage: symbol).font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading).padding(10) }.buttonStyle(DiskSidebarButtonStyle()).foregroundStyle(.secondary).disabled(model.checking)
    }
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text(model.page == "large" ? "大文件，直接找到。" : model.page == "types" ? "空间，都用在哪。" : model.page == "settings" ? "设置与更新" : model.page == "suggestions" ? "让空间，轻一点。" : model.page == "changes" ? "变化，有迹可循。" : "磁盘空间，一目了然。").font(.system(size: 24, weight: .semibold))
                HStack(spacing: 6) { Image(systemName: "internaldrive"); Text(DiskFormat.compactPath(model.root.path)).lineLimit(1).truncationMode(.middle) }.font(.system(size: 11)).foregroundStyle(.secondary).help(model.root.path)
            }
            Spacer(minLength: 16)
            Button { model.exportReport() } label: { Image(systemName: "square.and.arrow.up") }.help("导出扫描报告").accessibilityLabel("导出扫描报告").disabled(model.result == nil || model.scanning || model.exporting)
            Button { model.chooseFolder() } label: { Label("选择文件夹", systemImage: "folder") }.controlSize(.regular).disabled(model.checking)
            if model.scanning {
                Button("停止扫描", role: .cancel) { model.cancel() }.controlSize(.regular)
            } else {
                Button { model.start() } label: { Label(model.result == nil ? "开始扫描" : "重新扫描", systemImage: "arrow.clockwise") }.buttonStyle(DiskButtonStyle(kind: .primary)).controlSize(.regular).disabled(model.checking).accessibilityIdentifier("scan")
            }
        }
    }
    private var overview: some View {
        VStack(spacing: 14) {
            storageCard
            HStack(spacing: 12) {
                metric("扫描占用", model.result.map { DiskFormat.bytes($0.allocated) } ?? (model.scanning ? DiskFormat.bytes(model.progress.allocated) : "尚未扫描"), "已分配大小", "square.stack.3d.up", DiskTheme.accent)
                metric("可检查缓存", DiskFormat.bytes(model.eligibleBytes), "\(model.eligible.count) 项 · 确认后处理", "sparkles", DiskTheme.purple)
                metric("默认保护", "\(model.recommendations.filter(\.blocked).count) 项", "源码、安装包与个人数据", "lock.shield", .teal)
            }
            if model.scanning { scanStatus }
            if model.result == nil && !model.scanning { emptyScan }
            else {
                HStack(alignment: .top, spacing: 16) {
                    Surface {
                        VStack(alignment: .leading, spacing: 10) {
                            PanelTitle(title: "占用排行", caption: "已分配大小")
                            HStack(spacing: 8) {
                                DiskSearchField(placeholder: "搜索当前层级", text: $model.query)
                                if model.root != FileManager.default.homeDirectoryForCurrentUser {
                                    Button { model.start(model.root.deletingLastPathComponent()) } label: { Image(systemName: "arrow.up") }.help("扫描上一级")
                                }
                            }
                            HStack { Text("文件夹 / 文件"); Spacer(); Text("占用 / 比例") }.font(.system(size: 10)).foregroundStyle(.tertiary)
                            if model.rows.isEmpty { Text(model.scanning ? "正在收集目录…" : "此目录没有可列出的文件，或访问受到限制。").font(.system(size: 12)).foregroundStyle(.secondary).padding(.vertical, 28) }
                            VStack(spacing: 2) {
                                ForEach(Array(model.rows.prefix(40).enumerated()), id: \.element.id) { index, node in diskRow(model.protectedNode(node), index: index) }
                            }
                        }
                    }.frame(maxWidth: .infinity)
                    VStack(spacing: 16) { inspector; recommendationSummary }.frame(width: 246)
                }
            }
        }
    }
    private var storageCard: some View {
        Surface {
            HStack(spacing: 20) {
                ZStack {
                    Circle().stroke(DiskTheme.accent.opacity(0.09), lineWidth: 8)
                    Circle().trim(from: 0, to: model.volume.total > 0 ? CGFloat(model.volume.used) / CGFloat(model.volume.total) : 0).stroke(AngularGradient(colors: [DiskTheme.accent, DiskTheme.purple], center: .center, startAngle: .degrees(0), endAngle: .degrees(360)), style: StrokeStyle(lineWidth: 8, lineCap: .round)).rotationEffect(.degrees(-90))
                    VStack(spacing: 1) { Text(model.volume.total > 0 ? "\(Int(Double(model.volume.used) / Double(model.volume.total) * 100))%" : "—").font(.system(size: 19, weight: .semibold, design: .rounded)); Text("已使用").font(.system(size: 9)).foregroundStyle(.secondary) }
                }.frame(width: 64, height: 64).padding(4)
                VStack(alignment: .leading, spacing: 12) {
                    HStack { VStack(alignment: .leading, spacing: 5) { Text("所选位置所在磁盘").font(.system(size: 11)).foregroundStyle(.secondary); Text("还有 \(DiskFormat.bytes(model.volume.free)) 可用").font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit() }; Spacer(); Tag(text: "本机实时容量", color: .teal) }
                    GeometryReader { g in ZStack(alignment: .leading) { Capsule().fill(DiskTheme.accent.opacity(0.09)); Capsule().fill(LinearGradient(colors: [DiskTheme.accent, DiskTheme.purple], startPoint: .leading, endPoint: .trailing)).frame(width: model.volume.total > 0 ? g.size.width * CGFloat(model.volume.used) / CGFloat(model.volume.total) : 0) } }.frame(height: 6)
                    HStack { Text("已用 \(DiskFormat.bytes(model.volume.used))"); Spacer(); Text("总容量 \(DiskFormat.bytes(model.volume.total))") }.font(.system(size: 10)).foregroundStyle(.secondary).monospacedDigit()
                }
            }
        }
    }
    private func metric(_ title: String, _ value: String, _ caption: String, _ icon: String, _ tint: Color) -> some View {
        Surface(padding: 12) { HStack(alignment: .top, spacing: 10) { Image(systemName: icon).font(.system(size: 15)).foregroundStyle(tint).frame(width: 28, height: 28).background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8)); VStack(alignment: .leading, spacing: 6) { Text(title).font(.system(size: 11)).foregroundStyle(.secondary); Text(value).font(.system(size: 20, weight: .semibold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.75); Text(caption).font(.system(size: 9)).foregroundStyle(.tertiary) }; Spacer(minLength: 0) }.frame(maxWidth: .infinity, alignment: .leading) }
    }
    private var scanStatus: some View {
        HStack(spacing: 12) { ProgressView().controlSize(.small); VStack(alignment: .leading, spacing: 4) { Text("正在扫描 · \(model.progress.files.formatted()) 个文件").font(.system(size: 12, weight: .medium)); Text(DiskFormat.compactPath(model.progress.currentPath)).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle) }; Spacer(); Text("可随时停止").font(.system(size: 10)).foregroundStyle(.secondary) }.padding(14).background(DiskTheme.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }
    private var emptyScan: some View {
        Surface {
            VStack(spacing: 16) {
                Image(systemName: "folder.badge.magnifyingglass").font(.system(size: 34, weight: .light)).foregroundStyle(DiskTheme.accent).padding(.top, 20)
                Text("从一个文件夹开始").font(.system(size: 18, weight: .semibold))
                Text("包含隐藏目录，逐层看清占用。\n扫描不读取文件内容，也不会修改你的文件。").font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(5)
                Button("扫描个人文件夹") { model.start(FileManager.default.homeDirectoryForCurrentUser) }.buttonStyle(DiskButtonStyle(kind: .primary))
                HStack(spacing: 24) { Label("源码保护", systemImage: "chevron.left.forwardslash.chevron.right"); Label("确认后清理", systemImage: "checkmark.shield"); Label("本地处理", systemImage: "lock") }.font(.system(size: 10)).foregroundStyle(.secondary).padding(.vertical, 20)
            }.frame(maxWidth: .infinity)
        }
    }
    private func diskRow(_ node: DiskNode, index: Int) -> some View {
        let fraction = min(1, Double(node.allocated) / Double(max(1, model.result?.allocated ?? model.progress.allocated)))
        return HStack(spacing: 10) {
            Image(systemName: node.kind == .directory ? "folder.fill" : "doc.fill").font(.system(size: 15)).foregroundStyle(DiskTheme.colors[index % DiskTheme.colors.count]).frame(width: 28, height: 28).background(DiskTheme.colors[index % DiskTheme.colors.count].opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 5) { HStack(spacing: 5) { Text(node.name).font(.system(size: 12, weight: .medium)).lineLimit(1); if node.restricted { Image(systemName: "lock").font(.system(size: 9)).foregroundStyle(.orange) } }; GeometryReader { g in Capsule().fill(DiskTheme.colors[index % DiskTheme.colors.count].opacity(0.65)).frame(width: max(2, g.size.width * fraction)) }.frame(height: 3) }.frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 4) { Text(DiskFormat.bytes(node.allocated)).font(.system(size: 12, weight: .medium, design: .rounded)).monospacedDigit(); Text(String(format: "%.1f%%", fraction * 100)).font(.system(size: 9)).foregroundStyle(.tertiary) }.frame(width: 75, alignment: .trailing)
            if node.kind == .directory { Button { model.start(URL(fileURLWithPath: node.path)) } label: { Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(.tertiary) }.buttonStyle(DiskButtonStyle(kind: .quiet)).help("扫描 \(node.name)").accessibilityLabel("扫描 \(node.name)") } else { Color.clear.frame(width: 6) }
        }.padding(.horizontal, 8).padding(.vertical, 5).background(model.selectedPath == node.path ? DiskTheme.accent.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 9))
            .contentShape(Rectangle()).onTapGesture { model.selectedPath = node.path }
            .contextMenu { Button("在 Finder 中显示") { model.reveal(node.path) }; if node.kind == .directory { Button("保护此目录") { model.addProtection(node.path) }.disabled(model.checking); Button("扫描此文件夹") { model.start(URL(fileURLWithPath: node.path)) } } }
    }
    private var inspector: some View {
        Surface {
            VStack(alignment: .leading, spacing: 14) {
                PanelTitle(title: "所选项目")
                if let node = model.selectedNode {
                    Image(systemName: node.kind == .directory ? "folder.fill" : "doc.fill").font(.system(size: 25)).foregroundStyle(DiskTheme.accent)
                    Text(node.name).font(.system(size: 15, weight: .semibold)).lineLimit(2)
                    Text(DiskFormat.compactPath(node.path)).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(3).truncationMode(.middle).textSelection(.enabled)
                    Divider()
                    detail("已分配", DiskFormat.bytes(node.allocated)); detail("逻辑大小", DiskFormat.bytes(node.logical)); detail("文件数", node.fileCount.formatted())
                    if let delta = model.delta(node) { detail("较上次", (delta >= 0 ? "+" : "−") + DiskFormat.bytes(delta)) }
                    if !node.protection.isEmpty { Text(node.protection.map(\.title).sorted().joined(separator: " · ")).font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(4) }
                    Button { model.reveal(node.path) } label: { Label("在 Finder 中显示", systemImage: "arrow.up.forward.app") }.font(.system(size: 11)).controlSize(.small)
                } else { Text("选择一项，查看大小和保护状态。").font(.system(size: 12)).foregroundStyle(.secondary).padding(.vertical, 20) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func detail(_ label: String, _ value: String) -> some View { HStack { Text(label).foregroundStyle(.secondary); Spacer(); Text(value).monospacedDigit() }.font(.system(size: 11)) }
    private var recommendationSummary: some View {
        Surface {
            VStack(alignment: .leading, spacing: 12) {
                HStack { Image(systemName: "sparkles").foregroundStyle(DiskTheme.purple); Text("留一点呼吸空间").font(.system(size: 12, weight: .semibold)) }
                Text(model.eligible.isEmpty ? "暂无明确可处理的缓存。重要文件会默认保留。" : "发现 \(model.eligible.count) 项缓存可进一步检查，目录占用约 \(DiskFormat.bytes(model.eligibleBytes))。").font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
                Button("查看清理建议 →") { model.page = "suggestions" }.buttonStyle(DiskButtonStyle(kind: .quiet)).font(.system(size: 11, weight: .medium)).foregroundStyle(DiskTheme.accent)
                Text("目录占用不等于可释放空间。").font(.system(size: 9)).foregroundStyle(.tertiary)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private var suggestionsPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) { metric("可进一步检查", DiskFormat.bytes(model.eligibleBytes), "\(model.eligible.count) 个候选目录", "sparkles", DiskTheme.purple); metric("已保护项目", "\(model.recommendations.filter(\.blocked).count) 项", "包含源码、安装包或个人数据", "lock.shield", .teal) }
            HStack(spacing: 9) { Image(systemName: "checkmark.shield").foregroundStyle(.teal); Text("先检查，后确认。清理只移入废纸篓，不会直接永久删除。").font(.system(size: 11)).foregroundStyle(.secondary) }
            Surface {
                VStack(spacing: 0) {
                    PanelTitle(title: "建议清单", caption: "默认不勾选").padding(.bottom, 12)
                    if model.recommendations.isEmpty { Text(model.result == nil ? "先扫描一个文件夹，建议会在这里出现。" : "此次扫描未发现符合规则的缓存目录。").font(.system(size: 12)).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 48) }
                    ForEach(model.recommendations) { r in
                        HStack(alignment: .top, spacing: 12) {
                            Toggle("选择 \(r.node.name)", isOn: Binding(get: { model.selectedCaches.contains(r.id) }, set: { if $0 { model.selectedCaches.insert(r.id) } else { model.selectedCaches.remove(r.id) } })).labelsHidden().toggleStyle(.checkbox).disabled(r.blocked || !model.fresh || model.scanning || model.checking).padding(.top, 4)
                            Image(systemName: r.blocked ? "lock.shield.fill" : "shippingbox").font(.system(size: 18)).foregroundStyle(r.blocked ? Color.teal : DiskTheme.purple).frame(width: 30).padding(.top, 3)
                            VStack(alignment: .leading, spacing: 6) {
                                HStack { Text(r.node.name).font(.system(size: 13, weight: .semibold)); Tag(text: r.blocked ? "已保护" : "需要确认", color: r.blocked ? .teal : DiskTheme.accent) }
                                Text(DiskFormat.compactPath(r.id)).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                                Text(r.blocked ? r.node.protection.map(\.title).sorted().joined(separator: " · ") : r.reason).font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 9) { Text(DiskFormat.bytes(r.node.allocated)).font(.system(size: 14, weight: .semibold, design: .rounded)); Button("查看位置") { model.reveal(r.id) }.buttonStyle(DiskButtonStyle(kind: .quiet)).font(.system(size: 10)).foregroundStyle(DiskTheme.accent) }
                        }.padding(.vertical, 16)
                        if r.id != model.recommendations.last?.id { Divider().opacity(0.65) }
                    }
                }
            }
            HStack {
                Text("已选择 \(model.selectedCaches.count) 项").font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                if model.checking { ProgressView().controlSize(.small) }
                Button { model.preview() } label: { Label("检查并预览", systemImage: "checkmark.shield") }.buttonStyle(DiskButtonStyle(kind: .primary)).disabled(model.selectedCaches.isEmpty || !model.fresh || model.checking || model.scanning).accessibilityIdentifier("preview-cleanup")
            }
            Text("检查会重新确认文件占用与目录内容。新发现的源码、Git 跟踪文件、安装包或符号链接会阻止清理。移入废纸篓不代表已释放空间。").font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(4)
        }
    }
    private var changesPage: some View {
        Surface {
            VStack(alignment: .leading, spacing: 16) {
                PanelTitle(title: "与上次扫描对比", caption: "相同目录 · 已分配大小")
                if (model.previous?.unreadable ?? 0) > 0 || (model.result?.unreadable ?? 0) > 0 {
                    Text("扫描存在权限遗漏；差异可能受到统计范围影响。").font(.system(size: 11)).foregroundStyle(.orange)
                }
                if model.previous == nil || model.previous?.root != model.result?.root {
                    Image(systemName: "chart.line.uptrend.xyaxis").font(.system(size: 32, weight: .light)).foregroundStyle(DiskTheme.accent).frame(maxWidth: .infinity).padding(.top, 36)
                    Text("再扫描一次，就能看见变化").font(.system(size: 17, weight: .semibold)).frame(maxWidth: .infinity)
                    Text("本次结果只保存在本机。下次扫描同一目录时，比较各项目的占用变化。").font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.bottom, 40)
                } else {
                    ForEach(model.changes, id: \.0.id) { node, delta in HStack { Image(systemName: node.kind == .directory ? "folder" : "doc").foregroundStyle(DiskTheme.accent); Text(node.name).font(.system(size: 12)); Spacer(); Text((delta > 0 ? "+" : delta < 0 ? "−" : "") + DiskFormat.bytes(delta)).font(.system(size: 13, weight: .medium, design: .rounded)).monospacedDigit().foregroundStyle(delta > 0 ? Color.orange : delta < 0 ? .teal : .secondary) }.padding(.vertical, 10); Divider() }
                }
            }
        }
    }
    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: model.result?.unreadable ?? 0 > 0 ? "exclamationmark.circle" : "checkmark.shield")
            if let r = model.result { Text(r.cancelled ? "扫描已停止 · 部分结果" : "\(r.files.formatted()) 个文件 · \(String(format: "%.1f", r.duration)) 秒"); if r.unreadable > 0 { Button("\(r.unreadable) 个路径未能读取") { model.showIssues = true }.buttonStyle(DiskButtonStyle(kind: .quiet)).foregroundStyle(.orange).help("查看未读取路径与权限说明") } }
            else { Text("只读扫描 · 不读取文件内容") }
            Spacer()
            Text("APFS 共享数据可能使目录占用高于实际可释放空间").lineLimit(1)
        }.font(.system(size: 9)).foregroundStyle(.secondary)
    }
    private func confirmation(_ plan: CleanupPlan) -> some View {
        DiskDialog(title: "确认移入废纸篓？", subtitle: "\(plan.targets.count) 项 · 目录占用 \(DiskFormat.bytes(plan.allocated))", symbol: "trash", destructive: true) {
            Text("已检查源码、安装包、链接及文件占用。执行前会再次校验；检测到目录变化会停止清理。")
                .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
            ScrollView { VStack(alignment: .leading, spacing: 12) { ForEach(plan.targets) { target in HStack(alignment: .top) { Image(systemName: "folder").foregroundStyle(DiskTheme.accent); Text(target.path).font(.system(size: 11)).textSelection(.enabled); Spacer(); Text(DiskFormat.bytes(target.allocated)).font(.system(size: 11)).monospacedDigit() } } }.frame(maxWidth: .infinity, alignment: .leading).padding(12) }.frame(maxHeight: 170).background(DiskTheme.inset, in: RoundedRectangle(cornerRadius: DiskTheme.controlRadius))
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
