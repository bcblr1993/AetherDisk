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

    func testExpandedDeveloperCachesAndProjectBuildMarkers() throws {
        let xcodeSim = try file("Home/Library/Developer/CoreSimulator/Caches/sim.data").deletingLastPathComponent()
        let goBuild = try file("Home/.cache/go-build/blob.data").deletingLastPathComponent()
        let uvCache = try file("Home/.cache/uv/wheel.cache").deletingLastPathComponent()
        let vscodeCache = try file("Home/Library/Application Support/Code/CachedData/v8.bin").deletingLastPathComponent()
        XCTAssertEqual(RuleCatalog.category(for: xcodeSim, home: home), .xcode)
        XCTAssertEqual(RuleCatalog.category(for: goBuild, home: home), .compiler)
        XCTAssertEqual(RuleCatalog.category(for: uvCache, home: home), .compiler)
        XCTAssertEqual(RuleCatalog.category(for: vscodeCache, home: home), .compiler)
        XCTAssertNoThrow(try SafetyInspector.inspect(goBuild, home: home))

        let mavenTarget = try file("Home/maven-app/target/classes.bin").deletingLastPathComponent()
        let cmakeBuild = try file("Home/cpp-app/build/obj.bin").deletingLastPathComponent()
        let ruffCache = try file("Home/py-app/.ruff_cache/content.bin").deletingLastPathComponent()
        XCTAssertNil(RuleCatalog.category(for: mavenTarget, home: home))
        XCTAssertNil(RuleCatalog.category(for: cmakeBuild, home: home))
        XCTAssertNil(RuleCatalog.category(for: ruffCache, home: home))
        try file("Home/maven-app/pom.xml")
        try file("Home/cpp-app/CMakeLists.txt")
        try file("Home/py-app/pyproject.toml")
        XCTAssertEqual(RuleCatalog.category(for: mavenTarget, home: home), .build)
        XCTAssertEqual(RuleCatalog.category(for: cmakeBuild, home: home), .build)
        XCTAssertEqual(RuleCatalog.category(for: ruffCache, home: home), .build)
    }

    func testCacheCandidateSurvivesDirectoryDisplayBudget() throws {
        for i in 0..<20_010 { try file("Home/Downloads/\(i).data", bytes: 0) }
        let lateCache = try file("Home/Library/Caches/LateVisitedApp/cache.data", bytes: 8192).deletingLastPathComponent()
        let result = try DiskScanner.scan(root: home, home: home)
        XCTAssertTrue(result.recommendations.contains { $0.id == lateCache.path })
    }

    func testModernFrontendAndPackageManagerCacheRules() throws {
        let iosSupport = try file("Home/Library/Developer/Xcode/iOS DeviceSupport/17.0/symbols.data").deletingLastPathComponent().deletingLastPathComponent()
        let cargoCache = try file("Home/.cargo/registry/cache/crate.data").deletingLastPathComponent()
        let cargoBin = try file("Home/.cargo/bin/cargo-tool").deletingLastPathComponent()
        let pnpmStore = try file("Home/.pnpm-store/v3/blob.data").deletingLastPathComponent().deletingLastPathComponent()
        let bunCache = try file("Home/.bun/install/cache/pkg.data").deletingLastPathComponent()
        XCTAssertEqual(RuleCatalog.category(for: iosSupport, home: home), .xcode)
        XCTAssertEqual(RuleCatalog.category(for: cargoCache, home: home), .compiler)
        XCTAssertNil(RuleCatalog.category(for: cargoBin, home: home))
        XCTAssertEqual(RuleCatalog.category(for: pnpmStore, home: home), .compiler)
        XCTAssertEqual(RuleCatalog.category(for: bunCache, home: home), .compiler)
        XCTAssertNoThrow(try SafetyInspector.inspect(cargoCache, home: home))

        let nextCache = try file("Home/web-app/.next/cache/webpack.bin").deletingLastPathComponent()
        let turboCache = try file("Home/web-app/.turbo/turbo.bin").deletingLastPathComponent()
        let pytestCache = try file("Home/py-service/.pytest_cache/v.bin").deletingLastPathComponent()
        XCTAssertNil(RuleCatalog.category(for: nextCache, home: home))
        XCTAssertNil(RuleCatalog.category(for: turboCache, home: home))
        XCTAssertNil(RuleCatalog.category(for: pytestCache, home: home))

        try file("Home/web-app/package.json")
        try file("Home/py-service/setup.py")
        XCTAssertEqual(RuleCatalog.category(for: nextCache, home: home), .build)
        XCTAssertEqual(RuleCatalog.category(for: turboCache, home: home), .build)
        XCTAssertEqual(RuleCatalog.category(for: pytestCache, home: home), .build)
    }

    func testBulkDirectoryAttributeReaderMatchesStatAndPreservesHardlinkAndSymlinkRules() throws {
        let dirURL = home.appendingPathComponent("BulkTest")
        let reg = try file("Home/BulkTest/regular.bin", bytes: 12288)
        try FileManager.default.linkItem(at: reg, to: dirURL.appendingPathComponent("hardlink.bin"))
        try FileManager.default.createSymbolicLink(atPath: dirURL.appendingPathComponent("sym").path, withDestinationPath: "/Applications")
        let handle = try DirectoryHandle(path: dirURL.path)
        defer { close(handle.descriptor) }
        let bulk = try handle.bulkEntries()
        XCTAssertEqual(Set(bulk.map(\.name)), ["regular.bin", "hardlink.bin", "sym"])
        let regEntry = try XCTUnwrap(bulk.first { $0.name == "regular.bin" })
        var st = stat()
        XCTAssertEqual(lstat(reg.path, &st), 0)
        XCTAssertEqual(regEntry.ino, st.st_ino)
        XCTAssertEqual(regEntry.allocated, Int64(st.st_blocks) * 512)
        XCTAssertEqual(regEntry.logical, Int64(st.st_size))
        XCTAssertEqual(regEntry.nlink, UInt32(st.st_nlink))
        let symEntry = try XCTUnwrap(bulk.first { $0.name == "sym" })
        XCTAssertTrue(symEntry.isSymlink)
    }

    func testExpandedPlatformDeviceSupportAndEcosystemCacheRules() throws {
        let macSupport = try file("Home/Library/Developer/Xcode/macOS DeviceSupport/15.0/sym.data").deletingLastPathComponent().deletingLastPathComponent()
        let tvSupport = try file("Home/Library/Developer/Xcode/tvOS DeviceSupport/18.0/sym.data").deletingLastPathComponent().deletingLastPathComponent()
        let visionSupport = try file("Home/Library/Developer/Xcode/visionOS DeviceSupport/2.0/sym.data").deletingLastPathComponent().deletingLastPathComponent()
        XCTAssertEqual(RuleCatalog.category(for: macSupport, home: home), .xcode)
        XCTAssertEqual(RuleCatalog.category(for: tvSupport, home: home), .xcode)
        XCTAssertEqual(RuleCatalog.category(for: visionSupport, home: home), .xcode)

        let podsCache = try file("Home/Library/Caches/CocoaPods/Pods/spec.data").deletingLastPathComponent().deletingLastPathComponent()
        let pubCache = try file("Home/.pub-cache/hosted/pkg.data").deletingLastPathComponent().deletingLastPathComponent()
        let sbtBoot = try file("Home/.sbt/boot/scala.data").deletingLastPathComponent()
        let ivyCache = try file("Home/.ivy2/cache/org.data").deletingLastPathComponent()
        let hfHub = try file("Home/.cache/huggingface/hub/model.data").deletingLastPathComponent()
        let playwright = try file("Home/.cache/playwright/webkit.data").deletingLastPathComponent()
        XCTAssertEqual(RuleCatalog.category(for: podsCache, home: home), .compiler)
        XCTAssertEqual(RuleCatalog.category(for: pubCache, home: home), .compiler)
        XCTAssertEqual(RuleCatalog.category(for: sbtBoot, home: home), .compiler)
        XCTAssertEqual(RuleCatalog.category(for: ivyCache, home: home), .compiler)
        XCTAssertEqual(RuleCatalog.category(for: hfHub, home: home), .compiler)
        XCTAssertEqual(RuleCatalog.category(for: playwright, home: home), .compiler)

        let ngCache = try file("Home/ng-app/.angular/cache/chunk.bin").deletingLastPathComponent()
        let astroCache = try file("Home/astro-app/.astro/content.bin").deletingLastPathComponent()
        let viteCache = try file("Home/vite-app/.vite/deps.bin").deletingLastPathComponent()
        let toxCache = try file("Home/py-tox/.tox/env.bin").deletingLastPathComponent()
        let kotlinCache = try file("Home/kt-app/.kotlin/sessions.bin").deletingLastPathComponent()
        XCTAssertNil(RuleCatalog.category(for: ngCache, home: home))
        XCTAssertNil(RuleCatalog.category(for: astroCache, home: home))
        XCTAssertNil(RuleCatalog.category(for: viteCache, home: home))
        XCTAssertNil(RuleCatalog.category(for: toxCache, home: home))
        XCTAssertNil(RuleCatalog.category(for: kotlinCache, home: home))

        try file("Home/ng-app/angular.json")
        try file("Home/astro-app/package.json")
        try file("Home/vite-app/package.json")
        try file("Home/py-tox/tox.ini")
        try file("Home/kt-app/build.gradle.kts")
        XCTAssertEqual(RuleCatalog.category(for: ngCache, home: home), .build)
        XCTAssertEqual(RuleCatalog.category(for: astroCache, home: home), .build)
        XCTAssertEqual(RuleCatalog.category(for: viteCache, home: home), .build)
        XCTAssertEqual(RuleCatalog.category(for: toxCache, home: home), .build)
        XCTAssertEqual(RuleCatalog.category(for: kotlinCache, home: home), .build)

        let markers = RuleCatalog.projectMarkers(in: ["README.md", "go.mod", "composer.json", "mix.exs", "angular.json"])
        XCTAssertEqual(markers, ["angular.json", "composer.json", "go.mod", "mix.exs"])
        XCTAssertTrue(RuleCatalog.protection(name: "go.mod", directory: false).contains(.source))
        XCTAssertTrue(RuleCatalog.protection(name: "angular.json", directory: false).contains(.source))
        XCTAssertTrue(RuleCatalog.protection(name: "tox.ini", directory: false).contains(.source))
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
