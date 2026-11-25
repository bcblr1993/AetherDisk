import Foundation
import Darwin

public enum LaunchItemScope: String, Codable, CaseIterable, Sendable, Identifiable {
    case userAgent
    case systemAgent
    case systemDaemon

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .userAgent: "用户启动代理"
        case .systemAgent: "系统启动代理"
        case .systemDaemon: "系统后台守护"
        }
    }
}

public enum ProtectionTabMode: String, CaseIterable, Sendable, Identifiable {
    case launchItems
    case vaultShields
    case installers

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .launchItems: "后台启动代理"
        case .vaultShields: "隐私与保护防线"
        case .installers: "下载安装包核查"
        }
    }
}

public struct LaunchItemEntry: Identifiable, Codable, Sendable, Equatable {
    public var id: String { path }
    public var name: String
    public var path: String
    public var scope: LaunchItemScope
    public var vendorLabel: String
    public var allocated: Int64
    public var modifiedAt: Int64?
    public var isAppleSystem: Bool

    public init(
        name: String,
        path: String,
        scope: LaunchItemScope,
        vendorLabel: String,
        allocated: Int64,
        modifiedAt: Int64?,
        isAppleSystem: Bool
    ) {
        self.name = name
        self.path = path
        self.scope = scope
        self.vendorLabel = vendorLabel
        self.allocated = allocated
        self.modifiedAt = modifiedAt
        self.isAppleSystem = isAppleSystem
    }
}

public struct VaultShieldItem: Identifiable, Codable, Sendable, Equatable {
    public var id: String { path }
    public var title: String
    public var path: String
    public var exists: Bool
    public var shieldReason: String

    public init(title: String, path: String, exists: Bool, shieldReason: String) {
        self.title = title
        self.path = path
        self.exists = exists
        self.shieldReason = shieldReason
    }
}

public struct DownloadInstallerClue: Identifiable, Codable, Sendable, Equatable {
    public var id: String { path }
    public var name: String
    public var path: String
    public var allocated: Int64
    public var logical: Int64
    public var modifiedAt: Int64?

    public init(name: String, path: String, allocated: Int64, logical: Int64, modifiedAt: Int64?) {
        self.name = name
        self.path = path
        self.allocated = allocated
        self.logical = logical
        self.modifiedAt = modifiedAt
    }
}

public struct ProtectionAuditReport: Codable, Sendable, Equatable {
    public var launchItems: [LaunchItemEntry]
    public var vaultShields: [VaultShieldItem]
    public var downloadInstallers: [DownloadInstallerClue]
    public var customProtectedCount: Int
    public var fullDiskAccessGranted: Bool
    public var inspectedAt: Date

    public var thirdPartyLaunchCount: Int {
        launchItems.filter { !$0.isAppleSystem }.count
    }

    public var totalInstallerBytes: Int64 {
        downloadInstallers.reduce(0) { $0 + $1.allocated }
    }

    public init(
        launchItems: [LaunchItemEntry],
        vaultShields: [VaultShieldItem],
        downloadInstallers: [DownloadInstallerClue],
        customProtectedCount: Int,
        fullDiskAccessGranted: Bool,
        inspectedAt: Date = Date()
    ) {
        self.launchItems = launchItems
        self.vaultShields = vaultShields
        self.downloadInstallers = downloadInstallers
        self.customProtectedCount = customProtectedCount
        self.fullDiskAccessGranted = fullDiskAccessGranted
        self.inspectedAt = inspectedAt
    }
}

public enum ProtectionInspector {
    /// 100% read-only metadata audit for LaunchAgents, LaunchDaemons, Vault credential shields, and Downloads installers.
    /// Never opens or reads any regular file contents, never follows symlinks, never modifies system configurations.
    public static func inspect(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        systemRoot: URL = URL(fileURLWithPath: "/"),
        extraScanRoot: URL? = nil,
        customProtectedCount: Int = 0,
        fullDiskAccessGranted: Bool = true
    ) -> ProtectionAuditReport {
        let stdHome = home.standardizedFileURL
        let stdSys = systemRoot.standardizedFileURL

        let launchSources: [(URL, LaunchItemScope, Int)] = [
            (stdHome.appendingPathComponent("Library/LaunchAgents"), .userAgent, 100),
            (stdSys.appendingPathComponent("Library/LaunchAgents"), .systemAgent, 100),
            (stdSys.appendingPathComponent("Library/LaunchDaemons"), .systemDaemon, 100),
            (stdSys.appendingPathComponent("System/Library/LaunchAgents"), .systemAgent, 30)
        ]

        var launchItems: [LaunchItemEntry] = []
        for (dirURL, scope, maxCount) in launchSources {
            launchItems.append(contentsOf: readLaunchDirectory(at: dirURL, scope: scope).prefix(maxCount))
        }
        launchItems.sort { a, b in
            if a.isAppleSystem != b.isAppleSystem { return !a.isAppleSystem }
            if a.scope != b.scope { return a.scope.rawValue < b.scope.rawValue }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }

        let vaults = inspectVaultPresence(home: stdHome)
        var installers = readDownloadInstallers(at: stdHome.appendingPathComponent("Downloads"))
        if let extra = extraScanRoot?.standardizedFileURL,
           extra.path != stdHome.path,
           extra.path != "/" {
            let extraDownloads = extra.lastPathComponent == "Downloads" ? extra : extra.appendingPathComponent("Downloads")
            let extraItems = readDownloadInstallers(at: extraDownloads)
            var seen = Set(installers.map(\.path))
            for item in extraItems where seen.insert(item.path).inserted {
                installers.append(item)
            }
            installers.sort { $0.allocated == $1.allocated ? $0.path < $1.path : $0.allocated > $1.allocated }
        }

        return ProtectionAuditReport(
            launchItems: launchItems,
            vaultShields: vaults,
            downloadInstallers: installers,
            customProtectedCount: customProtectedCount,
            fullDiskAccessGranted: fullDiskAccessGranted,
            inspectedAt: Date()
        )
    }

    private static func readLaunchDirectory(at dirURL: URL, scope: LaunchItemScope) -> [LaunchItemEntry] {
        var st = stat()
        guard lstat(dirURL.path, &st) == 0,
              (st.st_mode & S_IFMT) == S_IFDIR,
              dirURL.resolvingSymlinksInPath().path == dirURL.path else {
            return []
        }
        let expectedDev = st.st_dev
        guard let handle = try? DirectoryHandle(path: dirURL.path) else { return [] }
        defer { close(handle.descriptor) }
        guard handle.matches(st), let entries = try? handle.bulkEntries() else { return [] }

        var output: [LaunchItemEntry] = []
        for entry in entries where entry.isRegularFile && !entry.isSymlink && entry.dev == expectedDev {
            guard entry.name.lowercased().hasSuffix(".plist") else { continue }
            let stem = String(entry.name.dropLast(".plist".count))
            let lower = stem.lowercased()
            let isApple = lower.hasPrefix("com.apple.")
            let parts = stem.split(separator: ".").map(String.init)
            let vendor: String
            if parts.count >= 2 && ["com", "org", "io", "net", "app", "dev", "me"].contains(parts[0].lowercased()) {
                vendor = parts[1]
            } else {
                vendor = parts.first ?? stem
            }
            output.append(
                LaunchItemEntry(
                    name: stem,
                    path: dirURL.appendingPathComponent(entry.name).path,
                    scope: scope,
                    vendorLabel: vendor,
                    allocated: entry.allocated,
                    modifiedAt: entry.modifiedAt,
                    isAppleSystem: isApple
                )
            )
        }
        return output
    }

    private static func inspectVaultPresence(home: URL) -> [VaultShieldItem] {
        let specs: [(String, String, String)] = [
            ("SSH 密钥与配置防线", home.appendingPathComponent(".ssh").path, "自动标记 .credentials 保护，禁止任何缓存规则触碰"),
            ("GPG 签名密钥环防线", home.appendingPathComponent(".gnupg").path, "自动标记 .credentials 保护，签名私钥与证书永不清理"),
            ("macOS 个人钥匙串目录", home.appendingPathComponent("Library/Keychains").path, "系统凭据核心区，全程锁定只读阻断"),
            ("Git 仓库与源码工作树防线", home.path, "存在 .git、跟踪文件、未忽略文件或源码清单时整目录拒绝清理"),
            ("应用本体与正式安装包防线", "/Applications", ".app / .dmg / .pkg / .xcarchive / SHA256SUMS 默认受保护")
        ]
        return specs.map { title, path, reason in
            var st = stat()
            let exists = (lstat(path, &st) == 0)
            return VaultShieldItem(title: title, path: path, exists: exists, shieldReason: reason)
        }
    }

    private static func readDownloadInstallers(at downloadsURL: URL) -> [DownloadInstallerClue] {
        var st = stat()
        guard lstat(downloadsURL.path, &st) == 0,
              (st.st_mode & S_IFMT) == S_IFDIR,
              downloadsURL.resolvingSymlinksInPath().path == downloadsURL.path else {
            return []
        }
        let expectedDev = st.st_dev
        guard let handle = try? DirectoryHandle(path: downloadsURL.path) else { return [] }
        defer { close(handle.descriptor) }
        guard handle.matches(st), let entries = try? handle.bulkEntries() else { return [] }

        let installerExts: Set<String> = ["dmg", "pkg", "iso", "xip", "ipsw", "mpkg"]
        var items: [DownloadInstallerClue] = []
        for entry in entries where entry.isRegularFile && !entry.isSymlink && entry.dev == expectedDev {
            let ext = (entry.name.lowercased() as NSString).pathExtension
            guard installerExts.contains(ext) else { continue }
            items.append(
                DownloadInstallerClue(
                    name: entry.name,
                    path: downloadsURL.appendingPathComponent(entry.name).path,
                    allocated: entry.allocated,
                    logical: entry.logical,
                    modifiedAt: entry.modifiedAt
                )
            )
        }
        items.sort { $0.allocated == $1.allocated ? $0.path < $1.path : $0.allocated > $1.allocated }
        return Array(items.prefix(60))
    }
}
