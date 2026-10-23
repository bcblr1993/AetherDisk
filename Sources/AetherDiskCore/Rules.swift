import Foundation

public enum RuleCatalog {
    public static func category(for url: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> CacheCategory? {
        let path = url.path; let h = home.path
        if path == h + "/Library/Developer/Xcode/DerivedData" { return .xcode }
        if path.hasPrefix(h + "/.cache/codex-runtimes/codex-runtime-install-") && url.deletingLastPathComponent().path == h + "/.cache/codex-runtimes" { return .update }
        let exact = ["/.docker/scout/sbom", "/.npm/_cacache", "/.nvm/.cache", "/Library/Application Support/Claude/Cache", "/Library/Application Support/Claude/Code Cache"]
        if exact.contains(where: { path == h + $0 }) { return .compiler }
        let prefix = h + "/Library/Caches/"
        if path.hasPrefix(prefix), !path.dropFirst(prefix.count).contains("/") { return .browser }
        if url.lastPathComponent == "target", FileManager.default.fileExists(atPath: url.deletingLastPathComponent().appendingPathComponent("Cargo.toml").path) { return .build }
        if url.lastPathComponent == ".build", FileManager.default.fileExists(atPath: url.deletingLastPathComponent().appendingPathComponent("Package.swift").path) { return .build }
        if ["DerivedData", ".dart_tool", ".gradle"].contains(url.lastPathComponent) { return .build }
        if url.lastPathComponent == "build" {
            let parent = url.deletingLastPathComponent()
            if ["Package.swift", "pubspec.yaml", "project.yml", "build.gradle", "build.gradle.kts"].contains(where: { FileManager.default.fileExists(atPath: parent.appendingPathComponent($0).path) }) { return .build }
        }
        return nil
    }
    public static func protection(name: String, directory: Bool) -> Set<Protection> {
        let n = name.lowercased(); var flags: Set<Protection> = []
        if n == ".git" { flags.insert(.git) }
        if [".ssh", ".gnupg", "keychains", "xwechat_files", "backup", "sessions", "archived_sessions"].contains(n) { flags.insert(.credentials) }
        if n.hasPrefix(".env.") || [".env", ".npmrc", ".netrc", ".git-credentials", "id_rsa", "id_ed25519"].contains(n) || ["pem", "key", "p12", "mobileprovision", "aetherroute"].contains((n as NSString).pathExtension) { flags.insert(.credentials) }
        if directory && ["app", "xcarchive"].contains((n as NSString).pathExtension) { flags.insert(.installer) }
        if !directory {
            let ext = (n as NSString).pathExtension
            if ["dmg", "pkg", "ipa", "apk", "aab", "zip", "gz", "xz", "tar", "7z", "rar", "deb", "rpm", "exe", "msi", "msix", "msixbundle", "appimage", "jar", "war", "whl", "bz2", "zst", "uf2", "hex"].contains(ext) || n.contains("sha256sums") || n == "appcast.xml" { flags.insert(.installer) }
            if ["swift", "rs", "c", "h", "cpp", "m", "mm", "py", "js", "ts", "tsx", "vue", "astro", "dart", "java", "kt", "sh", "go", "rb", "sql", "lua", "pl", "ps1", "bat", "cs", "fs", "cc", "cxx", "hpp", "hxx", "asm", "zig", "ex", "exs", "erl", "clj", "hs", "r", "jl", "ipynb", "html", "css", "scss", "svelte"].contains(ext) || ["cargo.toml", "package.json", "pom.xml", "project.yml", "pubspec.yaml", "agents.md"].contains(n) { flags.insert(.source) }
        }
        return flags
    }
    public static func recommendations(nodes: [DiskNode], home: URL) -> [Recommendation] {
        var result: [Recommendation] = []
        for node in nodes.filter({ $0.kind == .directory && $0.allocated > 0 }).sorted(by: { $0.path.count < $1.path.count }) {
            guard let category = category(for: URL(fileURLWithPath: node.path), home: home) else { continue }
            if result.contains(where: { node.path.hasPrefix($0.node.path + "/") }) { continue }
            result.append(.init(node: node, category: category))
        }
        return result.sorted { $0.node.allocated > $1.node.allocated }
    }
}
