import Foundation
import Darwin

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
    func matches(_ info: stat) -> Bool {
        var current = stat()
        return fstat(descriptor, &current) == 0 && current.st_dev == info.st_dev && current.st_ino == info.st_ino
    }
}
