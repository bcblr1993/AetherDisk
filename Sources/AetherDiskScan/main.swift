import Foundation
import AetherDiskCore

let args = Array(CommandLine.arguments.dropFirst())
if args.isEmpty || args.contains("--help") {
    print("用法：aetherdisk-scan [<目录>] [--profile eco|balanced|fast] [--json <报告路径>] [--csv <CSV路径>] [--compare <旧快照JSON>] [--top <数量>] [--duplicates] [--volumes] [--apps] [--health] [--cloud] [--version]\n只读扫描；包含隐藏目录、不跨卷、不跟随链接、不读取文件内容。")
    exit(0)
}
do {
    let options = try ScanCLIOptions.parse(args)
    if options.showVersion {
        print("aetherdisk-scan 3.1.0")
        exit(0)
    }
    if options.showVolumes {
        let volumes = VolumeDiscovery.mountedVolumes()
        print("已挂载卷（只读视图，共 \(volumes.count) 个）：")
        for vol in volumes {
            let role = vol.isExternal ? "外部卷·仅分析" : "内置卷"
            let ro = vol.isReadOnly ? " · 只读" : ""
            print("  \(vol.name) [\(vol.fileSystemType), \(role)\(ro)] -> \(vol.path)：可用 \(DiskFormat.bytes(vol.space.free)) / 总计 \(DiskFormat.bytes(vol.space.total))")
        }
    }
    if options.showHealth {
        let sampler = SystemHealthSampler()
        let snap = sampler.sample()
        print("系统健康只读快照（\(snap.hostModelLabel) · \(snap.osVersionLabel)）：")
        print("  内存：已用 \(DiskFormat.bytes(snap.memory.usedBytes)) / \(DiskFormat.bytes(snap.memory.totalBytes))（\(snap.memory.pressure.title)，压缩 \(DiskFormat.bytes(snap.memory.compressedBytes))）")
        print("  CPU：负载 \(String(format: "%.2f", snap.cpu.loadAverage1m))（\(snap.cpu.coreCount) 核 · \(snap.cpu.thermalLabel)）")
        print("  电源：\(snap.power.statusLabel)")
    }
    if options.showApps {
        let report = ApplicationInspector.inspect()
        print("应用与关联缓存只读透视（共 \(report.apps.count) 款应用，疑似残留 \(report.orphanedData.count) 项）：")
        for app in report.apps.prefix(options.topLimit) {
            let cacheInfo = app.associatedAllocated > 0 ? "（含关联缓存 \(DiskFormat.bytes(app.associatedAllocated))）" : ""
            print("  \(DiskFormat.bytes(app.totalFootprint))\t\(app.name) [\(app.source.title)]\(cacheInfo)")
        }
    }
    if options.showCloud {
        let extraCloudRoot = options.rootPath.isEmpty ? nil : CloudStorageInspector.candidateExtraCloudRoot(for: URL(fileURLWithPath: options.rootPath))
        let report = CloudStorageInspector.inspect(extraCloudRoot: extraCloudRoot)
        print("云盘空间只读透视（共 \(report.providers.count) 个服务 · 本地驻留 \(DiskFormat.bytes(report.totalAllocated)) · 云端占位 \(DiskFormat.bytes(report.totalCloudOnlyLogical)) · 本地文件 \(report.totalLocalFiles) 个 · 占位文件 \(report.totalDatalessFiles) 个）：")
        if report.providers.isEmpty {
            print("  未发现本地云盘同步目录（~/Library/CloudStorage 或 iCloud Drive）。")
        } else {
            for provider in report.providers {
                print("  \(provider.name) [\(DiskFormat.compactPath(provider.path))]：本地驻留 \(DiskFormat.bytes(provider.allocated))，云端占位 \(DiskFormat.bytes(provider.cloudOnlyLogical))，逻辑总计 \(DiskFormat.bytes(provider.logical))，本地文件 \(provider.localFileCount) 个，占位文件 \(provider.datalessFileCount) 个\(provider.unreadableCount > 0 ? "，未读取 \(provider.unreadableCount) 项" : "")")
                for item in provider.topLocalFiles.prefix(3) {
                    print("    - \(item.name)：本地 \(DiskFormat.bytes(item.allocated)) / 逻辑 \(DiskFormat.bytes(item.logical))")
                }
            }
        }
        if report.unreadableCount > 0 {
            print("  提示：部分云盘路径受权限限制，统计可能不完整（未读取 \(report.unreadableCount) 项）。")
        }
    }
    if options.rootPath.isEmpty {
        exit(0)
    }
    let root = URL(fileURLWithPath: options.rootPath).standardizedFileURL
    let result = try DiskScanner.scan(root: root, profile: options.profile)
    if let jsonPath = options.jsonPath {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(result).write(to: URL(fileURLWithPath: jsonPath), options: .atomic)
    }
    if let csvPath = options.csvPath {
        try ScanReport.csv(result).write(to: URL(fileURLWithPath: csvPath), atomically: true, encoding: .utf8)
    }
    print("扫描：\(root.path)（模式：\(options.profile.title)）\n已分配：\(DiskFormat.bytes(result.allocated))，逻辑大小：\(DiskFormat.bytes(result.logical))\n文件：\(result.files)，目录：\(result.directories)，未能读取：\(result.unreadable)\n耗时：\(String(format: "%.2f", result.duration)) 秒，建议：\(result.recommendations.count) 项")
    for node in result.nodes.filter({ $0.parent == root.path }).prefix(options.topLimit) {
        print("\(DiskFormat.bytes(node.allocated))\t\(node.name)")
    }
    if options.showDuplicates {
        let groups = result.analysis?.duplicateGroups ?? []
        print("疑似重复大文件线索（仅按逻辑大小与扩展名分组，未读取文件内容）：")
        if groups.isEmpty {
            print("  未发现 >= 1 MiB 且同体积同扩展名的多文件组。")
        } else {
            for group in groups.prefix(options.topLimit) {
                let extLabel = group.ext == "(无扩展名)" ? "(无扩展名)" : ".\(group.ext)"
                print("  \(DiskFormat.bytes(group.logicalSize)) [\(extLabel)] × \(group.files.count) 个文件（疑似可节省 \(DiskFormat.bytes(group.potentialRedundantAllocated))）：")
                for file in group.files {
                    print("    - \(file.path) (\(DiskFormat.bytes(file.allocated)))")
                }
            }
        }
    }
    if let comparePath = options.comparePath {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try Data(contentsOf: URL(fileURLWithPath: comparePath))
        let previous = try (try? decoder.decode(ScanResult.self, from: data)) ?? JSONDecoder().decode(ScanResult.self, from: data)
        print(ScanCLIOptions.formatComparison(current: result, previous: previous))
    }
    if result.unreadable > 0 {
        print("部分路径受权限限制，统计不完整。")
    }
} catch {
    fputs("扫描失败：\(error.localizedDescription)\n", stderr)
    exit(1)
}
