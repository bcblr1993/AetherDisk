import Foundation
import Darwin

public enum ScanFailure: Error, LocalizedError {
    case invalidRoot, unreadableRoot(String)
    public var errorDescription: String? {
        switch self { case .invalidRoot: "请选择一个真实文件夹；不扫描符号链接。"; case .unreadableRoot(let p): "无法读取所选文件夹：\(p)。请检查访问权限。" }
    }
}
public enum DiskScanner {
    public static func scan(root: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser, cancellation: ScanCancellation = .init(), progress: @escaping @Sendable (ScanProgress) -> Void = { _ in }) throws -> ScanResult {
        let worker = ScanWorker(root: root.standardizedFileURL, home: home, cancellation: cancellation, progress: progress)
        return try worker.run()
    }
}
private final class ScanWorker {
    let root: URL; let home: URL; let cancellation: ScanCancellation
    let progress: @Sendable (ScanProgress) -> Void
    let fm = FileManager(); var device: dev_t = 0
    var files = 0; var directories = 0; var allocated: Int64 = 0; var unreadable = 0
    var issues: [String] = []; var nodes: [DiskNode] = []; var largeFiles: [DiskNode] = []
    var hardLinks: Set<String> = []; var lastUpdate = Date.distantPast; var completedRoots: [DiskNode] = []
    init(root: URL, home: URL, cancellation: ScanCancellation, progress: @escaping @Sendable (ScanProgress) -> Void) {
        self.root = root; self.home = home; self.cancellation = cancellation; self.progress = progress
    }
    func note(_ path: String) {
        unreadable += 1
        if issues.count < 50 { issues.append(path) }
    }
    func run() throws -> ScanResult {
        var st = stat()
        guard lstat(root.path, &st) == 0, (st.st_mode & S_IFMT) == S_IFDIR, root.resolvingSymlinksInPath().path == root.path else { throw ScanFailure.invalidRoot }
        guard fm.isReadableFile(atPath: root.path), (try? fm.contentsOfDirectory(atPath: root.path)) != nil else { throw ScanFailure.unreadableRoot(root.path) }
        device = st.st_dev; let started = Date()
        let node = visit(root, depth: 0)
        nodes.append(contentsOf: largeFiles.sorted { $0.allocated > $1.allocated }.prefix(200))
        progress(.init(files: files, directories: directories, allocated: node.allocated, currentPath: root.path))
        return .init(root: root.path, scannedAt: Date(), duration: Date().timeIntervalSince(started), allocated: node.allocated, logical: node.logical, files: files, directories: directories, unreadable: unreadable, issues: issues, nodes: nodes.sorted { $0.allocated > $1.allocated }, recommendations: RuleCatalog.recommendations(nodes: nodes, home: home), cancelled: cancellation.isCancelled)
    }
    func publish(_ path: String) {
        lastUpdate = Date()
        var update = ScanProgress(files: files, directories: directories, allocated: allocated, currentPath: path)
        update.rootNodes = completedRoots
        progress(update)
    }
    func visit(_ url: URL, depth: Int) -> DiskNode {
        var st = stat(); var node = DiskNode(path: url.path)
        if cancellation.isCancelled { node.protection.insert(.incomplete); return node }
        guard lstat(url.path, &st) == 0 else { note(url.path); node.restricted = true; node.protection.insert(.incomplete); return node }
        let type = st.st_mode & S_IFMT
        if type == S_IFLNK { node.protection.insert(.symlink); return node }
        // Never cross into another mounted volume or follow APFS system/data aliases.
        guard st.st_dev == device else { return node }
        if type != S_IFDIR && type != S_IFREG { return node }
        node.protection = RuleCatalog.protection(name: url.lastPathComponent, directory: type == S_IFDIR)
        if type == S_IFREG {
            node.kind = .file; files += 1; node.fileCount = 1
            if st.st_nlink > 1 {
                let key = "\(st.st_dev):\(st.st_ino)"
                if !hardLinks.insert(key).inserted { return node }
            }
            node.allocated = Int64(st.st_blocks) * 512; node.logical = Int64(st.st_size); allocated += node.allocated
            if depth <= 3 && nodes.count < 20_000 { nodes.append(node) }
            if depth > 3 && node.allocated >= 16 * 1024 * 1024 {
                largeFiles.append(node)
                if largeFiles.count > 400 { largeFiles.sort { $0.allocated > $1.allocated }; largeFiles = Array(largeFiles.prefix(200)) }
            }
        } else {
            directories += 1
            guard depth < 256 else { note(url.path); node.protection.insert(.incomplete); return node }
            do {
                var children = try fm.contentsOfDirectory(atPath: url.path)
                if depth == 0 {
                    let priority = ["Downloads": 0, "Desktop": 1, "Documents": 2, "IdeaProjects": 3, "Library": 90]
                    children.sort { (priority[$0] ?? 40, $0) < (priority[$1] ?? 40, $1) }
                }
                node.allocated = Int64(st.st_blocks) * 512
                allocated += node.allocated
                for name in children {
                    if cancellation.isCancelled { node.protection.insert(.incomplete); break }
                    let child = autoreleasepool { visit(url.appendingPathComponent(name), depth: depth + 1) }
                    node.allocated += child.allocated; node.logical += child.logical; node.fileCount += child.fileCount
                    node.protection.formUnion(child.protection); node.restricted = node.restricted || child.restricted
                    if depth == 0 && completedRoots.count < 2000 { completedRoots.append(child); publish(url.path) }
                }
            } catch { note(url.path); node.restricted = true; node.protection.insert(.incomplete) }
            if depth == 0 || (nodes.count < 20_000 && (depth <= 3 || RuleCatalog.category(for: url, home: home) != nil)) { nodes.append(node) }
        }
        if Date().timeIntervalSince(lastUpdate) > 0.3 {
            publish(url.path)
        }
        return node
    }
}
