import XCTest
import Foundation
import Darwin
@testable import AetherDiskCore

final class CoreTests: XCTestCase, @unchecked Sendable {
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
    func testHiddenDirectoriesAndDeepAggregation() throws {
        try file("Home/.hidden/a.bin", bytes: 4096); try file("Home/Docs/deep/value.data", bytes: 8192)
        let r = try DiskScanner.scan(root: home, home: home)
        XCTAssertEqual(r.files, 2); XCTAssertEqual(r.logical, 12288); XCTAssertTrue(r.complete)
        XCTAssertTrue(r.nodes.contains { $0.name == ".hidden" && $0.allocated > 0 })
    }
    func testNoSymlinkTraversalOrOutsideContent() throws {
        try file("Home/safe.data"); let external = try file("Outside/secret.data", bytes: 65536)
        try FileManager.default.createSymbolicLink(at: home.appendingPathComponent("link"), withDestinationURL: external.deletingLastPathComponent())
        let r = try DiskScanner.scan(root: home, home: home)
        XCTAssertEqual(r.files, 1); XCTAssertEqual(r.logical, 8192)
    }
    func testRejectSymlinkScanRoot() throws {
        let c = try cache(); let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: c)
        XCTAssertThrowsError(try DiskScanner.scan(root: link))
    }
    func testSparseFileCountsAllocatedSeparately() throws {
        let p = try file("Home/sparse.data", bytes: 0)
        let h = try FileHandle(forWritingTo: p); try h.truncate(atOffset: 128 * 1024 * 1024); try h.close()
        let r = try DiskScanner.scan(root: home)
        XCTAssertEqual(r.logical, 128 * 1024 * 1024); XCTAssertLessThan(r.allocated, r.logical)
    }
    func testHardlinksAreNotDoubleCounted() throws {
        let p = try file("Home/a.data"); try FileManager.default.linkItem(at: p, to: home.appendingPathComponent("b.data"))
        let r = try DiskScanner.scan(root: home)
        XCTAssertEqual(r.files, 2); XCTAssertEqual(r.logical, 8192)
    }
    func testCancellationReturnsExplicitPartialResult() throws {
        for n in 0..<40 { try file("Home/\(n).data") }
        let token = ScanCancellation()
        let r = try DiskScanner.scan(root: home, cancellation: token) { update in if update.files > 0 { token.cancel() } }
        XCTAssertTrue(r.cancelled); XCTAssertFalse(r.complete); XCTAssertLessThan(r.files, 40)
    }
    func testInstallerAndSourceAreProtectedInSuggestions() throws {
        let c = try cache(); try file("Home/Library/Caches/Example/release.dmg"); try file("Home/Library/Caches/Example/private.swift")
        let r = try DiskScanner.scan(root: home, home: home)
        let suggestion = try XCTUnwrap(r.recommendations.first { $0.id == c.path })
        XCTAssertTrue(suggestion.blocked); XCTAssertTrue(suggestion.node.protection.contains(.installer)); XCTAssertTrue(suggestion.node.protection.contains(.source))
    }
    func testDirectoryNameAloneIsNotBuildEvidence() throws {
        let p = root.appendingPathComponent("Home/build"); try file("Home/build/random.data")
        XCTAssertNil(RuleCatalog.category(for: p, home: home))
        try file("Home/Package.swift")
        XCTAssertEqual(RuleCatalog.category(for: p, home: home), .build)
    }
    func testRejectSourceCredentialsAndInstallers() throws {
        for name in ["work.swift", "module.go", "release.dmg", "archive.tar.gz", ".env", ".env.production", "secret.key", "profile.aetherroute"] {
            let c = try cache(name); try file("Home/Library/Caches/\(name)/\(name)")
            XCTAssertThrowsError(try SafetyInspector.inspect(c, home: home), name)
        }
    }
    func testGitTrackedCacheLikeFileProtected() throws {
        let c = try cache()
        _ = try SafetyInspector.runProcess("/usr/bin/git", ["-C", home.path, "init", "-q"], allowFailure: false)
        _ = try SafetyInspector.runProcess("/usr/bin/git", ["-C", home.path, "add", "Library/Caches/Example/cache.data"], allowFailure: false)
        XCTAssertThrowsError(try SafetyInspector.inspect(c, home: home))
    }
    func testNestedWorktreeMarkerProtected() throws {
        let c = try cache(); try file("Home/Library/Caches/Example/working/.git", bytes: 5)
        XCTAssertThrowsError(try SafetyInspector.inspect(c, home: home))
    }
    func testRootAndUnknownPathsCannotBeCleaned() throws {
        _ = try cache(); let u = try file("Home/Documents/data").deletingLastPathComponent()
        XCTAssertThrowsError(try SafetyInspector.inspect(home, home: home)); XCTAssertThrowsError(try SafetyInspector.inspect(u, home: home))
    }
    func testOpenFileBlocksCleanup() throws {
        let c = try cache(); let handle = try FileHandle(forReadingFrom: c.appendingPathComponent("cache.data")); defer { try? handle.close() }
        XCTAssertThrowsError(try SafetyInspector.requireUnused([c.path]))
    }
    func testNoActionWithoutConfirmationAndSingleUsePlan() async throws {
        let c = try cache(); let moved = root.appendingPathComponent("Moved")
        let service = CleanupService(home: home, trash: { try FileManager.default.moveItem(at: $0, to: moved) }, checkUsage: { _ in })
        do { _ = try await service.execute(confirmedPlanID: UUID()); XCTFail("Unknown plan executed") } catch {}
        XCTAssertTrue(FileManager.default.fileExists(atPath: c.path))
        let plan = try await service.prepare(paths: [c.path]); XCTAssertTrue(FileManager.default.fileExists(atPath: c.path))
        let receipt = try await service.execute(confirmedPlanID: plan.id)
        XCTAssertEqual(receipt.moved, [c.path]); XCTAssertTrue(FileManager.default.fileExists(atPath: moved.path))
        do { _ = try await service.execute(confirmedPlanID: plan.id); XCTFail("Plan reused") } catch {}
    }
    func testNewSourceAfterConfirmationBlocksEntireBatch() async throws {
        let a = try cache("A"); let b = try cache("B"); let marker = root.appendingPathComponent("executed")
        let service = CleanupService(home: home, trash: { _ in try Data().write(to: marker) }, checkUsage: { _ in })
        let plan = try await service.prepare(paths: [a.path, b.path]); try file("Home/Library/Caches/B/new.swift")
        do { _ = try await service.execute(confirmedPlanID: plan.id); XCTFail("Source was not protected") } catch {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path)); XCTAssertTrue(FileManager.default.fileExists(atPath: a.path))
    }
    func testContentChangeAfterPreviewRequiresNewPlan() async throws {
        let c = try cache(); let service = CleanupService(home: home, trash: { _ in XCTFail("Should not move") }, checkUsage: { _ in })
        let plan = try await service.prepare(paths: [c.path]); try file("Home/Library/Caches/Example/cache.data", bytes: 16384)
        do { _ = try await service.execute(confirmedPlanID: plan.id); XCTFail("Changed content accepted") } catch {}
    }
    func testPreviewCannotCleanAncestorAndDescendantTogether() async throws {
        let c = try cache(); let service = CleanupService(home: home, checkUsage: { _ in })
        do { _ = try await service.prepare(paths: [c.path, c.appendingPathComponent("child").path]); XCTFail("Overlap allowed") } catch {}
    }
    func testIncrementalResultsArriveBeforeScanCompletes() throws {
        try file("Home/Afirst/cache.data"); try file("Home/Blast/cache.data")
        let token = ScanCancellation()
        let result = try DiskScanner.scan(root: home, cancellation: token) { update in
            if update.rootNodes.contains(where: { $0.name == "Afirst" }) { token.cancel() }
        }
        XCTAssertTrue(result.cancelled); XCTAssertEqual(result.files, 1)
    }
    func testSystemTrashPreservesRecoverableData() async throws {
        let c = try cache(); let marker = root.appendingPathComponent("trash-location.txt")
        let service = CleanupService(home: home, trash: { url in
            var resulting: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
            guard let path = resulting?.path else { throw CleanupError.invalidPlan }
            try Data(path.utf8).write(to: marker)
        }, checkUsage: { _ in })
        let plan = try await service.prepare(paths: [c.path]); let receipt = try await service.execute(confirmedPlanID: plan.id)
        XCTAssertTrue(receipt.failed.isEmpty)
        if FileManager.default.fileExists(atPath: marker.path) {
            let trashed = URL(fileURLWithPath: try String(contentsOf: marker, encoding: .utf8))
            XCTAssertEqual(try Data(contentsOf: trashed.appendingPathComponent("cache.data")).count, 8192)
            // Restore only the exact test-owned entry; production never empties Trash.
            try FileManager.default.moveItem(at: trashed, to: c)
        } else { XCTFail("System Trash did not return a recoverable test entry") }
    }
    func testComparisonIncludesRemovedAndNewDirectories() throws {
        let oldFile = try file("Home/Old/data", bytes: 8192)
        let before = try DiskScanner.scan(root: home)
        try FileManager.default.removeItem(at: oldFile.deletingLastPathComponent())
        try file("Home/New/data", bytes: 16384)
        let after = try DiskScanner.scan(root: home)
        let delta = ScanComparison.changes(current: after, previous: before)
        XCTAssertLessThan(try XCTUnwrap(delta.first { $0.0.name == "Old" }).1, 0)
        XCTAssertGreaterThan(try XCTUnwrap(delta.first { $0.0.name == "New" }).1, 0)
    }
    func testUpdateConfigurationRequiresHTTPSAndValidPublicKey() {
        let key = Data(repeating: 1, count: 32).base64EncodedString()
        XCTAssertTrue(UpdateConfiguration(feed: "https://aethernative.com/apps/aetherdisk/appcast.xml", publicKey: key).valid)
        for url in ["http://example.com/feed", "file:///tmp/feed", "https://user:pass@example.com/feed", "https://example.com/feed#fragment", ""] { XCTAssertFalse(UpdateConfiguration(feed: url, publicKey: key).valid) }
        XCTAssertFalse(UpdateConfiguration(feed: "https://example.com/feed", publicKey: "fake").valid)
    }
}
