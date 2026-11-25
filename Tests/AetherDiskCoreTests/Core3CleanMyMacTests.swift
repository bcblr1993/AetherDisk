import XCTest
import Foundation
import Darwin
@testable import AetherDiskCore

final class Core3CleanMyMacTests: XCTestCase, @unchecked Sendable {
    var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("AetherDiskCore3-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root {
            try? FileManager.default.removeItem(at: root)
        }
    }

    private var home: URL { root.appendingPathComponent("Home") }

    @discardableResult
    private func file(_ relPath: String, bytes: Int = 4096, byte: UInt8 = 5) throws -> URL {
        let url = root.appendingPathComponent(relPath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: byte, count: bytes).write(to: url)
        return url
    }

    // MARK: - 1. Space Lens BubbleLensLayout

    func testBubbleLensLayoutBoundsNonOverlapMonotonicRadiusAndHitTest() throws {
        XCTAssertTrue(BubbleLensLayout.pack(nodes: [], scopeTitle: "Empty", scopePath: "/empty").isEmpty)

        var nodes: [DiskNode] = [
            DiskNode(path: "/lens/Movies", kind: .directory, allocated: 800_000, protection: [.user]),
            DiskNode(path: "/lens/Xcode", kind: .directory, allocated: 500_000),
            DiskNode(path: "/lens/Downloads", kind: .directory, allocated: 320_000),
            DiskNode(path: "/lens/Documents", kind: .directory, allocated: 150_000, protection: [.document]),
            DiskNode(path: "/lens/Archive.dmg", kind: .file, allocated: 80_000, protection: [.installer])
        ]
        for i in 1...6 {
            nodes.append(DiskNode(path: "/lens/tiny-\(i).bin", kind: .file, allocated: 1_000))
        }

        let bubbles = BubbleLensLayout.pack(
            nodes: nodes,
            scopeTitle: "lens",
            scopePath: "/lens",
            scopeAllocated: 1_900_000,
            maxBubbles: 18,
            minFraction: 0.008
        )
        XCTAssertEqual(bubbles.count, 7) // 1 hub + 5 primary + 1 tail group (6 tiny items)

        let hub = try XCTUnwrap(bubbles.first)
        XCTAssertTrue(hub.isHub)
        XCTAssertEqual(hub.cx, 0.5, accuracy: 1e-9)
        XCTAssertEqual(hub.cy, 0.5, accuracy: 1e-9)
        XCTAssertEqual(hub.allocated, 1_900_000)

        let children = Array(bubbles.dropFirst())
        let tail = try XCTUnwrap(children.first(where: \.isTailGroup))
        XCTAssertEqual(tail.groupedCount, 6)
        XCTAssertEqual(tail.allocated, 6_000)

        let movies = try XCTUnwrap(children.first { $0.title == "Movies" })
        let xcode = try XCTUnwrap(children.first { $0.title == "Xcode" })
        let downloads = try XCTUnwrap(children.first { $0.title == "Downloads" })
        XCTAssertTrue(movies.isProtected)
        XCTAssertGreaterThan(movies.radius, xcode.radius)
        XCTAssertGreaterThan(xcode.radius, downloads.radius)

        // Bounds check: every bubble strictly inside [0, 1] x [0, 1]
        for b in bubbles {
            XCTAssertGreaterThan(b.radius, 0.0)
            XCTAssertGreaterThanOrEqual(b.cx - b.radius, -1e-9, "Left bound violated: \(b.id)")
            XCTAssertLessThanOrEqual(b.cx + b.radius, 1.0 + 1e-9, "Right bound violated: \(b.id)")
            XCTAssertGreaterThanOrEqual(b.cy - b.radius, -1e-9, "Top bound violated: \(b.id)")
            XCTAssertLessThanOrEqual(b.cy + b.radius, 1.0 + 1e-9, "Bottom bound violated: \(b.id)")
        }

        // Pairwise non-overlap across all bubbles (including hub)
        for i in 0..<bubbles.count {
            for j in (i + 1)..<bubbles.count {
                let a = bubbles[i], b = bubbles[j]
                let dist = hypot(a.cx - b.cx, a.cy - b.cy)
                XCTAssertGreaterThanOrEqual(dist + 1e-7, a.radius + b.radius, "Overlap between \(a.id) and \(b.id)")
            }
        }

        // Hit-test verification
        XCTAssertNil(BubbleLensLayout.hitTest(bubbles: bubbles, nx: -0.05, ny: 0.5))
        XCTAssertNil(BubbleLensLayout.hitTest(bubbles: bubbles, nx: 1.05, ny: 0.5))
        for b in bubbles {
            let hit = BubbleLensLayout.hitTest(bubbles: bubbles, nx: b.cx, ny: b.cy)
            XCTAssertEqual(hit?.id, b.id)
        }

        // Single tiny item must not merge into "其余 1 项"
        let singleTiny = BubbleLensLayout.pack(
            nodes: [
                DiskNode(path: "/lens/Big", kind: .directory, allocated: 999_000),
                DiskNode(path: "/lens/SoloTiny", kind: .file, allocated: 500)
            ],
            scopeTitle: "lens",
            scopePath: "/lens"
        )
        XCTAssertEqual(singleTiny.count, 3) // hub + 2 items
        XCTAssertTrue(singleTiny.allSatisfy { !$0.isTailGroup })
    }

    // MARK: - 2. Expanded System Junk Rules (Logs, Saved State, Self-Exclusion)

    func testLogsSavedStateAndSelfExclusionSafetyRules() throws {
        let appLog = try file("Home/Library/Logs/DemoWorker/worker.log", bytes: 8192).deletingLastPathComponent()
        let savedState = try file("Home/Library/Saved Application State/com.vendor.demo.savedState/windows.plist", bytes: 4096).deletingLastPathComponent()
        let nonSavedState = try file("Home/Library/Saved Application State/PlainFolder/state.dat", bytes: 4096).deletingLastPathComponent()
        let ownCache = try file("Home/Library/Caches/com.aethernative.AetherDisk/cache.db", bytes: 4096).deletingLastPathComponent()
        let ownState = try file("Home/Library/Saved Application State/com.aethernative.AetherDisk.savedState/data.data", bytes: 4096).deletingLastPathComponent()
        let denoCache = try file("Home/.cache/deno/dep.bin", bytes: 4096).deletingLastPathComponent()
        let windsurfCache = try file("Home/Library/Application Support/Windsurf/CachedData/v8.bin", bytes: 4096).deletingLastPathComponent()

        XCTAssertEqual(RuleCatalog.category(for: appLog, home: home), .logs)
        XCTAssertEqual(RuleCatalog.category(for: savedState, home: home), .savedState)
        XCTAssertNil(RuleCatalog.category(for: nonSavedState, home: home))
        XCTAssertNil(RuleCatalog.category(for: ownCache, home: home))
        XCTAssertNil(RuleCatalog.category(for: ownState, home: home))
        XCTAssertEqual(RuleCatalog.category(for: denoCache, home: home), .compiler)
        XCTAssertEqual(RuleCatalog.category(for: windsurfCache, home: home), .compiler)

        // Clean log and savedState pass SafetyInspector
        XCTAssertNoThrow(try SafetyInspector.inspect(appLog, home: home))
        XCTAssertNoThrow(try SafetyInspector.inspect(savedState, home: home))

        // Adding a document/report inside Logs immediately blocks SafetyInspector & Scanner recommendation
        try file("Home/Library/Logs/DemoWorker/audit-summary.pdf", bytes: 4096)
        XCTAssertThrowsError(try SafetyInspector.inspect(appLog, home: home))
        let scan = try DiskScanner.scan(root: home, home: home)
        let logRec = try XCTUnwrap(scan.recommendations.first { $0.id == appLog.path })
        XCTAssertTrue(logRec.blocked)
        XCTAssertTrue(logRec.node.protection.contains(.document))
    }

    // MARK: - 3. ApplicationInspector & Leftovers Correlation (100% Metadata Read-Only)

    func testApplicationInspectorCorrelatesAppsCachesOrphansAndIgnoresSymlinks() throws {
        let appsRoot = root.appendingPathComponent("Apps")
        try FileManager.default.createDirectory(at: appsRoot, withIntermediateDirectories: true)

        // 1) Standalone app with hardlinked resource inside
        let binA = try file("Apps/NebulaStudio.app/Contents/MacOS/NebulaStudio", bytes: 32_768)
        let resA = try file("Apps/NebulaStudio.app/Contents/Resources/assets.car", bytes: 16_384)
        try FileManager.default.linkItem(at: resA, to: appsRoot.appendingPathComponent("NebulaStudio.app/Contents/Resources/assets-link.car"))
        _ = binA

        // 2) App Store app with _MASReceipt/receipt
        try file("Apps/PixelCraft.app/Contents/MacOS/PixelCraft", bytes: 16_384)
        try file("Apps/PixelCraft.app/Contents/_MASReceipt/receipt", bytes: 4096)

        // 3) Symlinked .app pointing outside -> must NOT be traversed or listed
        let outsideApp = try file("OutsideApps/Secret.app/Contents/MacOS/Secret", bytes: 65_536).deletingLastPathComponent().deletingLastPathComponent()
        try FileManager.default.createSymbolicLink(at: appsRoot.appendingPathComponent("LinkedSecret.app"), withDestinationURL: outsideApp)

        // Associated user caches & logs
        let nebulaCache = try file("Home/Library/Caches/com.nebula.nebulastudio/blob.cache", bytes: 12_288).deletingLastPathComponent()
        let nebulaProtectedLog = try file("Home/Library/Logs/NebulaStudio/crash.md", bytes: 4096).deletingLastPathComponent()

        // Orphaned cache from uninstalled third-party app
        let orphanState = try file("Home/Library/Saved Application State/io.legacycorp.vanishedapp.savedState/win.data", bytes: 8192).deletingLastPathComponent()

        // Apple system cache -> must NOT be reported as uninstalled orphan
        _ = try file("Home/Library/Caches/com.apple.Safari/fsCachedData", bytes: 8192)

        let report = ApplicationInspector.inspect(
            applicationRoots: [appsRoot],
            home: home,
            protectedPaths: []
        )

        XCTAssertEqual(report.apps.count, 2)
        XCTAssertFalse(report.apps.contains { $0.name.contains("Secret") })

        let nebula = try XCTUnwrap(report.apps.first { $0.name == "NebulaStudio" })
        XCTAssertEqual(nebula.source, .standalone)
        XCTAssertEqual(nebula.associatedItems.count, 2)
        XCTAssertEqual(nebula.eligibleCachePaths, [nebulaCache.path])
        XCTAssertTrue(nebula.associatedItems.contains { $0.path == nebulaProtectedLog.path && $0.blocked })

        // Verify hardlink deduplication matches du -xsk on NebulaStudio.app
        let nebulaURL = appsRoot.appendingPathComponent("NebulaStudio.app")
        let du = try SafetyInspector.runProcess("/usr/bin/du", ["-xsk", nebulaURL.path], allowFailure: false)
        let duKiB = try XCTUnwrap(Int64(du.output.split(whereSeparator: \.isWhitespace)[0]))
        XCTAssertEqual((nebula.bundleAllocated + 1023) / 1024, duKiB)

        let pixel = try XCTUnwrap(report.apps.first { $0.name == "PixelCraft" })
        XCTAssertEqual(pixel.source, .appStore)

        // Verify orphan detection
        XCTAssertEqual(report.orphanedData.map(\.path), [orphanState.path])
        XCTAssertFalse(report.orphanedData[0].blocked)

        // Verify ApplicationQuery filters & sorting
        let withCaches = ApplicationQuery.filterApps(report.apps, mode: .withCaches, sort: .cacheSize, query: "")
        XCTAssertEqual(withCaches.map(\.name), ["NebulaStudio"])
        let searched = ApplicationQuery.filterApps(report.apps, mode: .all, sort: .bundleSize, query: "pixel")
        XCTAssertEqual(searched.map(\.name), ["PixelCraft"])
    }

    // MARK: - 4. SystemHealthSampler & SmartCareEngine

    func testSystemHealthSamplerAndSmartCareEvaluation() async throws {
        let sampler = SystemHealthSampler()
        let first = sampler.sample()
        try await Task.sleep(for: .milliseconds(180))
        let second = sampler.sample()

        XCTAssertGreaterThan(second.memory.totalBytes, 0)
        XCTAssertGreaterThanOrEqual(second.memory.usedBytes, 0)
        XCTAssertLessThanOrEqual(second.memory.usedBytes, second.memory.totalBytes)
        XCTAssertGreaterThanOrEqual(second.cpu.coreCount, 1)
        XCTAssertGreaterThanOrEqual(second.cpu.usageFraction, 0.0)
        XCTAssertLessThanOrEqual(second.cpu.usageFraction, 1.0)
        XCTAssertFalse(second.cpu.thermalLabel.isEmpty)
        XCTAssertGreaterThan(second.cpu.uptimeSeconds, 0)
        XCTAssertGreaterThanOrEqual(second.network.downloadBytesPerSec, 0)
        XCTAssertGreaterThanOrEqual(second.network.uploadBytesPerSec, 0)
        XCTAssertFalse(first.hostModelLabel.isEmpty)

        // SmartCareEngine on low-free-space internal volume vs read-only external volume
        let rec = Recommendation(
            node: DiskNode(path: "/Users/demo/Library/Caches/DemoApp", allocated: 64 * 1024 * 1024),
            category: .browser
        )
        let lowVol = VolumeSpace(total: 100 * 1024 * 1024 * 1024, free: 5 * 1024 * 1024 * 1024)
        let internalSummary = SmartCareEngine.evaluate(
            scan: nil,
            recommendations: [rec],
            volume: lowVol,
            health: second,
            appsReport: nil,
            trash: TrashSummary(itemCount: 2, allocated: 4096, readable: true),
            snapshots: APFSSnapshotReport(volumePath: "/", snapshots: [APFSSnapshotInfo(name: "snap1", dateLabel: "2026-11-24")], note: "ok"),
            fullDiskAccessGranted: false,
            isExternalVolume: false
        )
        XCTAssertEqual(internalSummary.pillars.count, 5)
        XCTAssertTrue(internalSummary.insights.contains { $0.id == "low-disk-space" })
        XCTAssertTrue(internalSummary.insights.contains { $0.id == "cleanable-caches" })
        XCTAssertTrue(internalSummary.insights.contains { $0.id == "apfs-snapshots" })

        let externalSummary = SmartCareEngine.evaluate(
            scan: nil,
            recommendations: [rec],
            volume: lowVol,
            health: second,
            appsReport: nil,
            trash: nil,
            snapshots: nil,
            fullDiskAccessGranted: true,
            isExternalVolume: true
        )
        let cleanupPillar = try XCTUnwrap(externalSummary.pillars.first { $0.id == "cleanup" })
        XCTAssertEqual(cleanupPillar.headlineValue, "仅分析")
        XCTAssertFalse(externalSummary.insights.contains { $0.id == "cleanable-caches" })
    }

    // MARK: - 5. CLI 3.0 Flags

    func testCLI3AppsAndHealthFlags() throws {
        let appsOnly = try ScanCLIOptions.parse(["--apps"])
        XCTAssertTrue(appsOnly.showApps)
        XCTAssertEqual(appsOnly.rootPath, "")

        let healthOnly = try ScanCLIOptions.parse(["--health"])
        XCTAssertTrue(healthOnly.showHealth)
        XCTAssertEqual(healthOnly.rootPath, "")

        let combined = try ScanCLIOptions.parse(["/tmp", "--apps", "--health", "--volumes", "--profile", "eco"])
        XCTAssertEqual(combined.rootPath, "/tmp")
        XCTAssertTrue(combined.showApps)
        XCTAssertTrue(combined.showHealth)
        XCTAssertTrue(combined.showVolumes)
        XCTAssertEqual(combined.profile, .eco)
    }

    // MARK: - 6. Static Source-Code Safety Invariants Audit

    func testStaticSourceCodeSafetyInvariants() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let packageSwift = try String(contentsOf: repoRoot.appendingPathComponent("Package.swift"), encoding: .utf8)
        XCTAssertTrue(packageSwift.contains("https://github.com/sparkle-project/Sparkle"))
        XCTAssertTrue(packageSwift.contains("2.10.0"))
        let packageOccurrences = packageSwift.components(separatedBy: ".package(url:").count - 1
        XCTAssertEqual(packageOccurrences, 1, "Sparkle 2.10.0 must remain the sole external dependency")

        let sourcesDir = repoRoot.appendingPathComponent("Sources")
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: sourcesDir, includingPropertiesForKeys: nil))
        var swiftFiles: [URL] = []
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
            swiftFiles.append(fileURL)
        }
        XCTAssertGreaterThanOrEqual(swiftFiles.count, 18)

        for fileURL in swiftFiles {
            let code = try String(contentsOf: fileURL, encoding: .utf8)
            let name = fileURL.lastPathComponent

            // Never permanently delete files or snapshots or force-kill apps in production code
            XCTAssertFalse(code.contains(".removeItem("), "\(name) must never call FileManager.removeItem")
            XCTAssertFalse(code.contains("deletelocalsnapshots"), "\(name) must never delete APFS snapshots")
            XCTAssertFalse(code.contains(".forceTerminate("), "\(name) must never force-terminate user apps")
            XCTAssertFalse(code.contains("/usr/bin/purge"), "\(name) must never invoke purge")

            // Only Cleanup.swift may invoke trashItem
            if name != "Cleanup.swift" {
                XCTAssertFalse(code.contains(".trashItem("), "Only Cleanup.swift may move confirmed plans to Trash (found in \(name))")
            }

            // Scanners & metadata inspectors must never open regular files to read contents
            if ["Scanner.swift", "Applications.swift", "VolumeSystem.swift", "ProtectionAudit.swift"].contains(name) {
                XCTAssertFalse(code.contains("Data(contentsOf:"), "\(name) must not read file contents")
                XCTAssertFalse(code.contains("String(contentsOf:"), "\(name) must not read file contents")
                XCTAssertFalse(code.contains("FileHandle("), "\(name) must not open regular file handles")
            }
        }
    }

    // MARK: - 7. ProtectionInspector Read-Only Audit Tests

    func testProtectionInspectorAuditsLaunchItemsVaultsAndInstallersWithoutFollowingSymlinks() throws {
        let sysRoot = root.appendingPathComponent("FakeSystem")
        _ = try file("Home/Library/LaunchAgents/com.acme.syncagent.plist", bytes: 4096)
        _ = try file("FakeSystem/Library/LaunchAgents/com.apple.systemui.plist", bytes: 4096)
        _ = try file("FakeSystem/Library/LaunchDaemons/org.docker.vmnetd.plist", bytes: 4096)
        _ = try file("Home/.ssh/id_ed25519.pub", bytes: 512)
        _ = try file("Home/Downloads/Setup-1.0.dmg", bytes: 16_384)
        _ = try file("Home/Downloads/Notes.txt", bytes: 4096)

        // Symlinked plist and symlinked dmg must be ignored
        let outsidePlist = try file("Outside/com.evil.linked.plist", bytes: 4096)
        try FileManager.default.createSymbolicLink(
            at: home.appendingPathComponent("Library/LaunchAgents/com.evil.linked.plist"),
            withDestinationURL: outsidePlist
        )
        let outsideDMG = try file("Outside/Linked.dmg", bytes: 32_768)
        try FileManager.default.createSymbolicLink(
            at: home.appendingPathComponent("Downloads/Linked.dmg"),
            withDestinationURL: outsideDMG
        )

        let report = ProtectionInspector.inspect(
            home: home,
            systemRoot: sysRoot,
            customProtectedCount: 2,
            fullDiskAccessGranted: true
        )

        XCTAssertEqual(report.launchItems.count, 3)
        XCTAssertEqual(report.thirdPartyLaunchCount, 2)
        XCTAssertFalse(report.launchItems.contains { $0.name.contains("evil") })
        XCTAssertEqual(report.launchItems.first { $0.name == "com.acme.syncagent" }?.vendorLabel, "acme")
        XCTAssertEqual(report.launchItems.first { $0.name == "com.apple.systemui" }?.isAppleSystem, true)

        XCTAssertEqual(report.downloadInstallers.map(\.name), ["Setup-1.0.dmg"])
        XCTAssertTrue(report.vaultShields.first { $0.path == home.appendingPathComponent(".ssh").path }?.exists == true)
    }

    // MARK: - 8. CloudStorageInspector Read-Only Metadata & Dataless Accounting

    func testCloudStorageInspectorLocalDatalessHardlinksSymlinksAndMultiProvider() throws {
        // 1) Provider under ~/Library/CloudStorage with local resident files, sparse/dataless placeholder, hardlink, and symlink
        let googleRoot = home.appendingPathComponent("Library/CloudStorage/GoogleDrive-qa@example.com")
        try FileManager.default.createDirectory(at: googleRoot, withIntermediateDirectories: true)

        var expectedGoogleLocalAllocated: Int64 = 0
        var expectedGoogleLocalLogical: Int64 = 0
        for i in 1...14 {
            let url = try file("Home/Library/CloudStorage/GoogleDrive-qa@example.com/nested/file-\(String(format: "%02d", i)).bin", bytes: i * 4096)
            var st = stat()
            XCTAssertEqual(lstat(url.path, &st), 0)
            expectedGoogleLocalAllocated += Int64(st.st_blocks) * 512
            expectedGoogleLocalLogical += st.st_size
        }

        // Hardlink inside same provider must be deduplicated by InodeKey
        let targetForHardlink = googleRoot.appendingPathComponent("nested/file-14.bin")
        try FileManager.default.linkItem(at: targetForHardlink, to: googleRoot.appendingPathComponent("nested/file-14-hardlink.bin"))

        // Sparse / dataless file (allocated == 0 && logical > 0) must count toward cloudOnlyLogical, not local top files
        let datalessURL = googleRoot.appendingPathComponent("cloud-only-archive.bin")
        FileManager.default.createFile(atPath: datalessURL.path, contents: nil)
        let datalessHandle = try FileHandle(forWritingTo: datalessURL)
        try datalessHandle.truncate(atOffset: 64 * 1024 * 1024)
        try datalessHandle.close()

        // Symlinked file & symlinked directory inside provider pointing outside -> must be skipped
        let outsideFile = try file("OutsideCloud/secret-huge.bin", bytes: 128 * 1024)
        let outsideDir = outsideFile.deletingLastPathComponent()
        try FileManager.default.createSymbolicLink(at: googleRoot.appendingPathComponent("linked-secret.bin"), withDestinationURL: outsideFile)
        try FileManager.default.createSymbolicLink(at: googleRoot.appendingPathComponent("linked-dir"), withDestinationURL: outsideDir)

        // Symlinked provider directory under CloudStorage -> must be skipped
        try FileManager.default.createSymbolicLink(
            at: home.appendingPathComponent("Library/CloudStorage/Dropbox-Linked"),
            withDestinationURL: outsideDir
        )

        // 2) iCloud Drive under ~/Library/Mobile Documents/com~apple~CloudDocs (purely dataless placeholder)
        let icloudRoot = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        try FileManager.default.createDirectory(at: icloudRoot, withIntermediateDirectories: true)
        let icloudStub = icloudRoot.appendingPathComponent("Presentation.key")
        FileManager.default.createFile(atPath: icloudStub.path, contents: nil)
        let icloudHandle = try FileHandle(forWritingTo: icloudStub)
        try icloudHandle.truncate(atOffset: 16 * 1024 * 1024)
        try icloudHandle.close()

        // 3) Extra cloud root provider (e.g. QA fixture CloudStorage)
        let extraRoot = root.appendingPathComponent("QAWorkspace/CloudStorage")
        let oneDriveFile = try file("QAWorkspace/CloudStorage/OneDrive-Work/deck.pdf", bytes: 24_576)
        var oneDriveStat = stat()
        XCTAssertEqual(lstat(oneDriveFile.path, &oneDriveStat), 0)
        let oneDriveAllocated = Int64(oneDriveStat.st_blocks) * 512

        XCTAssertEqual(
            CloudStorageInspector.candidateExtraCloudRoot(for: root.appendingPathComponent("QAWorkspace")),
            extraRoot.standardizedFileURL
        )
        XCTAssertNil(CloudStorageInspector.candidateExtraCloudRoot(for: root.appendingPathComponent("NonExistent")))

        let report = CloudStorageInspector.inspect(home: home, extraCloudRoot: extraRoot)
        XCTAssertEqual(report.providers.count, 3)
        XCTAssertFalse(report.providers.contains { $0.name.contains("Dropbox") })

        // Sorted descending by allocated bytes: Google Drive -> OneDrive -> iCloud Drive
        XCTAssertEqual(report.providers.map(\.name), ["Google Drive", "OneDrive", "iCloud Drive"])

        let google = try XCTUnwrap(report.providers.first { $0.name == "Google Drive" })
        XCTAssertEqual(google.allocated, expectedGoogleLocalAllocated)
        XCTAssertEqual(google.cloudOnlyLogical, 64 * 1024 * 1024)
        XCTAssertEqual(google.logical, expectedGoogleLocalLogical + 64 * 1024 * 1024)
        XCTAssertEqual(google.localFileCount, 14) // 14 unique inodes (hardlink deduplicated, symlink skipped)
        XCTAssertEqual(google.datalessFileCount, 1)
        XCTAssertEqual(google.topLocalFiles.count, 12)
        XCTAssertEqual(google.topLocalFiles.first?.name, "file-14.bin")
        XCTAssertEqual(google.topLocalFiles.last?.name, "file-03.bin")
        XCTAssertTrue(google.topLocalFiles.allSatisfy { !$0.isDataless && $0.allocated > 0 })
        for idx in 1..<google.topLocalFiles.count {
            XCTAssertGreaterThanOrEqual(google.topLocalFiles[idx - 1].allocated, google.topLocalFiles[idx].allocated)
        }

        let oneDrive = try XCTUnwrap(report.providers.first { $0.name == "OneDrive" })
        XCTAssertEqual(oneDrive.allocated, oneDriveAllocated)
        XCTAssertEqual(oneDrive.localFileCount, 1)
        XCTAssertEqual(oneDrive.datalessFileCount, 0)

        let icloud = try XCTUnwrap(report.providers.first { $0.name == "iCloud Drive" })
        XCTAssertEqual(icloud.allocated, 0)
        XCTAssertEqual(icloud.cloudOnlyLogical, 16 * 1024 * 1024)
        XCTAssertEqual(icloud.localFileCount, 0)
        XCTAssertEqual(icloud.datalessFileCount, 1)
        XCTAssertTrue(icloud.topLocalFiles.isEmpty)

        XCTAssertEqual(report.totalAllocated, expectedGoogleLocalAllocated + oneDriveAllocated)
        XCTAssertEqual(report.totalCloudOnlyLogical, 80 * 1024 * 1024)
        XCTAssertEqual(report.totalLocalFiles, 15)
        XCTAssertEqual(report.totalDatalessFiles, 2)

        // Passing home/Library/CloudStorage again as extraCloudRoot must deduplicate provider paths
        let deduped = CloudStorageInspector.inspect(
            home: home,
            extraCloudRoot: home.appendingPathComponent("Library/CloudStorage")
        )
        XCTAssertEqual(deduped.providers.count, 2)

        // Cancelled token returns empty report immediately
        let cancelled = ScanCancellation()
        cancelled.cancel()
        let emptyCancelled = CloudStorageInspector.inspect(home: home, extraCloudRoot: extraRoot, cancellation: cancelled)
        XCTAssertTrue(emptyCancelled.providers.isEmpty)
        XCTAssertEqual(emptyCancelled.totalAllocated, 0)

        // Static check: CloudStorage.swift & CloudStorageView.swift must never read contents or trigger cloud downloads/evictions
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        for rel in ["Sources/AetherDiskCore/CloudStorage.swift", "Sources/AetherDisk/CloudStorageView.swift"] {
            let src = try String(contentsOf: repoRoot.appendingPathComponent(rel), encoding: .utf8)
            XCTAssertFalse(src.contains("Data(contentsOf:"), rel)
            XCTAssertFalse(src.contains("String(contentsOf:"), rel)
            XCTAssertFalse(src.contains("FileHandle("), rel)
            XCTAssertFalse(src.contains("startDownloadingUbiquitousItem"), rel)
            XCTAssertFalse(src.contains("evictUbiquitousItem"), rel)
            XCTAssertFalse(src.contains(".trashItem("), rel)
            XCTAssertFalse(src.contains(".removeItem("), rel)
        }
    }

    // MARK: - 9. RecommendationQuery.groupedByApplication

    func testRecommendationQueryGroupedByApplicationAndSorting() throws {
        XCTAssertTrue(RecommendationQuery.groupedByApplication([], home: home).isEmpty)

        let recs: [Recommendation] = [
            Recommendation(
                node: DiskNode(path: home.appendingPathComponent("Library/Developer/Xcode/DerivedData").path, kind: .directory, allocated: 600_000),
                category: .xcode
            ),
            Recommendation(
                node: DiskNode(path: home.appendingPathComponent("Library/Developer/CoreSimulator/Caches").path, kind: .directory, allocated: 250_000, protection: [.source]),
                category: .xcode
            ),
            Recommendation(
                node: DiskNode(path: home.appendingPathComponent("Library/Caches/Homebrew").path, kind: .directory, allocated: 420_000),
                category: .compiler
            ),
            Recommendation(
                node: DiskNode(path: home.appendingPathComponent("Library/Caches/com.apple.Safari").path, kind: .directory, allocated: 200_000),
                category: .browser
            ),
            Recommendation(
                node: DiskNode(path: home.appendingPathComponent("Library/Logs/Safari").path, kind: .directory, allocated: 50_000),
                category: .logs
            ),
            Recommendation(
                node: DiskNode(path: home.appendingPathComponent("Library/Saved Application State/com.apple.Safari.savedState").path, kind: .directory, allocated: 30_000),
                category: .savedState
            ),
            Recommendation(
                node: DiskNode(path: home.appendingPathComponent("Projects/Demo/.build").path, kind: .directory, allocated: 180_000),
                category: .build
            ),
            Recommendation(
                node: DiskNode(path: home.appendingPathComponent("Library/Caches/com.acme.pixel-forge").path, kind: .directory, allocated: 90_000),
                category: .browser
            ),
            Recommendation(
                node: DiskNode(path: home.appendingPathComponent("Library/Saved Application State/com.acme.pixel-forge.savedState").path, kind: .directory, allocated: 40_000, protection: [.document]),
                category: .savedState
            )
        ]

        let groups = RecommendationQuery.groupedByApplication(recs, home: home)
        XCTAssertEqual(groups.map(\.name), ["Xcode", "Homebrew", "Safari", "项目构建 (.build)", "Pixel Forge"])
        XCTAssertEqual(groups.map(\.allocated), [850_000, 420_000, 280_000, 180_000, 130_000])

        for idx in 1..<groups.count {
            XCTAssertGreaterThanOrEqual(groups[idx - 1].allocated, groups[idx].allocated)
        }

        let xcode = try XCTUnwrap(groups.first { $0.name == "Xcode" })
        XCTAssertEqual(xcode.items.count, 2)
        XCTAssertEqual(xcode.eligibleCount, 1)
        XCTAssertEqual(xcode.blockedCount, 1)
        XCTAssertEqual(xcode.items.map(\.node.allocated), [600_000, 250_000])

        let safari = try XCTUnwrap(groups.first { $0.name == "Safari" })
        XCTAssertEqual(safari.items.count, 3)
        XCTAssertEqual(safari.eligibleCount, 3)
        XCTAssertEqual(safari.blockedCount, 0)
        XCTAssertEqual(safari.items.map(\.node.allocated), [200_000, 50_000, 30_000])

        let pixel = try XCTUnwrap(groups.first { $0.name == "Pixel Forge" })
        XCTAssertEqual(pixel.eligibleCount, 1)
        XCTAssertEqual(pixel.blockedCount, 1)
    }

    // MARK: - 10. Expanded Compiler Cache Rules & Document/Source Protection

    func testNewCompilerCacheRulesAndDocumentSourceProtection() throws {
        let relPaths = [
            "Library/Caches/Homebrew",
            ".cache/zig",
            ".cache/sccache",
            ".cache/ccache",
            ".cache/huggingface/transformers",
            ".cache/JetBrains",
            "Library/Caches/JetBrains"
        ]

        var dirs: [String: URL] = [:]
        for rel in relPaths {
            let dir = try file("Home/\(rel)/cache.data", bytes: 4096).deletingLastPathComponent()
            dirs[rel] = dir
            XCTAssertEqual(RuleCatalog.category(for: dir, home: home), .compiler, rel)
        }

        // Clean cache directories pass SafetyInspector
        XCTAssertNoThrow(try SafetyInspector.inspect(try XCTUnwrap(dirs["Library/Caches/Homebrew"]), home: home))
        XCTAssertNoThrow(try SafetyInspector.inspect(try XCTUnwrap(dirs[".cache/ccache"]), home: home))
        XCTAssertNoThrow(try SafetyInspector.inspect(try XCTUnwrap(dirs[".cache/huggingface/transformers"]), home: home))

        // Document inside zig cache & source file inside JetBrains / sccache caches must block cleanup
        let zigDir = try XCTUnwrap(dirs[".cache/zig"])
        let sccacheDir = try XCTUnwrap(dirs[".cache/sccache"])
        let jetbrainsDir = try XCTUnwrap(dirs["Library/Caches/JetBrains"])

        try file("Home/.cache/zig/design-notes.pdf", bytes: 4096)
        try file("Home/.cache/sccache/helper.swift", bytes: 4096)
        try file("Home/Library/Caches/JetBrains/plugin.kt", bytes: 4096)

        XCTAssertThrowsError(try SafetyInspector.inspect(zigDir, home: home))
        XCTAssertThrowsError(try SafetyInspector.inspect(sccacheDir, home: home))
        XCTAssertThrowsError(try SafetyInspector.inspect(jetbrainsDir, home: home))

        let scan = try DiskScanner.scan(root: home, home: home)
        let zigRec = try XCTUnwrap(scan.recommendations.first { $0.id == zigDir.path })
        XCTAssertTrue(zigRec.blocked)
        XCTAssertTrue(zigRec.node.protection.contains(.document))

        let sccacheRec = try XCTUnwrap(scan.recommendations.first { $0.id == sccacheDir.path })
        XCTAssertTrue(sccacheRec.blocked)
        XCTAssertTrue(sccacheRec.node.protection.contains(.source))

        let jbRec = try XCTUnwrap(scan.recommendations.first { $0.id == jetbrainsDir.path })
        XCTAssertTrue(jbRec.blocked)
        XCTAssertTrue(jbRec.node.protection.contains(.source))

        let brewDir = try XCTUnwrap(dirs["Library/Caches/Homebrew"])
        let brewRec = try XCTUnwrap(scan.recommendations.first { $0.id == brewDir.path })
        XCTAssertFalse(brewRec.blocked)
    }

    func testCLI3CloudFlag() throws {
        let cloudOnly = try ScanCLIOptions.parse(["--cloud"])
        XCTAssertTrue(cloudOnly.showCloud)
        XCTAssertEqual(cloudOnly.rootPath, "")

        let combined = try ScanCLIOptions.parse(["/tmp", "--cloud", "--apps", "--health"])
        XCTAssertEqual(combined.rootPath, "/tmp")
        XCTAssertTrue(combined.showCloud)
        XCTAssertTrue(combined.showApps)
        XCTAssertTrue(combined.showHealth)
    }

    // MARK: - 11. Phase 3 Clutter: accessedAt Capture, TimeAxis Filtering, ClutterSummary & Duplicate Comparison

    private func setTimestamps(_ url: URL, accessedAt: Int64, modifiedAt: Int64) throws {
        var times = [
            timespec(tv_sec: Int(accessedAt), tv_nsec: 0),
            timespec(tv_sec: Int(modifiedAt), tv_nsec: 0)
        ]
        let rc = utimensat(AT_FDCWD, url.path, &times, AT_SYMLINK_NOFOLLOW)
        XCTAssertEqual(rc, 0, "utimensat failed for \(url.path) with errno=\(errno)")
    }

    func testDiskScannerCapturesDistinctAccessedAtAggregatesDirectoriesAndDecodesLegacyJSON() throws {
        let deepFile = try file("Home/Archive/Sub/deep.bin", bytes: 2 * 1024 * 1024)
        let directFile = try file("Home/Direct.bin", bytes: 1_536 * 1024)
        let subDir = deepFile.deletingLastPathComponent()
        let archiveDir = subDir.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)

        let dirBaseTime: Int64 = 1_600_000_000
        let deepModified: Int64 = 1_650_000_000
        let deepAccessed: Int64 = 1_725_000_000
        let directAccessed: Int64 = 1_640_000_000
        let directModified: Int64 = 1_715_000_000

        try setTimestamps(deepFile, accessedAt: deepAccessed, modifiedAt: deepModified)
        try setTimestamps(directFile, accessedAt: directAccessed, modifiedAt: directModified)
        try setTimestamps(subDir, accessedAt: dirBaseTime, modifiedAt: dirBaseTime)
        try setTimestamps(archiveDir, accessedAt: dirBaseTime, modifiedAt: dirBaseTime)
        try setTimestamps(home, accessedAt: dirBaseTime, modifiedAt: dirBaseTime)

        let scan = try DiskScanner.scan(root: home, home: home)

        let deepNode = try XCTUnwrap(scan.nodes.first { $0.path == deepFile.path })
        XCTAssertEqual(deepNode.modifiedAt, deepModified)
        XCTAssertEqual(deepNode.accessedAt, deepAccessed)
        XCTAssertNotEqual(deepNode.accessedAt, deepNode.modifiedAt)

        let largeDeep = try XCTUnwrap(scan.analysis?.largeFiles.first { $0.path == deepFile.path })
        XCTAssertEqual(largeDeep.modifiedAt, deepModified)
        XCTAssertEqual(largeDeep.accessedAt, deepAccessed)

        let directNode = try XCTUnwrap(scan.nodes.first { $0.path == directFile.path })
        XCTAssertEqual(directNode.modifiedAt, directModified)
        XCTAssertEqual(directNode.accessedAt, directAccessed)

        let subNode = try XCTUnwrap(scan.nodes.first { $0.path == subDir.path })
        XCTAssertEqual(subNode.accessedAt, deepAccessed)
        XCTAssertEqual(subNode.modifiedAt, deepModified)

        let archiveNode = try XCTUnwrap(scan.nodes.first { $0.path == archiveDir.path })
        XCTAssertEqual(archiveNode.accessedAt, deepAccessed)
        XCTAssertEqual(archiveNode.modifiedAt, deepModified)

        let rootNode = try XCTUnwrap(scan.nodes.first { $0.path == home.path })
        XCTAssertEqual(rootNode.accessedAt, deepAccessed)
        XCTAssertEqual(rootNode.modifiedAt, directModified)

        // Legacy DiskNode JSON lacking "accessedAt" must decode cleanly with accessedAt == nil
        let encoded = try JSONEncoder().encode(deepNode)
        var jsonObject = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        jsonObject.removeValue(forKey: "accessedAt")
        let legacyData = try JSONSerialization.data(withJSONObject: jsonObject)
        let decodedLegacy = try JSONDecoder().decode(DiskNode.self, from: legacyData)
        XCTAssertNil(decodedLegacy.accessedAt)
        XCTAssertEqual(decodedLegacy.modifiedAt, deepModified)
        XCTAssertEqual(decodedLegacy.path, deepNode.path)
        XCTAssertEqual(decodedLegacy.allocated, deepNode.allocated)

        let minimalLegacyJSON = """
        {"path":"/legacy/archive.dmg","kind":"file","allocated":8192,"logical":8192,"fileCount":1,"restricted":false,"protection":[],"modifiedAt":1700000000}
        """
        let decodedMinimal = try JSONDecoder().decode(DiskNode.self, from: Data(minimalLegacyJSON.utf8))
        XCTAssertNil(decodedMinimal.accessedAt)
        XCTAssertEqual(decodedMinimal.modifiedAt, 1_700_000_000)
        XCTAssertEqual(decodedMinimal.path, "/legacy/archive.dmg")
    }

    func testLargeFileQueryTimeAxisAndClutterSummary() throws {
        let refTimestamp: Int64 = 1_800_000_000
        let refDate = Date(timeIntervalSince1970: TimeInterval(refTimestamp))
        let recent = refTimestamp - 5 * 86_400
        let stale120 = refTimestamp - 120 * 86_400
        let stale200 = refTimestamp - 200 * 86_400

        let modOldAccessRecent = DiskNode(
            path: "/clutter/mod-old.mp4",
            kind: .file,
            allocated: 40_000_000,
            logical: 40_000_000,
            fileCount: 1,
            modifiedAt: stale120,
            accessedAt: recent
        )
        let modRecentAccessOld = DiskNode(
            path: "/clutter/access-old.dmg",
            kind: .file,
            allocated: 30_000_000,
            logical: 30_000_000,
            fileCount: 1,
            protection: [.installer],
            modifiedAt: recent,
            accessedAt: stale120
        )
        let fallbackAccessed = DiskNode(
            path: "/clutter/fallback.png",
            kind: .file,
            allocated: 10_000_000,
            logical: 10_000_000,
            fileCount: 1,
            modifiedAt: stale200,
            accessedAt: nil
        )
        let freshAudio = DiskNode(
            path: "/clutter/track.flac",
            kind: .file,
            allocated: 20_000_000,
            logical: 20_000_000,
            fileCount: 1,
            modifiedAt: recent,
            accessedAt: recent
        )
        let archiveZip = DiskNode(
            path: "/clutter/sdk.zip",
            kind: .file,
            allocated: 15_000_000,
            logical: 15_000_000,
            fileCount: 1,
            protection: [.installer],
            modifiedAt: stale120,
            accessedAt: stale120
        )
        let bigDoc = DiskNode(
            path: "/clutter/report.pdf",
            kind: .file,
            allocated: 50_000_000,
            logical: 50_000_000,
            fileCount: 1,
            protection: [.document],
            modifiedAt: recent,
            accessedAt: stale200
        )

        let nodes = [modOldAccessRecent, modRecentAccessOld, fallbackAccessed, freshAudio, archiveZip, bigDoc]

        let modifiedStale = LargeFileQuery.rows(
            nodes,
            minimum: 1_000_000,
            staleDays: 90,
            timeAxis: .modified,
            referenceDate: refDate
        )
        XCTAssertEqual(
            modifiedStale.map(\.path),
            [modOldAccessRecent.path, archiveZip.path, fallbackAccessed.path]
        )

        let accessedStale = LargeFileQuery.rows(
            nodes,
            minimum: 1_000_000,
            staleDays: 90,
            timeAxis: .accessed,
            referenceDate: refDate
        )
        XCTAssertEqual(
            accessedStale.map(\.path),
            [bigDoc.path, modRecentAccessOld.path, archiveZip.path, fallbackAccessed.path]
        )

        let emptySummary = LargeFileQuery.clutterSummary([], timeAxis: .modified, referenceDate: refDate)
        XCTAssertEqual(emptySummary, ClutterHighlightSummary())

        let modifiedSummary = LargeFileQuery.clutterSummary(nodes, timeAxis: .modified, referenceDate: refDate)
        XCTAssertEqual(modifiedSummary.mediaCount, 3)
        XCTAssertEqual(modifiedSummary.mediaAllocated, 70_000_000)
        XCTAssertEqual(modifiedSummary.archiveCount, 2)
        XCTAssertEqual(modifiedSummary.archiveAllocated, 45_000_000)
        XCTAssertEqual(modifiedSummary.stale90Count, 3)
        XCTAssertEqual(modifiedSummary.stale90Allocated, 65_000_000)
        XCTAssertEqual(modifiedSummary.largestFile?.path, bigDoc.path)

        let accessedSummary = LargeFileQuery.clutterSummary(nodes, timeAxis: .accessed, referenceDate: refDate)
        XCTAssertEqual(accessedSummary.mediaCount, 3)
        XCTAssertEqual(accessedSummary.mediaAllocated, 70_000_000)
        XCTAssertEqual(accessedSummary.archiveCount, 2)
        XCTAssertEqual(accessedSummary.archiveAllocated, 45_000_000)
        XCTAssertEqual(accessedSummary.stale90Count, 4)
        XCTAssertEqual(accessedSummary.stale90Allocated, 105_000_000)
        XCTAssertEqual(accessedSummary.largestFile?.path, bigDoc.path)
    }

    func testDuplicateSizeGroupComparisonSummaryAndPhase3StaticSafetyAudit() throws {
        let base: Int64 = 1_800_000_000
        let oldest = DiskNode(
            path: "/dup/old.dmg",
            kind: .file,
            allocated: 10_000_000,
            logical: 10_000_000,
            fileCount: 1,
            protection: [.installer],
            modifiedAt: base - 45 * 86_400,
            accessedAt: base - 2 * 86_400
        )
        let middle = DiskNode(
            path: "/dup/mid.dmg",
            kind: .file,
            allocated: 10_000_000,
            logical: 10_000_000,
            fileCount: 1,
            protection: [],
            modifiedAt: base - 15 * 86_400,
            accessedAt: base - 30 * 86_400
        )
        let newest = DiskNode(
            path: "/dup/new.dmg",
            kind: .file,
            allocated: 10_000_000,
            logical: 10_000_000,
            fileCount: 1,
            protection: [.installer, .user],
            modifiedAt: base,
            accessedAt: base - 10 * 86_400
        )

        let group = DuplicateSizeGroup(
            logicalSize: 10_000_000,
            ext: "dmg",
            category: .archive,
            files: [oldest, middle, newest]
        )

        let modComparison = group.comparisonSummary(timeAxis: .modified)
        XCTAssertEqual(modComparison.newestPath, newest.path)
        XCTAssertEqual(modComparison.oldestPath, oldest.path)
        XCTAssertEqual(modComparison.protectedCount, 2)
        XCTAssertEqual(modComparison.spanDays, 45)

        let accComparison = group.comparisonSummary(timeAxis: .accessed)
        XCTAssertEqual(accComparison.newestPath, oldest.path)
        XCTAssertEqual(accComparison.oldestPath, middle.path)
        XCTAssertEqual(accComparison.protectedCount, 2)
        XCTAssertEqual(accComparison.spanDays, 28)

        let untimedGroup = DuplicateSizeGroup(
            logicalSize: 2_000_000,
            ext: "bin",
            category: .other,
            files: [
                DiskNode(path: "/dup/a.bin", kind: .file, allocated: 2_000_000, logical: 2_000_000, restricted: true),
                DiskNode(path: "/dup/b.bin", kind: .file, allocated: 2_000_000, logical: 2_000_000)
            ]
        )
        let untimedComparison = untimedGroup.comparisonSummary()
        XCTAssertNil(untimedComparison.newestPath)
        XCTAssertNil(untimedComparison.oldestPath)
        XCTAssertEqual(untimedComparison.protectedCount, 1)
        XCTAssertEqual(untimedComparison.spanDays, 0)

        // Explicit static safety audit on Phase 3 modified Core/UI files
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        for rel in [
            "Sources/AetherDiskCore/DirectoryHandle.swift",
            "Sources/AetherDiskCore/Scanner.swift",
            "Sources/AetherDiskCore/Analysis.swift",
            "Sources/AetherDisk/AnalysisViews.swift"
        ] {
            let src = try String(contentsOf: repoRoot.appendingPathComponent(rel), encoding: .utf8)
            XCTAssertFalse(src.contains("Data(contentsOf:"), rel)
            XCTAssertFalse(src.contains("String(contentsOf:"), rel)
            XCTAssertFalse(src.contains("FileHandle("), rel)
            XCTAssertFalse(src.contains(".removeItem("), rel)
            XCTAssertFalse(src.contains(".trashItem("), rel)
            XCTAssertFalse(src.contains("deletelocalsnapshots"), rel)
            XCTAssertFalse(src.contains(".forceTerminate("), rel)
            XCTAssertFalse(src.contains("/usr/bin/purge"), rel)
        }
    }

    // MARK: - 12. Phase 4 & 5: TelemetryHistoryBuffer, LowSpaceEvaluator & Accessibility Support

    private func makeHealthSnapshot(
        sampledAt: Date,
        cpuFraction: Double,
        memoryFraction: Double,
        downloadBytesPerSec: Int64 = 0,
        uploadBytesPerSec: Int64 = 0
    ) -> SystemHealthSnapshot {
        let totalMem: Int64 = 16 * 1024 * 1024 * 1024
        let clampedMem = memoryFraction.isFinite ? min(1.0, max(0.0, memoryFraction)) : 0.0
        let usedMem: Int64 = Int64(Double(totalMem) * clampedMem)
        return SystemHealthSnapshot(
            memory: MemoryTelemetry(
                totalBytes: totalMem,
                usedBytes: usedMem,
                appBytes: usedMem / 2,
                wiredBytes: usedMem / 4,
                compressedBytes: usedMem / 4,
                availableBytes: totalMem - usedMem,
                pressure: clampedMem >= 0.85 ? .high : (clampedMem >= 0.70 ? .elevated : .normal)
            ),
            cpu: CPUTelemetry(
                usageFraction: cpuFraction,
                userFraction: cpuFraction * 0.7,
                systemFraction: cpuFraction * 0.3,
                loadAverage1m: 1.2,
                loadAverage5m: 1.0,
                coreCount: 8,
                thermalLabel: "正常",
                thermalSeverity: .normal,
                uptimeSeconds: 3600
            ),
            power: PowerTelemetry(hasBattery: false, percentage: nil, isCharging: false, isPluggedIn: true, statusLabel: "交流电源直连"),
            network: NetworkTelemetry(
                totalReceivedBytes: 1024,
                totalSentBytes: 512,
                downloadBytesPerSec: downloadBytesPerSec,
                uploadBytesPerSec: uploadBytesPerSec,
                activeInterfaces: 1,
                sampledAt: sampledAt
            ),
            hostModelLabel: "Mac",
            osVersionLabel: "macOS 15",
            sampledAt: sampledAt
        )
    }

    func testTelemetryHistoryBufferEvictionAveragesPeaksAndClamping() throws {
        var buffer = TelemetryHistoryBuffer(capacity: 3)
        XCTAssertEqual(buffer.capacity, 3)
        XCTAssertTrue(buffer.samples.isEmpty)
        XCTAssertTrue(buffer.cpuSeries.isEmpty)
        XCTAssertTrue(buffer.memorySeries.isEmpty)
        XCTAssertEqual(buffer.peakCPU, 0)
        XCTAssertEqual(buffer.peakMemory, 0)
        XCTAssertEqual(buffer.averageCPU, 0)
        XCTAssertEqual(buffer.averageMemory, 0)

        let zeroCap = TelemetryHistoryBuffer(
            capacity: 0,
            samples: [
                TelemetryHistorySample(cpuFraction: 0.25, memoryFraction: 0.50),
                TelemetryHistorySample(cpuFraction: 1.80, memoryFraction: -0.50, downloadBytesPerSec: -10, uploadBytesPerSec: -20)
            ]
        )
        XCTAssertEqual(zeroCap.capacity, 1)
        XCTAssertEqual(zeroCap.samples.count, 1)
        XCTAssertEqual(zeroCap.cpuSeries, [1.0])
        XCTAssertEqual(zeroCap.memorySeries, [0.0])
        XCTAssertEqual(zeroCap.samples[0].downloadBytesPerSec, 0)
        XCTAssertEqual(zeroCap.samples[0].uploadBytesPerSec, 0)

        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        // Out-of-range CPU (-0.25 -> 0.0) & memory (1.45 -> 1.0) plus negative network speed (-50 -> 0)
        buffer.append(makeHealthSnapshot(sampledAt: t0, cpuFraction: -0.25, memoryFraction: 1.45, downloadBytesPerSec: -50, uploadBytesPerSec: 256))
        XCTAssertEqual(buffer.samples.count, 1)
        XCTAssertEqual(buffer.cpuSeries, [0.0])
        XCTAssertEqual(buffer.memorySeries, [1.0])
        XCTAssertEqual(buffer.samples[0].downloadBytesPerSec, 0)
        XCTAssertEqual(buffer.samples[0].uploadBytesPerSec, 256)

        // Append 3 more snapshots -> oldest (t0) evicted, capacity 3 preserved
        buffer.append(makeHealthSnapshot(sampledAt: t0.addingTimeInterval(2), cpuFraction: 0.20, memoryFraction: 0.40))
        buffer.append(makeHealthSnapshot(sampledAt: t0.addingTimeInterval(4), cpuFraction: 0.80, memoryFraction: 0.60))
        buffer.append(makeHealthSnapshot(sampledAt: t0.addingTimeInterval(6), cpuFraction: 0.50, memoryFraction: 0.80))

        XCTAssertEqual(buffer.samples.count, 3)
        XCTAssertEqual(buffer.samples.first?.sampledAt, t0.addingTimeInterval(2))
        XCTAssertEqual(buffer.samples.last?.sampledAt, t0.addingTimeInterval(6))
        XCTAssertEqual(buffer.cpuSeries.count, 3)
        XCTAssertEqual(buffer.memorySeries.count, 3)
        XCTAssertEqual(buffer.cpuSeries[0], 0.20, accuracy: 1e-9)
        XCTAssertEqual(buffer.cpuSeries[1], 0.80, accuracy: 1e-9)
        XCTAssertEqual(buffer.cpuSeries[2], 0.50, accuracy: 1e-9)
        XCTAssertEqual(buffer.memorySeries[0], 0.40, accuracy: 1e-9)
        XCTAssertEqual(buffer.memorySeries[1], 0.60, accuracy: 1e-9)
        XCTAssertEqual(buffer.memorySeries[2], 0.80, accuracy: 1e-9)
        XCTAssertEqual(buffer.peakCPU, 0.80, accuracy: 1e-9)
        XCTAssertEqual(buffer.peakMemory, 0.80, accuracy: 1e-9)
        XCTAssertEqual(buffer.averageCPU, 0.50, accuracy: 1e-9)
        XCTAssertEqual(buffer.averageMemory, 0.60, accuracy: 1e-9)

        // Non-finite fractions clamp cleanly to 0
        var nonFiniteBuffer = TelemetryHistoryBuffer(
            capacity: 2,
            samples: [TelemetryHistorySample(sampledAt: t0, cpuFraction: .nan, memoryFraction: .infinity)]
        )
        XCTAssertEqual(nonFiniteBuffer.cpuSeries, [0.0])
        XCTAssertEqual(nonFiniteBuffer.memorySeries, [0.0])
        nonFiniteBuffer.append(makeHealthSnapshot(sampledAt: t0.addingTimeInterval(1), cpuFraction: .infinity, memoryFraction: 0.25))
        XCTAssertEqual(nonFiniteBuffer.cpuSeries, [0.0, 0.0])
        XCTAssertEqual(nonFiniteBuffer.memorySeries, [0.0, 0.25])
    }

    func testLowSpaceEvaluatorAndSmartCareLowSpaceInsights() throws {
        let giB: Int64 = 1024 * 1024 * 1024
        XCTAssertEqual(LowSpaceThresholdGiB.allCases.map(\.rawValue), [10, 20, 50, 100])
        XCTAssertEqual(LowSpaceThresholdGiB.gb50.title, "50 GiB")
        XCTAssertEqual(LowSpaceThresholdGiB.gb20.bytes, 20 * giB)

        // Unsampled volume -> normal, not triggered
        let zeroVol = LowSpaceEvaluator.evaluate(volume: VolumeSpace(total: 0, free: 0), thresholdGiB: 20)
        XCTAssertFalse(zeroVol.isTriggered)
        XCTAssertEqual(zeroVol.deficitBytes, 0)
        XCTAssertEqual(zeroVol.severity, .normal)
        XCTAssertEqual(zeroVol.headline, "容量等待采样")

        // Clamped threshold (< 1 -> 1 GiB)
        let clamped = LowSpaceEvaluator.evaluate(volume: VolumeSpace(total: 10 * giB, free: 2 * giB), thresholdGiB: 0)
        XCTAssertEqual(clamped.thresholdBytes, 1 * giB)
        XCTAssertFalse(clamped.isTriggered)

        // Exact boundary (free == threshold) -> normal, not triggered
        let atThreshold = LowSpaceEvaluator.evaluate(volume: VolumeSpace(total: 200 * giB, free: 50 * giB), thresholdGiB: 50)
        XCTAssertFalse(atThreshold.isTriggered)
        XCTAssertEqual(atThreshold.deficitBytes, 0)
        XCTAssertEqual(atThreshold.severity, .normal)

        // Elevated (free >= threshold / 2 && free < threshold)
        let elevated = LowSpaceEvaluator.evaluate(volume: VolumeSpace(total: 200 * giB, free: 30 * giB), thresholdGiB: 50)
        XCTAssertTrue(elevated.isTriggered)
        XCTAssertEqual(elevated.freeBytes, 30 * giB)
        XCTAssertEqual(elevated.thresholdBytes, 50 * giB)
        XCTAssertEqual(elevated.deficitBytes, 20 * giB)
        XCTAssertEqual(elevated.severity, .elevated)

        // High (free < threshold / 2)
        let high = LowSpaceEvaluator.evaluate(volume: VolumeSpace(total: 200 * giB, free: 24 * giB), thresholdGiB: 50)
        XCTAssertTrue(high.isTriggered)
        XCTAssertEqual(high.freeBytes, 24 * giB)
        XCTAssertEqual(high.thresholdBytes, 50 * giB)
        XCTAssertEqual(high.deficitBytes, 26 * giB)
        XCTAssertEqual(high.severity, .high)

        // SmartCareEngine integration with lowSpaceThresholdGiB
        let health = makeHealthSnapshot(sampledAt: Date(), cpuFraction: 0.2, memoryFraction: 0.4)

        let normalSmart = SmartCareEngine.evaluate(
            scan: nil,
            recommendations: [],
            volume: VolumeSpace(total: 500 * giB, free: 120 * giB),
            health: health,
            appsReport: nil,
            trash: nil,
            snapshots: nil,
            fullDiskAccessGranted: true,
            isExternalVolume: false,
            lowSpaceThresholdGiB: 100
        )
        XCTAssertFalse(normalSmart.insights.contains { $0.id == "low-space-threshold" || $0.id == "low-disk-space" })

        // Free = 60 GiB (12% of 500 GiB -> freeRatio >= 0.10, below 100 GiB threshold) inserts low-space-threshold
        let thresholdOnlySmart = SmartCareEngine.evaluate(
            scan: nil,
            recommendations: [],
            volume: VolumeSpace(total: 500 * giB, free: 60 * giB),
            health: health,
            appsReport: nil,
            trash: nil,
            snapshots: nil,
            fullDiskAccessGranted: true,
            isExternalVolume: false,
            lowSpaceThresholdGiB: 100
        )
        let thresholdInsight = try XCTUnwrap(thresholdOnlySmart.insights.first { $0.id == "low-space-threshold" })
        XCTAssertEqual(thresholdInsight.severity, .elevated)
        XCTAssertEqual(thresholdInsight.targetPage, "suggestions")
        XCTAssertFalse(thresholdOnlySmart.insights.contains { $0.id == "low-disk-space" })

        let externalThresholdSmart = SmartCareEngine.evaluate(
            scan: nil,
            recommendations: [],
            volume: VolumeSpace(total: 500 * giB, free: 40 * giB),
            health: health,
            appsReport: nil,
            trash: nil,
            snapshots: nil,
            fullDiskAccessGranted: true,
            isExternalVolume: true,
            lowSpaceThresholdGiB: 100
        )
        let lowRatioInsight = try XCTUnwrap(externalThresholdSmart.insights.first { $0.id == "low-disk-space" })
        XCTAssertTrue(lowRatioInsight.detail.contains("100 GiB"))
        XCTAssertFalse(externalThresholdSmart.insights.contains { $0.id == "low-space-threshold" })
    }

    func testPhase4And5StaticSafetyAndAccessibilityInvariants() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let readOnlySourceFiles = [
            "Sources/AetherDiskCore/SystemHealth.swift",
            "Sources/AetherDisk/Theme.swift",
            "Sources/AetherDisk/ContentView.swift",
            "Sources/AetherDisk/PerformanceAndAssistantViews.swift",
            "Sources/AetherDisk/AppUpdater.swift"
        ]
        for rel in readOnlySourceFiles {
            let src = try String(contentsOf: repoRoot.appendingPathComponent(rel), encoding: .utf8)
            XCTAssertFalse(src.contains("Data(contentsOf:"), rel)
            XCTAssertFalse(src.contains("String(contentsOf:"), rel)
            XCTAssertFalse(src.contains("FileHandle("), rel)
            XCTAssertFalse(src.contains(".removeItem("), rel)
            XCTAssertFalse(src.contains(".trashItem("), rel)
            XCTAssertFalse(src.contains(".forceTerminate("), rel)
            XCTAssertFalse(src.contains("/usr/bin/purge"), rel)
            XCTAssertFalse(src.contains("deletelocalsnapshots"), rel)
        }

        let appModelSrc = try String(contentsOf: repoRoot.appendingPathComponent("Sources/AetherDisk/AppModel.swift"), encoding: .utf8)
        XCTAssertFalse(appModelSrc.contains(".removeItem("))
        XCTAssertFalse(appModelSrc.contains(".trashItem("))
        XCTAssertFalse(appModelSrc.contains(".forceTerminate("))
        XCTAssertFalse(appModelSrc.contains("/usr/bin/purge"))
        XCTAssertFalse(appModelSrc.contains("deletelocalsnapshots"))

        // Theme.swift & ContentView.swift accessibilityReduceTransparency + accessibilityReduceMotion verification
        let themeSrc = try String(contentsOf: repoRoot.appendingPathComponent("Sources/AetherDisk/Theme.swift"), encoding: .utf8)
        XCTAssertTrue(themeSrc.contains("enum DiskMotion"))
        XCTAssertTrue(themeSrc.contains("@Environment(\\.accessibilityReduceTransparency)"))
        XCTAssertTrue(themeSrc.contains("@Environment(\\.accessibilityReduceMotion)"))
        XCTAssertTrue(themeSrc.contains("if !reduceTransparency"))
        XCTAssertTrue(themeSrc.contains("reduceMotion ? nil : .linear(duration: 1.15).repeatForever"))
        XCTAssertTrue(themeSrc.contains("OrbWingCapsuleModifier(reduceTransparency: reduceTransparency)"))

        let contentViewSrc = try String(contentsOf: repoRoot.appendingPathComponent("Sources/AetherDisk/ContentView.swift"), encoding: .utf8)
        XCTAssertTrue(contentViewSrc.contains("@Environment(\\.accessibilityReduceTransparency)"))
        XCTAssertTrue(contentViewSrc.contains("@Environment(\\.accessibilityReduceMotion)"))
        XCTAssertTrue(contentViewSrc.contains("DiskMotion.transition(reduceMotion: effectiveReduceMotion)"))
        XCTAssertTrue(contentViewSrc.contains("DiskMotion.subtle(reduceMotion: effectiveReduceMotion)"))
        XCTAssertTrue(contentViewSrc.contains("AETHERDISK_QA"))
        XCTAssertTrue(contentViewSrc.contains("let sidebarFill: AnyShapeStyle = reduceTransparency"))

        // Phase 4 read-only sparkline, launch-items linkage, and low-space threshold picker identifiers
        let perfViewSrc = try String(contentsOf: repoRoot.appendingPathComponent("Sources/AetherDisk/PerformanceAndAssistantViews.swift"), encoding: .utf8)
        XCTAssertTrue(perfViewSrc.contains("@Environment(\\.accessibilityReduceMotion)"))
        XCTAssertTrue(perfViewSrc.contains("\"cpu-sparkline\""))
        XCTAssertTrue(perfViewSrc.contains("\"memory-sparkline\""))
        XCTAssertTrue(perfViewSrc.contains("\"performance-launch-link\""))
        XCTAssertTrue(perfViewSrc.contains("\"performance-open-launch-items\""))

        let updaterSrc = try String(contentsOf: repoRoot.appendingPathComponent("Sources/AetherDisk/AppUpdater.swift"), encoding: .utf8)
        XCTAssertTrue(updaterSrc.contains("\"low-space-threshold-picker\""))
        XCTAssertTrue(updaterSrc.contains("LowSpaceThresholdGiB.allCases"))
    }

    // MARK: - 13. Phase 3.1.0 Refinements: App Unused Days, SmartCare Drawer, Bubble Zoom & MenuBar Sparklines

    func testInstalledAppUnusedDaysLastUsedAtAndLegacyJSON() throws {
        let appsDir = root.appendingPathComponent("Apps310")
        let staleApp = appsDir.appendingPathComponent("ArchiveViewer.app")
        let recentApp = appsDir.appendingPathComponent("ActiveEditor.app")
        let staleCache = home.appendingPathComponent("Library/Caches/ArchiveViewer")
        let recentCache = home.appendingPathComponent("Library/Caches/ActiveEditor")

        let staleBin = staleApp.appendingPathComponent("Contents/MacOS/ArchiveViewer")
        let recentBin = recentApp.appendingPathComponent("Contents/MacOS/ActiveEditor")
        try FileManager.default.createDirectory(at: staleBin.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: recentBin.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: staleCache, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: recentCache, withIntermediateDirectories: true)

        try Data(repeating: 0x01, count: 4096).write(to: staleBin)
        try Data(repeating: 0x02, count: 4096).write(to: recentBin)
        try Data(repeating: 0x03, count: 8192).write(to: staleCache.appendingPathComponent("cache.db"))
        try Data(repeating: 0x04, count: 8192).write(to: recentCache.appendingPathComponent("cache.db"))

        let refTs: Int64 = 1_800_000_000
        let refDate = Date(timeIntervalSince1970: TimeInterval(refTs))
        let staleOldTs = refTs - 120 * 86_400
        let recentBundleOldTs = refTs - 150 * 86_400
        let recentCacheActiveTs = refTs - 2 * 86_400

        // Apply old timestamps everywhere in staleApp + staleCache
        for url in [staleBin, staleBin.deletingLastPathComponent(), staleApp.appendingPathComponent("Contents"), staleApp, staleCache.appendingPathComponent("cache.db"), staleCache] {
            try setTimestamps(url, accessedAt: staleOldTs, modifiedAt: staleOldTs)
        }
        // recentApp bundle itself is old (150d), but its associated cache was accessed 2 days ago
        for url in [recentBin, recentBin.deletingLastPathComponent(), recentApp.appendingPathComponent("Contents"), recentApp] {
            try setTimestamps(url, accessedAt: recentBundleOldTs, modifiedAt: recentBundleOldTs)
        }
        try setTimestamps(recentCache.appendingPathComponent("cache.db"), accessedAt: recentCacheActiveTs, modifiedAt: recentBundleOldTs)
        try setTimestamps(recentCache, accessedAt: recentCacheActiveTs, modifiedAt: recentBundleOldTs)

        let report = ApplicationInspector.inspect(applicationRoots: [appsDir], home: home)
        let staleItem = try XCTUnwrap(report.apps.first { $0.name == "ArchiveViewer" })
        let recentItem = try XCTUnwrap(report.apps.first { $0.name == "ActiveEditor" })

        XCTAssertEqual(staleItem.unusedDays(referenceDate: refDate), 120)
        XCTAssertTrue(staleItem.isStale(days: 90, referenceDate: refDate))
        XCTAssertEqual(recentItem.unusedDays(referenceDate: refDate), 2)
        XCTAssertFalse(recentItem.isStale(days: 90, referenceDate: refDate))

        XCTAssertEqual(AppFilterMode.unused.title, "久未使用")
        XCTAssertEqual(AppSortMode.stale.title, "久未使用")

        let unusedOnly = ApplicationQuery.filterApps(report.apps, mode: .unused, sort: .stale, query: "", referenceDate: refDate)
        XCTAssertEqual(unusedOnly.map(\.name), ["ArchiveViewer"])

        let sortedByStale = ApplicationQuery.filterApps(report.apps, mode: .all, sort: .stale, query: "", referenceDate: refDate)
        XCTAssertEqual(sortedByStale.map(\.name), ["ArchiveViewer", "ActiveEditor"])

        // Legacy JSON decoding without lastUsedAt falls back to modifiedAt
        let legacyJSON = """
        {"name":"LegacyApp","path":"/Applications/LegacyApp.app","bundleAllocated":4096,"bundleLogical":4096,"fileCount":1,"modifiedAt":\(staleOldTs),"source":"standalone","associatedItems":[]}
        """
        let decoded = try JSONDecoder().decode(InstalledAppItem.self, from: Data(legacyJSON.utf8))
        XCTAssertNil(decoded.lastUsedAt)
        XCTAssertEqual(decoded.unusedDays(referenceDate: refDate), 120)
        XCTAssertTrue(decoded.isStale(days: 90, referenceDate: refDate))
    }

    func test310StaticSafetyAndUIEnhancementInvariants() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        for rel in [
            "Sources/AetherDiskCore/Applications.swift",
            "Sources/AetherDisk/SmartCareView.swift",
            "Sources/AetherDisk/Visualizations/BubbleLensView.swift",
            "Sources/AetherDisk/ApplicationsView.swift",
            "Sources/AetherDisk/PerformanceAndAssistantViews.swift"
        ] {
            let src = try String(contentsOf: repoRoot.appendingPathComponent(rel), encoding: .utf8)
            XCTAssertFalse(src.contains("Data(contentsOf:"), rel)
            XCTAssertFalse(src.contains("String(contentsOf:"), rel)
            XCTAssertFalse(src.contains("FileHandle("), rel)
            XCTAssertFalse(src.contains(".removeItem("), rel)
            XCTAssertFalse(src.contains(".trashItem("), rel)
        }

        let smartCareSrc = try String(contentsOf: repoRoot.appendingPathComponent("Sources/AetherDisk/SmartCareView.swift"), encoding: .utf8)
        XCTAssertTrue(smartCareSrc.contains("\"pillar-expand-\""))
        XCTAssertTrue(smartCareSrc.contains("\"smartcare-pillar-drawer\""))
        XCTAssertTrue(smartCareSrc.contains("\"smartcare-drawer-close\""))

        let bubbleSrc = try String(contentsOf: repoRoot.appendingPathComponent("Sources/AetherDisk/Visualizations/BubbleLensView.swift"), encoding: .utf8)
        XCTAssertTrue(bubbleSrc.contains("\"bubble-zoom-controls\""))
        XCTAssertTrue(bubbleSrc.contains("\"bubble-zoom-in\""))
        XCTAssertTrue(bubbleSrc.contains("\"bubble-zoom-out\""))
        XCTAssertTrue(bubbleSrc.contains("\"bubble-zoom-reset\""))

        let perfSrc = try String(contentsOf: repoRoot.appendingPathComponent("Sources/AetherDisk/PerformanceAndAssistantViews.swift"), encoding: .utf8)
        XCTAssertTrue(perfSrc.contains("\"menubar-telemetry-sparklines\""))
    }
}
