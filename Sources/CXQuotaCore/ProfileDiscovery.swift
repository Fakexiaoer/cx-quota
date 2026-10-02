import Foundation

public struct CodexProfile: Equatable, Sendable {
    public let name: String
    public let directory: URL

    public init(name: String, directory: URL) {
        self.name = name
        self.directory = directory
    }
}

public enum ProfileDiscovery {
    private static let namePattern = try! NSRegularExpression(pattern: "^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$")

    public static func profiles(in root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex-profiles", isDirectory: true)) -> [CodexProfile] {
        guard ProfileDirectorySecurity.isOwnedAndPrivateDirectory(root) else {
            return []
        }
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return children.compactMap { child in
            let name = child.lastPathComponent
            let range = NSRange(name.startIndex..., in: name)
            guard namePattern.firstMatch(in: name, range: range) != nil,
                  ProfileDirectorySecurity.isOwnedAndPrivateDirectory(child) else {
                return nil
            }
            return CodexProfile(name: name, directory: child)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
