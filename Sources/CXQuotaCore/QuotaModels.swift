import Foundation

public struct QuotaWindow: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let usedPercent: Int
    public let windowDurationMins: Int
    public let resetsAt: Date?

    public init(id: String, name: String, usedPercent: Int, windowDurationMins: Int, resetsAt: Date?) {
        self.id = id
        self.name = name
        self.usedPercent = usedPercent
        self.windowDurationMins = windowDurationMins
        self.resetsAt = resetsAt
    }

    public var remainingPercent: Int {
        max(0, min(100, 100 - usedPercent))
    }
}

public enum QuotaAvailability: String, Codable, Equatable, Sendable {
    case available
    case unavailable
    case failed
}

public struct ResetCredit: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let expiresAt: Date?

    public init(id: String, expiresAt: Date?) {
        self.id = id
        self.expiresAt = expiresAt
    }
}

public struct QuotaSnapshot: Codable, Equatable, Identifiable, Sendable {
    public let profile: String
    public let planType: String?
    public let windows: [QuotaWindow]
    public let availability: QuotaAvailability
    public let updatedAt: Date?
    public let errorMessage: String?
    public let availableResetCreditCount: Int?
    public let resetCredits: [ResetCredit]?

    public init(
        profile: String,
        planType: String? = nil,
        windows: [QuotaWindow] = [],
        availability: QuotaAvailability,
        updatedAt: Date? = nil,
        errorMessage: String? = nil,
        availableResetCreditCount: Int? = nil,
        resetCredits: [ResetCredit]? = nil
    ) {
        self.profile = profile
        self.planType = planType
        self.windows = windows
        self.availability = availability
        self.updatedAt = updatedAt
        self.errorMessage = errorMessage
        self.availableResetCreditCount = availableResetCreditCount
        self.resetCredits = resetCredits
    }

    public var id: String { profile }

    public var resetCreditCount: Int {
        availableResetCreditCount ?? resetCredits?.count ?? 0
    }

    public var needsResetCreditDetailRefresh: Bool {
        resetCreditCount > 0 && resetCredits == nil
    }

    public var weeklyWindow: QuotaWindow? {
        windows.first { $0.name == "周限额" }
    }

    public var fiveHourWindow: QuotaWindow? {
        windows.first { $0.name == "5H 限额" }
    }

    public var expiringResetCreditsBeforeWeeklyReset: [ResetCredit] {
        guard let weeklyReset = weeklyWindow?.resetsAt else { return [] }
        return (resetCredits ?? []).filter { credit in
            guard let expiration = credit.expiresAt else { return false }
            return expiration <= weeklyReset
        }
    }

    public var needsReset: Bool {
        weeklyWindow?.remainingPercent == 0 && !expiringResetCreditsBeforeWeeklyReset.isEmpty
    }

    public func requiresAutomaticRefresh(at now: Date = Date()) -> Bool {
        guard let updatedAt else { return true }
        if needsResetCreditDetailRefresh { return true }
        return windows.contains { window in
            guard window.remainingPercent == 0, let resetAt = window.resetsAt else { return false }
            return updatedAt < resetAt && resetAt <= now
        }
    }

    public func failing(with message: String) -> QuotaSnapshot {
        QuotaSnapshot(
            profile: profile,
            planType: planType,
            windows: windows,
            availability: .failed,
            updatedAt: updatedAt,
            errorMessage: message,
            availableResetCreditCount: availableResetCreditCount,
            resetCredits: resetCredits
        )
    }
}
