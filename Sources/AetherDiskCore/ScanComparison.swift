import Foundation

public enum ComparisonDepth: String, CaseIterable, Sendable, Identifiable {
    case top, deep
    public var id: String { rawValue }
    public var title: String { self == .top ? "顶层目录" : "深层目录" }
}

public enum ScanComparison {
    public static func changes(current: ScanResult, previous: ScanResult, depth: ComparisonDepth = .top) -> [(DiskNode, Int64)] {
        guard current.root == previous.root else { return [] }
        if depth == .top {
            let new = Dictionary(uniqueKeysWithValues: current.nodes.filter { $0.parent == current.root && $0.path != current.root }.map { ($0.path, $0) })
            let old = Dictionary(uniqueKeysWithValues: previous.nodes.filter { $0.parent == previous.root && $0.path != previous.root }.map { ($0.path, $0) })
            return Set(new.keys).union(old.keys).map { path in
                var node = new[path] ?? old[path]!
                if new[path] == nil { node.allocated = 0; node.logical = 0; node.fileCount = 0 }
                return (node, (new[path]?.allocated ?? 0) - (old[path]?.allocated ?? 0))
            }.sorted { abs($0.1) == abs($1.1) ? $0.0.path < $1.0.path : abs($0.1) > abs($1.1) }
        }
        let new = Dictionary(uniqueKeysWithValues: current.nodes.filter { $0.kind == .directory && $0.path != current.root }.map { ($0.path, $0) })
        let old = Dictionary(uniqueKeysWithValues: previous.nodes.filter { $0.kind == .directory && $0.path != previous.root }.map { ($0.path, $0) })
        let allPaths = Set(new.keys).union(old.keys)
        return allPaths.compactMap { path -> (DiskNode, Int64)? in
            let delta = (new[path]?.allocated ?? 0) - (old[path]?.allocated ?? 0)
            guard delta != 0 else { return nil }
            let parent = URL(fileURLWithPath: path).deletingLastPathComponent().path
            if parent != current.root && ((new[path] == nil && new[parent] == nil && old[parent] != nil) || (old[path] == nil && old[parent] == nil && new[parent] != nil)) {
                return nil
            }
            var node = new[path] ?? old[path]!
            if new[path] == nil { node.allocated = 0; node.logical = 0; node.fileCount = 0 }
            return (node, delta)
        }.sorted { abs($0.1) == abs($1.1) ? $0.0.path < $1.0.path : abs($0.1) > abs($1.1) }
    }
}

public enum ScanHistoryStore {
    public static let maxSnapshots = 5
    public static func append(_ result: ScanResult, into existing: [ScanResult], limit: Int = maxSnapshots) -> [ScanResult] {
        guard result.complete else { return existing }
        let combined = ([result] + existing.filter { $0.root == result.root && abs($0.scannedAt.timeIntervalSince(result.scannedAt)) > 0.001 })
            .sorted { $0.scannedAt > $1.scannedAt }
        return Array(combined.prefix(max(1, limit)))
    }
}
