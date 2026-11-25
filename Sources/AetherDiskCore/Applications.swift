import Foundation
import Darwin

public enum AppDistributionSource: String, Codable, Sendable, Equatable {
    case appStore
    case standalone

    public var title: String {
        switch self {
        case .appStore: "App Store"
        case .standalone: "独立安装"
        }
    }
}

public enum AppFilterMode: String, CaseIterable, Sendable, Identifiable {
    case all
    case large
    case unused
    case withCaches
    case orphans

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: "全部应用"
        case .large: "大型应用"
        case .unused: "久未使用"
        case .withCaches: "含关联缓存"
        case .orphans: "卸载残留线索"
        }
    }
}

public enum AppSortMode: String, CaseIterable, Sendable, Identifiable {
    case totalFootprint
    case bundleSize
    case cacheSize
    case stale

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .totalFootprint: "总占用"
        case .bundleSize: "本体大小"
        case .cacheSize: "关联缓存"
        case .stale: "久未使用"
        }
    }
}

public struct AppAssociatedItem: Identifiable, Codable, Sendable, Equatable {
    public var id: String { path }
    public var path: String
    public var name: String { URL(fileURLWithPath: path).lastPathComponent }
    public var category: CacheCategory
    public var allocated: Int64
    public var blocked: Bool
    public var protectionTitles: [String]

    public init(
        path: String,
        category: CacheCategory,
        allocated: Int64,
        blocked: Bool,
        protectionTitles: [String]
    ) {
        self.path = path
        self.category = category
        self.allocated = allocated
        self.blocked = blocked
        self.protectionTitles = protectionTitles
    }
}

public struct InstalledAppItem: Identifiable, Codable, Sendable, Equatable {
    public var id: String { path }
    public var name: String
    public var path: String
    public var bundleAllocated: Int64
    public var bundleLogical: Int64
    public var fileCount: Int
    public var modifiedAt: Int64?
    public var lastUsedAt: Int64? = nil
    public var source: AppDistributionSource
    public var associatedItems: [AppAssociatedItem]

    public var associatedAllocated: Int64 {
        associatedItems.reduce(0) { $0 + $1.allocated }
    }

    public var eligibleCacheAllocated: Int64 {
        associatedItems.filter { !$0.blocked }.reduce(0) { $0 + $1.allocated }
    }

    public var eligibleCachePaths: [String] {
        associatedItems.filter { !$0.blocked }.map(\.path)
    }

    public var totalFootprint: Int64 {
        bundleAllocated + associatedAllocated
    }

    public func unusedDays(referenceDate: Date = Date()) -> Int? {
        guard let ts = lastUsedAt ?? modifiedAt else { return nil }
        let nowTs = Int64(referenceDate.timeIntervalSince1970)
        return max(0, Int((nowTs - ts) / 86_400))
    }

    public func isStale(days: Int = 90, referenceDate: Date = Date()) -> Bool {
        guard days > 0, let ts = lastUsedAt ?? modifiedAt else { return false }
        return ts <= Int64(referenceDate.timeIntervalSince1970) - Int64(days) * 86_400
    }

    public init(
        name: String,
        path: String,
        bundleAllocated: Int64,
        bundleLogical: Int64,
        fileCount: Int,
        modifiedAt: Int64?,
        lastUsedAt: Int64? = nil,
        source: AppDistributionSource,
        associatedItems: [AppAssociatedItem] = []
    ) {
        self.name = name
        self.path = path
        self.bundleAllocated = bundleAllocated
        self.bundleLogical = bundleLogical
        self.fileCount = fileCount
        self.modifiedAt = modifiedAt
        self.lastUsedAt = lastUsedAt
        self.source = source
        self.associatedItems = associatedItems
    }
}

public struct OrphanedAppDataItem: Identifiable, Codable, Sendable, Equatable {
    public var id: String { path }
    public var path: String
    public var name: String { URL(fileURLWithPath: path).lastPathComponent }
    public var inferredBundleToken: String
    public var category: CacheCategory
    public var allocated: Int64
    public var modifiedAt: Int64?
    public var blocked: Bool
    public var protectionTitles: [String]

    public init(
        path: String,
        inferredBundleToken: String,
        category: CacheCategory,
        allocated: Int64,
        modifiedAt: Int64?,
        blocked: Bool,
        protectionTitles: [String]
    ) {
        self.path = path
        self.inferredBundleToken = inferredBundleToken
        self.category = category
        self.allocated = allocated
        self.modifiedAt = modifiedAt
        self.blocked = blocked
        self.protectionTitles = protectionTitles
    }
}

public struct ApplicationsReport: Codable, Sendable, Equatable {
    public var apps: [InstalledAppItem]
    public var orphanedData: [OrphanedAppDataItem]
    public var inspectedAt: Date
    public var unreadableCount: Int

    public var totalAppsBundleAllocated: Int64 {
        apps.reduce(0) { $0 + $1.bundleAllocated }
    }

    public var totalAssociatedAllocated: Int64 {
        apps.reduce(0) { $0 + $1.associatedAllocated }
    }

    public var totalOrphanedAllocated: Int64 {
        orphanedData.reduce(0) { $0 + $1.allocated }
    }

    public init(
        apps: [InstalledAppItem],
        orphanedData: [OrphanedAppDataItem],
        inspectedAt: Date = Date(),
        unreadableCount: Int = 0
    ) {
        self.apps = apps
        self.orphanedData = orphanedData
        self.inspectedAt = inspectedAt
        self.unreadableCount = unreadableCount
    }
}

public enum ApplicationQuery {
    public static func filterApps(
        _ apps: [InstalledAppItem],
        mode: AppFilterMode,
        sort: AppSortMode,
        query: String,
        referenceDate: Date = Date()
    ) -> [InstalledAppItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = apps.filter { app in
            let matchesQuery = trimmed.isEmpty
                || app.name.localizedCaseInsensitiveContains(trimmed)
                || app.path.localizedCaseInsensitiveContains(trimmed)
            guard matchesQuery else { return false }
            switch mode {
            case .all, .orphans:
                return true
            case .large:
                return app.totalFootprint >= 250 * 1024 * 1024
            case .unused:
                return app.isStale(days: 90, referenceDate: referenceDate)
            case .withCaches:
                return !app.associatedItems.isEmpty
            }
        }
        return filtered.sorted { a, b in
            switch sort {
            case .totalFootprint:
                return a.totalFootprint == b.totalFootprint ? a.path < b.path : a.totalFootprint > b.totalFootprint
            case .bundleSize:
                return a.bundleAllocated == b.bundleAllocated ? a.path < b.path : a.bundleAllocated > b.bundleAllocated
            case .cacheSize:
                return a.associatedAllocated == b.associatedAllocated
                    ? (a.totalFootprint == b.totalFootprint ? a.path < b.path : a.totalFootprint > b.totalFootprint)
                    : a.associatedAllocated > b.associatedAllocated
            case .stale:
                let ma = a.lastUsedAt ?? a.modifiedAt ?? Int64.max
                let mb = b.lastUsedAt ?? b.modifiedAt ?? Int64.max
                return ma == mb ? a.totalFootprint > b.totalFootprint : ma < mb
            }
        }
    }
}

public enum ApplicationInspector {
    private struct InodeIdentity: Hashable {
        let dev: dev_t
        let ino: ino_t
    }

    private static let maxEntriesPerBundle = 25_000
    private static let maxDepthPerBundle = 12
    private static let maxEntriesPerCacheDir = 8_000

    /// Strictly read-only, metadata-only `.app` bundle & user-space cache/leftover inspector.
    /// Never opens or reads any regular file content, never follows symlinks, never crosses volume boundaries.
    public static func inspect(
        applicationRoots: [URL]? = nil,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        protectedPaths: [String] = [],
        cancellation: ScanCancellation = .init()
    ) -> ApplicationsReport {
        let stdHome = home.standardizedFileURL
        let defaultRoots = [
            URL(fileURLWithPath: "/Applications"),
            stdHome.appendingPathComponent("Applications")
        ]
        let roots = applicationRoots ?? defaultRoots

        var seenAppPaths = Set<String>()
        var discoveredBundleURLs: [URL] = []
        var unreadableCount = 0

        for rootURL in roots {
            if cancellation.isCancelled { break }
            let stdRoot = rootURL.standardizedFileURL
            var st = stat()
            guard lstat(stdRoot.path, &st) == 0,
                  (st.st_mode & S_IFMT) == S_IFDIR,
                  stdRoot.resolvingSymlinksInPath().path == stdRoot.path else {
                continue
            }
            let rootDev = st.st_dev
            collectAppBundles(
                in: stdRoot,
                rootDevice: rootDev,
                depth: 0,
                maxContainerDepth: 2,
                seenPaths: &seenAppPaths,
                output: &discoveredBundleURLs,
                unreadableCount: &unreadableCount,
                cancellation: cancellation
            )
        }

        // Inspect user-space cache, logs, and saved state directories read-only.
        let userDataDirs = scanUserLibraryCandidates(
            home: stdHome,
            protectedPaths: protectedPaths,
            unreadableCount: &unreadableCount,
            cancellation: cancellation
        )

        var claimedDataPaths = Set<String>()
        var installedApps: [InstalledAppItem] = []
        installedApps.reserveCapacity(discoveredBundleURLs.count)

        for bundleURL in discoveredBundleURLs {
            if cancellation.isCancelled { break }
            guard let summary = measureDirectoryMetadata(
                at: bundleURL,
                maxEntries: maxEntriesPerBundle,
                maxDepth: maxDepthPerBundle,
                trackProtection: false,
                cancellation: cancellation
            ) else {
                unreadableCount += 1
                continue
            }

            let rawStem = bundleURL.deletingPathExtension().lastPathComponent
            let normToken = normalizeToken(rawStem)
            let isMAS = hasAppStoreReceiptDirectoryEntry(bundleURL: bundleURL, expectedDevice: summary.device)

            var matchedData: [AppAssociatedItem] = []
            var appLastUsed = maxOptional(summary.accessedAt, summary.modifiedAt)
            if normToken.count >= 3 {
                for candidate in userDataDirs where matchesAppToken(appNorm: normToken, candidateTokens: candidate.tokens) {
                    claimedDataPaths.insert(candidate.path)
                    appLastUsed = maxOptional(appLastUsed, maxOptional(candidate.accessedAt, candidate.modifiedAt))
                    matchedData.append(
                        AppAssociatedItem(
                            path: candidate.path,
                            category: candidate.category,
                            allocated: candidate.allocated,
                            blocked: candidate.blocked,
                            protectionTitles: candidate.protectionTitles
                        )
                    )
                }
            }
            matchedData.sort { $0.allocated == $1.allocated ? $0.path < $1.path : $0.allocated > $1.allocated }

            installedApps.append(
                InstalledAppItem(
                    name: rawStem,
                    path: bundleURL.path,
                    bundleAllocated: summary.allocated,
                    bundleLogical: summary.logical,
                    fileCount: summary.files,
                    modifiedAt: summary.modifiedAt,
                    lastUsedAt: appLastUsed,
                    source: isMAS ? .appStore : .standalone,
                    associatedItems: matchedData
                )
            )
        }

        installedApps.sort {
            $0.totalFootprint == $1.totalFootprint ? $0.path < $1.path : $0.totalFootprint > $1.totalFootprint
        }

        let allInstalledTokens = Set(installedApps.map { normalizeToken($0.name) }.filter { $0.count >= 3 })
        var orphans: [OrphanedAppDataItem] = []

        for candidate in userDataDirs where !claimedDataPaths.contains(candidate.path) && candidate.allocated > 0 {
            guard candidate.looksLikeReverseDNSAppContainer else { continue }
            guard !candidate.isSystemVendor else { continue }
            let overlapsAnyInstalled = candidate.tokens.contains { tok in
                tok.count >= 3 && allInstalledTokens.contains { appTok in
                    appTok == tok || (tok.count >= 4 && appTok.contains(tok)) || (appTok.count >= 4 && tok.contains(appTok))
                }
            }
            guard !overlapsAnyInstalled else { continue }
            orphans.append(
                OrphanedAppDataItem(
                    path: candidate.path,
                    inferredBundleToken: candidate.displayToken,
                    category: candidate.category,
                    allocated: candidate.allocated,
                    modifiedAt: candidate.modifiedAt,
                    blocked: candidate.blocked,
                    protectionTitles: candidate.protectionTitles
                )
            )
        }

        orphans.sort { $0.allocated == $1.allocated ? $0.path < $1.path : $0.allocated > $1.allocated }

        return ApplicationsReport(
            apps: installedApps,
            orphanedData: orphans,
            inspectedAt: Date(),
            unreadableCount: unreadableCount
        )
    }

    // MARK: - Private Read-Only Helpers

    private struct DirectoryMeasurement {
        let device: dev_t
        let allocated: Int64
        let logical: Int64
        let files: Int
        let modifiedAt: Int64?
        let accessedAt: Int64?
        let protection: Set<Protection>
        let restricted: Bool
    }

    private struct UserDataCandidate {
        let path: String
        let category: CacheCategory
        let allocated: Int64
        let modifiedAt: Int64?
        let accessedAt: Int64?
        let blocked: Bool
        let protectionTitles: [String]
        let tokens: [String]
        let displayToken: String
        let looksLikeReverseDNSAppContainer: Bool
        let isSystemVendor: Bool
    }

    private static func maxOptional(_ a: Int64?, _ b: Int64?) -> Int64? {
        switch (a, b) {
        case (nil, nil): return nil
        case (let x?, nil): return x
        case (nil, let y?): return y
        case (let x?, let y?): return max(x, y)
        }
    }

    private static func normalizeToken(_ text: String) -> String {
        let scalars = text.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        return String(String.UnicodeScalarView(scalars))
    }

    private static func extractCandidateTokens(directoryName: String) -> (tokens: [String], displayToken: String, reverseDNS: Bool, systemVendor: Bool) {
        var base = directoryName
        if base.lowercased().hasSuffix(".savedstate") {
            base = String(base.dropLast(".savedstate".count))
        }
        let lower = base.lowercased()
        let parts = lower.split(separator: ".").map(String.init)
        let reverseDNSPrefixes: Set<String> = ["com", "org", "io", "net", "app", "dev", "me", "co", "ai", " studio"]
        let isReverseDNS = parts.count >= 3 && reverseDNSPrefixes.contains(parts[0])
        let isSystem = lower.hasPrefix("com.apple.") || lower.hasPrefix("group.com.apple.") || lower.hasPrefix("com.aethernative.aetherdisk")

        var tokens: [String] = []
        let whole = normalizeToken(base)
        if !whole.isEmpty { tokens.append(whole) }
        if isReverseDNS {
            for part in parts.dropFirst(2) {
                let norm = normalizeToken(part)
                if norm.count >= 3 && !["macos", "desktop", "helper", "shipit", "agent", "client", "app"].contains(norm) {
                    tokens.append(norm)
                }
            }
            if parts.count >= 2 {
                let vendor = normalizeToken(parts[1])
                if vendor.count >= 4 && !["apple", "google", "microsoft", "jetbrains", "mozilla"].contains(vendor) {
                    tokens.append(vendor)
                }
            }
        }
        let display = isReverseDNS ? (parts.last ?? base) : base
        return (Array(Set(tokens)), display, isReverseDNS, isSystem)
    }

    private static func matchesAppToken(appNorm: String, candidateTokens: [String]) -> Bool {
        for tok in candidateTokens where tok.count >= 3 {
            if tok == appNorm { return true }
            if appNorm.count >= 4 && tok.hasPrefix(appNorm) { return true }
            if tok.count >= 5 && appNorm.contains(tok) { return true }
        }
        return false
    }

    private static func hasAppStoreReceiptDirectoryEntry(bundleURL: URL, expectedDevice: dev_t) -> Bool {
        let receiptPath = bundleURL.appendingPathComponent("Contents/_MASReceipt/receipt").path
        var st = stat()
        guard lstat(receiptPath, &st) == 0 else { return false }
        return st.st_dev == expectedDevice && (st.st_mode & S_IFMT) == S_IFREG
    }

    private static func collectAppBundles(
        in dirURL: URL,
        rootDevice: dev_t,
        depth: Int,
        maxContainerDepth: Int,
        seenPaths: inout Set<String>,
        output: inout [URL],
        unreadableCount: inout Int,
        cancellation: ScanCancellation
    ) {
        guard !cancellation.isCancelled, depth <= maxContainerDepth else { return }
        guard let handle = try? DirectoryHandle(path: dirURL.path) else {
            unreadableCount += 1
            return
        }
        defer { close(handle.descriptor) }

        guard let entries = try? handle.bulkEntries() else {
            unreadableCount += 1
            return
        }

        for entry in entries.sorted(by: { $0.name < $1.name }) {
            if cancellation.isCancelled { break }
            guard !entry.isSymlink, entry.isDirectory, entry.dev == rootDevice else { continue }
            let childURL = dirURL.appendingPathComponent(entry.name)
            if entry.name.lowercased().hasSuffix(".app") {
                if seenPaths.insert(childURL.path).inserted {
                    output.append(childURL)
                }
            } else if depth < maxContainerDepth && !entry.name.hasPrefix(".") {
                collectAppBundles(
                    in: childURL,
                    rootDevice: rootDevice,
                    depth: depth + 1,
                    maxContainerDepth: maxContainerDepth,
                    seenPaths: &seenPaths,
                    output: &output,
                    unreadableCount: &unreadableCount,
                    cancellation: cancellation
                )
            }
        }
    }

    private static func scanUserLibraryCandidates(
        home: URL,
        protectedPaths: [String],
        unreadableCount: inout Int,
        cancellation: ScanCancellation
    ) -> [UserDataCandidate] {
        var homeStat = stat()
        guard lstat(home.path, &homeStat) == 0, (homeStat.st_mode & S_IFMT) == S_IFDIR else { return [] }
        let homeDevice = homeStat.st_dev

        let containers = [
            home.appendingPathComponent("Library/Caches"),
            home.appendingPathComponent("Library/Logs"),
            home.appendingPathComponent("Library/Saved Application State")
        ]

        var results: [UserDataCandidate] = []
        for parentURL in containers {
            if cancellation.isCancelled { break }
            var st = stat()
            guard lstat(parentURL.path, &st) == 0,
                  (st.st_mode & S_IFMT) == S_IFDIR,
                  st.st_dev == homeDevice,
                  parentURL.resolvingSymlinksInPath().path == parentURL.path else {
                continue
            }
            guard let handle = try? DirectoryHandle(path: parentURL.path) else {
                unreadableCount += 1
                continue
            }
            defer { close(handle.descriptor) }

            guard let entries = try? handle.bulkEntries() else {
                unreadableCount += 1
                continue
            }

            for entry in entries where entry.isDirectory && !entry.isSymlink && entry.dev == homeDevice {
                if cancellation.isCancelled { break }
                let itemURL = parentURL.appendingPathComponent(entry.name)
                guard let category = RuleCatalog.category(for: itemURL, home: home) else { continue }
                guard let measured = measureDirectoryMetadata(
                    at: itemURL,
                    expectedDevice: homeDevice,
                    maxEntries: maxEntriesPerCacheDir,
                    maxDepth: 10,
                    trackProtection: true,
                    cancellation: cancellation
                ) else {
                    continue
                }
                var flags = measured.protection
                flags.formUnion(RuleCatalog.ancestorProtection(for: itemURL))
                if UserProtection.overlaps(itemURL.path, protectedPaths: protectedPaths) {
                    flags.insert(.user)
                }
                let blocked = !flags.isEmpty || measured.restricted
                let parsed = extractCandidateTokens(directoryName: entry.name)
                results.append(
                    UserDataCandidate(
                        path: itemURL.path,
                        category: category,
                        allocated: measured.allocated,
                        modifiedAt: measured.modifiedAt,
                        accessedAt: measured.accessedAt,
                        blocked: blocked,
                        protectionTitles: flags.map(\.title).sorted(),
                        tokens: parsed.tokens,
                        displayToken: parsed.displayToken,
                        looksLikeReverseDNSAppContainer: parsed.reverseDNS || entry.name.lowercased().hasSuffix(".savedstate"),
                        isSystemVendor: parsed.systemVendor
                    )
                )
            }
        }
        return results
    }

    private static func measureDirectoryMetadata(
        at rootURL: URL,
        expectedDevice: dev_t? = nil,
        maxEntries: Int,
        maxDepth: Int,
        trackProtection: Bool,
        cancellation: ScanCancellation
    ) -> DirectoryMeasurement? {
        var rootStat = stat()
        guard lstat(rootURL.path, &rootStat) == 0,
              (rootStat.st_mode & S_IFMT) == S_IFDIR,
              rootURL.resolvingSymlinksInPath().path == rootURL.path else {
            return nil
        }
        let device = expectedDevice ?? rootStat.st_dev
        guard rootStat.st_dev == device else { return nil }

        var totalAllocated: Int64 = Int64(rootStat.st_blocks) * 512
        var totalLogical: Int64 = 0
        var totalFiles = 0
        var latestModified: Int64? = Int64(rootStat.st_mtimespec.tv_sec)
        var latestAccessed: Int64? = Int64(rootStat.st_atimespec.tv_sec)
        var visited = 0
        var seenInodes = Set<InodeIdentity>()
        var protection: Set<Protection> = trackProtection ? RuleCatalog.protection(name: rootURL.lastPathComponent, directory: true) : []
        var restricted = false

        func walk(parentHandle: DirectoryHandle?, url: URL, expectedStat: stat, depth: Int) {
            if cancellation.isCancelled {
                protection.insert(.incomplete)
                return
            }
            if visited >= maxEntries || depth > maxDepth {
                if trackProtection { protection.insert(.incomplete) }
                return
            }
            guard let dirHandle = try? (parentHandle.map { try DirectoryHandle(parent: $0.descriptor, name: url.lastPathComponent) } ?? DirectoryHandle(path: url.path)) else {
                restricted = true
                if trackProtection { protection.insert(.incomplete) }
                return
            }
            defer { close(dirHandle.descriptor) }

            guard dirHandle.matches(expectedStat), let entries = try? dirHandle.bulkEntries() else {
                restricted = true
                if trackProtection { protection.insert(.incomplete) }
                return
            }

            for entry in entries {
                if visited >= maxEntries {
                    if trackProtection { protection.insert(.incomplete) }
                    break
                }
                visited += 1
                if entry.dev != device {
                    restricted = true
                    if trackProtection { protection.insert(.incomplete) }
                    continue
                }
                if entry.isSymlink {
                    totalAllocated += entry.allocated
                    if trackProtection { protection.insert(.symlink) }
                    continue
                }
                let m = entry.modifiedAt
                latestModified = max(latestModified ?? m, m)
                if entry.accessedAt > 0 {
                    latestAccessed = max(latestAccessed ?? entry.accessedAt, entry.accessedAt)
                }
                if entry.isRegularFile {
                    totalFiles += 1
                    if trackProtection {
                        protection.formUnion(RuleCatalog.protection(name: entry.name, directory: false))
                        let ext = (entry.name as NSString).pathExtension
                        if ext.isEmpty && (entry.mode & 0o111 != 0) {
                            protection.insert(.source)
                        }
                    }
                    if entry.nlink > 1 {
                        if !seenInodes.insert(InodeIdentity(dev: entry.dev, ino: entry.ino)).inserted {
                            continue
                        }
                    }
                    totalAllocated += entry.allocated
                    totalLogical += entry.logical
                } else if entry.isDirectory {
                    totalAllocated += entry.allocated
                    if trackProtection {
                        protection.formUnion(RuleCatalog.protection(name: entry.name, directory: true))
                    }
                    var childStat = stat()
                    if fstatat(dirHandle.descriptor, entry.name, &childStat, AT_SYMLINK_NOFOLLOW) == 0,
                       (childStat.st_mode & S_IFMT) == S_IFDIR,
                       childStat.st_dev == device {
                        let dirA = Int64(childStat.st_atimespec.tv_sec)
                        if dirA > 0 {
                            latestAccessed = max(latestAccessed ?? dirA, dirA)
                        }
                        walk(parentHandle: dirHandle, url: url.appendingPathComponent(entry.name), expectedStat: childStat, depth: depth + 1)
                    }
                }
            }
        }

        walk(parentHandle: nil, url: rootURL, expectedStat: rootStat, depth: 0)
        return DirectoryMeasurement(
            device: device,
            allocated: totalAllocated,
            logical: totalLogical,
            files: totalFiles,
            modifiedAt: latestModified,
            accessedAt: latestAccessed,
            protection: protection,
            restricted: restricted
        )
    }
}
