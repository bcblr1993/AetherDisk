import Foundation
import Darwin

public enum ItemKind: String, Codable, Sendable { case directory, file }
public struct DiskNode: Identifiable, Codable, Sendable, Equatable {
    public var id: String { path }
    public var path: String
    public var kind: ItemKind
    public var allocated: Int64
    public var logical: Int64
    public var fileCount: Int
    public var restricted: Bool
    public var protection: Set<Protection>
    public var name: String { URL(fileURLWithPath: path).lastPathComponent }
    public var parent: String { URL(fileURLWithPath: path).deletingLastPathComponent().path }
    public init(path: String, kind: ItemKind = .directory, allocated: Int64 = 0, logical: Int64 = 0, fileCount: Int = 0, restricted: Bool = false, protection: Set<Protection> = []) {
        self.path = path; self.kind = kind; self.allocated = allocated; self.logical = logical; self.fileCount = fileCount; self.restricted = restricted; self.protection = protection
    }
}
public enum Protection: String, Codable, Sendable, CaseIterable {
    case source, git, installer, credentials, symlink, incomplete, user, document
    public var title: String {
        switch self {
        case .document: "文档与扫描报告"; case .user: "自定义保护"; case .source: "含源码"; case .git: "Git 工作树"; case .installer: "安装包 / 发布归档"
        case .credentials: "凭据或个人数据"; case .symlink: "符号链接"; case .incomplete: "扫描不完整"
        }
    }
}
public struct Recommendation: Identifiable, Codable, Sendable {
    public var id: String { node.path }
    public var node: DiskNode
    public var category: CacheCategory
    public var blocked: Bool { !node.protection.isEmpty || node.restricted }
    public var reason: String { category.reason }
}
public enum CacheCategory: String, Codable, Sendable {
    case xcode, browser, compiler, update, build
    public var title: String {
        switch self {
        case .xcode: "Xcode 编译缓存"; case .browser: "网页与应用缓存"; case .compiler: "开发工具缓存"
        case .update: "更新安装暂存"; case .build: "项目构建目录"
        }
    }
    public var reason: String {
        switch self {
        case .xcode: "可由 Xcode 重新生成。首次构建与索引会稍慢。"
        case .browser: "缓存可以重新下载。检查时会保留正在使用的文件。"
        case .compiler: "工具可以重新生成或下载。下次构建可能需要联网。"
        case .update: "已下载的安装暂存；当前运行环境不在清理范围。"
        case .build: "构建目录需要逐项检查；源码、工作树、安装包会阻止清理。"
        }
    }
}
public struct ScanProgress: Sendable {
    public var files: Int; public var directories: Int; public var allocated: Int64; public var currentPath: String
    public var rootNodes: [DiskNode] = []
    public init(files: Int = 0, directories: Int = 0, allocated: Int64 = 0, currentPath: String = "") {
        self.files = files; self.directories = directories; self.allocated = allocated; self.currentPath = currentPath
    }
}
public struct ScanResult: Codable, Sendable {
    public var root: String
    public var scannedAt: Date
    public var duration: Double
    public var allocated: Int64
    public var logical: Int64
    public var files: Int
    public var directories: Int
    public var unreadable: Int
    public var issues: [String]
    public var nodes: [DiskNode]
    public var recommendations: [Recommendation]
    public var cancelled: Bool
    public var analysis: ScanAnalysis? = nil
    public var complete: Bool { !cancelled && unreadable == 0 }
}
public struct VolumeSpace: Sendable {
    public var total: Int64; public var free: Int64
    public var used: Int64 { max(0, total - free) }
    public static func read(at url: URL) -> VolumeSpace {
        var info = statfs()
        if statfs(url.path, &info) == 0 {
            return .init(total: Int64(info.f_blocks) * Int64(info.f_bsize), free: Int64(info.f_bavail) * Int64(info.f_bsize))
        }
        return .init(total: 0, free: 0)
    }
}
public enum DiskFormat {
    public static func bytes(_ value: Int64) -> String {
        let magnitude = abs(Double(value)); let units = ["B", "KiB", "MiB", "GiB", "TiB"]
        var n = magnitude; var unit = 0
        while n >= 1024 && unit < units.count - 1 { n /= 1024; unit += 1 }
        return String(format: n >= 100 || unit == 0 ? "%.0f %@" : "%.1f %@", n, units[unit])
    }
    public static func compactPath(_ path: String, home: String = FileManager.default.homeDirectoryForCurrentUser.path) -> String {
        if path == home { return "~" }; if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }; return path
    }
}
public final class ScanCancellation: @unchecked Sendable {
    private let lock = NSLock(); private var value = false
    public init() {}
    public func cancel() { lock.withLock { value = true } }
    public var isCancelled: Bool { lock.withLock { value } }
}
