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
                            Text(DiskFormat.compactPath(node.path)).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled)
                            if !node.protection.isEmpty { Text(node.protection.map(\.title).sorted().joined(separator: " · ")).font(.system(size: 10)).foregroundStyle(.teal) }
                        }
                        Spacer(minLength: 12)
                        VStack(alignment: .trailing, spacing: 5) {
                            Text(DiskFormat.bytes(model.largeBasis.size(node))).font(.system(size: 14, weight: .semibold, design: .rounded)).monospacedDigit()
                            Text(model.largeBasis == .allocated ? "逻辑 " + DiskFormat.bytes(node.logical) : "占用 " + DiskFormat.bytes(node.allocated)).font(.system(size: 10)).foregroundStyle(.secondary)
                            Button("在 Finder 中显示") { model.reveal(node.path) }.buttonStyle(DiskButtonStyle(kind: .quiet)).controlSize(.small).accessibilityLabel("定位 " + node.name)
                        }
                    }.padding(.vertical, 10)
                    Divider().opacity(0.6)
                }
            } }
        }
    }
}
struct FileTypesPage: View {
    @ObservedObject var model: AppModel
    var types: [FileTypeUsage] { model.result?.analysis?.fileTypes ?? [] }
    var total: Int64 { max(1, types.reduce(0) { $0 + $1.allocated }) }
    var body: some View {
        Surface { VStack(alignment: .leading, spacing: 18) {
            PanelTitle(title: "文件类型占用", caption: "按已分配大小")
            Text("按扩展名归类，不读取文件内容。统计扫描到的唯一文件，含目录列表未保留的深层文件；目录自身元数据不计入以下占比。").font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
            if types.isEmpty { Text("开始一次新扫描，获取文件类型统计。").font(.system(size: 12)).foregroundStyle(.secondary).padding(.vertical, 28) }
            ForEach(Array(types.enumerated()), id: \.element.id) { index, usage in
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Circle().fill(DiskTheme.colors[index % DiskTheme.colors.count]).frame(width: 8, height: 8); Text(usage.category.title).font(.system(size: 13, weight: .medium)); Text("\(usage.files.formatted()) 个文件").font(.system(size: 10)).foregroundStyle(.secondary); Spacer(); Text(DiskFormat.bytes(usage.allocated)).font(.system(size: 14, weight: .semibold, design: .rounded)); Text(String(format: "%.1f%%", Double(usage.allocated) / Double(total) * 100)).font(.system(size: 10)).foregroundStyle(.secondary).frame(width: 48, alignment: .trailing) }
                    GeometryReader { g in Capsule().fill(DiskTheme.colors[index % DiskTheme.colors.count].opacity(0.12)).overlay(alignment: .leading) { Capsule().fill(DiskTheme.colors[index % DiskTheme.colors.count]).frame(width: max(2, g.size.width * CGFloat(usage.allocated) / CGFloat(total))) } }.frame(height: 5)
                    HStack { Text("逻辑大小 " + DiskFormat.bytes(usage.logical)).font(.system(size: 10)).foregroundStyle(.secondary); Spacer(); Button("查看此类大文件") { model.largeCategory = usage.category; model.page = "large" }.buttonStyle(DiskButtonStyle(kind: .quiet)).font(.system(size: 11)).foregroundStyle(DiskTheme.accent).accessibilityLabel("查看大文件 " + usage.category.title) }
                }.padding(.vertical, 9)
            }
            if let r = model.result, !r.complete { Text("扫描不完整，统计仅包含已读取的文件。").font(.system(size: 11)).foregroundStyle(.orange) }
        } }
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
