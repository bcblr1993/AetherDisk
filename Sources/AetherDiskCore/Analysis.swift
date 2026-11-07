import Foundation

public enum FileCategory: String, Codable, CaseIterable, Sendable, Identifiable {
    case video, audio, image, archive, source, document, other
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .video: "视频"; case .audio: "音频"; case .image: "图片"; case .archive: "安装包与归档"
        case .source: "源码与脚本"; case .document: "文档"; case .other: "其他文件"
        }
    }
    public static func classify(_ name: String, allocated: Int64 = 0) -> Self {
        let ext = (name.lowercased() as NSString).pathExtension
        if ["mp4","mkv","mov","avi","m4v","webm","ts","m2ts","flv"].contains(ext) {
            return (ext == "ts" && allocated < 64 * 1024 * 1024) ? .source : .video
        }
        if ["mp3","flac","aac","m4a","wav","aiff","ogg","opus"].contains(ext) { return .audio }
        if ["png","jpg","jpeg","heic","gif","webp","tiff","svg","raw","dng","avif"].contains(ext) { return .image }
        let flags = RuleCatalog.protection(name: name, directory: false)
        if flags.contains(.installer) { return .archive }
        if flags.contains(.source) { return .source }
        if ["pdf","txt","md","rtf","doc","docx","xls","xlsx","ppt","pptx","csv","pages","numbers","keynote","epub"].contains(ext) { return .document }
        return .other
    }
}
public struct ExtensionUsage: Codable, Sendable, Equatable, Identifiable {
    public var id: String { ext }
    public var ext: String
    public var allocated: Int64 = 0
    public var logical: Int64 = 0
    public var files: Int = 0
}
public struct FileTypeUsage: Codable, Sendable, Identifiable {
    public var id: FileCategory { category }
    public var category: FileCategory
    public var allocated: Int64 = 0
    public var logical: Int64 = 0
    public var files: Int = 0
    public var extensions: [ExtensionUsage] = []
    enum CodingKeys: String, CodingKey { case category, allocated, logical, files, extensions }
    public init(category: FileCategory, allocated: Int64 = 0, logical: Int64 = 0, files: Int = 0, extensions: [ExtensionUsage] = []) {
        self.category = category; self.allocated = allocated; self.logical = logical; self.files = files; self.extensions = extensions
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        category = try c.decode(FileCategory.self, forKey: .category)
        allocated = try c.decode(Int64.self, forKey: .allocated)
        logical = try c.decode(Int64.self, forKey: .logical)
        files = try c.decode(Int.self, forKey: .files)
        extensions = (try? c.decode([ExtensionUsage].self, forKey: .extensions)) ?? []
    }
}
public struct ProjectSummary: Codable, Sendable, Equatable, Identifiable {
    public var id: String { path }
    public var path: String
    public var name: String { URL(fileURLWithPath: path).lastPathComponent }
    public var markers: [String]
    public var allocated: Int64
    public var logical: Int64
    public var fileCount: Int
    public var cacheAllocated: Int64
    public var cachePaths: [String]
    public var modifiedAt: Int64?
    public var protection: Set<Protection>
    public var nonCacheAllocated: Int64 { max(0, allocated - cacheAllocated) }
    public var cacheRatio: Double { allocated > 0 ? min(1, Double(cacheAllocated) / Double(allocated)) : 0 }
    public init(path: String, markers: [String], allocated: Int64, logical: Int64, fileCount: Int, cacheAllocated: Int64 = 0, cachePaths: [String] = [], modifiedAt: Int64? = nil, protection: Set<Protection> = []) {
        self.path = path; self.markers = markers; self.allocated = allocated; self.logical = logical; self.fileCount = fileCount; self.cacheAllocated = cacheAllocated; self.cachePaths = cachePaths; self.modifiedAt = modifiedAt; self.protection = protection
    }
}
public enum AgeBucket: String, Codable, CaseIterable, Sendable, Identifiable {
    case recent30d, days30to90, days90to365, over1y
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .recent30d: "近 30 天"; case .days30to90: "30–90 天"; case .days90to365: "90 天–1 年"; case .over1y: "1 年以上未改"
        }
    }
    public var staleDaysFilter: Int {
        switch self {
        case .recent30d: 0; case .days30to90: 30; case .days90to365: 90; case .over1y: 365
        }
    }
    public static func classify(modifiedAt: Int64?, referenceDate: Date = Date()) -> Self {
        guard let ts = modifiedAt else { return .recent30d }
        let ageDays = max(0, (Int64(referenceDate.timeIntervalSince1970) - ts) / 86_400)
        if ageDays >= 365 { return .over1y }
        if ageDays >= 90 { return .days90to365 }
        if ageDays >= 30 { return .days30to90 }
        return .recent30d
    }
}
public struct AgeBucketUsage: Codable, Sendable, Equatable, Identifiable {
    public var id: AgeBucket { bucket }
    public var bucket: AgeBucket
    public var allocated: Int64 = 0
    public var logical: Int64 = 0
    public var files: Int = 0
    public init(bucket: AgeBucket, allocated: Int64 = 0, logical: Int64 = 0, files: Int = 0) {
        self.bucket = bucket; self.allocated = allocated; self.logical = logical; self.files = files
    }
}
public struct ScanAnalysis: Codable, Sendable {
    public var fileTypes: [FileTypeUsage]
    public var largeFiles: [DiskNode]
    public var projects: [ProjectSummary]
    public var ageBuckets: [AgeBucketUsage]
    enum CodingKeys: String, CodingKey { case fileTypes, largeFiles, projects, ageBuckets }
    public init(fileTypes: [FileTypeUsage], largeFiles: [DiskNode], projects: [ProjectSummary] = [], ageBuckets: [AgeBucketUsage] = []) {
        self.fileTypes = fileTypes; self.largeFiles = largeFiles; self.projects = projects; self.ageBuckets = ageBuckets
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fileTypes = try c.decode([FileTypeUsage].self, forKey: .fileTypes)
        largeFiles = try c.decode([DiskNode].self, forKey: .largeFiles)
        projects = (try? c.decode([ProjectSummary].self, forKey: .projects)) ?? []
        ageBuckets = (try? c.decode([AgeBucketUsage].self, forKey: .ageBuckets)) ?? []
    }
}
public enum SizeBasis: String, CaseIterable, Sendable, Identifiable {
    case allocated, logical
    public var id: String { rawValue }
    public var title: String { self == .allocated ? "磁盘占用" : "逻辑大小" }
    public func size(_ node: DiskNode) -> Int64 { self == .allocated ? node.allocated : node.logical }
}
public enum LargeFileQuery {
    public static func rows(_ files: [DiskNode], query: String = "", category: FileCategory? = nil, minimum: Int64 = 100 * 1024 * 1024, basis: SizeBasis = .allocated, staleDays: Int = 0, referenceDate: Date = Date()) -> [DiskNode] {
        let cutoff = Int64(referenceDate.timeIntervalSince1970) - Int64(staleDays) * 86_400
        return files.filter { node in
            let matchesStale = staleDays <= 0 || (node.modifiedAt.map { $0 <= cutoff } ?? false)
            return matchesStale && basis.size(node) >= minimum && (category == nil || FileCategory.classify(node.name, allocated: node.allocated) == category) && (query.isEmpty || node.path.localizedCaseInsensitiveContains(query))
        }.sorted { basis.size($0) == basis.size($1) ? $0.path < $1.path : basis.size($0) > basis.size($1) }
    }
}
public enum RankingSort: String, CaseIterable, Sendable, Identifiable {
    case allocated, logical, files
    public var id: String { rawValue }
    public var title: String {
        switch self { case .allocated: "已分配"; case .logical: "逻辑大小"; case .files: "文件数" }
    }
    public func sort(_ nodes: [DiskNode]) -> [DiskNode] {
        nodes.sorted { a, b in
            switch self {
            case .allocated: a.allocated == b.allocated ? a.path < b.path : a.allocated > b.allocated
            case .logical: a.logical == b.logical ? a.path < b.path : a.logical > b.logical
            case .files: a.fileCount == b.fileCount ? (a.allocated == b.allocated ? a.path < b.path : a.allocated > b.allocated) : a.fileCount > b.fileCount
            }
        }
    }
}
public enum SuggestionFilter: String, CaseIterable, Sendable, Identifiable {
    case all, eligible, protected
    public var id: String { rawValue }
    public var title: String {
        switch self { case .all: "全部"; case .eligible: "可检查"; case .protected: "已保护" }
    }
}
public enum RecommendationQuery {
    public static func rows(_ items: [Recommendation], filter: SuggestionFilter = .all, category: CacheCategory? = nil, query: String = "", staleOnly: Bool = false, staleDays: Int = 90, referenceDate: Date = Date()) -> [Recommendation] {
        items.filter { item in
            let matchesFilter = filter == .all || (filter == .eligible && !item.blocked) || (filter == .protected && item.blocked)
            let matchesCategory = category == nil || item.category == category
            let matchesQuery = query.isEmpty || item.node.name.localizedCaseInsensitiveContains(query) || item.id.localizedCaseInsensitiveContains(query)
            let matchesStale = !staleOnly || item.isStale(days: staleDays, referenceDate: referenceDate)
            return matchesFilter && matchesCategory && matchesQuery && matchesStale
        }
    }
    public static func staleEligibleIDs(_ items: [Recommendation], days: Int = 90, referenceDate: Date = Date()) -> Set<String> {
        Set(items.filter { !$0.blocked && $0.isStale(days: days, referenceDate: referenceDate) }.map(\.id))
    }
    public static func categoryTotals(_ items: [Recommendation]) -> [(category: CacheCategory, allocated: Int64, count: Int)] {
        var map: [CacheCategory: (allocated: Int64, count: Int)] = [:]
        for item in items {
            let cur = map[item.category] ?? (0, 0)
            map[item.category] = (cur.allocated + item.node.allocated, cur.count + 1)
        }
        return map.map { (category: $0.key, allocated: $0.value.allocated, count: $0.value.count) }
            .sorted { $0.allocated == $1.allocated ? $0.category.rawValue < $1.category.rawValue : $0.allocated > $1.allocated }
    }
}
public enum ProjectSort: String, CaseIterable, Sendable, Identifiable {
    case allocated, cache, nonCache, stale
    public var id: String { rawValue }
    public var title: String {
        switch self { case .allocated: "总占用"; case .cache: "构建缓存"; case .nonCache: "源码与资产"; case .stale: "久未活跃" }
    }
}
public enum ProjectWorkspaceQuery {
    public static func rows(_ items: [ProjectSummary], sort: ProjectSort = .allocated, query: String = "") -> [ProjectSummary] {
        items.filter { item in
            query.isEmpty || item.name.localizedCaseInsensitiveContains(query) || item.path.localizedCaseInsensitiveContains(query)
        }.sorted { a, b in
            switch sort {
            case .allocated: return a.allocated == b.allocated ? a.path < b.path : a.allocated > b.allocated
            case .cache: return a.cacheAllocated == b.cacheAllocated ? (a.allocated == b.allocated ? a.path < b.path : a.allocated > b.allocated) : a.cacheAllocated > b.cacheAllocated
            case .nonCache: return a.nonCacheAllocated == b.nonCacheAllocated ? (a.allocated == b.allocated ? a.path < b.path : a.allocated > b.allocated) : a.nonCacheAllocated > b.nonCacheAllocated
            case .stale:
                let ma = a.modifiedAt ?? Int64.max
                let mb = b.modifiedAt ?? Int64.max
                return ma == mb ? (a.allocated == b.allocated ? a.path < b.path : a.allocated > b.allocated) : ma < mb
            }
        }
    }
}
public enum HierarchyBrowser {
    public static func canBrowse(_ node: DiskNode, in result: ScanResult?) -> Bool {
        guard node.kind == .directory, let result else { return false }
        return result.nodes.contains { $0.parent == node.path && $0.path != node.path }
    }
    public static func nextBrowseAction(for node: DiskNode, selectedPath: String?, in result: ScanResult?) -> (selectedPath: String, browseTo: String?) {
        if selectedPath == node.path && canBrowse(node, in: result) {
            return (node.path, node.path)
        }
        return (node.path, nil)
    }
    public static func breadcrumbs(root: String, current: String) -> [(name: String, path: String)] {
        let stdRoot = URL(fileURLWithPath: root).standardizedFileURL.path
        let stdCurrent = URL(fileURLWithPath: current).standardizedFileURL.path
        guard stdCurrent == stdRoot || stdCurrent.hasPrefix(stdRoot == "/" ? "/" : stdRoot + "/") else {
            return [(URL(fileURLWithPath: stdRoot).lastPathComponent, stdRoot)]
        }
        var items: [(name: String, path: String)] = []
        var cursor = stdCurrent
        while true {
            let name = cursor == "/" ? "/" : URL(fileURLWithPath: cursor).lastPathComponent
            items.append((name, cursor))
            if cursor == stdRoot || cursor == "/" { break }
            cursor = URL(fileURLWithPath: cursor).deletingLastPathComponent().path
        }
        return items.reversed()
    }
}
// Kept separate from the directory display budget: metadata beyond 20,000 nodes still contributes.
struct AnalysisAccumulator {
    var types: [FileCategory: FileTypeUsage] = [:]
    var extMap: [FileCategory: [String: ExtensionUsage]] = [:]
    var ageMap: [AgeBucket: AgeBucketUsage] = [:]
    var physical: [DiskNode] = []; var logical: [DiskNode] = []
    var physicalFloor: Int64 = 0; var logicalFloor: Int64 = 0
    mutating func record(_ node: DiskNode) {
        let category = FileCategory.classify(node.name, allocated: node.allocated)
        var usage = types[category] ?? .init(category: category)
        usage.allocated += node.allocated; usage.logical += node.logical; usage.files += 1; types[category] = usage
        let rawExt = (node.name.lowercased() as NSString).pathExtension
        let extKey = rawExt.isEmpty ? "(无扩展名)" : rawExt
        var catExts = extMap[category] ?? [:]
        var extUsage = catExts[extKey] ?? .init(ext: extKey)
        extUsage.allocated += node.allocated; extUsage.logical += node.logical; extUsage.files += 1
        catExts[extKey] = extUsage; extMap[category] = catExts
        let bucket = AgeBucket.classify(modifiedAt: node.modifiedAt)
        var bUsage = ageMap[bucket] ?? .init(bucket: bucket)
        bUsage.allocated += node.allocated; bUsage.logical += node.logical; bUsage.files += 1
        ageMap[bucket] = bUsage
        if node.allocated >= 1024 * 1024 && (physical.count < 200 || node.allocated >= physicalFloor) {
            physical.append(node)
            if physical.count >= 400 { physical.sort { $0.allocated > $1.allocated }; physical = Array(physical.prefix(200)); physicalFloor = physical.last?.allocated ?? 0 }
        }
        if node.logical >= 1024 * 1024 && (logical.count < 200 || node.logical >= logicalFloor) {
            logical.append(node)
            if logical.count >= 400 { logical.sort { $0.logical > $1.logical }; logical = Array(logical.prefix(200)); logicalFloor = logical.last?.logical ?? 0 }
        }
    }
    func result(projects: [ProjectSummary] = []) -> ScanAnalysis {
        let top = Array(physical.sorted { $0.allocated > $1.allocated }.prefix(200)) + Array(logical.sorted { $0.logical > $1.logical }.prefix(200))
        let unique = Dictionary(top.map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })
        let enrichedTypes = types.values.map { item -> FileTypeUsage in
            var copy = item
            let exts = (extMap[item.category]?.values.sorted { $0.allocated == $1.allocated ? $0.ext < $1.ext : $0.allocated > $1.allocated }) ?? []
            copy.extensions = Array(exts.prefix(10))
            return copy
        }.sorted { $0.allocated == $1.allocated ? $0.category.rawValue < $1.category.rawValue : $0.allocated > $1.allocated }
        let orderedBuckets = AgeBucket.allCases.map { ageMap[$0] ?? .init(bucket: $0) }
        return .init(fileTypes: enrichedTypes, largeFiles: unique.values.sorted { $0.allocated == $1.allocated ? $0.path < $1.path : $0.allocated > $1.allocated }, projects: projects, ageBuckets: orderedBuckets)
    }
}
public enum UserProtection {
    public static func contains(_ parent: String, _ child: String) -> Bool { parent == child || child.hasPrefix(parent == "/" ? "/" : parent + "/") }
    public static func overlaps(_ path: String, protectedPaths: [String]) -> Bool {
        let p = URL(fileURLWithPath: path).standardizedFileURL.path.precomposedStringWithCanonicalMapping.lowercased()
        return protectedPaths.contains { value in let r = URL(fileURLWithPath: value).standardizedFileURL.path.precomposedStringWithCanonicalMapping.lowercased(); return contains(r, p) || contains(p, r) }
    }
    public static func apply(_ node: DiskNode, paths: [String]) -> DiskNode {
        var value = node; value.protection.remove(.user)
        if overlaps(node.path, protectedPaths: paths) { value.protection.insert(.user) }
        return value
    }
    public static func requireAllowed(_ paths: [String], protectedPaths: [String]) throws {
        if paths.contains(where: { overlaps($0, protectedPaths: protectedPaths) }) { throw CleanupError.refused("该目录或其内部包含自定义保护目录，已阻止清理。") }
    }
}
public struct SpaceMapBlock: Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var path: String?
    public var allocated: Int64
    public var fraction: Double
    public var isDirectory: Bool
    public var isProtected: Bool
    public var isTailGroup: Bool
    public var groupedCount: Int
}
public enum SpaceMapLayout {
    public static func blocks(for nodes: [DiskNode], minFraction: Double = 0.02, maxBlocks: Int = 8) -> [SpaceMapBlock] {
        let positive = nodes.filter { $0.allocated > 0 }.sorted { $0.allocated == $1.allocated ? $0.path < $1.path : $0.allocated > $1.allocated }
        let total = positive.reduce(Int64(0)) { $0 + $1.allocated }
        guard total > 0 else { return [] }
        var primary: [DiskNode] = []
        var tail: [DiskNode] = []
        for (idx, node) in positive.enumerated() {
            let frac = Double(node.allocated) / Double(total)
            if idx < max(1, maxBlocks - 1) && (frac >= minFraction || primary.isEmpty) {
                primary.append(node)
            } else {
                tail.append(node)
            }
        }
        if tail.count == 1, let single = tail.first, primary.count < maxBlocks {
            primary.append(single); tail.removeAll()
        }
        var result = primary.map { node in
            SpaceMapBlock(id: node.path, title: node.name, path: node.path, allocated: node.allocated, fraction: Double(node.allocated) / Double(total), isDirectory: node.kind == .directory, isProtected: !node.protection.isEmpty, isTailGroup: false, groupedCount: 1)
        }
        if !tail.isEmpty {
            let tailAlloc = tail.reduce(Int64(0)) { $0 + $1.allocated }
            let anyProtected = tail.contains { !$0.protection.isEmpty }
            result.append(SpaceMapBlock(id: "__tail__", title: "其余 \(tail.count) 项", path: nil, allocated: tailAlloc, fraction: Double(tailAlloc) / Double(total), isDirectory: false, isProtected: anyProtected, isTailGroup: true, groupedCount: tail.count))
        }
        return result
    }
}
public struct ScanCLIOptions: Sendable, Equatable {
    public var rootPath: String
    public var jsonPath: String?
    public var csvPath: String?
    public var comparePath: String?
    public var topLimit: Int
    private static func expand(_ raw: String) -> String {
        NSString(string: raw).expandingTildeInPath
    }
    public static func parse(_ args: [String]) throws -> ScanCLIOptions {
        guard let first = args.first, !first.hasPrefix("-"), !first.isEmpty else { throw ScanFailure.invalidRoot }
        var opts = ScanCLIOptions(rootPath: expand(first), jsonPath: nil, csvPath: nil, comparePath: nil, topLimit: 15)
        var i = 1
        while i < args.count {
            let flag = args[i]
            if flag == "--json" {
                guard i + 1 < args.count, !args[i + 1].hasPrefix("-") else { throw ScanFailure.invalidRoot }
                opts.jsonPath = expand(args[i + 1]); i += 2
            } else if flag == "--csv" {
                guard i + 1 < args.count, !args[i + 1].hasPrefix("-") else { throw ScanFailure.invalidRoot }
                opts.csvPath = expand(args[i + 1]); i += 2
            } else if flag == "--compare" {
                guard i + 1 < args.count, !args[i + 1].hasPrefix("-") else { throw ScanFailure.invalidRoot }
                opts.comparePath = expand(args[i + 1]); i += 2
            } else if flag == "--top" {
                guard i + 1 < args.count, let n = Int(args[i + 1]), n > 0 else { throw ScanFailure.invalidRoot }
                opts.topLimit = min(200, n); i += 2
            } else {
                throw ScanFailure.invalidRoot
            }
        }
        return opts
    }
    public static func formatComparison(current: ScanResult, previous: ScanResult) -> String {
        let sum = ScanComparison.summary(current: current, previous: previous)
        let sign = sum.allocatedDelta >= 0 ? "+" : "−"
        var lines = ["对比基线：\(ISO8601DateFormatter().string(from: previous.scannedAt))，总变化：\(sign)\(DiskFormat.bytes(sum.allocatedDelta))（增长 \(sum.grownCount) 项，减少 \(sum.shrunkCount) 项）"]
        for (node, delta) in ScanComparison.changes(current: current, previous: previous, depth: .top).prefix(10) where delta != 0 {
            let dSign = delta >= 0 ? "+" : "−"
            lines.append("\(dSign)\(DiskFormat.bytes(delta))\t\(node.name)")
        }
        return lines.joined(separator: "\n")
    }
}
