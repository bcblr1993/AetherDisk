import Foundation
import Darwin

public enum RuleCatalog {
    public static func category(for url: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> CacheCategory? {
        let path = url.path; let h = home.path
        func regular(_ path: String) -> Bool {
            var info = stat(); return lstat(path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFREG
        }
        let xcodePaths = [
            "/Library/Developer/Xcode/DerivedData",
            "/Library/Developer/CoreSimulator/Caches",
            "/Library/Developer/Xcode/DocumentationCache",
            "/Library/Developer/Xcode/iOS DeviceSupport",
            "/Library/Developer/Xcode/watchOS DeviceSupport",
            "/Library/Developer/Xcode/macOS DeviceSupport",
            "/Library/Developer/Xcode/tvOS DeviceSupport",
            "/Library/Developer/Xcode/visionOS DeviceSupport"
        ]
        if xcodePaths.contains(where: { path == h + $0 }) { return .xcode }
        if path.hasPrefix(h + "/.cache/codex-runtimes/codex-runtime-install-") && url.deletingLastPathComponent().path == h + "/.cache/codex-runtimes" { return .update }
        let exact = [
            "/.docker/scout/sbom", "/.npm/_cacache", "/.nvm/.cache",
            "/.cache/go-build", "/.cache/pip/http-v2", "/.cache/uv", "/.gradle/caches",
            "/.cargo/registry/cache", "/.pnpm-store", "/.bun/install/cache", "/.yarn/berry/cache",
            "/Library/Caches/CocoaPods", "/.pub-cache", "/.sbt/boot", "/.ivy2/cache",
            "/.cache/huggingface/hub", "/.cache/playwright",
            "/Library/Application Support/Claude/Cache", "/Library/Application Support/Claude/Code Cache",
            "/Library/Application Support/Code/Cache", "/Library/Application Support/Code/CachedData",
            "/Library/Application Support/Cursor/Cache", "/Library/Application Support/Cursor/CachedData"
        ]
        if exact.contains(where: { path == h + $0 }) { return .compiler }
        let prefix = h + "/Library/Caches/"
        if path.hasPrefix(prefix), !path.dropFirst(prefix.count).contains("/") { return .browser }
        let parent = url.deletingLastPathComponent()
        func marker(_ names: [String], in dir: URL = parent) -> Bool {
            names.contains { regular(dir.appendingPathComponent($0).path) }
        }
        if url.lastPathComponent == "target", marker(["Cargo.toml", "pom.xml"]) { return .build }
        if url.lastPathComponent == ".build", marker(["Package.swift"]) { return .build }
        if url.lastPathComponent == ".dart_tool", marker(["pubspec.yaml"]) { return .build }
        if [".gradle", ".kotlin"].contains(url.lastPathComponent), marker(["settings.gradle", "settings.gradle.kts", "build.gradle", "build.gradle.kts"]) { return .build }
        if url.lastPathComponent == "DerivedData", marker(["project.yml"]) { return .build }
        if [".ruff_cache", ".pytest_cache", ".mypy_cache", ".tox", ".nox"].contains(url.lastPathComponent), marker(["pyproject.toml", "setup.py", "tox.ini"]) { return .build }
        if [".nuxt", ".turbo", ".svelte-kit", ".parcel-cache", ".astro", ".vite"].contains(url.lastPathComponent), marker(["package.json"]) { return .build }
        if url.lastPathComponent == "cache", parent.lastPathComponent == ".next", marker(["package.json"], in: parent.deletingLastPathComponent()) { return .build }
        if url.lastPathComponent == "cache", parent.lastPathComponent == ".angular", marker(["angular.json", "package.json"], in: parent.deletingLastPathComponent()) { return .build }
        if url.lastPathComponent == "build", marker(["Package.swift", "pubspec.yaml", "project.yml", "build.gradle", "build.gradle.kts", "CMakeLists.txt"]) { return .build }
        return nil
    }
    public static func protection(name: String, directory: Bool) -> Set<Protection> {
        let n = name.lowercased(); var flags: Set<Protection> = []
        if [".git", ".hg", ".svn", "head", "packed-refs"].contains(n) { flags.insert(.git) }
        if [".ssh", ".gnupg", "keychains", "xwechat_files", "backup", "sessions", "archived_sessions"].contains(n) { flags.insert(.credentials) }
        if n.hasPrefix(".env.") || [".env", ".npmrc", ".netrc", ".git-credentials", "id_rsa", "id_ed25519"].contains(n) || ["pem", "key", "p12", "mobileprovision", "aetherroute"].contains((n as NSString).pathExtension) { flags.insert(.credentials) }
        if directory && ["app", "xcarchive", "pkg", "xip", "dmg", "sparsebundle", "framework", "dsym"].contains((n as NSString).pathExtension) { flags.insert(.installer) }
        if directory && (["src", "source", "sources", "releases", "release", "installers", "dist", "artifacts"].contains(n) || ["xcodeproj", "xcworkspace", "playground"].contains((n as NSString).pathExtension)) { flags.insert(.source) }
        if !directory {
            let ext = (n as NSString).pathExtension
            if ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages", "numbers", "keynote", "csv", "md", "rtf", "epub"].contains(ext) { flags.insert(.document) }
            if ["dmg", "pkg", "ipa", "apk", "aab", "zip", "gz", "xz", "tar", "7z", "rar", "deb", "rpm", "exe", "msi", "msix", "msixbundle", "appimage", "jar", "war", "whl", "bz2", "zst", "uf2", "hex", "tgz", "tbz", "tbz2", "txz", "tzst", "xip", "iso", "img", "ipsw", "aar", "nupkg", "cab", "msu", "msp", "vhd", "vhdx", "vmdk", "qcow2", "bin", "run"].contains(ext) || n.contains("sha256sums") || n == "appcast.xml" { flags.insert(.installer) }
            if ["swift", "rs", "c", "h", "cpp", "m", "mm", "py", "js", "ts", "tsx", "vue", "astro", "dart", "java", "kt", "sh", "go", "rb", "sql", "lua", "pl", "ps1", "bat", "cs", "fs", "cc", "cxx", "hpp", "hxx", "asm", "zig", "ex", "exs", "erl", "clj", "hs", "r", "jl", "ipynb", "html", "css", "scss", "svelte", "jsx", "kts", "gradle", "bash", "zsh", "fish", "cmake", "sln", "csproj", "vb", "vbs", "php", "phtml", "pas", "f90", "f95", "f03", "f08", "for", "f", "vue", "less", "sass", "styl", "proto", "graphql", "gql", "tex", "sty", "cls", "s", "ino"].contains(ext) || ["cargo.toml", "package.json", "pom.xml", "project.yml", "pubspec.yaml", "agents.md", ".gitignore", ".gitattributes", ".gitmodules", "makefile", "gnumakefile", "cmakelists.txt", "dockerfile", "jenkinsfile", "gemfile", "rakefile", "justfile", "meson.build", "build.ninja", "configure", "gradlew", "mvnw", "go.mod", "composer.json", "mix.exs", "angular.json", "tox.ini", "pyproject.toml", "setup.py"].contains(n) { flags.insert(.source) }
        }
        return flags
    }
    public static func ancestorProtection(for url: URL) -> Set<Protection> {
        var flags: Set<Protection> = []; var parent = url.deletingLastPathComponent()
        while parent.path != "/" {
            flags.formUnion(protection(name: parent.lastPathComponent, directory: true))
            parent.deleteLastPathComponent()
        }
        return flags
    }
    public static func recommendations(nodes: [DiskNode], home: URL) -> [Recommendation] {
        var result: [Recommendation] = []
        for node in nodes.filter({ $0.kind == .directory && $0.allocated > 0 }).sorted(by: { $0.path.count < $1.path.count }) {
            guard let category = category(for: URL(fileURLWithPath: node.path), home: home) else { continue }
            if result.contains(where: { node.path.hasPrefix($0.node.path + "/") }) { continue }
            var protected = node; protected.protection.formUnion(ancestorProtection(for: URL(fileURLWithPath: node.path)))
            result.append(.init(node: protected, category: category))
        }
        return result.sorted { $0.node.allocated > $1.node.allocated }
    }
    public static func projectMarkers(in children: [String]) -> [String] {
        let known: Set<String> = [".git", "Package.swift", "Cargo.toml", "pom.xml", "build.gradle", "build.gradle.kts", "CMakeLists.txt", "package.json", "pyproject.toml", "setup.py", "pubspec.yaml", "project.yml", "go.mod", "composer.json", "Gemfile", "mix.exs", "angular.json"]
        return children.filter { known.contains($0) }.sorted()
    }
}
