import Foundation

public enum QuotaParser {
    public static func snapshot(profile: String, planType: String?, responseData: Data, now: Date) throws -> QuotaSnapshot {
        let object = try JSONSerialization.jsonObject(with: responseData)
        guard let envelope = object as? [String: Any] else { throw QuotaError.invalidResponse }
        if let error = envelope["error"] as? [String: Any], let message = error["message"] as? String {
            throw QuotaError.server(message)
        }
        guard let result = envelope["result"] as? [String: Any] else { throw QuotaError.invalidResponse }

        let buckets = result["rateLimitsByLimitId"] as? [String: Any]
        let primaryBucket = result["rateLimits"] as? [String: Any]
        let resetCreditData = result["rateLimitResetCredits"] as? [String: Any]
        let resetCreditCount = resetCreditData?["availableCount"] as? Int
        let resetCredits = (resetCreditData?["credits"] as? [[String: Any]])?.compactMap { credit -> ResetCredit? in
            guard let id = credit["id"] as? String else { return nil }
            let expiresAt = (credit["expiresAt"] as? TimeInterval).map(Date.init(timeIntervalSince1970:))
            return ResetCredit(id: id, expiresAt: expiresAt)
        }.sorted { ($0.expiresAt ?? .distantFuture) < ($1.expiresAt ?? .distantFuture) }
        let windows = parseWindows(buckets: buckets, primaryBucket: primaryBucket)

        return QuotaSnapshot(
            profile: profile,
            planType: planType ?? (primaryBucket?["planType"] as? String),
            windows: windows,
            availability: windows.isEmpty ? .unavailable : .available,
            updatedAt: now,
            availableResetCreditCount: resetCreditCount,
            resetCredits: resetCredits
        )
    }

    private static func parseWindows(buckets: [String: Any]?, primaryBucket: [String: Any]?) -> [QuotaWindow] {
        if let buckets {
            return buckets.flatMap { limitID, value in
                [
                    window(from: value as? [String: Any], limitID: limitID, role: "primary"),
                    window(from: value as? [String: Any], limitID: limitID, role: "secondary", secondary: true),
                ].compactMap { $0 }
            }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        guard let primaryBucket else { return [] }
        return [
            window(from: primaryBucket, limitID: "codex", role: "primary"),
            window(from: primaryBucket, limitID: "codex", role: "secondary", secondary: true),
        ].compactMap { $0 }
    }

    private static func window(from bucket: [String: Any]?, limitID: String, role: String, secondary: Bool = false) -> QuotaWindow? {
        guard let bucket,
              let contents = bucket[secondary ? "secondary" : "primary"] as? [String: Any],
              let usedPercent = contents["usedPercent"] as? Int,
              let windowDurationMins = contents["windowDurationMins"] as? Int else {
            return nil
        }
        let reset = (contents["resetsAt"] as? TimeInterval).map(Date.init(timeIntervalSince1970:))
        return QuotaWindow(id: "\(limitID)-\(role)", name: secondary ? "周限额" : "5H 限额", usedPercent: usedPercent, windowDurationMins: windowDurationMins, resetsAt: reset)
    }
}
