import Foundation
import Darwin

public struct VolumeDescriptor: Identifiable, Sendable, Equatable {
    public var id: String { path }
    public var name: String
    public var path: String
    public var space: VolumeSpace
    public var fileSystemType: String
    public var isInternal: Bool
    public var isRemovable: Bool
    public var isReadOnly: Bool
    public var isSystemRoot: Bool

    public var isExternal: Bool { !isInternal || isRemovable }

    public init(
        name: String,
        path: String,
        space: VolumeSpace,
        fileSystemType: String,
        isInternal: Bool,
        isRemovable: Bool,
        isReadOnly: Bool,
        isSystemRoot: Bool
    ) {
        self.name = name
        self.path = path
        self.space = space
        self.fileSystemType = fileSystemType
        self.isInternal = isInternal
        self.isRemovable = isRemovable
        self.isReadOnly = isReadOnly
        self.isSystemRoot = isSystemRoot
    }

    public static func == (lhs: VolumeDescriptor, rhs: VolumeDescriptor) -> Bool {
        lhs.name == rhs.name &&
        lhs.path == rhs.path &&
        lhs.space.total == rhs.space.total &&
        lhs.space.free == rhs.space.free &&
        lhs.space.opportunisticFree == rhs.space.opportunisticFree &&
        lhs.fileSystemType == rhs.fileSystemType &&
        lhs.isInternal == rhs.isInternal &&
        lhs.isRemovable == rhs.isRemovable &&
        lhs.isReadOnly == rhs.isReadOnly &&
        lhs.isSystemRoot == rhs.isSystemRoot
    }
}

public enum VolumeDiscovery {
    public static func mountedVolumes() -> [VolumeDescriptor] {
        let keys: [URLResourceKey] = [
            .volumeNameKey,
            .volumeIsInternalKey,
            .volumeIsRemovableKey,
            .volumeIsReadOnlyKey,
            .volumeLocalizedFormatDescriptionKey,
            .volumeIsRootFileSystemKey
        ]
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) ?? []

        var seenPaths = Set<String>()
        var descriptors: [VolumeDescriptor] = []

        for url in urls {
            let path = url.standardizedFileURL.path
            guard seenPaths.insert(path).inserted else { continue }
            let space = VolumeSpace.read(at: url)
            guard space.total > 0 else { continue }

            let values = try? url.resourceValues(forKeys: Set(keys))
            let isSystemRoot = (values?.volumeIsRootFileSystem ?? false) || path == "/"
            let rawName = values?.volumeName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let name = rawName.isEmpty ? (path == "/" ? "Macintosh HD" : url.lastPathComponent) : rawName
            let fsDesc = values?.volumeLocalizedFormatDescription?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let fileSystemType = fsDesc.isEmpty ? readFileSystemTypeName(at: path) : fsDesc
            let isInternal = values?.volumeIsInternal ?? isSystemRoot
            let isRemovable = values?.volumeIsRemovable ?? false
            let isReadOnly = values?.volumeIsReadOnly ?? false

            descriptors.append(
                VolumeDescriptor(
                    name: name,
                    path: path,
                    space: space,
                    fileSystemType: fileSystemType,
                    isInternal: isInternal,
                    isRemovable: isRemovable,
                    isReadOnly: isReadOnly,
                    isSystemRoot: isSystemRoot
                )
            )
        }

        descriptors.sort { a, b in
            let aRoot = a.path == "/" || a.isSystemRoot
            let bRoot = b.path == "/" || b.isSystemRoot
            if aRoot != bRoot { return aRoot }
            let cmp = a.name.localizedCaseInsensitiveCompare(b.name)
            if cmp != .orderedSame { return cmp == .orderedAscending }
            if a.name != b.name { return a.name < b.name }
            return a.path < b.path
        }
        return descriptors
    }

    private static func readFileSystemTypeName(at path: String) -> String {
        var info = statfs()
        guard statfs(path, &info) == 0 else { return "未知" }
        return withUnsafePointer(to: &info.f_fstypename) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: Int(MFSNAMELEN)) { cStr in
                let name = String(cString: cStr)
                return name.isEmpty ? "未知" : name.uppercased()
            }
        }
    }
}

public struct APFSSnapshotInfo: Identifiable, Sendable, Equatable {
    public var id: String { name }
    public var name: String
    public var dateLabel: String

    public init(name: String, dateLabel: String) {
        self.name = name
        self.dateLabel = dateLabel
    }
}

public struct APFSSnapshotReport: Sendable, Equatable {
    public var volumePath: String
    public var snapshots: [APFSSnapshotInfo]
    public var note: String
    public var inspectedAt: Date

    public init(
        volumePath: String,
        snapshots: [APFSSnapshotInfo],
        note: String,
        inspectedAt: Date = Date()
    ) {
        self.volumePath = volumePath
        self.snapshots = snapshots
        self.note = note
        self.inspectedAt = inspectedAt
    }
}

public enum APFSSnapshotInspector {
    public static func parse(tmutilOutput: String) -> [APFSSnapshotInfo] {
        var result: [APFSSnapshotInfo] = []
        var seen = Set<String>()
        for rawLine in tmutilOutput.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            let lower = line.lowercased()
            if lower.hasPrefix("snapshots for ") && line.hasSuffix(":") {
                continue
            }
            guard seen.insert(line).inserted else { continue }
            result.append(APFSSnapshotInfo(name: line, dateLabel: extractDateLabel(from: line)))
        }
        return result
    }

    private static func extractDateLabel(from name: String) -> String {
        // Match YYYY-MM-DD-HHMMSS (e.g. com.apple.TimeMachine.2026-11-23-091234.local)
        if let regex = try? NSRegularExpression(pattern: #"(\d{4}-\d{2}-\d{2})-(\d{2})(\d{2})(\d{2})"#),
           let match = regex.firstMatch(in: name, range: NSRange(name.startIndex..<name.endIndex, in: name)),
           match.numberOfRanges == 5,
           let dateRange = Range(match.range(at: 1), in: name),
           let hhRange = Range(match.range(at: 2), in: name),
           let mmRange = Range(match.range(at: 3), in: name),
           let ssRange = Range(match.range(at: 4), in: name) {
            return "\(name[dateRange]) \(name[hhRange]):\(name[mmRange]):\(name[ssRange])"
        }
        return name
    }

    private final class ProcessGuard: @unchecked Sendable {
        private let lock = NSLock()
        private let process: Process
        private var finished = false
        private var timedOut = false

        init(process: Process) {
            self.process = process
        }

        func markFinished() {
            lock.withLock { finished = true }
        }

        func timeoutIfRunning() {
            lock.withLock {
                guard !finished, process.isRunning else { return }
                timedOut = true
                let pid = process.processIdentifier
                if pid > 0 {
                    kill(pid, SIGKILL)
                }
            }
        }

        var didTimeOut: Bool {
            lock.withLock { timedOut }
        }
    }

    public static func inspect(volumePath: String = "/") -> APFSSnapshotReport {
        let now = Date()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tmutil")
        process.arguments = ["listlocalsnapshots", volumePath]
        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return APFSSnapshotReport(
                volumePath: volumePath,
                snapshots: [],
                note: "无法启动系统快照只读检查工具",
                inspectedAt: now
            )
        }

        let guardState = ProcessGuard(process: process)
        let timeoutItem = DispatchWorkItem { guardState.timeoutIfRunning() }
        DispatchQueue.global().asyncAfter(deadline: .now() + 3, execute: timeoutItem)

        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guardState.markFinished()
        timeoutItem.cancel()

        if guardState.didTimeOut || process.terminationReason != .exit {
            return APFSSnapshotReport(
                volumePath: volumePath,
                snapshots: [],
                note: "读取 APFS 本地快照超时（已只读中止）",
                inspectedAt: Date()
            )
        }

        guard process.terminationStatus == 0 else {
            return APFSSnapshotReport(
                volumePath: volumePath,
                snapshots: [],
                note: "无法读取该卷的 APFS 本地快照（可能非 APFS 卷或权限受限）",
                inspectedAt: Date()
            )
        }

        let output = String(decoding: data, as: UTF8.self)
        let parsed = parse(tmutilOutput: output)
        let note = parsed.isEmpty
            ? "当前未检测到 APFS 本地快照"
            : "检测到 \(parsed.count) 个 APFS 本地快照（只读展示）"
        return APFSSnapshotReport(
            volumePath: volumePath,
            snapshots: parsed,
            note: note,
            inspectedAt: Date()
        )
    }
}

public enum FullDiskAccessProbe {
    public static func isGranted(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
        let candidates = [
            home.appendingPathComponent("Library/Mail"),
            home.appendingPathComponent("Library/Safari"),
            home.appendingPathComponent("Library/Cookies")
        ]
        for url in candidates {
            let fd = open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            if fd >= 0 {
                close(fd)
                return true
            }
            if errno == EPERM || errno == EACCES {
                return false
            }
        }
        return true
    }
}

public struct TrashSummary: Sendable, Equatable {
    public var itemCount: Int
    public var allocated: Int64
    public var readable: Bool

    public init(itemCount: Int, allocated: Int64, readable: Bool) {
        self.itemCount = itemCount
        self.allocated = allocated
        self.readable = readable
    }
}

public enum TrashInspector {
    private struct InodeKey: Hashable {
        let dev: dev_t
        let ino: ino_t
    }

    private static let maxEntries = 2_000
    private static let maxDepth = 6

    public static func inspect(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> TrashSummary {
        let trashURL = home.appendingPathComponent(".Trash")
        let rootFD = open(trashURL.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        if rootFD < 0 {
            if errno == ENOENT {
                return TrashSummary(itemCount: 0, allocated: 0, readable: true)
            }
            return TrashSummary(itemCount: 0, allocated: 0, readable: false)
        }
        defer { close(rootFD) }

        var rootStat = stat()
        guard fstat(rootFD, &rootStat) == 0 else {
            return TrashSummary(itemCount: 0, allocated: 0, readable: false)
        }
        let rootDevice = rootStat.st_dev

        var itemCount = 0
        var totalAllocated: Int64 = 0
        var visitedEntries = 0
        var seenHardLinks = Set<InodeKey>()

        func readNames(of fd: Int32) -> [String]? {
            let dupFD = openat(fd, ".", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard dupFD >= 0 else { return nil }
            guard let stream = fdopendir(dupFD) else {
                close(dupFD)
                return nil
            }
            defer { closedir(stream) }
            var names: [String] = []
            while true {
                errno = 0
                guard let entry = readdir(stream) else {
                    if errno != 0 { return nil }
                    return names
                }
                let name = withUnsafePointer(to: &entry.pointee.d_name) {
                    $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) {
                        String(cString: $0)
                    }
                }
                if name != "." && name != ".." {
                    names.append(name)
                }
            }
        }

        func walk(dirFD: Int32, depth: Int) -> Bool {
            guard let names = readNames(of: dirFD) else { return false }
            for name in names {
                if visitedEntries >= maxEntries { break }
                visitedEntries += 1
                if depth == 0 {
                    itemCount += 1
                }
                var st = stat()
                guard fstatat(dirFD, name, &st, AT_SYMLINK_NOFOLLOW) == 0 else { continue }
                guard st.st_dev == rootDevice else { continue }

                let type = st.st_mode & S_IFMT
                if type == S_IFLNK {
                    totalAllocated += Int64(st.st_blocks) * 512
                    continue
                }
                if type == S_IFREG {
                    if st.st_nlink > 1 {
                        let key = InodeKey(dev: st.st_dev, ino: st.st_ino)
                        if !seenHardLinks.insert(key).inserted { continue }
                    }
                    totalAllocated += Int64(st.st_blocks) * 512
                } else if type == S_IFDIR {
                    totalAllocated += Int64(st.st_blocks) * 512
                    if depth + 1 < maxDepth {
                        let childFD = openat(dirFD, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                        if childFD >= 0 {
                            defer { close(childFD) }
                            var childStat = stat()
                            if fstat(childFD, &childStat) == 0,
                               childStat.st_dev == st.st_dev,
                               childStat.st_ino == st.st_ino {
                                _ = walk(dirFD: childFD, depth: depth + 1)
                            }
                        }
                    }
                }
            }
            return true
        }

        guard walk(dirFD: rootFD, depth: 0) else {
            return TrashSummary(itemCount: 0, allocated: 0, readable: false)
        }
        return TrashSummary(itemCount: itemCount, allocated: totalAllocated, readable: true)
    }
}
