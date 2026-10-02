import Foundation

public enum QuotaCache {
    public static func load(from url: URL = cacheURL()) -> [QuotaSnapshot] {
        guard let data = try? Data(contentsOf: url),
              let snapshots = try? JSONDecoder().decode([QuotaSnapshot].self, from: data) else {
            return []
        }
        return snapshots
    }

    public static func save(_ snapshots: [QuotaSnapshot], to url: URL = cacheURL()) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let data = try JSONEncoder().encode(snapshots)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public static func cacheURL() -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CXQuota", isDirectory: true)
            .appendingPathComponent("quota-cache.json")
    }
}
