import Foundation
import AetherDiskCore

let args = Array(CommandLine.arguments.dropFirst())
if args.isEmpty || args.contains("--help") {
    print("用法：aetherdisk-scan <目录> [--profile eco|balanced|fast] [--json <报告路径>] [--csv <CSV路径>] [--compare <旧快照JSON>] [--top <数量>] [--duplicates] [--volumes] [--version]\n只读扫描；包含隐藏目录、不跨卷、不跟随链接。")
    exit(0)
}
do {
    let options = try ScanCLIOptions.parse(args)
    if options.showVersion {
        print("aetherdisk-scan 2.0.0")
        exit(0)
    }
    if options.showVolumes {
        // 待与 VolumeSystem.swift 合并后接通 VolumeDiscovery.mountedVolumes()
        print("卷信息发现（--volumes）等待与 VolumeSystem.swift 合并后接通 VolumeDiscovery.mountedVolumes()。")
        if options.rootPath.isEmpty { exit(0) }
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
