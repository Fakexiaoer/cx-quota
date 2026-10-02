import Foundation

public enum AppServerClient {
    public static func fetch(profile: CodexProfile, executableURL: URL? = nil) async -> QuotaSnapshot {
        for attempt in 0..<2 {
            let result = await fetchAttempt(profile: profile, executableURL: executableURL)
            switch result {
            case let .success(snapshot):
                if attempt == 0, snapshot.needsResetCreditDetailRefresh {
                    try? await Task.sleep(for: .milliseconds(750))
                    continue
                }
                return snapshot
            case let .failure(error):
                if attempt == 0, isTransient(error) {
                    try? await Task.sleep(for: .milliseconds(750))
                    continue
                }
                return QuotaSnapshot(
                    profile: profile.name,
                    availability: .failed,
                    errorMessage: displayMessage(for: error)
                )
            }
        }
        return QuotaSnapshot(profile: profile.name, availability: .failed, errorMessage: "额度查询失败")
    }

    public static func consumeReset(profile: CodexProfile, creditID: String?, executableURL: URL? = nil) async -> Result<Void, QuotaError> {
        await Task.detached(priority: .userInitiated) {
            do {
                try consumeResetSynchronously(profile: profile, creditID: creditID, executableURL: executableURL)
                return .success(())
            } catch let error as QuotaError {
                return .failure(error)
            } catch {
                return .failure(.processFailed(error.localizedDescription))
            }
        }.value
    }

    static func isTransient(_ error: QuotaError) -> Bool {
        if isInvalidAuthentication(error) {
            return false
        }
        let message: String
        switch error {
        case let .server(value), let .processFailed(value):
            message = value.lowercased()
        default:
            return false
        }
        return message.contains("wham/usage")
            || message.contains("error sending request")
            || message.contains("connection")
            || message.contains("network")
    }

    static func displayMessage(for error: QuotaError) -> String {
        if isInvalidAuthentication(error) {
            return "登录已失效，请重新登录此账号"
        }
        return isTransient(error) ? "官方额度服务暂时不可用，请稍后刷新" : error.localizedDescription
    }

    private static func isInvalidAuthentication(_ error: QuotaError) -> Bool {
        let message: String
        switch error {
        case let .server(value), let .processFailed(value):
            message = value.lowercased()
        default:
            return false
        }
        return message.contains("token_revoked")
            || message.contains("invalidated oauth token")
            || message.contains("401 unauthorized")
            || message.contains("authentication required")
    }

    private static func fetchAttempt(profile: CodexProfile, executableURL: URL?) async -> Result<QuotaSnapshot, QuotaError> {
        await Task.detached(priority: .userInitiated) {
            do {
                return .success(try fetchSynchronously(profile: profile, executableURL: executableURL))
            } catch let error as QuotaError {
                return .failure(error)
            } catch {
                return .failure(.processFailed(error.localizedDescription))
            }
        }.value
    }

    private static func fetchSynchronously(profile: CodexProfile, executableURL: URL?) throws -> QuotaSnapshot {
        let response = try runRequest(
            profile: profile,
            executableURL: executableURL,
            messages: [
                ["method": "account/read", "id": 1, "params": ["refreshToken": false]],
                ["method": "account/rateLimits/read", "id": 2],
            ],
            responseID: 2
        )
        let account = try accountInfo(from: response)
        return try QuotaParser.snapshot(profile: profile.name, planType: account, responseData: response, now: Date())
    }

    private static func consumeResetSynchronously(profile: CodexProfile, creditID: String?, executableURL: URL?) throws {
        var parameters: [String: Any] = ["idempotencyKey": UUID().uuidString]
        if let creditID {
            parameters["creditId"] = creditID
        }
        let response = try runRequest(
            profile: profile,
            executableURL: executableURL,
            messages: [[
                "method": "account/rateLimitResetCredit/consume",
                "id": 1,
                "params": parameters,
            ]],
            responseID: 1
        )
        try validateResetOutcome(response)
    }

    static func validateResetOutcome(_ response: Data) throws {
        let responseResult = try responseResult(from: response)
        switch responseResult["outcome"] as? String {
        case "reset", "alreadyRedeemed":
            return
        case "nothingToReset":
            throw QuotaError.server("当前没有需要重置的额度")
        case "noCredit":
            throw QuotaError.server("这张重置卡已不可用")
        default:
            throw QuotaError.invalidResponse
        }
    }

    private static func runRequest(
        profile: CodexProfile,
        executableURL: URL?,
        messages: [[String: Any]],
        responseID: Int
    ) throws -> Data {
        let executable = try executableURL ?? resolvedExecutable()
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = executable
        process.arguments = ["app-server", "--stdio"]
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        var environment = ProcessInfo.processInfo.environment
        environment["CODEX_HOME"] = profile.directory.path
        process.environment = environment

        try process.run()
        defer { input.fileHandleForWriting.closeFile() }
        let handshake: [[String: Any]] = [
            ["method": "initialize", "id": 0, "params": ["clientInfo": ["name": "cx_quota", "title": "CX Quota", "version": "1.0.0"]]],
            ["method": "initialized", "params": [:]],
        ]
        for message in handshake + messages {
            let data = try JSONSerialization.data(withJSONObject: message)
            input.fileHandleForWriting.write(data)
            input.fileHandleForWriting.write(Data([0x0A]))
        }

        let timeout = DispatchSource.makeTimerSource(queue: .global(qos: .userInitiated))
        timeout.schedule(deadline: .now() + 20)
        timeout.setEventHandler {
            if process.isRunning { process.terminate() }
        }
        timeout.resume()
        defer { timeout.cancel() }

        var lineBuffer = Data()
        var response: Data?
        let outputHandle = output.fileHandleForReading
        while true {
            let data = outputHandle.availableData
            if data.isEmpty { break }
            lineBuffer.append(data)
            while let newline = lineBuffer.firstIndex(of: 0x0A) {
                let line = lineBuffer.prefix(upTo: newline)
                lineBuffer.removeSubrange(...newline)
                guard !line.isEmpty,
                      let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      (object["id"] as? Int) == responseID else {
                    continue
                }
                response = Data(line)
                if process.isRunning { process.terminate() }
                break
            }
            if response != nil { break }
        }
        process.waitUntilExit()

        guard let response else {
            let stderr = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            if stderr.localizedCaseInsensitiveContains("authentication required") {
                throw QuotaError.processFailed("\u{9700}\u{8981}\u{5728} cx \u{914D}\u{7F6E}\u{4E2D}\u{91CD}\u{65B0}\u{767B}\u{5F55}")
            }
            if process.terminationStatus == SIGTERM {
                throw QuotaError.timedOut
            }
            throw QuotaError.processFailed("Codex \u{8BF7}\u{6C42}\u{5931}\u{8D25}")
        }
        return response
    }

    private static func responseResult(from response: Data) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: response)
        guard let envelope = object as? [String: Any] else {
            throw QuotaError.invalidResponse
        }
        if let error = envelope["error"] as? [String: Any],
           let message = error["message"] as? String {
            throw QuotaError.server(message)
        }
        guard let result = envelope["result"] as? [String: Any] else {
            throw QuotaError.invalidResponse
        }
        return result
    }

    private static func accountInfo(from rateLimitResponse: Data) throws -> String? {
        let result = try responseResult(from: rateLimitResponse)
        return (result["rateLimits"] as? [String: Any])?["planType"] as? String
    }

    private static func resolvedExecutable() throws -> URL {
        let candidates = [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "/usr/bin/codex",
        ].map(URL.init(fileURLWithPath:))
        guard let executable = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else {
            throw QuotaError.executableUnavailable
        }
        return executable
    }
}
