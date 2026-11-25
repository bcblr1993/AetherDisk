import Foundation
import Darwin

/// Metadata summary for a locally resident or cloud-only file discovered inside a cloud storage folder.
public struct CloudLocalFileItem: Identifiable, Codable, Sendable, Equatable {
    public var id: String { path }
    public var path: String
    public var name: String
    public var providerName: String
    public var allocated: Int64
    public var logical: Int64
    public var modifiedAt: Int64
    public var isDataless: Bool

    public init(
        path: String,
        name: String,
        providerName: String,
        allocated: Int64,
        logical: Int64,
        modifiedAt: Int64,
        isDataless: Bool? = nil
    ) {
        self.path = path
        self.name = name
        self.providerName = providerName
        self.allocated = allocated
        self.logical = logical
        self.modifiedAt = modifiedAt
        self.isDataless = isDataless ?? (allocated == 0 && logical > 0)
    }
}

/// Read-only storage footprint summary for a single cloud sync provider directory.
public struct CloudProviderSummary: Identifiable, Codable, Sendable, Equatable {
    public var id: String { path }
    public var name: String
    public var path: String
    public var allocated: Int64
    public var logical: Int64
    public var cloudOnlyLogical: Int64
    public var localFileCount: Int
    public var datalessFileCount: Int
    public var unreadableCount: Int
    public var topLocalFiles: [CloudLocalFileItem]

    public init(
        name: String,
        path: String,
        allocated: Int64,
        logical: Int64,
        cloudOnlyLogical: Int64,
        localFileCount: Int,
        datalessFileCount: Int,
        unreadableCount: Int = 0,
        topLocalFiles: [CloudLocalFileItem] = []
    ) {
        self.name = name
        self.path = path
        self.allocated = allocated
        self.logical = logical
        self.cloudOnlyLogical = cloudOnlyLogical
        self.localFileCount = localFileCount
        self.datalessFileCount = datalessFileCount
        self.unreadableCount = unreadableCount
        self.topLocalFiles = topLocalFiles
    }
}

/// Aggregated read-only report across all detected cloud storage providers.
public struct CloudStorageReport: Codable, Sendable, Equatable {
    public var scannedAt: Date
    public var providers: [CloudProviderSummary]
    public var totalAllocated: Int64
    public var totalLogical: Int64
    public var totalCloudOnlyLogical: Int64
    public var totalLocalFiles: Int
    public var totalDatalessFiles: Int
    public var unreadableCount: Int

    public init(
        scannedAt: Date = Date(),
        providers: [CloudProviderSummary],
        totalAllocated: Int64,
        totalLogical: Int64,
        totalCloudOnlyLogical: Int64,
        totalLocalFiles: Int,
        totalDatalessFiles: Int,
        unreadableCount: Int = 0
    ) {
        self.scannedAt = scannedAt
        self.providers = providers
        self.totalAllocated = totalAllocated
        self.totalLogical = totalLogical
        self.totalCloudOnlyLogical = totalCloudOnlyLogical
        self.totalLocalFiles = totalLocalFiles
        self.totalDatalessFiles = totalDatalessFiles
        self.unreadableCount = unreadableCount
    }
}

/// 100% read-only metadata-only inspector for macOS FileProvider / CloudStorage and iCloud Drive directories.
/// Never opens or reads regular file contents, never triggers FileProvider downloads, never follows symlinks,
/// and never crosses filesystem volume boundaries (`st_dev`).
public enum CloudStorageInspector {
    private static let maxEntriesPerProvider = 60_000
    private static let maxDepthPerProvider = 128
    private static let topLocalLimit = 12

    /// Resolves an optional `CloudStorage` fixture root relative to a user-selected scan root.
    public static func candidateExtraCloudRoot(for scanRoot: URL) -> URL? {
        let stdRoot = scanRoot.standardizedFileURL
        if stdRoot.lastPathComponent == "CloudStorage", isRealDirectory(at: stdRoot) != nil {
            return stdRoot
        }
        let direct = stdRoot.appendingPathComponent("CloudStorage")
        if isRealDirectory(at: direct) != nil {
            return direct
        }
        let libraryCloud = stdRoot.appendingPathComponent("Library/CloudStorage")
        if isRealDirectory(at: libraryCloud) != nil {
            return libraryCloud
        }
        return nil
    }

    /// Inspects `~/Library/CloudStorage/*`, `~/Library/Mobile Documents/com~apple~CloudDocs`,
    /// and an optional `extraCloudRoot`'s direct non-symlink subdirectories strictly via read-only directory metadata.
    public static func inspect(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        extraCloudRoot: URL? = nil,
        cancellation: ScanCancellation? = nil
    ) -> CloudStorageReport {
        if cancellation?.isCancelled == true {
            return CloudStorageReport(
                scannedAt: Date(),
                providers: [],
                totalAllocated: 0,
                totalLogical: 0,
                totalCloudOnlyLogical: 0,
                totalLocalFiles: 0,
                totalDatalessFiles: 0,
                unreadableCount: 0
            )
        }

        let stdHome = home.standardizedFileURL
        var candidates: [(url: URL, name: String)] = []
        var seenProviderPaths = Set<String>()
        var rootUnreadableCount = 0

        func addProvider(url: URL, name: String) {
            let std = url.standardizedFileURL
            if seenProviderPaths.insert(std.path).inserted {
                candidates.append((std, name))
            }
        }

        if let homeStat = isRealDirectory(at: stdHome) {
            let cloudStorageRoot = stdHome.appendingPathComponent("Library/CloudStorage")
            collectDirectSubdirectories(
                in: cloudStorageRoot,
                expectedDevice: homeStat.st_dev,
                unreadableCount: &rootUnreadableCount,
                cancellation: cancellation
            ) { childURL, folderName in
                addProvider(url: childURL, name: friendlyProviderName(for: folderName))
            }

            let cloudDocsURL = stdHome.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
            var icStat = stat()
            if lstat(cloudDocsURL.path, &icStat) == 0 {
                if (icStat.st_mode & S_IFMT) == S_IFDIR,
                   icStat.st_dev == homeStat.st_dev,
                   cloudDocsURL.resolvingSymlinksInPath().path == cloudDocsURL.path {
                    addProvider(url: cloudDocsURL, name: "iCloud Drive")
                }
            } else if errno == EACCES || errno == EPERM {
                rootUnreadableCount += 1
            }
        }

        if let extra = extraCloudRoot?.standardizedFileURL,
           let extraStat = isRealDirectory(at: extra) {
            collectDirectSubdirectories(
                in: extra,
                expectedDevice: extraStat.st_dev,
                unreadableCount: &rootUnreadableCount,
                cancellation: cancellation
            ) { childURL, folderName in
                addProvider(url: childURL, name: friendlyProviderName(for: folderName))
            }
        }

        let providers: [CloudProviderSummary] = withThreadDiskIOThrottled(true) {
            var summaries: [CloudProviderSummary] = []
            summaries.reserveCapacity(candidates.count)
            for candidate in candidates {
                if cancellation?.isCancelled == true { break }
                if let summary = measureProvider(
                    at: candidate.url,
                    displayName: candidate.name,
                    cancellation: cancellation
                ) {
                    summaries.append(summary)
                }
            }
            return summaries.sorted { a, b in
                if a.allocated != b.allocated { return a.allocated > b.allocated }
                if a.cloudOnlyLogical != b.cloudOnlyLogical { return a.cloudOnlyLogical > b.cloudOnlyLogical }
                if a.logical != b.logical { return a.logical > b.logical }
                return a.path < b.path
            }
        }

        let totalAllocated = providers.reduce(Int64(0)) { $0 + $1.allocated }
        let totalLogical = providers.reduce(Int64(0)) { $0 + $1.logical }
        let totalCloudOnlyLogical = providers.reduce(Int64(0)) { $0 + $1.cloudOnlyLogical }
        let totalLocalFiles = providers.reduce(0) { $0 + $1.localFileCount }
        let totalDatalessFiles = providers.reduce(0) { $0 + $1.datalessFileCount }
        let totalUnreadable = rootUnreadableCount + providers.reduce(0) { $0 + $1.unreadableCount }

        return CloudStorageReport(
            scannedAt: Date(),
            providers: providers,
            totalAllocated: totalAllocated,
            totalLogical: totalLogical,
            totalCloudOnlyLogical: totalCloudOnlyLogical,
            totalLocalFiles: totalLocalFiles,
            totalDatalessFiles: totalDatalessFiles,
            unreadableCount: totalUnreadable
        )
    }

    // MARK: - Private Read-Only Metadata Helpers

    private static func isRealDirectory(at url: URL) -> stat? {
        let std = url.standardizedFileURL
        var st = stat()
        guard lstat(std.path, &st) == 0,
              (st.st_mode & S_IFMT) == S_IFDIR,
              std.resolvingSymlinksInPath().path == std.path else {
            return nil
        }
        return st
    }

    private static func collectDirectSubdirectories(
        in parentURL: URL,
        expectedDevice: dev_t,
        unreadableCount: inout Int,
        cancellation: ScanCancellation?,
        onSubdir: (URL, String) -> Void
    ) {
        var st = stat()
        guard lstat(parentURL.path, &st) == 0 else {
            if errno == EACCES || errno == EPERM {
                unreadableCount += 1
            }
            return
        }
        guard (st.st_mode & S_IFMT) == S_IFDIR,
              st.st_dev == expectedDevice,
              parentURL.resolvingSymlinksInPath().path == parentURL.path else {
            return
        }
        guard let handle = try? DirectoryHandle(path: parentURL.path) else {
            unreadableCount += 1
            return
        }
        defer { close(handle.descriptor) }

        guard handle.matches(st), let entries = try? handle.bulkEntries() else {
            unreadableCount += 1
            return
        }

        for entry in entries.sorted(by: { $0.name < $1.name }) {
            if cancellation?.isCancelled == true { break }
            guard entry.isDirectory, !entry.isSymlink, entry.dev == st.st_dev else { continue }
            onSubdir(parentURL.appendingPathComponent(entry.name), entry.name)
        }
    }

    private static func measureProvider(
        at rootURL: URL,
        displayName: String,
        cancellation: ScanCancellation?
    ) -> CloudProviderSummary? {
        var rootStat = stat()
        guard lstat(rootURL.path, &rootStat) == 0,
              (rootStat.st_mode & S_IFMT) == S_IFDIR,
              rootURL.resolvingSymlinksInPath().path == rootURL.path else {
            return nil
        }

        let providerDev = rootStat.st_dev
        var totalAllocated: Int64 = 0
        var totalLogical: Int64 = 0
        var cloudOnlyLogical: Int64 = 0
        var localFileCount = 0
        var datalessFileCount = 0
        var unreadableCount = 0
        var visitedEntries = 0
        var seenInodes = Set<InodeKey>()
        var topCandidates: [CloudLocalFileItem] = []

        func trimTopCandidates() {
            topCandidates.sort { a, b in
                if a.allocated != b.allocated { return a.allocated > b.allocated }
                if a.logical != b.logical { return a.logical > b.logical }
                return a.path < b.path
            }
            if topCandidates.count > topLocalLimit {
                topCandidates = Array(topCandidates.prefix(topLocalLimit))
            }
        }

        func walk(parentHandle: DirectoryHandle?, dirURL: URL, expectedStat: stat, depth: Int) {
            if cancellation?.isCancelled == true || visitedEntries >= maxEntriesPerProvider || depth > maxDepthPerProvider {
                return
            }
            guard let dirHandle = try? (parentHandle.map { try DirectoryHandle(parent: $0.descriptor, name: dirURL.lastPathComponent) } ?? DirectoryHandle(path: dirURL.path)) else {
                unreadableCount += 1
                return
            }
            defer { close(dirHandle.descriptor) }

            guard dirHandle.matches(expectedStat), let entries = try? dirHandle.bulkEntries() else {
                unreadableCount += 1
                return
            }

            for entry in entries {
                if cancellation?.isCancelled == true || visitedEntries >= maxEntriesPerProvider {
                    break
                }
                visitedEntries += 1

                if entry.isSymlink {
                    continue
                }
                guard entry.dev == providerDev else {
                    unreadableCount += 1
                    continue
                }

                if entry.isRegularFile {
                    if entry.nlink > 1 {
                        guard seenInodes.insert(InodeKey(dev: entry.dev, ino: entry.ino)).inserted else {
                            continue
                        }
                    }
                    let allocated = entry.allocated
                    let logical = entry.logical
                    let dataless = (allocated == 0 && logical > 0)

                    totalAllocated += allocated
                    totalLogical += logical

                    if dataless {
                        datalessFileCount += 1
                        cloudOnlyLogical += logical
                    } else {
                        localFileCount += 1
                        if allocated > 0 {
                            let filePath = dirURL.appendingPathComponent(entry.name).path
                            topCandidates.append(
                                CloudLocalFileItem(
                                    path: filePath,
                                    name: entry.name,
                                    providerName: displayName,
                                    allocated: allocated,
                                    logical: logical,
                                    modifiedAt: entry.modifiedAt,
                                    isDataless: false
                                )
                            )
                            if topCandidates.count >= 64 {
                                trimTopCandidates()
                            }
                        }
                    }
                } else if entry.isDirectory {
                    var childStat = stat()
                    guard fstatat(dirHandle.descriptor, entry.name, &childStat, AT_SYMLINK_NOFOLLOW) == 0 else {
                        unreadableCount += 1
                        continue
                    }
                    let childType = childStat.st_mode & S_IFMT
                    if childType == S_IFLNK {
                        continue
                    }
                    guard childStat.st_dev == providerDev else {
                        unreadableCount += 1
                        continue
                    }
                    if childType == S_IFDIR {
                        walk(
                            parentHandle: dirHandle,
                            dirURL: dirURL.appendingPathComponent(entry.name),
                            expectedStat: childStat,
                            depth: depth + 1
                        )
                    }
                }
            }
        }

        walk(parentHandle: nil, dirURL: rootURL, expectedStat: rootStat, depth: 0)
        trimTopCandidates()

        return CloudProviderSummary(
            name: displayName,
            path: rootURL.path,
            allocated: totalAllocated,
            logical: totalLogical,
            cloudOnlyLogical: cloudOnlyLogical,
            localFileCount: localFileCount,
            datalessFileCount: datalessFileCount,
            unreadableCount: unreadableCount,
            topLocalFiles: topCandidates
        )
    }

    private static func friendlyProviderName(for folderName: String) -> String {
        let lower = folderName.lowercased()
        if lower == "com~apple~clouddocs" || lower == "iclouddrive" || lower == "icloud drive" {
            return "iCloud Drive"
        }
        if lower == "googledrive" || lower.hasPrefix("googledrive-") || lower.hasPrefix("google drive") {
            return "Google Drive"
        }
        if lower == "onedrive" || lower.hasPrefix("onedrive-") || lower.hasPrefix("onedrive -") {
            return "OneDrive"
        }
        if lower == "dropbox" || lower.hasPrefix("dropbox-") || lower.hasPrefix("dropbox (") || lower.hasPrefix("dropbox ") {
            return "Dropbox"
        }
        if lower == "box" || lower == "box-box" || lower.hasPrefix("box-") {
            return "Box"
        }
        if lower == "pcloud drive" || lower.hasPrefix("pcloud") {
            return "pCloud Drive"
        }
        if lower.hasPrefix("nextcloud") {
            return "Nextcloud"
        }
        if lower.hasPrefix("owncloud") {
            return "ownCloud"
        }
        if lower.hasPrefix("synologydrive") || lower.hasPrefix("synology drive") {
            return "Synology Drive"
        }
        return folderName
    }
}
