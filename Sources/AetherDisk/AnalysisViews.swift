import SwiftUI
import AetherDiskCore

struct LargeFilesPage: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Surface { VStack(alignment: .leading, spacing: 14) {
                PanelTitle(title: "跨目录大文件排行", caption: "只查看 · 不提供批量删除")
                HStack(spacing: 12) {
                    DiskSearchField(placeholder: "搜索文件名或路径", text: $model.largeQuery, identifier: "large-search")
                    Picker("大小", selection: $model.largeBasis) { ForEach(SizeBasis.allCases) { basis in Text(basis.title).tag(basis) } }.frame(width: 150).accessibilityIdentifier("large-basis")
                    Picker("至少", selection: $model.largeMinimum) {
                        Text("1 MiB").tag(Int64(1024 * 1024)); Text("10 MiB").tag(Int64(10 * 1024 * 1024))
                        Text("100 MiB").tag(Int64(100 * 1024 * 1024)); Text("1 GiB").tag(Int64(1024 * 1024 * 1024))
                    }.frame(width: 120).accessibilityIdentifier("large-minimum")
                    Picker("修改", selection: $model.largeStaleDays) {
                        Text("不限时间").tag(0); Text("30 天未改").tag(30); Text("90 天未改").tag(90); Text("1 年未改").tag(365)
                    }.frame(width: 128).accessibilityIdentifier("large-stale")
                }.font(.system(size: 11)).controlSize(.large)
                Picker("文件类型", selection: $model.largeCategory) {
                    Text("全部类型").tag(nil as FileCategory?)
                    ForEach(FileCategory.allCases) { Text($0.title).tag(Optional($0)) }
                }.pickerStyle(.segmented).font(.system(size: 11)).accessibilityIdentifier("large-category")
                Text("按磁盘占用和逻辑大小各保留前 200 个、至少 1 MiB 的文件；不受目录列表条数限制。硬链接去重。稀疏文件可能逻辑很大、实际占用很小。").font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(3)
            } }
            if let result = model.result, !result.complete { Label("当前为部分扫描结果，排行与类型统计可能不完整。", systemImage: "exclamationmark.circle").font(.system(size: 11)).foregroundStyle(.orange) }
            Surface { VStack(alignment: .leading, spacing: 10) {
                PanelTitle(title: "文件清单", caption: "\(model.largeFiles.count) 项")
                if model.result?.analysis == nil {
                    Text(model.scanning ? "扫描完成后显示全目录排行。" : "开始一次新扫描，获取大文件排行。").font(.system(size: 12)).foregroundStyle(.secondary).padding(.vertical, 28)
                } else if model.largeFiles.isEmpty {
                    Text("没有符合当前大小、类型和搜索条件的文件。").font(.system(size: 12)).foregroundStyle(.secondary).padding(.vertical, 28)
                }
                ForEach(model.largeFiles) { node in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "doc.fill").font(.system(size: 19)).foregroundStyle(DiskTheme.accent).frame(width: 28)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(node.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                            Text(DiskFormat.compactPath(node.path)).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2).help(node.path)
                            if !node.protection.isEmpty { Text(node.protection.map(\.title).sorted().joined(separator: " · ")).font(.system(size: 10)).foregroundStyle(.teal) }
                        }
                        Spacer(minLength: 12)
                        VStack(alignment: .trailing, spacing: 5) {
                            Text(DiskFormat.bytes(model.largeBasis.size(node))).font(.system(size: 14, weight: .semibold, design: .rounded)).monospacedDigit()
                            Text(model.largeBasis == .allocated ? "逻辑 " + DiskFormat.bytes(node.logical) : "占用 " + DiskFormat.bytes(node.allocated)).font(.system(size: 10)).foregroundStyle(.secondary)
                            Button("在 Finder 中显示") { model.reveal(node.path) }.buttonStyle(DiskButtonStyle(kind: .quiet)).controlSize(.small).accessibilityLabel("定位 " + node.name)
                        }
                    }.padding(.vertical, 10).contentShape(Rectangle())
                        .contextMenu { Button("在 Finder 中显示") { model.reveal(node.path) }; Button("复制路径") { model.copyPath(node.path) } }
                    Divider().opacity(0.6)
                }
            } }
        }
    }
}
struct FileTypesPage: View {
    @ObservedObject var model: AppModel
    var types: [FileTypeUsage] { model.result?.analysis?.fileTypes ?? [] }
    var ageBuckets: [AgeBucketUsage] { (model.result?.analysis?.ageBuckets ?? []).filter { $0.files > 0 } }
    var total: Int64 { max(1, types.reduce(0) { $0 + $1.allocated }) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Surface { VStack(alignment: .leading, spacing: 18) {
                PanelTitle(title: "文件类型占用", caption: "按已分配大小")
                Text("按扩展名归类，不读取文件内容。统计扫描到的唯一文件，含目录列表未保留的深层文件；目录自身元数据不计入以下占比。").font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
                if types.isEmpty { Text("开始一次新扫描，获取文件类型统计。").font(.system(size: 12)).foregroundStyle(.secondary).padding(.vertical, 28) }
                ForEach(Array(types.enumerated()), id: \.element.id) { index, usage in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { Circle().fill(DiskTheme.colors[index % DiskTheme.colors.count]).frame(width: 8, height: 8); Text(usage.category.title).font(.system(size: 13, weight: .medium)); Text("\(usage.files.formatted()) 个文件").font(.system(size: 10)).foregroundStyle(.secondary); Spacer(); Text(DiskFormat.bytes(usage.allocated)).font(.system(size: 14, weight: .semibold, design: .rounded)); Text(String(format: "%.1f%%", Double(usage.allocated) / Double(total) * 100)).font(.system(size: 10)).foregroundStyle(.secondary).frame(width: 48, alignment: .trailing) }
                        GeometryReader { g in Capsule().fill(DiskTheme.colors[index % DiskTheme.colors.count].opacity(0.12)).overlay(alignment: .leading) { Capsule().fill(DiskTheme.colors[index % DiskTheme.colors.count]).frame(width: max(2, g.size.width * CGFloat(usage.allocated) / CGFloat(total))) } }.frame(height: 5)
                        if !usage.extensions.isEmpty {
                            HStack(spacing: 6) {
                                ForEach(usage.extensions.prefix(6)) { ext in
                                    Button {
                                        model.largeCategory = usage.category
                                        model.largeQuery = ext.ext == "(无扩展名)" ? "" : "." + ext.ext
                                        model.page = "large"
                                    } label: {
                                        Text("\(ext.ext == "(无扩展名)" ? ext.ext : "." + ext.ext) \(DiskFormat.bytes(ext.allocated))")
                                            .font(.system(size: 10)).padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(DiskTheme.inset, in: Capsule())
                                    }.buttonStyle(DiskButtonStyle(kind: .quiet))
                                }
                            }
                        }
                        HStack { Text("逻辑大小 " + DiskFormat.bytes(usage.logical)).font(.system(size: 10)).foregroundStyle(.secondary); Spacer(); Button("查看此类大文件") { model.largeCategory = usage.category; model.page = "large" }.buttonStyle(DiskButtonStyle(kind: .quiet)).font(.system(size: 11)).foregroundStyle(DiskTheme.accent).accessibilityLabel("查看大文件 " + usage.category.title) }
                    }.padding(.vertical, 9)
                }
                if let r = model.result, !r.complete { Text("扫描不完整，统计仅包含已读取的文件。").font(.system(size: 11)).foregroundStyle(.orange) }
            } }
            if !ageBuckets.isEmpty {
                Surface { VStack(alignment: .leading, spacing: 14) {
                    PanelTitle(title: "文件活跃度与陈旧分布", caption: "按最后修改时间统计")
                    HStack(spacing: 12) {
                        ForEach(ageBuckets) { item in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.bucket.title).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                                Text(DiskFormat.bytes(item.allocated)).font(.system(size: 15, weight: .semibold, design: .rounded)).monospacedDigit()
                                Text("\(item.files.formatted()) 个文件 · \(String(format: "%.1f%%", Double(item.allocated) / Double(total) * 100))").font(.system(size: 10)).foregroundStyle(.tertiary)
                                Button("筛选大文件 →") {
                                    model.largeCategory = nil
                                    model.largeStaleDays = item.bucket.staleDaysFilter
                                    model.page = "large"
                                }.buttonStyle(DiskButtonStyle(kind: .quiet)).font(.system(size: 10)).foregroundStyle(DiskTheme.accent)
                            }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(DiskTheme.inset, in: RoundedRectangle(cornerRadius: DiskTheme.controlRadius))
                        }
                    }
                } }
            }
        }
    }
}
struct ProjectsPage: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Surface {
                VStack(alignment: .leading, spacing: 12) {
                    PanelTitle(title: "开发工程工作区洞察", caption: "\(model.projects.count) 个工程 · 按工程汇总构建缓存与陈旧度")
                    HStack(spacing: 10) {
                        DiskSearchField(placeholder: "搜索工程名称或路径", text: $model.projectQuery, identifier: "project-search")
                        Picker("排序", selection: $model.projectSort) {
                            ForEach(ProjectSort.allCases) { item in Text(item.title).tag(item) }
                        }.pickerStyle(.segmented).labelsHidden().frame(width: 264).accessibilityIdentifier("project-sort")
                    }.font(.system(size: 11))
                    Text("自动识别包含 Git 或语言工程清单的项目根目录，汇总其总占用与可识别构建缓存占用。勾选缓存后仍需在清理建议页确认才移入废纸篓。").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            Surface {
                VStack(alignment: .leading, spacing: 10) {
                    if model.result == nil {
                        Text(model.scanning ? "正在扫描识别工程目录…" : "开始一次扫描，识别工作区内的开发工程。").font(.system(size: 12)).foregroundStyle(.secondary).padding(.vertical, 28)
                    } else if model.projects.isEmpty {
                        Text("当前扫描范围内未发现符合筛选条件的开发工程。").font(.system(size: 12)).foregroundStyle(.secondary).padding(.vertical, 28)
                    }
                    ForEach(model.projects) { project in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "hammer.circle.fill").font(.system(size: 20)).foregroundStyle(DiskTheme.accent).frame(width: 28).padding(.top, 2)
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(spacing: 6) {
                                    Text(project.name).font(.system(size: 13, weight: .semibold))
                                    Tag(text: project.markers.prefix(2).joined(separator: " · "), color: .teal)
                                    if let ts = project.modifiedAt, ts <= Int64(Date().timeIntervalSince1970) - 90 * 86_400 {
                                        Tag(text: "久未活跃", color: .orange)
                                    }
                                }
                                Text(DiskFormat.compactPath(project.path)).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).help(project.path)
                                HStack(spacing: 12) {
                                    Text("\(project.fileCount.formatted()) 文件")
                                    Text("源码与资产 \(DiskFormat.bytes(project.nonCacheAllocated))")
                                    if project.cacheAllocated > 0 {
                                        Text("构建缓存 \(DiskFormat.bytes(project.cacheAllocated)) (\(Int((project.cacheRatio * 100).rounded()))%)").foregroundStyle(DiskTheme.purple)
                                    }
                                    if let ts = project.modifiedAt {
                                        Text("最近活跃 \(Date(timeIntervalSince1970: TimeInterval(ts)).formatted(date: .abbreviated, time: .omitted))")
                                    }
                                }.font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 6) {
                                Text(DiskFormat.bytes(project.allocated)).font(.system(size: 14, weight: .semibold, design: .rounded)).monospacedDigit()
                                HStack(spacing: 8) {
                                    if !project.cachePaths.isEmpty {
                                        Button("前往清理建议") { model.selectProjectCaches(project) }.buttonStyle(DiskButtonStyle(kind: .quiet)).font(.system(size: 10)).foregroundStyle(DiskTheme.purple)
                                    }
                                    Button("概览中查看") { model.browseProject(project) }.buttonStyle(DiskButtonStyle(kind: .quiet)).font(.system(size: 10)).foregroundStyle(DiskTheme.accent)
                                    Button("在 Finder 中显示") { model.reveal(project.path) }.buttonStyle(DiskButtonStyle(kind: .quiet)).font(.system(size: 10)).foregroundStyle(.secondary)
                                }
                            }
                        }.padding(.vertical, 10).contentShape(Rectangle())
                            .contextMenu { Button("概览中查看") { model.browseProject(project) }; Button("在 Finder 中显示") { model.reveal(project.path) }; Button("复制路径") { model.copyPath(project.path) } }
                        if project.id != model.projects.last?.id { Divider().opacity(0.6) }
                    }
                }
            }
        }
    }
}
struct ScanIssuesView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        DiskDialog(title: "未读取的路径", subtitle: "保留前 50 条路径 · 当前统计可能不完整", symbol: "folder.badge.questionmark") {
            Text("这些位置未计入完整占用。可能受 macOS 隐私权限、文件夹权限或扫描期间的目录变化影响。")
                .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
            ScrollView { VStack(alignment: .leading, spacing: 12) { ForEach(model.result?.issues ?? [], id: \.self) { path in
                Label(path, systemImage: "folder").font(.system(size: 11)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            } }.padding(12) }.frame(height: 220).background(DiskTheme.inset, in: RoundedRectangle(cornerRadius: DiskTheme.controlRadius))
            Text("开启权限后需重新扫描。扫描不会读取文件内容。").font(.system(size: 11)).foregroundStyle(.secondary)
        } actions: {
            Button("打开完整磁盘访问设置") { model.permissions() }
            Spacer()
            Button("完成") { model.showIssues = false }.buttonStyle(DiskButtonStyle(kind: .primary)).keyboardShortcut(.defaultAction)
        }
    }
}
