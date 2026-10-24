import Foundation
import Darwin

public enum RuleCatalog {
    public static func category(for url: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> CacheCategory? {
        let path = url.path; let h = home.path
        func regular(_ path: String) -> Bool {
            var info = stat(); return lstat(path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFREG
        }
        if path == h + "/Library/Developer/Xcode/DerivedData" { return .xcode }
        if path.hasPrefix(h + "/.cache/codex-runtimes/codex-runtime-install-") && url.deletingLastPathComponent().path == h + "/.cache/codex-runtimes" { return .update }
        let exact = ["/.docker/scout/sbom", "/.npm/_cacache", "/.nvm/.cache", "/Library/Application Support/Claude/Cache", "/Library/Application Support/Claude/Code Cache"]
        if exact.contains(where: { path == h + $0 }) { return .compiler }
        let prefix = h + "/Library/Caches/"
        if path.hasPrefix(prefix), !path.dropFirst(prefix.count).contains("/") { return .browser }
        if url.lastPathComponent == "target", regular(url.deletingLastPathComponent().appendingPathComponent("Cargo.toml").path) { return .build }
        if url.lastPathComponent == ".build", regular(url.deletingLastPathComponent().appendingPathComponent("Package.swift").path) { return .build }
        let parent = url.deletingLastPathComponent()
        func marker(_ names: [String]) -> Bool {
            names.contains { name in
                var info = stat()
                return lstat(parent.appendingPathComponent(name).path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFREG
            }
        }
        if url.lastPathComponent == ".dart_tool", marker(["pubspec.yaml"]) { return .build }
        if url.lastPathComponent == ".gradle", marker(["settings.gradle", "settings.gradle.kts", "build.gradle", "build.gradle.kts"]) { return .build }
        if url.lastPathComponent == "DerivedData", marker(["project.yml"]) { return .build }
        if url.lastPathComponent == "build" {
            let parent = url.deletingLastPathComponent()
            if ["Package.swift", "pubspec.yaml", "project.yml", "build.gradle", "build.gradle.kts"].contains(where: { regular(parent.appendingPathComponent($0).path) }) { return .build }
        }
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
            if ["swift", "rs", "c", "h", "cpp", "m", "mm", "py", "js", "ts", "tsx", "vue", "astro", "dart", "java", "kt", "sh", "go", "rb", "sql", "lua", "pl", "ps1", "bat", "cs", "fs", "cc", "cxx", "hpp", "hxx", "asm", "zig", "ex", "exs", "erl", "clj", "hs", "r", "jl", "ipynb", "html", "css", "scss", "svelte", "jsx", "kts", "gradle", "bash", "zsh", "fish", "cmake", "sln", "csproj", "vb", "vbs", "php", "phtml", "pas", "f90", "f95", "f03", "f08", "for", "f", "vue", "less", "sass", "styl", "proto", "graphql", "gql", "tex", "sty", "cls", "s", "ino"].contains(ext) || ["cargo.toml", "package.json", "pom.xml", "project.yml", "pubspec.yaml", "agents.md", ".gitignore", ".gitattributes", ".gitmodules", "makefile", "gnumakefile", "cmakelists.txt", "dockerfile", "jenkinsfile", "gemfile", "rakefile", "justfile", "meson.build", "build.ninja", "configure", "gradlew", "mvnw"].contains(n) { flags.insert(.source) }
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
}
