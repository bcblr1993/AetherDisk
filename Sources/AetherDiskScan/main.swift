import Foundation
import AetherDiskCore

let args = Array(CommandLine.arguments.dropFirst())
if args.isEmpty || args.contains("--help") {
    print("用法：aetherdisk-scan <目录> [--json <报告路径>] [--csv <CSV路径>] [--compare <旧快照JSON>] [--top <数量>]\n只读扫描；包含隐藏目录、不跨卷、不跟随链接。")
    exit(0)
}
do {
    let options = try ScanCLIOptions.parse(args)
    let root = URL(fileURLWithPath: options.rootPath).standardizedFileURL
    let result = try DiskScanner.scan(root: root)
    if let jsonPath = options.jsonPath {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(result).write(to: URL(fileURLWithPath: jsonPath), options: .atomic)
    }
    if let csvPath = options.csvPath {
        try ScanReport.csv(result).write(to: URL(fileURLWithPath: csvPath), atomically: true, encoding: .utf8)
    }
    print("扫描：\(root.path)\n已分配：\(DiskFormat.bytes(result.allocated))，逻辑大小：\(DiskFormat.bytes(result.logical))\n文件：\(result.files)，目录：\(result.directories)，未能读取：\(result.unreadable)\n耗时：\(String(format: "%.2f", result.duration)) 秒，建议：\(result.recommendations.count) 项")
    for node in result.nodes.filter({ $0.parent == root.path }).prefix(options.topLimit) { print("\(DiskFormat.bytes(node.allocated))\t\(node.name)") }
    if let comparePath = options.comparePath {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let data = try Data(contentsOf: URL(fileURLWithPath: comparePath))
        let previous = try (try? decoder.decode(ScanResult.self, from: data)) ?? JSONDecoder().decode(ScanResult.self, from: data)
        print(ScanCLIOptions.formatComparison(current: result, previous: previous))
    }
    if result.unreadable > 0 { print("部分路径受权限限制，统计不完整。") }
} catch { fputs("扫描失败：\(error.localizedDescription)\n", stderr); exit(1) }
