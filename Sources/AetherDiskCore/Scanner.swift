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
    var device: dev_t = 0
    var files = 0; var directories = 0; var allocated: Int64 = 0; var unreadable = 0
    var issues: [String] = []; var nodes: [DiskNode] = []; var cacheCandidates: [DiskNode] = []; var deepDirectories: [DiskNode] = []; var projectCandidates: [(node: DiskNode, markers: [String])] = []; var analysis = AnalysisAccumulator()
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
        let handle: DirectoryHandle
        do {
            handle = try DirectoryHandle(path: root.path)
        } catch { throw ScanFailure.unreadableRoot(root.path) }
        defer { close(handle.descriptor) }
        guard handle.matches(st), (try? handle.names()) != nil else { throw ScanFailure.unreadableRoot(root.path) }
        device = st.st_dev; let started = Date()
        let node = visit(root, depth: 0, openedRoot: handle)
        var storedPaths = Set(nodes.map(\.path))
        for candidate in cacheCandidates where !storedPaths.contains(candidate.path) {
            nodes.append(candidate); storedPaths.insert(candidate.path)
        }
        for dir in deepDirectories where !storedPaths.contains(dir.path) {
            nodes.append(dir); storedPaths.insert(dir.path)
        }
        let recs = RuleCatalog.recommendations(nodes: nodes, home: home)
        var topProjects: [ProjectSummary] = []
        for cand in projectCandidates.sorted(by: { $0.node.path.count < $1.node.path.count }) {
            if topProjects.contains(where: { cand.node.path.hasPrefix($0.path + "/") }) { continue }
            let matchedCaches = recs.filter { $0.id.hasPrefix(cand.node.path + "/") }
            let cacheBytes = matchedCaches.reduce(Int64(0)) { $0 + $1.node.allocated }
            topProjects.append(ProjectSummary(path: cand.node.path, markers: cand.markers, allocated: cand.node.allocated, logical: cand.node.logical, fileCount: cand.node.fileCount, cacheAllocated: cacheBytes, cachePaths: matchedCaches.map(\.id), modifiedAt: cand.node.modifiedAt, protection: cand.node.protection))
        }
        let details = analysis.result(projects: Array(topProjects.sorted { $0.allocated == $1.allocated ? $0.path < $1.path : $0.allocated > $1.allocated }.prefix(200)))
        nodes.append(contentsOf: details.largeFiles.filter { !storedPaths.contains($0.path) })
        publish(root.path)
        return .init(root: root.path, scannedAt: Date(), duration: Date().timeIntervalSince(started), allocated: node.allocated, logical: node.logical, files: files, directories: directories, unreadable: unreadable, issues: issues, nodes: nodes.sorted { $0.allocated > $1.allocated }, recommendations: recs, cancelled: cancellation.isCancelled, analysis: details)
    }
    func publish(_ path: String) {
        lastUpdate = Date()
        var update = ScanProgress(files: files, directories: directories, allocated: allocated, currentPath: path)
        update.rootNodes = completedRoots
        progress(update)
    }
    func visit(_ url: URL, depth: Int, parent: DirectoryHandle? = nil, openedRoot: DirectoryHandle? = nil, bulk: BulkEntry? = nil) -> DiskNode {
        var st = stat(); var node = DiskNode(path: url.path)
        if cancellation.isCancelled { node.protection.insert(.incomplete); return node }
        if let bulk, bulk.isRegularFile {
            guard bulk.dev == device else { note(url.path); node.protection.insert(.incomplete); node.restricted = true; return node }
            node.modifiedAt = bulk.modifiedAt
            node.protection = RuleCatalog.protection(name: bulk.name, directory: false)
            node.kind = .file; files += 1; node.fileCount = 1
            if url.pathExtension.isEmpty, bulk.mode & 0o111 != 0 { node.protection.insert(.source) }
            if bulk.nlink > 1 {
                let key = "\(bulk.dev):\(bulk.ino)"
                if !hardLinks.insert(key).inserted { return node }
            }
            node.allocated = bulk.allocated; node.logical = bulk.logical; allocated += node.allocated
            if depth <= 3 && nodes.count < 20_000 { nodes.append(node) }
            analysis.record(node)
            if Date().timeIntervalSince(lastUpdate) > 0.3 { publish(url.path) }
            return node
        }
        guard (parent.map { fstatat($0.descriptor, url.lastPathComponent, &st, AT_SYMLINK_NOFOLLOW) } ?? lstat(url.path, &st)) == 0 else { note(url.path); node.restricted = true; node.protection.insert(.incomplete); return node }
        let type = st.st_mode & S_IFMT
        if type == S_IFLNK {
            node.protection.insert(.symlink)
            node.allocated = Int64(st.st_blocks) * 512; allocated += node.allocated
            return node
        }
        // Never cross into another mounted volume or follow APFS system/data aliases.
        guard st.st_dev == device else { note(url.path); node.protection.insert(.incomplete); node.restricted = true; return node }
        if type != S_IFDIR && type != S_IFREG { return node }
        node.modifiedAt = Int64(st.st_mtimespec.tv_sec)
        node.protection = RuleCatalog.protection(name: url.lastPathComponent, directory: type == S_IFDIR)
        if type == S_IFREG {
            node.kind = .file; files += 1; node.fileCount = 1
            if url.pathExtension.isEmpty, st.st_mode & 0o111 != 0 { node.protection.insert(.source) }
            if st.st_nlink > 1 {
                let key = "\(st.st_dev):\(st.st_ino)"
                if !hardLinks.insert(key).inserted { return node }
            }
            node.allocated = Int64(st.st_blocks) * 512; node.logical = Int64(st.st_size); allocated += node.allocated
            if depth <= 3 && nodes.count < 20_000 { nodes.append(node) }
            analysis.record(node)
        } else {
            directories += 1
            guard depth < 256 else { note(url.path); node.protection.insert(.incomplete); return node }
            do {
                let dir = try openedRoot ?? parent.map { try DirectoryHandle(parent: $0.descriptor, name: url.lastPathComponent) } ?? DirectoryHandle(path: url.path)
                defer { if openedRoot == nil { close(dir.descriptor) } }
                guard dir.matches(st) else { throw CleanupError.changed }
                var entries = try dir.bulkEntries()
                let markers = depth <= 4 ? RuleCatalog.projectMarkers(in: entries) : []
                if depth == 0 {
                    let priority = ["Downloads": 0, "Desktop": 1, "Documents": 2, "IdeaProjects": 3, "Library": 90]
                    entries.sort { (priority[$0.name] ?? 40, $0.name) < (priority[$1.name] ?? 40, $1.name) }
                }
                node.allocated = Int64(st.st_blocks) * 512
                allocated += node.allocated
                for entry in entries {
                    if cancellation.isCancelled { node.protection.insert(.incomplete); break }
                    let child = autoreleasepool { visit(url.appendingPathComponent(entry.name), depth: depth + 1, parent: dir, bulk: entry) }
                    node.allocated += child.allocated; node.logical += child.logical; node.fileCount += child.fileCount
                    if let childModified = child.modifiedAt { node.modifiedAt = max(node.modifiedAt ?? childModified, childModified) }
                    node.protection.formUnion(child.protection); node.restricted = node.restricted || child.restricted
                    if depth == 0 && completedRoots.count < 2000 { completedRoots.append(child); publish(url.path) }
                }
                if !markers.isEmpty && projectCandidates.count < 400 {
                    projectCandidates.append((node: node, markers: markers))
                }
                var after = stat()
                if fstat(dir.descriptor, &after) != 0 || after.st_mtimespec.tv_sec != st.st_mtimespec.tv_sec || after.st_mtimespec.tv_nsec != st.st_mtimespec.tv_nsec || after.st_ctimespec.tv_sec != st.st_ctimespec.tv_sec || after.st_ctimespec.tv_nsec != st.st_ctimespec.tv_nsec {
                    note(url.path); node.protection.insert(.incomplete)
                }
            } catch { note(url.path); node.restricted = true; node.protection.insert(.incomplete) }
            let isCache = RuleCatalog.category(for: url, home: home) != nil
            if depth == 0 || (nodes.count < 20_000 && (depth <= 3 || isCache)) { nodes.append(node) }
            else if isCache && cacheCandidates.count < 200 { cacheCandidates.append(node) }
            else if depth <= 6 && node.allocated >= 4 * 1024 * 1024 && deepDirectories.count < 500 { deepDirectories.append(node) }
        }
        if Date().timeIntervalSince(lastUpdate) > 0.3 {
            publish(url.path)
        }
        return node
    }
}
