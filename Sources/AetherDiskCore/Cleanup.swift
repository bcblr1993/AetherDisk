import Foundation
import Darwin
import CryptoKit

public enum CleanupError: Error, LocalizedError {
    case refused(String), changed, expired, invalidPlan
    public var errorDescription: String? {
        switch self {
        case .refused(let reason): reason
        case .changed: "目录内容或路径已变化。请重新扫描并确认。"
        case .expired: "确认预览已过期，请重新检查。"
        case .invalidPlan: "没有有效的确认计划。未执行任何清理。"
        }
    }
}
public struct CleanupTarget: Sendable, Identifiable {
    public var id: String { path }
    public let path: String
    public let allocated: Int64
    fileprivate let fingerprint: String
    fileprivate let allocationByInode: [String: Int64]
}
public struct CleanupPlan: Sendable, Identifiable {
    public let id: UUID
    public let createdAt: Date
    public let targets: [CleanupTarget]
    public var allocated: Int64 {
        var unique: [String: Int64] = [:]
        for target in targets { unique.merge(target.allocationByInode, uniquingKeysWith: max) }
        return unique.values.reduce(0, +)
    }
}
public struct CleanupReceipt: Sendable {
    public let moved: [String]
    public let failed: [String]
    public let freeSpaceChange: Int64
}
public struct Inspection: Sendable {
    public let fingerprint: String
    public let allocated: Int64
    public let files: Int
    fileprivate let allocationByInode: [String: Int64]
}
public enum SafetyInspector {
    public static func inspect(_ url: URL, home: URL) throws -> Inspection {
        let root = url.standardizedFileURL
        guard root.path != home.path, root.path.hasPrefix(home.path + "/"), root.resolvingSymlinksInPath().path == root.path else { throw CleanupError.refused("只处理个人文件夹内的真实缓存目录；不处理链接、磁盘根目录或外部卷。") }
        guard RuleCatalog.category(for: root, home: home) != nil else { throw CleanupError.refused("不在已识别的缓存规则中，仅支持查看。") }
        var own = stat(); var homeInfo = stat()
        guard lstat(home.path, &homeInfo) == 0, lstat(root.path, &own) == 0, own.st_dev == homeInfo.st_dev, (own.st_mode & S_IFMT) == S_IFDIR else { throw CleanupError.changed }
        guard RuleCatalog.ancestorProtection(for: root).isEmpty else { throw CleanupError.refused("缓存位于受保护的源码、安装包或备份目录内，已保留。") }
        var all: [[String]] = []; var allocated: Int64 = 0; var files = 0
        var inodes: [String: Int64] = [:]
        func walk(_ path: URL, info st: stat, parent: DirectoryHandle?, depth: Int) throws {
            guard st.st_dev == own.st_dev, depth < 256 else { throw CleanupError.refused("跨卷或目录过深，保留原文件。") }
            let type = st.st_mode & S_IFMT
            guard type == S_IFDIR || type == S_IFREG else { throw CleanupError.refused("目录包含链接或特殊文件，暂不清理。") }
            var protection = RuleCatalog.protection(name: path.lastPathComponent, directory: type == S_IFDIR)
            if type == S_IFREG, path.pathExtension.isEmpty, st.st_mode & 0o111 != 0 { protection.insert(.source) }
            guard protection.isEmpty else { throw CleanupError.refused("已保护：\(protection.map(\.title).sorted().joined(separator: "、"))。请在 Finder 中查看。") }
            guard all.count < 1_000_000 else { throw CleanupError.refused("目录过大，无法安全复核，保留原文件。") }
            all.append([String(path.path.dropFirst(root.path.count)), String(st.st_dev), String(st.st_ino), String(st.st_mode), String(st.st_size), String(st.st_blocks), String(st.st_nlink), String(st.st_mtimespec.tv_sec), String(st.st_mtimespec.tv_nsec), String(st.st_ctimespec.tv_sec), String(st.st_ctimespec.tv_nsec)])
            let identity = "\(st.st_dev):\(st.st_ino)"
            if inodes[identity] == nil { let bytes = Int64(st.st_blocks) * 512; inodes[identity] = bytes; allocated += bytes }
            if type == S_IFDIR {
                let dir = try parent.map { try DirectoryHandle(parent: $0.descriptor, name: path.lastPathComponent) } ?? DirectoryHandle(path: path.path)
                defer { close(dir.descriptor) }
                guard dir.matches(st) else { throw CleanupError.changed }
                let names = try dir.names().sorted()
                for name in names {
                    var child = stat()
                    guard fstatat(dir.descriptor, name, &child, AT_SYMLINK_NOFOLLOW) == 0 else { throw CleanupError.changed }
                    try walk(path.appendingPathComponent(name), info: child, parent: dir, depth: depth + 1)
                }
                var after = stat()
                guard fstat(dir.descriptor, &after) == 0, after.st_mtimespec.tv_sec == st.st_mtimespec.tv_sec, after.st_mtimespec.tv_nsec == st.st_mtimespec.tv_nsec, after.st_ctimespec.tv_sec == st.st_ctimespec.tv_sec, after.st_ctimespec.tv_nsec == st.st_ctimespec.tv_nsec, try dir.names().sorted() == names else { throw CleanupError.changed }
            } else { files += 1 }
        }
        try walk(root, info: own, parent: nil, depth: 0)
        // Check repository context explicitly; Git errors must never mean "untracked".
        var ancestor = root
        while true {
            var marker = stat()
            if lstat(ancestor.appendingPathComponent(".git").path, &marker) == 0 {
                let git = try runProcess("/usr/bin/git", ["--no-optional-locks", "-c", "core.fsmonitor=false", "-c", "core.untrackedCache=false", "-C", root.path, "ls-files", "-z", "--", "."], allowFailure: true)
                guard git.status == 0 else { throw CleanupError.refused("无法验证 Git 跟踪状态，已保留文件。") }
                guard git.output.isEmpty else { throw CleanupError.refused("该目录含有 Git 跟踪文件，已阻止清理。") }
                let untracked = try runProcess("/usr/bin/git", ["--no-optional-locks", "-c", "core.fsmonitor=false", "-c", "core.untrackedCache=false", "-C", root.path, "ls-files", "--others", "--exclude-standard", "-z", "--", "."], allowFailure: true)
                guard untracked.status == 0, untracked.output.isEmpty else { throw CleanupError.refused("目录包含未被 Git 忽略的文件或无法验证忽略状态，已保留。") }
                break
            }
            if ancestor.path == "/" { break }; ancestor.deleteLastPathComponent()
        }
        guard root.resolvingSymlinksInPath().path == root.path else { throw CleanupError.changed }
        let hash = SHA256.hash(data: try JSONEncoder().encode(all.sorted { $0[0] < $1[0] })).map { String(format: "%02x", $0) }.joined()
        return .init(fingerprint: hash, allocated: allocated, files: files, allocationByInode: inodes)
    }
    public static func requireUnused(_ paths: [String]) throws {
        let result = try runProcess("/usr/sbin/lsof", ["-nP", "-F0n"], allowFailure: true)
        guard [0, 1].contains(result.status), !result.output.isEmpty else { throw CleanupError.refused("无法确认文件占用状态，已保留文件。") }
        func canonical(_ value: String) -> String {
            let path = value.hasSuffix(" (deleted)") ? String(value.dropLast(10)) : value
            guard let pointer = path.withCString({ realpath($0, nil) }) else { return path }
            defer { free(pointer) }; return String(cString: pointer)
        }
        let targets = paths.map(canonical)
        for line in result.output.split(separator: "\0") where line.hasPrefix("n/") {
            let path = canonical(String(line.dropFirst()))
            if targets.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) { throw CleanupError.refused("目录正被应用使用。退出相关应用后重新检查。") }
        }
    }
    struct ProcessResult { let status: Int32; let output: String }
    static func runProcess(_ tool: String, _ args: [String], allowFailure: Bool) throws -> ProcessResult {
        let p = Process(); p.executableURL = URL(fileURLWithPath: tool); p.arguments = args
        p.environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("GIT_") }
        p.environment?["GIT_CONFIG_GLOBAL"] = "/dev/null"
        p.environment?["GIT_CONFIG_NOSYSTEM"] = "1"
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        try p.run()
        let timedOut = ScanCancellation()
        let timeout = DispatchWorkItem { if p.isRunning { timedOut.cancel(); kill(p.processIdentifier, SIGKILL) } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 6, execute: timeout)
        let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit(); timeout.cancel()
        guard !timedOut.isCancelled, p.terminationReason == .exit else { throw CleanupError.refused("检查超时，未清理任何文件。") }
        if !allowFailure && p.terminationStatus != 0 { throw CleanupError.refused("检查失败，未清理任何文件。") }
        return .init(status: p.terminationStatus, output: String(decoding: data, as: UTF8.self))
    }
}
public actor CleanupService {
    public typealias TrashAction = @Sendable (URL) throws -> Void
    private let home: URL
    private let trash: TrashAction
    private let checkUsage: @Sendable ([String]) throws -> Void
    private var plans: [UUID: CleanupPlan] = [:]
    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, trash: @escaping TrashAction = { url in try FileManager.default.trashItem(at: url, resultingItemURL: nil) }, checkUsage: @escaping @Sendable ([String]) throws -> Void = SafetyInspector.requireUnused) {
        self.home = home; self.trash = trash; self.checkUsage = checkUsage
    }
    public func prepare(paths: [String], protectedPaths: [String] = []) throws -> CleanupPlan {
        let unique = Array(Set(paths.map { URL(fileURLWithPath: $0).standardizedFileURL.path })).sorted()
        guard !unique.isEmpty && unique.count <= 50 else { throw CleanupError.refused("请选择 1–50 个缓存目录。") }
        for p in unique { if unique.contains(where: { p.hasPrefix($0 + "/") }) { throw CleanupError.refused("不能同时选择父目录和子目录。") } }
        try UserProtection.requireAllowed(unique, protectedPaths: protectedPaths)
        try checkUsage(unique)
        let targets = try unique.map { path in
            let result = try SafetyInspector.inspect(URL(fileURLWithPath: path), home: home)
            return CleanupTarget(path: path, allocated: result.allocated, fingerprint: result.fingerprint, allocationByInode: result.allocationByInode)
        }
        let plan = CleanupPlan(id: UUID(), createdAt: Date(), targets: targets)
        plans = [plan.id: plan]; return plan
    }
    public func execute(confirmedPlanID: UUID, protectedPaths: [String] = []) throws -> CleanupReceipt {
        guard let plan = plans.removeValue(forKey: confirmedPlanID) else { throw CleanupError.invalidPlan }
        guard Date().timeIntervalSince(plan.createdAt) < 120 else { throw CleanupError.expired }
        try UserProtection.requireAllowed(plan.targets.map(\.path), protectedPaths: protectedPaths)
        try checkUsage(plan.targets.map(\.path))
        // Revalidate every item before moving any item. New source or installers block the whole batch.
        for target in plan.targets {
            let state = try SafetyInspector.inspect(URL(fileURLWithPath: target.path), home: home)
            guard state.fingerprint == target.fingerprint else { throw CleanupError.changed }
        }
        let before = VolumeSpace.read(at: home).free
        var moved: [String] = []; var failed: [String] = []
        for target in plan.targets {
            do {
                // Keep the final per-target check immediately adjacent to the reversible operation.
                try checkUsage([target.path])
                let current = try SafetyInspector.inspect(URL(fileURLWithPath: target.path), home: home)
                guard current.fingerprint == target.fingerprint else { throw CleanupError.changed }
                try trash(URL(fileURLWithPath: target.path)); moved.append(target.path)
            } catch {
                let remaining = plan.targets.dropFirst(moved.count)
                failed.append(contentsOf: remaining.map { "\($0.path)：\(error.localizedDescription)（已保留）" }); break
            }
        }
        return .init(moved: moved, failed: failed, freeSpaceChange: VolumeSpace.read(at: home).free - before)
    }
}
