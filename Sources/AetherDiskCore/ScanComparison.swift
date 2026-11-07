import Foundation

public enum ComparisonDepth: String, CaseIterable, Sendable, Identifiable {
    case top, deep
    public var id: String { rawValue }
    public var title: String { self == .top ? "顶层目录" : "深层目录" }
}

public enum ChangeDirection: String, CaseIterable, Sendable, Identifiable {
    case all, grown, shrunk
    public var id: String { rawValue }
    public var title: String {
        switch self { case .all: "全部"; case .grown: "仅增长"; case .shrunk: "仅减少" }
    }
    public func matches(_ delta: Int64) -> Bool {
        switch self { case .all: true; case .grown: delta > 0; case .shrunk: delta < 0 }
    }
}

public struct ComparisonSummary: Equatable, Sendable {
    public var allocatedDelta: Int64
    public var logicalDelta: Int64
    public var filesDelta: Int
    public var grownCount: Int
    public var shrunkCount: Int
}

public enum ScanComparison {
    public static func summary(current: ScanResult, previous: ScanResult) -> ComparisonSummary {
        guard current.root == previous.root else { return .init(allocatedDelta: 0, logicalDelta: 0, filesDelta: 0, grownCount: 0, shrunkCount: 0) }
        let top = changes(current: current, previous: previous, depth: .top)
        return .init(
            allocatedDelta: current.allocated - previous.allocated,
            logicalDelta: current.logical - previous.logical,
            filesDelta: current.files - previous.files,
            grownCount: top.filter { $0.1 > 0 }.count,
            shrunkCount: top.filter { $0.1 < 0 }.count
        )
    }

    public static func changes(current: ScanResult, previous: ScanResult, depth: ComparisonDepth = .top, direction: ChangeDirection = .all, query: String = "") -> [(DiskNode, Int64)] {
        guard current.root == previous.root else { return [] }
        let raw: [(DiskNode, Int64)]
        if depth == .top {
            let new = Dictionary(uniqueKeysWithValues: current.nodes.filter { $0.parent == current.root && $0.path != current.root }.map { ($0.path, $0) })
            let old = Dictionary(uniqueKeysWithValues: previous.nodes.filter { $0.parent == previous.root && $0.path != previous.root }.map { ($0.path, $0) })
            raw = Set(new.keys).union(old.keys).map { path in
                var node = new[path] ?? old[path]!
                if new[path] == nil { node.allocated = 0; node.logical = 0; node.fileCount = 0 }
                return (node, (new[path]?.allocated ?? 0) - (old[path]?.allocated ?? 0))
            }
        } else {
            let new = Dictionary(uniqueKeysWithValues: current.nodes.filter { $0.kind == .directory && $0.path != current.root }.map { ($0.path, $0) })
            let old = Dictionary(uniqueKeysWithValues: previous.nodes.filter { $0.kind == .directory && $0.path != previous.root }.map { ($0.path, $0) })
            let allPaths = Set(new.keys).union(old.keys)
            raw = allPaths.compactMap { path -> (DiskNode, Int64)? in
                let delta = (new[path]?.allocated ?? 0) - (old[path]?.allocated ?? 0)
                guard delta != 0 else { return nil }
                let parent = URL(fileURLWithPath: path).deletingLastPathComponent().path
                if parent != current.root && ((new[path] == nil && new[parent] == nil && old[parent] != nil) || (old[path] == nil && old[parent] == nil && new[parent] != nil)) {
                    return nil
                }
                var node = new[path] ?? old[path]!
                if new[path] == nil { node.allocated = 0; node.logical = 0; node.fileCount = 0 }
                return (node, delta)
            }
        }
        return raw.filter { node, delta in
            direction.matches(delta) && (query.isEmpty || node.name.localizedCaseInsensitiveContains(query) || node.path.localizedCaseInsensitiveContains(query))
        }.sorted { abs($0.1) == abs($1.1) ? $0.0.path < $1.0.path : abs($0.1) > abs($1.1) }
    }
}

public enum ScanHistoryStore {
    public static let maxSnapshots = 10
    public static func append(_ result: ScanResult, into existing: [ScanResult], limit: Int = maxSnapshots) -> [ScanResult] {
        guard result.complete else { return existing }
        let combined = ([result] + existing.filter { $0.root == result.root && abs($0.scannedAt.timeIntervalSince(result.scannedAt)) > 0.001 })
            .sorted { $0.scannedAt > $1.scannedAt }
        return Array(combined.prefix(max(1, limit)))
    }
}

public struct TrendPoint: Equatable, Sendable, Identifiable {
    public var id: Date { scannedAt }
    public var scannedAt: Date
    public var allocated: Int64
    public var files: Int
}

public struct GrowthHotspot: Equatable, Sendable, Identifiable {
    public var id: String { path }
    public var path: String
    public var name: String { URL(fileURLWithPath: path).lastPathComponent }
    public var currentAllocated: Int64
    public var totalGrowth: Int64
    public var consecutiveGrows: Int
}

public enum ScanTrendAnalyzer {
    public static func timeline(from snapshots: [ScanResult]) -> [TrendPoint] {
        snapshots.sorted { $0.scannedAt < $1.scannedAt }.map {
            TrendPoint(scannedAt: $0.scannedAt, allocated: $0.allocated, files: $0.files)
        }
    }
    public static func growthHotspots(from snapshots: [ScanResult]) -> [GrowthHotspot] {
        let ordered = snapshots.sorted { $0.scannedAt < $1.scannedAt }
        guard ordered.count >= 3, let latest = ordered.last else { return [] }
        let root = latest.root
        let candidatePaths = latest.nodes.filter { $0.parent == root && $0.path != root && $0.allocated > 0 }.map(\.path)
        var hotspots: [GrowthHotspot] = []
        for path in candidatePaths {
            let series = ordered.map { snap in snap.nodes.first { $0.path == path }?.allocated ?? 0 }
            var monotonic = true
            var grows = 0
            for idx in 1..<series.count {
                if series[idx] > series[idx - 1] { grows += 1 }
                else { monotonic = false; break }
            }
            if monotonic && grows >= 2, let first = series.first, let last = series.last, last > first {
                hotspots.append(GrowthHotspot(path: path, currentAllocated: last, totalGrowth: last - first, consecutiveGrows: grows))
            }
        }
        return hotspots.sorted { $0.totalGrowth == $1.totalGrowth ? $0.path < $1.path : $0.totalGrowth > $1.totalGrowth }
    }
}
