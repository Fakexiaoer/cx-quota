import Foundation

public enum CXProfileManager {
    public static func isValidProfileName(_ name: String) -> Bool {
        guard let expression = try? NSRegularExpression(pattern: "^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$") else {
            return false
        }
        let range = NSRange(name.startIndex..., in: name)
        return expression.firstMatch(in: name, range: range) != nil
    }

    public static func createAndLogin(profile: String) async -> Result<Void, CXProfileManagerError> {
        await Task.detached(priority: .userInitiated) {
            guard isValidProfileName(profile) else {
                return .failure(.invalidProfileName)
            }
            do {
                let launcher = try launcherURL()
                try run(launcher, arguments: ["init", profile])
                try run(launcher, arguments: ["login", profile])
                return .success(())
            } catch let error as CXProfileManagerError {
                return .failure(error)
            } catch {
                return .failure(.commandFailed)
            }
        }.value
    }

    public static func makeLoginProcess(profile: String) throws -> Process {
        let directory = try profileDirectory(for: profile)
        let process = Process()
        process.executableURL = try codexURL()
        process.arguments = ["login"]
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        process.environment = ProcessInfo.processInfo.environment.merging(["CODEX_HOME": directory.path]) { _, replacement in replacement }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        return process
    }

    public static func logoutAndRemove(profile: String) async -> Result<Void, CXProfileManagerError> {
        await Task.detached(priority: .userInitiated) {
            do {
                let directory = try profileDirectory(for: profile)
                try run(try codexURL(), arguments: ["logout"], environment: ["CODEX_HOME": directory.path])
                try FileManager.default.removeItem(at: directory)
                return .success(())
            } catch let error as CXProfileManagerError {
                return .failure(error)
            } catch {
                return .failure(.commandFailed)
            }
        }.value
    }

    private static func launcherURL() throws -> URL {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/cx")
        guard FileManager.default.isExecutableFile(atPath: url.path) else {
            throw CXProfileManagerError.launcherUnavailable
        }
        return url
    }

    private static func codexURL() throws -> URL {
        let candidates = ["/opt/homebrew/bin/codex", "/usr/local/bin/codex", "/usr/bin/codex"]
            .map(URL.init(fileURLWithPath:))
        guard let executable = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else {
            throw CXProfileManagerError.launcherUnavailable
        }
        return executable
    }

    private static func profileDirectory(for profile: String) throws -> URL {
        guard isValidProfileName(profile) else {
            throw CXProfileManagerError.invalidProfileName
        }
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex-profiles", isDirectory: true)
        let directory = root.appendingPathComponent(profile, isDirectory: true)
        guard ProfileDirectorySecurity.isOwnedAndPrivateDirectory(root),
              ProfileDirectorySecurity.isOwnedAndPrivateDirectory(directory),
              directory.deletingLastPathComponent().standardizedFileURL == root.standardizedFileURL else {
            throw CXProfileManagerError.profileUnavailable
        }
        return directory
    }

    private static func run(_ executable: URL, arguments: [String], environment: [String: String]? = nil) throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        if let environment {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, replacement in replacement }
        }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CXProfileManagerError.commandFailed
        }
    }
}

public enum CXProfileManagerError: LocalizedError, Sendable {
    case invalidProfileName
    case launcherUnavailable
    case profileUnavailable
    case commandFailed

    public var errorDescription: String? {
        switch self {
        case .invalidProfileName: "名称只能使用字母、数字、点、下划线或连字符"
        case .launcherUnavailable: "未找到 cx 命令"
        case .profileUnavailable: "账号配置目录不可用"
        case .commandFailed: "账号操作失败"
        }
    }
}
