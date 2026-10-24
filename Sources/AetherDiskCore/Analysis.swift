import Foundation

public enum FileCategory: String, Codable, CaseIterable, Sendable, Identifiable {
    case video, audio, image, archive, source, document, other
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .video: "视频"; case .audio: "音频"; case .image: "图片"; case .archive: "安装包与归档"
        case .source: "源码与脚本"; case .document: "文档"; case .other: "其他文件"
        }
    }
    public static func classify(_ name: String) -> Self {
        let ext = (name.lowercased() as NSString).pathExtension
        if ["mp4","mkv","mov","avi","m4v","webm","ts","m2ts","flv"].contains(ext) { return ext == "ts" ? .source : .video }
        if ["mp3","flac","aac","m4a","wav","aiff","ogg","opus"].contains(ext) { return .audio }
        if ["png","jpg","jpeg","heic","gif","webp","tiff","svg","raw","dng","avif"].contains(ext) { return .image }
        let flags = RuleCatalog.protection(name: name, directory: false)
        if flags.contains(.installer) { return .archive }
        if flags.contains(.source) { return .source }
        if ["pdf","txt","md","rtf","doc","docx","xls","xlsx","ppt","pptx","csv","pages","numbers","keynote","epub"].contains(ext) { return .document }
        return .other
    }
}
public struct FileTypeUsage: Codable, Sendable, Identifiable {
    public var id: FileCategory { category }
    public var category: FileCategory
    public var allocated: Int64 = 0
    public var logical: Int64 = 0
    public var files: Int = 0
}
public struct ScanAnalysis: Codable, Sendable {
    public var fileTypes: [FileTypeUsage]
    public var largeFiles: [DiskNode]
}
public enum SizeBasis: String, CaseIterable, Sendable, Identifiable {
    case allocated, logical
    public var id: String { rawValue }
    public var title: String { self == .allocated ? "磁盘占用" : "逻辑大小" }
    public func size(_ node: DiskNode) -> Int64 { self == .allocated ? node.allocated : node.logical }
}
public enum LargeFileQuery {
    public static func rows(_ files: [DiskNode], query: String = "", category: FileCategory? = nil, minimum: Int64 = 100 * 1024 * 1024, basis: SizeBasis = .allocated) -> [DiskNode] {
        files.filter { basis.size($0) >= minimum && (category == nil || FileCategory.classify($0.name) == category) && (query.isEmpty || $0.path.localizedCaseInsensitiveContains(query)) }
            .sorted { basis.size($0) == basis.size($1) ? $0.path < $1.path : basis.size($0) > basis.size($1) }
    }
}
// Kept separate from the directory display budget: metadata beyond 20,000 nodes still contributes.
struct AnalysisAccumulator {
    var types: [FileCategory: FileTypeUsage] = [:]
    var physical: [DiskNode] = []; var logical: [DiskNode] = []
    var physicalFloor: Int64 = 0; var logicalFloor: Int64 = 0
    mutating func record(_ node: DiskNode) {
        let category = FileCategory.classify(node.name)
        var usage = types[category] ?? .init(category: category)
        usage.allocated += node.allocated; usage.logical += node.logical; usage.files += 1; types[category] = usage
        if node.allocated >= 1024 * 1024 && (physical.count < 200 || node.allocated >= physicalFloor) {
            physical.append(node)
            if physical.count >= 400 { physical.sort { $0.allocated > $1.allocated }; physical = Array(physical.prefix(200)); physicalFloor = physical.last?.allocated ?? 0 }
        }
        if node.logical >= 1024 * 1024 && (logical.count < 200 || node.logical >= logicalFloor) {
            logical.append(node)
            if logical.count >= 400 { logical.sort { $0.logical > $1.logical }; logical = Array(logical.prefix(200)); logicalFloor = logical.last?.logical ?? 0 }
        }
    }
    func result() -> ScanAnalysis {
        let top = Array(physical.sorted { $0.allocated > $1.allocated }.prefix(200)) + Array(logical.sorted { $0.logical > $1.logical }.prefix(200))
        let unique = Dictionary(top.map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })
        return .init(fileTypes: types.values.sorted { $0.allocated == $1.allocated ? $0.category.rawValue < $1.category.rawValue : $0.allocated > $1.allocated }, largeFiles: unique.values.sorted { $0.allocated == $1.allocated ? $0.path < $1.path : $0.allocated > $1.allocated })
    }
}
public enum UserProtection {
    public static func contains(_ parent: String, _ child: String) -> Bool { parent == child || child.hasPrefix(parent == "/" ? "/" : parent + "/") }
    public static func overlaps(_ path: String, protectedPaths: [String]) -> Bool {
        let p = URL(fileURLWithPath: path).standardizedFileURL.path.precomposedStringWithCanonicalMapping.lowercased()
        return protectedPaths.contains { value in let r = URL(fileURLWithPath: value).standardizedFileURL.path.precomposedStringWithCanonicalMapping.lowercased(); return contains(r, p) || contains(p, r) }
    }
    public static func apply(_ node: DiskNode, paths: [String]) -> DiskNode {
        var value = node; value.protection.remove(.user)
        if overlaps(node.path, protectedPaths: paths) { value.protection.insert(.user) }
        return value
    }
    public static func requireAllowed(_ paths: [String], protectedPaths: [String]) throws {
        if paths.contains(where: { overlaps($0, protectedPaths: protectedPaths) }) { throw CleanupError.refused("该目录或其内部包含自定义保护目录，已阻止清理。") }
    }
}
