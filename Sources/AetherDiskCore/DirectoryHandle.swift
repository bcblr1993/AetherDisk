import Foundation
import Darwin

public struct BulkEntry: Sendable, Equatable {
    public let name: String
    public let dev: dev_t
    public let ino: ino_t
    public let mode: mode_t
    public let nlink: UInt32
    public let allocated: Int64
    public let logical: Int64
    public let modifiedAt: Int64
    public var isDirectory: Bool { (mode & S_IFMT) == S_IFDIR }
    public var isRegularFile: Bool { (mode & S_IFMT) == S_IFREG }
    public var isSymlink: Bool { (mode & S_IFMT) == S_IFLNK }
}

// Bind traversal to an opened directory, never to a path that can turn into a link.
struct DirectoryHandle {
    let descriptor: Int32
    init(path: String) throws {
        descriptor = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw CleanupError.changed }
    }
    init(parent: Int32, name: String) throws {
        descriptor = openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw CleanupError.changed }
    }
    func names() throws -> [String] {
        // A new open description gives each enumeration its own offset.
        let copy = openat(descriptor, ".", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard copy >= 0 else { throw CleanupError.changed }
        guard let stream = fdopendir(copy) else { close(copy); throw CleanupError.changed }
        defer { closedir(stream) }
        var result: [String] = []
        while true {
            errno = 0
            guard let entry = readdir(stream) else {
                guard errno == 0 else { throw CleanupError.changed }
                return result
            }
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
            }
            if name != "." && name != ".." { result.append(name) }
        }
    }
    func bulkEntries() throws -> [BulkEntry] {
        let copy = openat(descriptor, ".", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard copy >= 0 else { throw CleanupError.changed }
        defer { close(copy) }
        var alist = attrlist()
        alist.bitmapcount = UInt16(ATTR_BIT_MAP_COUNT)
        alist.commonattr = attrgroup_t(ATTR_CMN_RETURNED_ATTRS) | attrgroup_t(ATTR_CMN_NAME) | attrgroup_t(ATTR_CMN_DEVID) | attrgroup_t(ATTR_CMN_OBJTYPE) | attrgroup_t(ATTR_CMN_MODTIME) | attrgroup_t(ATTR_CMN_ACCESSMASK) | attrgroup_t(ATTR_CMN_FILEID)
        alist.fileattr = attrgroup_t(ATTR_FILE_LINKCOUNT) | attrgroup_t(ATTR_FILE_TOTALSIZE) | attrgroup_t(ATTR_FILE_ALLOCSIZE)
        let bufSize = 64 * 1024
        let buf = UnsafeMutableRawPointer.allocate(byteCount: bufSize, alignment: 8)
        defer { buf.deallocate() }
        var results: [BulkEntry] = []
        while true {
            let count = getattrlistbulk(copy, &alist, buf, bufSize, UInt64(FSOPT_NOFOLLOW))
            if count < 0 { throw CleanupError.changed }
            if count == 0 { break }
            var entryPtr = UnsafeRawPointer(buf)
            for _ in 0..<count {
                let recLen = Int(entryPtr.loadUnaligned(as: UInt32.self))
                var cursor = entryPtr.advanced(by: 4)
                let returnedCommon = cursor.loadUnaligned(as: UInt32.self)
                let returnedFile = cursor.loadUnaligned(fromByteOffset: 12, as: UInt32.self)
                cursor = cursor.advanced(by: 20)
                var name = ""
                if (returnedCommon & UInt32(ATTR_CMN_NAME)) != 0 {
                    let nameRefPtr = cursor
                    let dataOffset = Int(cursor.loadUnaligned(as: Int32.self))
                    cursor = cursor.advanced(by: 8)
                    let cStr = nameRefPtr.advanced(by: dataOffset).assumingMemoryBound(to: CChar.self)
                    name = String(cString: cStr)
                }
                var dev: dev_t = 0
                if (returnedCommon & UInt32(ATTR_CMN_DEVID)) != 0 {
                    dev = cursor.loadUnaligned(as: dev_t.self)
                    cursor = cursor.advanced(by: 4)
                }
                var objType: UInt32 = 0
                if (returnedCommon & UInt32(ATTR_CMN_OBJTYPE)) != 0 {
                    objType = cursor.loadUnaligned(as: UInt32.self)
                    cursor = cursor.advanced(by: 4)
                }
                var mtime: Int64 = 0
                if (returnedCommon & UInt32(ATTR_CMN_MODTIME)) != 0 {
                    mtime = Int64(cursor.loadUnaligned(as: Int.self))
                    cursor = cursor.advanced(by: 16)
                }
                var accessMask: UInt32 = 0
                if (returnedCommon & UInt32(ATTR_CMN_ACCESSMASK)) != 0 {
                    accessMask = cursor.loadUnaligned(as: UInt32.self)
                    cursor = cursor.advanced(by: 4)
                }
                var fileID: UInt64 = 0
                if (returnedCommon & UInt32(ATTR_CMN_FILEID)) != 0 {
                    fileID = cursor.loadUnaligned(as: UInt64.self)
                    cursor = cursor.advanced(by: 8)
                }
                if name != "." && name != ".." && !name.isEmpty {
                    let hasAllFileAttrs = objType == 1 && (returnedFile & UInt32(ATTR_FILE_LINKCOUNT | ATTR_FILE_TOTALSIZE | ATTR_FILE_ALLOCSIZE)) == UInt32(ATTR_FILE_LINKCOUNT | ATTR_FILE_TOTALSIZE | ATTR_FILE_ALLOCSIZE)
                    if hasAllFileAttrs {
                        let nlink = cursor.loadUnaligned(as: UInt32.self)
                        let logical = cursor.loadUnaligned(fromByteOffset: 4, as: Int64.self)
                        let allocated = cursor.loadUnaligned(fromByteOffset: 12, as: Int64.self)
                        let mode = mode_t(S_IFREG) | mode_t(accessMask & 0o7777)
                        results.append(BulkEntry(name: name, dev: dev, ino: ino_t(fileID), mode: mode, nlink: nlink, allocated: allocated, logical: logical, modifiedAt: mtime))
                    } else {
                        var st = stat()
                        if fstatat(descriptor, name, &st, AT_SYMLINK_NOFOLLOW) == 0 {
                            results.append(BulkEntry(name: name, dev: st.st_dev, ino: st.st_ino, mode: st.st_mode, nlink: UInt32(st.st_nlink), allocated: Int64(st.st_blocks) * 512, logical: Int64(st.st_size), modifiedAt: Int64(st.st_mtimespec.tv_sec)))
                        }
                    }
                }
                entryPtr = entryPtr.advanced(by: recLen)
            }
        }
        return results
    }
    func matches(_ info: stat) -> Bool {
        var current = stat()
        return fstat(descriptor, &current) == 0 && current.st_dev == info.st_dev && current.st_ino == info.st_ino
    }
}
