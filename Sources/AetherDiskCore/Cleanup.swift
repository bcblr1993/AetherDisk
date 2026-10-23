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
}
public struct CleanupPlan: Sendable, Identifiable {
    public let id: UUID
    public let createdAt: Date
    public let targets: [CleanupTarget]
    public var allocated: Int64 { targets.reduce(0) { $0 + $1.allocated } }
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
}
public enum SafetyInspector {
    public static func inspect(_ url: URL, home: URL) throws -> Inspection {
        let root = url.standardizedFileURL
        guard root.path != home.path, root.path.hasPrefix(home.path + "/"), root.resolvingSymlinksInPath().path == root.path else { throw CleanupError.refused("只处理个人文件夹内的真实缓存目录；不处理链接、磁盘根目录或外部卷。") }
        guard RuleCatalog.category(for: root, home: home) != nil else { throw CleanupError.refused("不在已识别的缓存规则中，仅支持查看。") }
        let fm = FileManager(); var own = stat()
        guard lstat(root.path, &own) == 0, (own.st_mode & S_IFMT) == S_IFDIR else { throw CleanupError.changed }
        var all: [String] = []; var allocated: Int64 = 0; var files = 0
        func walk(_ path: URL) throws {
            var st = stat()
            guard lstat(path.path, &st) == 0, st.st_dev == own.st_dev else { throw CleanupError.refused("目录不可读取或跨越挂载卷，保留原文件。") }
            let type = st.st_mode & S_IFMT
            guard type == S_IFDIR || type == S_IFREG else { throw CleanupError.refused("目录包含链接或特殊文件，暂不清理。") }
            let protection = RuleCatalog.protection(name: path.lastPathComponent, directory: type == S_IFDIR)
            guard protection.isEmpty else { throw CleanupError.refused("已保护：\(protection.map(\.title).sorted().joined(separator: "、"))。请在 Finder 中查看。") }
            let rel = String(path.path.dropFirst(root.path.count))
            all.append("\(rel)|\(st.st_dev)|\(st.st_ino)|\(st.st_mode)|\(st.st_size)|\(st.st_mtimespec.tv_sec)|\(st.st_mtimespec.tv_nsec)")
            allocated += Int64(st.st_blocks) * 512
            if type == S_IFDIR {
                for name in try fm.contentsOfDirectory(atPath: path.path) { try walk(path.appendingPathComponent(name)) }
            } else { files += 1 }
        }
        try walk(root)
        // Git's tracked paths are protected even when their extension looks like cache data.
        let git = try runProcess("/usr/bin/git", ["-C", root.path, "ls-files", "-z", "--", "."], allowFailure: true)
        if git.status == 0 && !git.output.isEmpty { throw CleanupError.refused("该目录含有 Git 跟踪文件，已阻止清理。") }
        let hash = SHA256.hash(data: try JSONEncoder().encode(all.sorted())).map { String(format: "%02x", $0) }.joined()
        return .init(fingerprint: hash, allocated: allocated, files: files)
    }
    public static func requireUnused(_ paths: [String]) throws {
        let result = try runProcess("/usr/sbin/lsof", ["-nP", "-Fn"], allowFailure: true)
        guard [0, 1].contains(result.status), !result.output.isEmpty else { throw CleanupError.refused("无法确认文件占用状态，已保留文件。") }
        func canonical(_ value: String) -> String {
            let path = value.hasSuffix(" (deleted)") ? String(value.dropLast(10)) : value
            guard let pointer = path.withCString({ realpath($0, nil) }) else { return path }
            defer { free(pointer) }; return String(cString: pointer)
        }
        let targets = paths.map(canonical)
        for line in result.output.split(separator: "\n") where line.hasPrefix("n/") {
            let path = canonical(String(line.dropFirst()))
            if targets.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) { throw CleanupError.refused("目录正被应用使用。退出相关应用后重新检查。") }
        }
    }
    struct ProcessResult { let status: Int32; let output: String }
    static func runProcess(_ tool: String, _ args: [String], allowFailure: Bool) throws -> ProcessResult {
        let p = Process(); p.executableURL = URL(fileURLWithPath: tool); p.arguments = args
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        try p.run()
        let timeout = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 6, execute: timeout)
        let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit(); timeout.cancel()
        guard p.terminationReason == .exit else { throw CleanupError.refused("检查超时，未清理任何文件。") }
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
    public func prepare(paths: [String]) throws -> CleanupPlan {
        let unique = Array(Set(paths)).sorted()
        guard !unique.isEmpty && unique.count <= 50 else { throw CleanupError.refused("请选择 1–50 个缓存目录。") }
        for p in unique { if unique.contains(where: { p.hasPrefix($0 + "/") }) { throw CleanupError.refused("不能同时选择父目录和子目录。") } }
        try checkUsage(unique)
        let targets = try unique.map { path in
            let result = try SafetyInspector.inspect(URL(fileURLWithPath: path), home: home)
            return CleanupTarget(path: path, allocated: result.allocated, fingerprint: result.fingerprint)
        }
        let plan = CleanupPlan(id: UUID(), createdAt: Date(), targets: targets)
        plans = [plan.id: plan]; return plan
    }
    public func execute(confirmedPlanID: UUID) throws -> CleanupReceipt {
        guard let plan = plans.removeValue(forKey: confirmedPlanID) else { throw CleanupError.invalidPlan }
        guard Date().timeIntervalSince(plan.createdAt) < 120 else { throw CleanupError.expired }
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
                let current = try SafetyInspector.inspect(URL(fileURLWithPath: target.path), home: home)
                guard current.fingerprint == target.fingerprint else { throw CleanupError.changed }
                try checkUsage([target.path]); try trash(URL(fileURLWithPath: target.path)); moved.append(target.path)
            } catch { failed.append("\(target.path)：\(error.localizedDescription)"); break }
        }
        return .init(moved: moved, failed: failed, freeSpaceChange: VolumeSpace.read(at: home).free - before)
    }
}
