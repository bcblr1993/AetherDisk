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
    public var duplicateGroups: [DuplicateSizeGroup]
    enum CodingKeys: String, CodingKey { case fileTypes, largeFiles, projects, ageBuckets, duplicateGroups }
    public init(fileTypes: [FileTypeUsage], largeFiles: [DiskNode], projects: [ProjectSummary] = [], ageBuckets: [AgeBucketUsage] = [], duplicateGroups: [DuplicateSizeGroup] = []) {
        self.fileTypes = fileTypes; self.largeFiles = largeFiles; self.projects = projects; self.ageBuckets = ageBuckets; self.duplicateGroups = duplicateGroups
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fileTypes = try c.decode([FileTypeUsage].self, forKey: .fileTypes)
        largeFiles = try c.decode([DiskNode].self, forKey: .largeFiles)
        projects = (try? c.decode([ProjectSummary].self, forKey: .projects)) ?? []
        ageBuckets = (try? c.decode([AgeBucketUsage].self, forKey: .ageBuckets)) ?? []
        duplicateGroups = (try? c.decode([DuplicateSizeGroup].self, forKey: .duplicateGroups)) ?? []
    }
}
public enum SizeBasis: String, CaseIterable, Sendable, Identifiable {
    case allocated, logical
    public var id: String { rawValue }
    public var title: String { self == .allocated ? "磁盘占用" : "逻辑大小" }
    public func size(_ node: DiskNode) -> Int64 { self == .allocated ? node.allocated : node.logical }
}
public enum TimeAxis: String, CaseIterable, Sendable, Identifiable {
    case modified, accessed
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .modified: "按修改时间"
        case .accessed: "按访问时间"
        }
    }
    public func timestamp(for node: DiskNode) -> Int64? {
        switch self {
        case .modified: node.modifiedAt
        case .accessed: node.accessedAt ?? node.modifiedAt
        }
    }
}
public struct ClutterHighlightSummary: Sendable, Equatable {
    public var mediaAllocated: Int64
    public var mediaCount: Int
    public var archiveAllocated: Int64
    public var archiveCount: Int
    public var stale90Allocated: Int64
    public var stale90Count: Int
    public var largestFile: DiskNode?

    public init(
        mediaAllocated: Int64 = 0,
        mediaCount: Int = 0,
        archiveAllocated: Int64 = 0,
        archiveCount: Int = 0,
        stale90Allocated: Int64 = 0,
        stale90Count: Int = 0,
        largestFile: DiskNode? = nil
    ) {
        self.mediaAllocated = mediaAllocated
        self.mediaCount = mediaCount
        self.archiveAllocated = archiveAllocated
        self.archiveCount = archiveCount
        self.stale90Allocated = stale90Allocated
        self.stale90Count = stale90Count
        self.largestFile = largestFile
    }
}
public struct DuplicateGroupComparison: Sendable, Equatable {
    public var newestPath: String?
    public var oldestPath: String?
    public var protectedCount: Int
    public var spanDays: Int

    public init(
        newestPath: String? = nil,
        oldestPath: String? = nil,
        protectedCount: Int = 0,
        spanDays: Int = 0
    ) {
        self.newestPath = newestPath
        self.oldestPath = oldestPath
        self.protectedCount = protectedCount
        self.spanDays = spanDays
    }
}
extension DuplicateSizeGroup {
    public func comparisonSummary(timeAxis: TimeAxis = .modified) -> DuplicateGroupComparison {
        let protectedCount = files.filter { !$0.protection.isEmpty || $0.restricted }.count
        let timed = files.compactMap { file in
            timeAxis.timestamp(for: file).map { (file: file, ts: $0) }
        }
        guard
            let oldest = timed.min(by: { $0.ts == $1.ts ? $0.file.path < $1.file.path : $0.ts < $1.ts }),
            let newest = timed.max(by: { $0.ts == $1.ts ? $0.file.path < $1.file.path : $0.ts < $1.ts })
        else {
            return DuplicateGroupComparison(
                newestPath: nil,
                oldestPath: nil,
                protectedCount: protectedCount,
                spanDays: 0
            )
        }
        let spanDays = Int(max(0, newest.ts - oldest.ts) / 86_400)
        return DuplicateGroupComparison(
            newestPath: newest.file.path,
            oldestPath: oldest.file.path,
            protectedCount: protectedCount,
            spanDays: spanDays
        )
    }
}
public enum LargeFileQuery {
    public static func rows(
        _ files: [DiskNode],
        query: String = "",
        category: FileCategory? = nil,
        minimum: Int64 = 100 * 1024 * 1024,
        basis: SizeBasis = .allocated,
        staleDays: Int = 0,
        timeAxis: TimeAxis = .modified,
        referenceDate: Date = Date()
    ) -> [DiskNode] {
        let cutoff = Int64(referenceDate.timeIntervalSince1970) - Int64(staleDays) * 86_400
        return files.filter { node in
            let matchesStale = staleDays <= 0 || (timeAxis.timestamp(for: node).map { $0 <= cutoff } ?? false)
            return matchesStale && basis.size(node) >= minimum && (category == nil || FileCategory.classify(node.name, allocated: node.allocated) == category) && (query.isEmpty || node.path.localizedCaseInsensitiveContains(query))
        }.sorted { basis.size($0) == basis.size($1) ? $0.path < $1.path : basis.size($0) > basis.size($1) }
    }

    public static func clutterSummary(
        _ files: [DiskNode],
        timeAxis: TimeAxis = .modified,
        referenceDate: Date = Date()
    ) -> ClutterHighlightSummary {
        let cutoff90 = Int64(referenceDate.timeIntervalSince1970) - 90 * 86_400
        var mediaAllocated: Int64 = 0
        var mediaCount = 0
        var archiveAllocated: Int64 = 0
        var archiveCount = 0
        var stale90Allocated: Int64 = 0
        var stale90Count = 0
        var largestFile: DiskNode?

        for node in files {
            let category = FileCategory.classify(node.name, allocated: node.allocated)
            switch category {
            case .video, .audio, .image:
                mediaAllocated += node.allocated
                mediaCount += 1
            case .archive:
                archiveAllocated += node.allocated
                archiveCount += 1
            case .source, .document, .other:
                break
            }

            if let ts = timeAxis.timestamp(for: node), ts <= cutoff90 {
                stale90Allocated += node.allocated
                stale90Count += 1
            }

            if let current = largestFile {
                if node.allocated > current.allocated || (node.allocated == current.allocated && node.path < current.path) {
                    largestFile = node
                }
            } else {
                largestFile = node
            }
        }

        return ClutterHighlightSummary(
            mediaAllocated: mediaAllocated,
            mediaCount: mediaCount,
            archiveAllocated: archiveAllocated,
            archiveCount: archiveCount,
            stale90Allocated: stale90Allocated,
            stale90Count: stale90Count,
            largestFile: largestFile
        )
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
extension Recommendation: Equatable {
    public static func == (lhs: Recommendation, rhs: Recommendation) -> Bool {
        lhs.node == rhs.node && lhs.category == rhs.category
    }
}

/// Logical application or toolchain grouping of cache cleanup recommendations.
public struct RecommendationAppGroup: Identifiable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var symbol: String
    public var allocated: Int64
    public var eligibleCount: Int
    public var blockedCount: Int
    public var items: [Recommendation]

    public init(
        id: String,
        name: String,
        symbol: String,
        allocated: Int64,
        eligibleCount: Int,
        blockedCount: Int,
        items: [Recommendation]
    ) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.allocated = allocated
        self.eligibleCount = eligibleCount
        self.blockedCount = blockedCount
        self.items = items
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
    public static func sanitizedSelection(_ selected: Set<String>, in items: [Recommendation], fresh: Bool) -> Set<String> {
        guard fresh else { return [] }
        let allowed = Set(items.filter { !$0.blocked }.map(\.id))
        return selected.intersection(allowed)
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

    /// Groups recommendations by recognized macOS app, developer toolchain, or extracted bundle/app name, sorted descending by allocated bytes.
    public static func groupedByApplication(
        _ recommendations: [Recommendation],
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [RecommendationAppGroup] {
        guard !recommendations.isEmpty else { return [] }
        let homePath = home.standardizedFileURL.path

        struct Bucket {
            var id: String
            var name: String
            var symbol: String
            var items: [Recommendation]
        }

        var buckets: [String: Bucket] = [:]
        for item in recommendations {
            let descriptor = groupDescriptor(for: item, homePath: homePath)
            if var existing = buckets[descriptor.id] {
                existing.items.append(item)
                if upperCaseCount(descriptor.name) > upperCaseCount(existing.name) {
                    existing.name = descriptor.name
                }
                buckets[descriptor.id] = existing
            } else {
                buckets[descriptor.id] = Bucket(
                    id: descriptor.id,
                    name: descriptor.name,
                    symbol: descriptor.symbol,
                    items: [item]
                )
            }
        }

        return buckets.values.map { bucket in
            let sortedItems = bucket.items.sorted { a, b in
                if a.node.allocated != b.node.allocated { return a.node.allocated > b.node.allocated }
                return a.id < b.id
            }
            let allocated = sortedItems.reduce(Int64(0)) { $0 + $1.node.allocated }
            let eligibleCount = sortedItems.filter { !$0.blocked }.count
            let blockedCount = sortedItems.count - eligibleCount
            return RecommendationAppGroup(
                id: bucket.id,
                name: bucket.name,
                symbol: bucket.symbol,
                allocated: allocated,
                eligibleCount: eligibleCount,
                blockedCount: blockedCount,
                items: sortedItems
            )
        }.sorted { a, b in
            if a.allocated != b.allocated { return a.allocated > b.allocated }
            if a.name != b.name { return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending }
            return a.id < b.id
        }
    }

    private static func upperCaseCount(_ text: String) -> Int {
        text.unicodeScalars.filter { CharacterSet.uppercaseLetters.contains($0) }.count
    }

    private static func groupDescriptor(
        for item: Recommendation,
        homePath: String
    ) -> (id: String, name: String, symbol: String) {
        let path = item.node.path
        let rel: String
        if path == homePath {
            rel = ""
        } else if path.hasPrefix(homePath + "/") {
            rel = String(path.dropFirst(homePath.count))
        } else {
            rel = path
        }
        let lowerRel = rel.lowercased()
        let lowerName = item.node.name.lowercased()

        if item.category == .build {
            return ("toolchain:project-builds", "项目构建 (.build)", "cube.box.fill")
        }

        if item.category == .xcode
            || lowerRel.contains("/library/developer/xcode/")
            || lowerRel.contains("/library/developer/coresimulator/")
            || lowerName.contains("com.apple.dt.xcode")
            || lowerName == "xcode" {
            return ("app:xcode", "Xcode", "hammer.fill")
        }

        if lowerRel.contains("/library/application support/cursor/")
            || lowerName.contains("com.todesktop.230313mzl4w4u92")
            || lowerName == "cursor"
            || lowerName.hasPrefix("cursor.")
            || lowerName.hasSuffix(".cursor")
            || lowerName.hasSuffix(".cursor.savedstate") {
            return ("app:cursor", "Cursor", "chevron.left.forwardslash.chevron.right")
        }

        if lowerRel.contains("/library/application support/code/")
            || lowerName.contains("com.microsoft.vscode")
            || (lowerName == "code" && lowerRel.contains("/library/"))
            || lowerName == "vscode"
            || lowerName.hasPrefix("vscode") {
            return ("app:vscode", "VS Code", "chevron.left.forwardslash.chevron.right")
        }

        if lowerRel.contains("/library/application support/windsurf/")
            || lowerName.contains("windsurf") {
            return ("app:windsurf", "Windsurf", "wind")
        }

        if lowerRel.contains("/library/application support/claude/")
            || lowerName.contains("com.anthropic.claude")
            || lowerName == "claude"
            || lowerName.hasPrefix("claude.")
            || lowerName.hasSuffix(".claude.savedstate") {
            return ("app:claude", "Claude", "sparkles")
        }

        if (item.category == .update && lowerRel.contains("codex-runtime")) || lowerName.contains("codex") {
            return ("app:codex", "Codex", "terminal.fill")
        }

        if lowerName.contains("com.apple.safari")
            || lowerName == "safari"
            || lowerName == "safari.savedstate" {
            return ("app:safari", "Safari", "safari.fill")
        }

        if lowerName.contains("com.google.chrome")
            || lowerRel.contains("/google/chrome")
            || lowerName == "chrome"
            || lowerName == "google chrome" {
            return ("app:chrome", "Google Chrome", "globe")
        }

        if lowerName.contains("company.thebrowser.browser")
            || lowerName == "arc"
            || lowerName == "arc.savedstate" {
            return ("app:arc", "Arc", "globe")
        }

        if lowerName.contains("org.mozilla.firefox")
            || lowerName == "firefox"
            || lowerName == "firefox.savedstate" {
            return ("app:firefox", "Firefox", "flame.fill")
        }

        if lowerRel == "/library/caches/homebrew"
            || lowerRel.hasSuffix("/library/caches/homebrew")
            || lowerName == "homebrew" {
            return ("toolchain:homebrew", "Homebrew", "shippingbox.fill")
        }

        if lowerRel.hasPrefix("/.cargo/") || lowerRel.contains("/.cargo/") || lowerName == "cargo" {
            return ("toolchain:cargo", "Cargo / Rust", "gearshape.2.fill")
        }

        let nodePrefixes = [
            "/.npm/", "/.nvm/", "/.pnpm-store", "/.bun/", "/.yarn/",
            "/.cache/deno", "/.cache/prisma", "/.cache/turbo", "/.cache/electron", "/.cache/cypress"
        ]
        if nodePrefixes.contains(where: { lowerRel.hasPrefix($0) || lowerRel.contains($0) }) {
            return ("toolchain:node", "Node / npm / pnpm / bun", "cube.fill")
        }

        if lowerRel.hasPrefix("/.gradle/")
            || lowerRel.contains("/.gradle/")
            || lowerRel.contains("/.cache/jetbrains")
            || lowerRel.contains("/library/caches/jetbrains")
            || lowerName.contains("jetbrains")
            || lowerName.hasPrefix("com.jetbrains.") {
            return ("toolchain:jetbrains", "Gradle / JetBrains", "wrench.and.screwdriver.fill")
        }

        let pythonPrefixes = ["/.cache/pip", "/.cache/uv", "/.cache/torch", "/.cache/huggingface", "/.cache/pre-commit"]
        if pythonPrefixes.contains(where: { lowerRel.hasPrefix($0) || lowerRel.contains($0) }) {
            return ("toolchain:python", "Python / uv / pip", "terminal.fill")
        }

        if lowerRel.hasPrefix("/.docker/")
            || lowerRel.contains("/.docker/")
            || lowerName.contains("com.docker.")
            || lowerName == "docker" {
            return ("toolchain:docker", "Docker", "shippingbox.fill")
        }

        if ["/.cache/zig", "/.cache/sccache", "/.cache/ccache"].contains(where: { lowerRel.hasPrefix($0) || lowerRel.contains($0) }) {
            return ("toolchain:cc-zig", "Zig / ccache / sccache", "cpu.fill")
        }

        if lowerRel.hasPrefix("/.cache/go-build") || lowerRel.contains("/.cache/go-build") {
            return ("toolchain:go", "Go", "hammer.fill")
        }

        if lowerRel.contains("/library/caches/cocoapods") {
            return ("toolchain:cocoapods", "CocoaPods", "shippingbox.fill")
        }

        if lowerRel.hasPrefix("/.pub-cache") || lowerRel.contains("/.pub-cache") {
            return ("toolchain:dart", "Dart / Pub", "shippingbox.fill")
        }

        if lowerRel.hasPrefix("/.cache/bazel") || lowerRel.contains("/.cache/bazel") {
            return ("toolchain:bazel", "Bazel", "hammer.fill")
        }

        if ["/.cache/playwright", "/.cache/ms-playwright", "/.cache/puppeteer"].contains(where: { lowerRel.hasPrefix($0) || lowerRel.contains($0) }) {
            return ("toolchain:browser-test", "Playwright / Puppeteer", "globe")
        }

        if lowerRel.hasPrefix("/.sbt/") || lowerRel.contains("/.sbt/") || lowerRel.hasPrefix("/.ivy2/") || lowerRel.contains("/.ivy2/") {
            return ("toolchain:jvm", "sbt / Ivy", "wrench.and.screwdriver.fill")
        }

        if lowerName.hasSuffix(".savedstate")
            || lowerRel.contains("/library/caches/")
            || lowerRel.contains("/library/logs/")
            || lowerRel.contains("/library/saved application state/") {
            let friendly = friendlyAppName(from: item.node.name)
            let normalizedKey = friendly.lowercased().unicodeScalars
                .filter { CharacterSet.alphanumerics.contains($0) }
                .map(String.init)
                .joined()
            let key = normalizedKey.isEmpty ? lowerName : normalizedKey
            return ("app:\(key)", friendly, "app.fill")
        }

        return ("category:\(item.category.rawValue)", item.category.title, item.category.symbol)
    }

    private static func friendlyAppName(from rawDirectoryName: String) -> String {
        var stem = rawDirectoryName
        if stem.lowercased().hasSuffix(".savedstate") {
            stem = String(stem.dropLast(".savedstate".count))
        }
        let parts = stem.split(separator: ".").map(String.init)
        let reverseDNSPrefixes: Set<String> = [
            "com", "org", "io", "net", "app", "dev", "me", "co", "ai",
            "edu", "gov", "company", "studio", "us", "uk", "de", "jp", "cn"
        ]
        let chosen: String
        if parts.count >= 3, reverseDNSPrefixes.contains(parts[0].lowercased()) {
            let genericSuffixes: Set<String> = [
                "app", "macos", "osx", "mac", "desktop", "client", "helper",
                "shipit", "agent", "service", "daemon", "extension", "framework",
                "cache", "caches", "logs", "savedstate", "shared", "runtime", "installer"
            ]
            var tail = Array(parts.dropFirst(1))
            if tail.count >= 2 && tail[0].lowercased() == "apple" {
                tail.removeFirst()
                if tail.count >= 2 && tail[0].lowercased() == "dt" {
                    tail.removeFirst()
                }
            }
            var idx = tail.count - 1
            while idx > 0 && genericSuffixes.contains(tail[idx].lowercased()) {
                idx -= 1
            }
            chosen = tail[idx]
        } else {
            chosen = stem
        }
        return formatAppToken(chosen)
    }

    private static func formatAppToken(_ token: String) -> String {
        guard !token.isEmpty else { return token }
        let hasUppercase = token.unicodeScalars.contains { CharacterSet.uppercaseLetters.contains($0) }
        if hasUppercase {
            return token
        }
        let words = token.split(whereSeparator: { $0 == "-" || $0 == "_" }).map { part -> String in
            guard let first = part.first else { return "" }
            return String(first).uppercased() + part.dropFirst()
        }.filter { !$0.isEmpty }
        return words.isEmpty ? token : words.joined(separator: " ")
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
    public static func parentScope(root: String, current: String) -> String? {
        let stdRoot = URL(fileURLWithPath: root).standardizedFileURL.path
        let stdCurrent = URL(fileURLWithPath: current).standardizedFileURL.path
        guard stdCurrent != stdRoot, stdCurrent != "/", stdCurrent.hasPrefix(stdRoot == "/" ? "/" : stdRoot + "/") else { return nil }
        let parent = URL(fileURLWithPath: stdCurrent).deletingLastPathComponent().path
        return parent == stdRoot ? nil : parent
    }
    public static func resolveNavigationTarget(for path: String, in result: ScanResult?) -> (browseScope: String?, selectedPath: String?)? {
        guard let result else { return nil }
        let stdRoot = URL(fileURLWithPath: result.root).standardizedFileURL.path
        let stdPath = URL(fileURLWithPath: path).standardizedFileURL.path
        guard stdPath == stdRoot || stdPath.hasPrefix(stdRoot == "/" ? "/" : stdRoot + "/") else { return nil }
        if canBrowse(.init(path: stdPath, kind: .directory), in: result) {
            let scope = stdPath == stdRoot ? nil : stdPath
            let firstChild = result.nodes.filter { $0.parent == stdPath && $0.path != stdPath }.sorted { $0.allocated == $1.allocated ? $0.path < $1.path : $0.allocated > $1.allocated }.first?.path
            return (scope, firstChild)
        }
        if result.nodes.contains(where: { $0.path == stdPath }) {
            let parent = URL(fileURLWithPath: stdPath).deletingLastPathComponent().path
            return (parent == stdRoot ? nil : parent, stdPath)
        }
        return nil
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
struct DuplicateBucketKey: Hashable, Sendable {
    let logicalSize: Int64
    let ext: String
}

// Kept separate from the directory display budget: metadata beyond 40,000 nodes still contributes.
struct AnalysisAccumulator {
    static let maxTopLargePerBasis = 200
    static let maxDuplicateBucketFiles = 20
    static let maxDuplicateBuckets = 50_000
    static let maxDuplicateGroupsOutput = 100

    var types: [FileCategory: FileTypeUsage] = [:]
    var extMap: [FileCategory: [String: ExtensionUsage]] = [:]
    var ageMap: [AgeBucket: AgeBucketUsage] = [:]
    var physical: [DiskNode] = []; var logical: [DiskNode] = []
    var physicalFloor: Int64 = 0; var logicalFloor: Int64 = 0
    var duplicateBuckets: [DuplicateBucketKey: [DiskNode]] = [:]

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
        if node.allocated >= 1024 * 1024 && (physical.count < Self.maxTopLargePerBasis || node.allocated >= physicalFloor) {
            physical.append(node)
            if physical.count >= Self.maxTopLargePerBasis * 2 {
                physical.sort { $0.allocated == $1.allocated ? $0.path < $1.path : $0.allocated > $1.allocated }
                physical = Array(physical.prefix(Self.maxTopLargePerBasis))
                physicalFloor = physical.last?.allocated ?? 0
            }
        }
        if node.logical >= 1024 * 1024 && (logical.count < Self.maxTopLargePerBasis || node.logical >= logicalFloor) {
            logical.append(node)
            if logical.count >= Self.maxTopLargePerBasis * 2 {
                logical.sort { $0.logical == $1.logical ? $0.path < $1.path : $0.logical > $1.logical }
                logical = Array(logical.prefix(Self.maxTopLargePerBasis))
                logicalFloor = logical.last?.logical ?? 0
            }
        }
        if node.kind == .file && node.logical >= 1024 * 1024 {
            let dupKey = DuplicateBucketKey(logicalSize: node.logical, ext: extKey)
            if var list = duplicateBuckets[dupKey] {
                if list.count < Self.maxDuplicateBucketFiles {
                    list.append(node)
                    duplicateBuckets[dupKey] = list
                }
            } else if duplicateBuckets.count < Self.maxDuplicateBuckets {
                duplicateBuckets[dupKey] = [node]
            }
        }
    }

    mutating func merge(_ other: AnalysisAccumulator) {
        for (cat, item) in other.types {
            var usage = types[cat] ?? .init(category: cat)
            usage.allocated += item.allocated
            usage.logical += item.logical
            usage.files += item.files
            types[cat] = usage
        }
        for (cat, otherExts) in other.extMap {
            var catExts = extMap[cat] ?? [:]
            for (extKey, extItem) in otherExts {
                var extUsage = catExts[extKey] ?? .init(ext: extKey)
                extUsage.allocated += extItem.allocated
                extUsage.logical += extItem.logical
                extUsage.files += extItem.files
                catExts[extKey] = extUsage
            }
            extMap[cat] = catExts
        }
        for (bucket, item) in other.ageMap {
            var bUsage = ageMap[bucket] ?? .init(bucket: bucket)
            bUsage.allocated += item.allocated
            bUsage.logical += item.logical
            bUsage.files += item.files
            ageMap[bucket] = bUsage
        }
        if !other.physical.isEmpty {
            physical.append(contentsOf: other.physical)
            if physical.count > Self.maxTopLargePerBasis {
                physical.sort { $0.allocated == $1.allocated ? $0.path < $1.path : $0.allocated > $1.allocated }
                physical = Array(physical.prefix(Self.maxTopLargePerBasis))
                physicalFloor = physical.last?.allocated ?? 0
            }
        }
        if !other.logical.isEmpty {
            logical.append(contentsOf: other.logical)
            if logical.count > Self.maxTopLargePerBasis {
                logical.sort { $0.logical == $1.logical ? $0.path < $1.path : $0.logical > $1.logical }
                logical = Array(logical.prefix(Self.maxTopLargePerBasis))
                logicalFloor = logical.last?.logical ?? 0
            }
        }
        for (key, list) in other.duplicateBuckets {
            if var existing = duplicateBuckets[key] {
                if existing.count < Self.maxDuplicateBucketFiles {
                    var seen = Set(existing.map(\.path))
                    for item in list where !seen.contains(item.path) {
                        existing.append(item)
                        seen.insert(item.path)
                        if existing.count >= Self.maxDuplicateBucketFiles { break }
                    }
                    duplicateBuckets[key] = existing
                }
            } else if duplicateBuckets.count < Self.maxDuplicateBuckets {
                duplicateBuckets[key] = list
            }
        }
    }

    func result(projects: [ProjectSummary] = []) -> ScanAnalysis {
        let topPhysical = physical.sorted { $0.allocated == $1.allocated ? $0.path < $1.path : $0.allocated > $1.allocated }.prefix(Self.maxTopLargePerBasis)
        let topLogical = logical.sorted { $0.logical == $1.logical ? $0.path < $1.path : $0.logical > $1.logical }.prefix(Self.maxTopLargePerBasis)
        let top = Array(topPhysical) + Array(topLogical)
        let unique = Dictionary(top.map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })
        let enrichedTypes = types.values.map { item -> FileTypeUsage in
            var copy = item
            let exts = (extMap[item.category]?.values.sorted { $0.allocated == $1.allocated ? $0.ext < $1.ext : $0.allocated > $1.allocated }) ?? []
            copy.extensions = Array(exts.prefix(10))
            return copy
        }.sorted { $0.allocated == $1.allocated ? $0.category.rawValue < $1.category.rawValue : $0.allocated > $1.allocated }
        let orderedBuckets = AgeBucket.allCases.map { ageMap[$0] ?? .init(bucket: $0) }
        var groups: [DuplicateSizeGroup] = []
        for (key, list) in duplicateBuckets where list.count >= 2 {
            let sortedFiles = list.sorted { $0.path < $1.path }
            let maxAllocated = sortedFiles.map(\.allocated).max() ?? 0
            let category = FileCategory.classify(sortedFiles[0].name, allocated: maxAllocated)
            groups.append(DuplicateSizeGroup(logicalSize: key.logicalSize, ext: key.ext, category: category, files: sortedFiles))
        }
        let topDuplicates = Array(groups.sorted {
            if $0.potentialRedundantAllocated != $1.potentialRedundantAllocated {
                return $0.potentialRedundantAllocated > $1.potentialRedundantAllocated
            }
            if $0.totalAllocated != $1.totalAllocated {
                return $0.totalAllocated > $1.totalAllocated
            }
            if $0.logicalSize != $1.logicalSize {
                return $0.logicalSize > $1.logicalSize
            }
            return $0.id < $1.id
        }.prefix(Self.maxDuplicateGroupsOutput))
        return .init(
            fileTypes: enrichedTypes,
            largeFiles: unique.values.sorted { $0.allocated == $1.allocated ? $0.path < $1.path : $0.allocated > $1.allocated },
            projects: projects,
            ageBuckets: orderedBuckets,
            duplicateGroups: topDuplicates
        )
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
    public var profile: ScanPerformanceProfile
    public var showDuplicates: Bool
    public var showVolumes: Bool
    public var showApps: Bool
    public var showHealth: Bool
    public var showCloud: Bool
    public var showVersion: Bool
    public init(
        rootPath: String = "",
        jsonPath: String? = nil,
        csvPath: String? = nil,
        comparePath: String? = nil,
        topLimit: Int = 15,
        profile: ScanPerformanceProfile = .balanced,
        showDuplicates: Bool = false,
        showVolumes: Bool = false,
        showApps: Bool = false,
        showHealth: Bool = false,
        showCloud: Bool = false,
        showVersion: Bool = false
    ) {
        self.rootPath = rootPath
        self.jsonPath = jsonPath
        self.csvPath = csvPath
        self.comparePath = comparePath
        self.topLimit = topLimit
        self.profile = profile
        self.showDuplicates = showDuplicates
        self.showVolumes = showVolumes
        self.showApps = showApps
        self.showHealth = showHealth
        self.showCloud = showCloud
        self.showVersion = showVersion
    }
    private static func expand(_ raw: String) -> String {
        NSString(string: raw).expandingTildeInPath
    }
    public static func parse(_ args: [String]) throws -> ScanCLIOptions {
        guard !args.isEmpty else { throw ScanFailure.invalidRoot }
        var opts = ScanCLIOptions()
        var hasRoot = false
        var i = 0
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
            } else if flag == "--profile" {
                guard i + 1 < args.count, let profile = ScanPerformanceProfile(rawValue: args[i + 1]) else { throw ScanFailure.invalidRoot }
                opts.profile = profile; i += 2
            } else if flag == "--duplicates" {
                opts.showDuplicates = true; i += 1
            } else if flag == "--volumes" {
                opts.showVolumes = true; i += 1
            } else if flag == "--apps" {
                opts.showApps = true; i += 1
            } else if flag == "--health" {
                opts.showHealth = true; i += 1
            } else if flag == "--cloud" {
                opts.showCloud = true; i += 1
            } else if flag == "--version" {
                opts.showVersion = true; i += 1
            } else if !flag.hasPrefix("-"), !flag.isEmpty, !hasRoot {
                opts.rootPath = expand(flag); hasRoot = true; i += 1
            } else {
                throw ScanFailure.invalidRoot
            }
        }
        let standaloneInfoOnly = opts.showVersion || opts.showVolumes || opts.showApps || opts.showHealth || opts.showCloud
        let needsRoot = opts.jsonPath != nil || opts.csvPath != nil || opts.comparePath != nil || opts.showDuplicates || !standaloneInfoOnly
        guard !needsRoot || hasRoot else { throw ScanFailure.invalidRoot }
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
