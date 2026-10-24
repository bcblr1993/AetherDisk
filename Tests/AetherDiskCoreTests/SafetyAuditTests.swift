import XCTest
import Foundation
import Darwin
@testable import AetherDiskCore

final class SafetyAuditTests: XCTestCase, @unchecked Sendable {
    var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("AetherDiskTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { if let root { try? FileManager.default.removeItem(at: root) } }
    @discardableResult func file(_ path: String, bytes: Int = 8192) throws -> URL {
        let p = root.appendingPathComponent(path); try FileManager.default.createDirectory(at: p.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 7, count: bytes).write(to: p); return p
    }
    func cache(_ name: String = "Example") throws -> URL { let p = try file("Home/Library/Caches/\(name)/cache.data"); return p.deletingLastPathComponent() }
    var home: URL { root.appendingPathComponent("Home") }

    func testBatchPreviewDeduplicatesHardlinksAcrossTargets() async throws {
        let a = try cache("A"); let b = home.appendingPathComponent("Library/Caches/B")
        try FileManager.default.createDirectory(at: b, withIntermediateDirectories: true)
        try FileManager.default.linkItem(at: a.appendingPathComponent("cache.data"), to: b.appendingPathComponent("alias.data"))
        let service = CleanupService(home: home, checkUsage: { _ in })
        let plan = try await service.prepare(paths: [a.path, b.path])
        let scan = try DiskScanner.scan(root: home.appendingPathComponent("Library/Caches"), home: home)
        var parentInfo = stat(); XCTAssertEqual(lstat(home.appendingPathComponent("Library/Caches").path, &parentInfo), 0)
        XCTAssertEqual(plan.allocated, scan.allocated - Int64(parentInfo.st_blocks) * 512)
        XCTAssertLessThan(plan.allocated, plan.targets.reduce(0) { $0 + $1.allocated })
    }
    func testBareRepositoryIsProtected() throws {
        let candidate = try cache()
        _ = try SafetyInspector.runProcess("/usr/bin/git", ["init", "--bare", "-q", candidate.path], allowFailure: false)
        XCTAssertThrowsError(try SafetyInspector.inspect(candidate, home: home))
        XCTAssertTrue(try DiskScanner.scan(root: candidate, home: home).recommendations.first?.blocked == true)
    }
    func testProjectMarkerCannotBeDirectoryOrSymlink() throws {
        let candidate = try file("Home/project/.build/cache.data").deletingLastPathComponent()
        let marker = home.appendingPathComponent("project/Package.swift")
        try FileManager.default.createDirectory(at: marker, withIntermediateDirectories: true)
        XCTAssertNil(RuleCatalog.category(for: candidate, home: home))
        try FileManager.default.removeItem(at: marker)
        let outside = try file("Outside/Package.swift")
        try FileManager.default.createSymbolicLink(at: marker, withDestinationURL: outside)
        XCTAssertNil(RuleCatalog.category(for: candidate, home: home))
    }
    func testExecutableWithoutExtensionIsProtected() throws {
        let candidate = try cache(); let script = candidate.appendingPathComponent("run")
        try Data("#!/bin/sh\necho code\n".utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        XCTAssertThrowsError(try SafetyInspector.inspect(candidate, home: home))
        XCTAssertTrue(try DiskScanner.scan(root: candidate, home: home).recommendations.first?.blocked == true)
    }
    func testDirectoryMutationDuringScanIsExplicitlyPartial() throws {
        try file("Home/A/data"); try file("Home/B/data")
        let location = home.appendingPathComponent("new.data"); let once = LockedCount()
        let result = try DiskScanner.scan(root: home) { progress in
            if !progress.rootNodes.isEmpty, once.next() == 1 { try? Data([1]).write(to: location) }
        }
        XCTAssertFalse(result.complete); XCTAssertTrue(result.issues.contains(home.path))
    }
    func testAllocationMatchesDuWithSparseHardlinksAndLongSymlink() throws {
        let candidate = try cache()
        let payload = candidate.appendingPathComponent("cache.data")
        try FileManager.default.linkItem(at: payload, to: candidate.appendingPathComponent("alias"))
        let sparse = candidate.appendingPathComponent("sparse")
        FileManager.default.createFile(atPath: sparse.path, contents: nil)
        let handle = try FileHandle(forWritingTo: sparse); try handle.truncate(atOffset: 1 << 30); try handle.close()
        try FileManager.default.createSymbolicLink(atPath: candidate.appendingPathComponent("long-link").path, withDestinationPath: String(repeating: "a/", count: 450))
        let scan = try DiskScanner.scan(root: candidate, home: home)
        let du = try SafetyInspector.runProcess("/usr/bin/du", ["-xsk", candidate.path], allowFailure: false)
        let kib = try XCTUnwrap(Int64(du.output.split(whereSeparator: \.isWhitespace)[0]))
        XCTAssertEqual((scan.allocated + 1023) / 1024, kib)
        XCTAssertEqual(scan.files, 3); XCTAssertEqual(scan.logical, (1 << 30) + 8192)
    }
    func testAdditionalSourceAndReleaseFormatsBlockCleanup() throws {
        for name in ["Component.jsx", "script.kts", "tool.php", "Makefile", "CMakeLists.txt", "Dockerfile", "archive.tgz", "Apple.xip", "system.iso", "firmware.ipsw", "library.aar"] {
            let candidate = try cache(name)
            try file("Home/Library/Caches/\(name)/\(name)")
            XCTAssertThrowsError(try SafetyInspector.inspect(candidate, home: home), name)
            XCTAssertTrue(try DiskScanner.scan(root: candidate, home: home).recommendations.first?.blocked == true, name)
        }
    }
    func testCacheInsideProtectedContainerCannotBeCleanedDirectly() throws {
        for container in ["Saved.app", "Release.xcarchive", "Backup", "Sources", "Releases"] {
            let candidate = try file("Home/\(container)/project/.build/cache.data").deletingLastPathComponent()
            try file("Home/\(container)/project/Package.swift")
            XCTAssertThrowsError(try SafetyInspector.inspect(candidate, home: home), container)
            XCTAssertTrue(try DiskScanner.scan(root: candidate, home: home).recommendations.first?.blocked == true)
        }
    }
    func testBuildLikeNamesNeedProjectEvidence() throws {
        for name in [".gradle", ".dart_tool", "DerivedData"] {
            let candidate = try file("Home/work/\(name)/valuable.data").deletingLastPathComponent()
            XCTAssertNil(RuleCatalog.category(for: candidate, home: home))
            XCTAssertThrowsError(try SafetyInspector.inspect(candidate, home: home))
        }
        try file("Home/work/pubspec.yaml")
        XCTAssertEqual(RuleCatalog.category(for: home.appendingPathComponent("work/.dart_tool"), home: home), .build)
    }
    func testInspectionAndScanAgreeOnHardlinkAllocation() throws {
        let candidate = try cache()
        try FileManager.default.linkItem(at: candidate.appendingPathComponent("cache.data"), to: candidate.appendingPathComponent("alias.data"))
        let scan = try DiskScanner.scan(root: candidate, home: home)
        let inspection = try SafetyInspector.inspect(candidate, home: home)
        XCTAssertEqual(scan.allocated, inspection.allocated); XCTAssertEqual(inspection.files, 2)
    }
    func testFileChangedDuringLastUsageCheckIsPreserved() async throws {
        let candidate = try cache(); let counter = LockedCount()
        let service = CleanupService(home: home, trash: { _ in XCTFail("Must preserve changed cache") }, checkUsage: { _ in
            if counter.next() == 3 { try Data("source".utf8).write(to: candidate.appendingPathComponent("new.jsx")) }
        })
        let plan = try await service.prepare(paths: [candidate.path])
        let receipt = try await service.execute(confirmedPlanID: plan.id)
        XCTAssertTrue(receipt.moved.isEmpty); XCTAssertEqual(receipt.failed.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: candidate.appendingPathComponent("new.jsx").path))
    }
    func testFailedBatchReportsEveryRetainedTarget() async throws {
        let a = try cache("A"); let b = try cache("B")
        let service = CleanupService(home: home, trash: { _ in throw CleanupError.changed }, checkUsage: { _ in })
        let plan = try await service.prepare(paths: [a.path, b.path])
        let receipt = try await service.execute(confirmedPlanID: plan.id)
        XCTAssertTrue(receipt.moved.isEmpty); XCTAssertEqual(receipt.failed.count, 2)
    }
    func testEquivalentPathsUseOneCanonicalTarget() async throws {
        let candidate = try cache()
        let service = CleanupService(home: home, checkUsage: { _ in })
        let plan = try await service.prepare(paths: [candidate.path, candidate.path + "/../Example/"])
        XCTAssertEqual(plan.targets.map(\.path), [candidate.path])
    }
    func testBrokenGitMetadataFailsClosed() throws {
        let candidate = try cache(); try file("Home/.git", bytes: 3)
        XCTAssertThrowsError(try SafetyInspector.inspect(candidate, home: home))
    }
    func testUnignoredGitFileWithUnknownExtensionIsProtected() throws {
        let candidate = try cache()
        _ = try SafetyInspector.runProcess("/usr/bin/git", ["-C", home.path, "init", "-q"], allowFailure: false)
        XCTAssertThrowsError(try SafetyInspector.inspect(candidate, home: home))
        try Data("Library/Caches/\n".utf8).write(to: home.appendingPathComponent(".gitignore"))
        XCTAssertNoThrow(try SafetyInspector.inspect(candidate, home: home))
    }
    func testDirectoryDescriptorDoesNotFollowReplacementLink() throws {
        let candidate = try cache(); let handle = try DirectoryHandle(path: candidate.path)
        defer { close(handle.descriptor) }
        let outside = try file("Outside/secret.data").deletingLastPathComponent()
        try FileManager.default.moveItem(at: candidate, to: candidate.appendingPathExtension("old"))
        try FileManager.default.createSymbolicLink(at: candidate, withDestinationURL: outside)
        XCTAssertEqual(try handle.names(), ["cache.data"])
        XCTAssertThrowsError(try DirectoryHandle(path: candidate.path))
        XCTAssertThrowsError(try SafetyInspector.inspect(candidate, home: home))
    }
    func testLastProgressRetainsCompletedRootRows() throws {
        try file("Home/A/data")
        let updates = ProgressCapture()
        _ = try DiskScanner.scan(root: home) { updates.store($0) }
        XCTAssertEqual(updates.last?.rootNodes.map(\.name), ["A"])
    }
    func testChangeTimeDetectsSameSizeRewriteWithRestoredModificationTime() throws {
        let candidate = try cache(); let payload = candidate.appendingPathComponent("cache.data")
        let before = try SafetyInspector.inspect(candidate, home: home)
        let attrs = try FileManager.default.attributesOfItem(atPath: payload.path)
        let handle = try FileHandle(forWritingTo: payload); try handle.write(contentsOf: Data(repeating: 9, count: 8192)); try handle.close()
        try FileManager.default.setAttributes([.modificationDate: attrs[.modificationDate]!], ofItemAtPath: payload.path)
        XCTAssertNotEqual(before.fingerprint, try SafetyInspector.inspect(candidate, home: home).fingerprint)
    }
}
private final class LockedCount: @unchecked Sendable {
    private let lock = NSLock(); private var count = 0
    func next() -> Int { lock.lock(); defer { lock.unlock() }; count += 1; return count }
}
private final class ProgressCapture: @unchecked Sendable {
    private let lock = NSLock(); private var value: ScanProgress?
    var last: ScanProgress? { lock.lock(); defer { lock.unlock() }; return value }
    func store(_ update: ScanProgress) { lock.lock(); defer { lock.unlock() }; value = update }
}
