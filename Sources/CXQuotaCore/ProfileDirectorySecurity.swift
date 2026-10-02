import Darwin
import Foundation

enum ProfileDirectorySecurity {
    static func isOwnedAndPrivateDirectory(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
              values.isDirectory == true,
              values.isSymbolicLink != true,
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let owner = (attributes[.ownerAccountID] as? NSNumber)?.uintValue,
              let permissions = (attributes[.posixPermissions] as? NSNumber)?.uintValue else {
            return false
        }
        return owner == UInt(getuid()) && permissions & 0o077 == 0
    }
}
