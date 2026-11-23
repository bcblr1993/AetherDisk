import Foundation
import Darwin

public enum ScanFailure: Error, LocalizedError {
    case invalidRoot, unreadableRoot(String)
    public var errorDescription: String? {
        switch self {
        case .invalidRoot: "请选择一个真实文件夹；不扫描符号链接。"
        case .unreadableRoot(let p): "无法读取所选文件夹：\(p)。请检查访问权限。"
        }
    }
}

public enum DiskScanner {
    public static func scan(
        root: URL,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        profile: ScanPerformanceProfile = .balanced,
        cancellation: ScanCancellation = .init(),
        progress: @escaping @Sendable (ScanProgress) -> Void = { _ in }
    ) throws -> ScanResult {
        let worker = ScanWorker(root: root.standardizedFileURL, home: home, profile: profile, cancellation: cancellation, progress: progress)
        return try worker.run()
    }
}

private struct RetainedNode: Sendable {
    let depth: Int
    let isCache: Bool
    let node: DiskNode
}

private final class SubtreeState {
    var pendingFiles = 0
    var pendingDirectories = 0
    var pendingAllocated: Int64 = 0
    var unreadable = 0
    var issues: [String] = []
    var retainedDirs: [RetainedNode] = []
    var retainedFiles: [RetainedNode] = []
    var cacheCandidates: [DiskNode] = []
    var deepDirectories: [DiskNode] = []
    var projectCandidates: [(node: DiskNode, markers: [String])] = []
    var analysis = AnalysisAccumulator()
    var localLastCheck = Date.distantPast

    func note(_ path: String) {
        unreadable += 1
        if issues.count < ScanWorker.maxIssues {
            issues.append(path)
        }
    }
}

private final class SubdirResults: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [DiskNode] = []
    func append(_ node: DiskNode) { lock.withLock { items.append(node) } }
    func all() -> [DiskNode] { lock.withLock { items } }
}

private final class ScanWorker: @unchecked Sendable {
    static let maxRegularNodes = 40_000
    static let maxCacheCandidates = 400
    static let maxDeepDirectories = 1_500
    static let maxProjectCandidates = 400
    static let maxIssues = 50
    static let maxCompletedRoots = 2_000
    static let parallelSubdirThreshold = 4

    let root: URL
    let home: URL
    let profile: ScanPerformanceProfile
    let cancellation: ScanCancellation
    let progress: @Sendable (ScanProgress) -> Void
    private var device: dev_t = 0

    private let hardLinkLock = NSLock()
    private var hardLinks: Set<InodeKey> = []

    private let stateLock = NSLock()
    private var files = 0
    private var directories = 0
    private var allocated: Int64 = 0
    private var unreadable = 0
    private var issues: [String] = []
    private var retainedDirs: [RetainedNode] = []
    private var retainedFiles: [RetainedNode] = []
    private var cacheCandidates: [DiskNode] = []
    private var deepDirectories: [DiskNode] = []
    private var projectCandidates: [(node: DiskNode, markers: [String])] = []
    private var analysis = AnalysisAccumulator()
    private var lastUpdate = Date.distantPast
    private var completedRoots: [DiskNode] = []

    init(
        root: URL,
        home: URL,
        profile: ScanPerformanceProfile,
        cancellation: ScanCancellation,
        progress: @escaping @Sendable (ScanProgress) -> Void
    ) {
        self.root = root
        self.home = home
        self.profile = profile
        self.cancellation = cancellation
        self.progress = progress
    }

    func run() throws -> ScanResult {
        var st = stat()
        guard lstat(root.path, &st) == 0,
              (st.st_mode & S_IFMT) == S_IFDIR,
              root.resolvingSymlinksInPath().path == root.path else {
            throw ScanFailure.invalidRoot
        }
        let handle: DirectoryHandle
        do {
            handle = try DirectoryHandle(path: root.path)
        } catch {
            throw ScanFailure.unreadableRoot(root.path)
        }
        defer { close(handle.descriptor) }
        guard handle.matches(st), (try? handle.names()) != nil else {
            throw ScanFailure.unreadableRoot(root.path)
        }
        device = st.st_dev
        let started = Date()

        let rootState = SubtreeState()
        let node = withThreadDiskIOThrottled(profile.throttleDiskIO) {
            visit(root, depth: 0, openedRoot: handle, state: rootState)
        }
        mergeSubtree(rootState, completedRoot: nil, rootPath: nil)

        var nodes = finalizeRegularNodes()
        var storedPaths = Set(nodes.map(\.path))
        for candidate in cacheCandidates where !storedPaths.contains(candidate.path) {
            nodes.append(candidate)
            storedPaths.insert(candidate.path)
        }
        for dir in deepDirectories where !storedPaths.contains(dir.path) {
            nodes.append(dir)
            storedPaths.insert(dir.path)
        }
        let recs = RuleCatalog.recommendations(nodes: nodes, home: home)
        var topProjects: [ProjectSummary] = []
        let sortedProjects = projectCandidates.sorted {
            $0.node.path.count == $1.node.path.count ? $0.node.path < $1.node.path : $0.node.path.count < $1.node.path.count
        }
        for cand in sortedProjects {
            if topProjects.contains(where: { cand.node.path.hasPrefix($0.path + "/") }) { continue }
            let matchedCaches = recs.filter { $0.id.hasPrefix(cand.node.path + "/") }
            let cacheBytes = matchedCaches.reduce(Int64(0)) { $0 + $1.node.allocated }
            topProjects.append(ProjectSummary(
                path: cand.node.path,
                markers: cand.markers,
                allocated: cand.node.allocated,
                logical: cand.node.logical,
                fileCount: cand.node.fileCount,
                cacheAllocated: cacheBytes,
                cachePaths: matchedCaches.map(\.id),
                modifiedAt: cand.node.modifiedAt,
                protection: cand.node.protection
            ))
        }
        let details = analysis.result(projects: Array(topProjects.sorted {
            $0.allocated == $1.allocated ? $0.path < $1.path : $0.allocated > $1.allocated
        }.prefix(200)))
        for file in details.largeFiles where !storedPaths.contains(file.path) {
            nodes.append(file)
            storedPaths.insert(file.path)
        }
        let sortedNodes = nodes.sorted {
            $0.allocated == $1.allocated ? $0.path < $1.path : $0.allocated > $1.allocated
        }
        let finalSnapshot = stateLock.withLock { () -> ScanProgress in
            lastUpdate = Date()
            var update = ScanProgress(files: files, directories: directories, allocated: allocated, currentPath: root.path)
            update.rootNodes = completedRoots
            return update
        }
        progress(finalSnapshot)

        return .init(
            root: root.path,
            scannedAt: Date(),
            duration: Date().timeIntervalSince(started),
            allocated: node.allocated,
            logical: node.logical,
            files: files,
            directories: directories,
            unreadable: unreadable,
            issues: issues,
            nodes: sortedNodes,
            recommendations: recs,
            cancelled: cancellation.isCancelled,
            analysis: details
        )
    }

    private func claimHardLink(dev: dev_t, ino: ino_t) -> Bool {
        hardLinkLock.withLock {
            hardLinks.insert(InodeKey(dev: dev, ino: ino)).inserted
        }
    }

    private func maybePublish(_ local: SubtreeState, path: String) {
        let now = Date()
        guard now.timeIntervalSince(local.localLastCheck) > 0.3 else { return }
        local.localLastCheck = now
        var snapshot: ScanProgress?
        stateLock.lock()
        files += local.pendingFiles
        directories += local.pendingDirectories
        allocated += local.pendingAllocated
        local.pendingFiles = 0
        local.pendingDirectories = 0
        local.pendingAllocated = 0
        if now.timeIntervalSince(lastUpdate) > 0.3 {
            lastUpdate = now
            var update = ScanProgress(files: files, directories: directories, allocated: allocated, currentPath: path)
            update.rootNodes = completedRoots
            snapshot = update
        }
        stateLock.unlock()
        if let snapshot {
            progress(snapshot)
        }
    }

    private func flushPending(_ local: SubtreeState) {
        stateLock.withLock {
            files += local.pendingFiles
            directories += local.pendingDirectories
            allocated += local.pendingAllocated
            local.pendingFiles = 0
            local.pendingDirectories = 0
            local.pendingAllocated = 0
        }
    }

    private func recordRootChild(_ child: DiskNode, local: SubtreeState, rootPath: String) {
        let snapshot: ScanProgress = stateLock.withLock {
            files += local.pendingFiles
            directories += local.pendingDirectories
            allocated += local.pendingAllocated
            local.pendingFiles = 0
            local.pendingDirectories = 0
            local.pendingAllocated = 0
            if completedRoots.count < Self.maxCompletedRoots {
                completedRoots.append(child)
            }
            lastUpdate = Date()
            var update = ScanProgress(files: files, directories: directories, allocated: allocated, currentPath: rootPath)
            update.rootNodes = completedRoots
            return update
        }
        progress(snapshot)
    }

    private func mergeSubtree(_ local: SubtreeState, completedRoot: DiskNode?, rootPath: String?) {
        var snapshot: ScanProgress?
        stateLock.lock()
        files += local.pendingFiles
        directories += local.pendingDirectories
        allocated += local.pendingAllocated
        local.pendingFiles = 0
        local.pendingDirectories = 0
        local.pendingAllocated = 0

        unreadable += local.unreadable
        if issues.count < Self.maxIssues && !local.issues.isEmpty {
            let remaining = Self.maxIssues - issues.count
            issues.append(contentsOf: local.issues.prefix(remaining))
        }
        if !local.retainedDirs.isEmpty {
            retainedDirs.append(contentsOf: local.retainedDirs)
            if retainedDirs.count > Self.maxRegularNodes * 2 {
                retainedDirs = Self.compactRetained(retainedDirs, limit: Self.maxRegularNodes)
            }
        }
        if !local.retainedFiles.isEmpty {
            retainedFiles.append(contentsOf: local.retainedFiles)
            if retainedFiles.count > Self.maxRegularNodes * 2 {
                retainedFiles = Self.compactRetained(retainedFiles, limit: Self.maxRegularNodes)
            }
        }
        if cacheCandidates.count < Self.maxCacheCandidates && !local.cacheCandidates.isEmpty {
            let remaining = Self.maxCacheCandidates - cacheCandidates.count
            cacheCandidates.append(contentsOf: local.cacheCandidates.prefix(remaining))
        }
        if deepDirectories.count < Self.maxDeepDirectories && !local.deepDirectories.isEmpty {
            let remaining = Self.maxDeepDirectories - deepDirectories.count
            deepDirectories.append(contentsOf: local.deepDirectories.prefix(remaining))
        }
        if projectCandidates.count < Self.maxProjectCandidates && !local.projectCandidates.isEmpty {
            let remaining = Self.maxProjectCandidates - projectCandidates.count
            projectCandidates.append(contentsOf: local.projectCandidates.prefix(remaining))
        }
        analysis.merge(local.analysis)

        if let completedRoot {
            if completedRoots.count < Self.maxCompletedRoots {
                completedRoots.append(completedRoot)
            }
            if let rootPath {
                lastUpdate = Date()
                var update = ScanProgress(files: files, directories: directories, allocated: allocated, currentPath: rootPath)
                update.rootNodes = completedRoots
                snapshot = update
            }
        }
        stateLock.unlock()

        if let snapshot {
            progress(snapshot)
        }
    }

    private static func compactRetained(_ items: [RetainedNode], limit: Int) -> [RetainedNode] {
        guard items.count > limit else { return items }
        let sorted = items.sorted { a, b in
            let aPriority = a.depth <= 1 || a.isCache
            let bPriority = b.depth <= 1 || b.isCache
            if aPriority != bPriority { return aPriority }
            if a.depth != b.depth { return a.depth < b.depth }
            if a.node.allocated != b.node.allocated { return a.node.allocated > b.node.allocated }
            return a.node.path < b.node.path
        }
        return Array(sorted.prefix(limit))
    }

    private func finalizeRegularNodes() -> [DiskNode] {
        var deduped: [DiskNode] = []
        var seen: Set<String> = []
        let combinedCount = retainedDirs.count + retainedFiles.count
        let chosen: [RetainedNode]
        if combinedCount <= Self.maxRegularNodes {
            chosen = retainedDirs + retainedFiles
        } else {
            let topLevelFiles = retainedFiles.filter { $0.depth <= 1 }
            let deeperFiles = retainedFiles.filter { $0.depth > 1 }
            let dirBudget = max(0, Self.maxRegularNodes - topLevelFiles.count)
            let sortedDirs = Self.compactRetained(retainedDirs, limit: dirBudget)
            let remaining = max(0, Self.maxRegularNodes - topLevelFiles.count - sortedDirs.count)
            let sortedFiles = Self.compactRetained(deeperFiles, limit: remaining)
            chosen = topLevelFiles + sortedDirs + sortedFiles
        }
        deduped.reserveCapacity(chosen.count)
        for item in chosen where seen.insert(item.node.path).inserted {
            deduped.append(item.node)
        }
        return deduped
    }

    private func visit(
        _ url: URL,
        depth: Int,
        parent: DirectoryHandle? = nil,
        openedRoot: DirectoryHandle? = nil,
        bulk: BulkEntry? = nil,
        state: SubtreeState
    ) -> DiskNode {
        var st = stat()
        var node = DiskNode(path: url.path)
        if cancellation.isCancelled {
            node.protection.insert(.incomplete)
            return node
        }
        if let bulk, bulk.isRegularFile {
            guard bulk.dev == device else {
                state.note(url.path)
                node.protection.insert(.incomplete)
                node.restricted = true
                return node
            }
            node.modifiedAt = bulk.modifiedAt
            node.protection = RuleCatalog.protection(name: bulk.name, directory: false)
            node.kind = .file
            state.pendingFiles += 1
            node.fileCount = 1
            if url.pathExtension.isEmpty, bulk.mode & 0o111 != 0 {
                node.protection.insert(.source)
            }
            if bulk.nlink > 1 {
                if !claimHardLink(dev: bulk.dev, ino: bulk.ino) {
                    return node
                }
            }
            node.allocated = bulk.allocated
            node.logical = bulk.logical
            state.pendingAllocated += node.allocated
            if depth <= 4 && state.retainedFiles.count < Self.maxRegularNodes {
                state.retainedFiles.append(RetainedNode(depth: depth, isCache: false, node: node))
            }
            state.analysis.record(node)
            maybePublish(state, path: url.path)
            return node
        }
        guard (parent.map { fstatat($0.descriptor, url.lastPathComponent, &st, AT_SYMLINK_NOFOLLOW) } ?? lstat(url.path, &st)) == 0 else {
            state.note(url.path)
            node.restricted = true
            node.protection.insert(.incomplete)
            return node
        }
        let type = st.st_mode & S_IFMT
        if type == S_IFLNK {
            node.protection.insert(.symlink)
            node.allocated = Int64(st.st_blocks) * 512
            state.pendingAllocated += node.allocated
            return node
        }
        // Never cross into another mounted volume or follow APFS system/data aliases.
        guard st.st_dev == device else {
            state.note(url.path)
            node.protection.insert(.incomplete)
            node.restricted = true
            return node
        }
        if type != S_IFDIR && type != S_IFREG {
            return node
        }
        node.modifiedAt = Int64(st.st_mtimespec.tv_sec)
        node.protection = RuleCatalog.protection(name: url.lastPathComponent, directory: type == S_IFDIR)
        if type == S_IFREG {
            node.kind = .file
            state.pendingFiles += 1
            node.fileCount = 1
            if url.pathExtension.isEmpty, st.st_mode & 0o111 != 0 {
                node.protection.insert(.source)
            }
            if st.st_nlink > 1 {
                if !claimHardLink(dev: st.st_dev, ino: st.st_ino) {
                    return node
                }
            }
            node.allocated = Int64(st.st_blocks) * 512
            node.logical = Int64(st.st_size)
            state.pendingAllocated += node.allocated
            if depth <= 4 && state.retainedFiles.count < Self.maxRegularNodes {
                state.retainedFiles.append(RetainedNode(depth: depth, isCache: false, node: node))
            }
            state.analysis.record(node)
        } else {
            state.pendingDirectories += 1
            guard depth < 256 else {
                state.note(url.path)
                node.protection.insert(.incomplete)
                return node
            }
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
                state.pendingAllocated += node.allocated

                if depth == 0 && profile.maxConcurrency > 1 {
                    let subdirs = entries.filter(\.isDirectory)
                    if subdirs.count >= Self.parallelSubdirThreshold {
                        let nonDirs = entries.filter { !$0.isDirectory }
                        for entry in nonDirs {
                            if cancellation.isCancelled {
                                node.protection.insert(.incomplete)
                                break
                            }
                            let child = autoreleasepool {
                                visit(url.appendingPathComponent(entry.name), depth: 1, parent: dir, bulk: entry, state: state)
                            }
                            accumulateChild(child, into: &node)
                            recordRootChild(child, local: state, rootPath: url.path)
                        }

                        if !cancellation.isCancelled {
                            flushPending(state)
                            let queue = DispatchQueue(label: "com.aetherdisk.scanner.worker", qos: .utility, attributes: .concurrent)
                            let semaphore = DispatchSemaphore(value: profile.maxConcurrency)
                            let group = DispatchGroup()
                            let subdirResults = SubdirResults()
                            let rootPath = url.path
                            let throttle = profile.throttleDiskIO

                            for subdir in subdirs {
                                if cancellation.isCancelled {
                                    node.protection.insert(.incomplete)
                                    break
                                }
                                semaphore.wait()
                                if cancellation.isCancelled {
                                    semaphore.signal()
                                    node.protection.insert(.incomplete)
                                    break
                                }
                                let childURL = url.appendingPathComponent(subdir.name)
                                group.enter()
                                queue.async {
                                    defer {
                                        semaphore.signal()
                                        group.leave()
                                    }
                                    withThreadDiskIOThrottled(throttle) {
                                        let childState = SubtreeState()
                                        let child = autoreleasepool {
                                            self.visit(childURL, depth: 1, parent: dir, bulk: subdir, state: childState)
                                        }
                                        self.mergeSubtree(childState, completedRoot: child, rootPath: rootPath)
                                        subdirResults.append(child)
                                    }
                                }
                            }
                            group.wait()
                            for child in subdirResults.all() {
                                accumulateChild(child, into: &node)
                            }
                        }
                    } else {
                        visitSequentially(entries: entries, parentURL: url, depth: depth, dir: dir, node: &node, state: state)
                    }
                } else {
                    visitSequentially(entries: entries, parentURL: url, depth: depth, dir: dir, node: &node, state: state)
                }

                if !markers.isEmpty && state.projectCandidates.count < Self.maxProjectCandidates {
                    state.projectCandidates.append((node: node, markers: markers))
                }
                var after = stat()
                if fstat(dir.descriptor, &after) != 0 ||
                    after.st_mtimespec.tv_sec != st.st_mtimespec.tv_sec ||
                    after.st_mtimespec.tv_nsec != st.st_mtimespec.tv_nsec ||
                    after.st_ctimespec.tv_sec != st.st_ctimespec.tv_sec ||
                    after.st_ctimespec.tv_nsec != st.st_ctimespec.tv_nsec {
                    state.note(url.path)
                    node.protection.insert(.incomplete)
                }
            } catch {
                state.note(url.path)
                node.restricted = true
                node.protection.insert(.incomplete)
            }
            let isCache = RuleCatalog.category(for: url, home: home) != nil
            if depth == 0 || (state.retainedDirs.count < Self.maxRegularNodes && (depth <= 4 || isCache)) {
                state.retainedDirs.append(RetainedNode(depth: depth, isCache: isCache, node: node))
            } else if isCache && state.cacheCandidates.count < Self.maxCacheCandidates {
                state.cacheCandidates.append(node)
            } else if depth <= 10 && node.allocated >= 1024 * 1024 && state.deepDirectories.count < Self.maxDeepDirectories {
                state.deepDirectories.append(node)
            }
        }
        maybePublish(state, path: url.path)
        return node
    }

    private func visitSequentially(
        entries: [BulkEntry],
        parentURL: URL,
        depth: Int,
        dir: DirectoryHandle,
        node: inout DiskNode,
        state: SubtreeState
    ) {
        for entry in entries {
            if cancellation.isCancelled {
                node.protection.insert(.incomplete)
                break
            }
            let child = autoreleasepool {
                visit(parentURL.appendingPathComponent(entry.name), depth: depth + 1, parent: dir, bulk: entry, state: state)
            }
            accumulateChild(child, into: &node)
            if depth == 0 {
                recordRootChild(child, local: state, rootPath: parentURL.path)
            }
        }
    }

    private func accumulateChild(_ child: DiskNode, into parent: inout DiskNode) {
        parent.allocated += child.allocated
        parent.logical += child.logical
        parent.fileCount += child.fileCount
        if let childModified = child.modifiedAt {
            parent.modifiedAt = max(parent.modifiedAt ?? childModified, childModified)
        }
        parent.protection.formUnion(child.protection)
        parent.restricted = parent.restricted || child.restricted
    }
}
