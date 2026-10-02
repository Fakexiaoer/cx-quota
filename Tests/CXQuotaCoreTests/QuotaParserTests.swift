import Foundation
import XCTest
@testable import CXQuotaCore

final class QuotaParserTests: XCTestCase {
    func testParsesMultipleBucketsAndPreservesResetTime() throws {
        let json = """
        {"id":2,"result":{"rateLimitsByLimitId":{"codex":{"limitId":"codex","primary":{"usedPercent":100,"windowDurationMins":300,"resetsAt":1790856264},"secondary":{"usedPercent":100,"windowDurationMins":10080,"resetsAt":1791400000}}},"rateLimitResetCredits":{"availableCount":2,"credits":[{"id":"credit-1","expiresAt":1791000000},{"id":"credit-2","expiresAt":1793000000}]}}}
        """.data(using: .utf8)!

        let snapshot = try QuotaParser.snapshot(profile: "primary", planType: "pro", responseData: json, now: Date(timeIntervalSince1970: 1))

        XCTAssertEqual(snapshot.availability, .available)
        XCTAssertEqual(snapshot.windows.count, 2)
        XCTAssertEqual(snapshot.windows.first?.remainingPercent, 0)
        XCTAssertEqual(snapshot.windows.first?.windowDurationMins, 300)
        XCTAssertEqual(snapshot.windows.map(\.name), ["5H 限额", "周限额"])
        XCTAssertEqual(snapshot.resetCreditCount, 2)
        XCTAssertEqual(snapshot.resetCredits?.count, 2)
        XCTAssertTrue(snapshot.needsReset)
        XCTAssertEqual(snapshot.expiringResetCreditsBeforeWeeklyReset.map(\.id), ["credit-1"])
    }

    func testMarksEmptyRateLimitResponseUnavailable() throws {
        let json = "{\"id\":2,\"result\":{\"rateLimits\":null}}".data(using: .utf8)!

        let snapshot = try QuotaParser.snapshot(profile: "sample", planType: nil, responseData: json, now: Date())

        XCTAssertEqual(snapshot.availability, .unavailable)
        XCTAssertTrue(snapshot.windows.isEmpty)
    }

    func testRejectsServerError() {
        let json = "{\"id\":2,\"error\":{\"message\":\"authentication required\"}}".data(using: .utf8)!

        XCTAssertThrowsError(try QuotaParser.snapshot(profile: "sample", planType: nil, responseData: json, now: Date()))
    }

    func testFormatsResetCountdownByHoursAndDays() {
        let now = Date(timeIntervalSince1970: 1_000_000)

        XCTAssertEqual(QuotaCountdown.text(until: now.addingTimeInterval(2 * 3_600 + 13 * 60), now: now), "2小时13分后")
        XCTAssertEqual(QuotaCountdown.text(until: now.addingTimeInterval(3 * 86_400 + 4 * 3_600 + 20 * 60), now: now), "3天4小时后")
        XCTAssertEqual(QuotaCountdown.compactText(until: now.addingTimeInterval(3 * 86_400 + 4 * 3_600 + 20 * 60), now: now), "3D 4H")
    }

    func testFormatsResetTimesForQuotaRings() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: 14, minute: 30))!

        XCTAssertEqual(QuotaCountdown.timeOfDay(until: date, calendar: calendar), "14:30")
        XCTAssertEqual(QuotaCountdown.monthDayHour(until: date, calendar: calendar), "10月2日14时")
    }

    func testRefreshesOnlyAfterAnExhaustedWindowHasReset() {
        let updatedAt = Date(timeIntervalSince1970: 1_000)
        let expiredReset = QuotaWindow(id: "5h", name: "5H 限额", usedPercent: 100, windowDurationMins: 300, resetsAt: Date(timeIntervalSince1970: 1_100))
        let futureReset = QuotaWindow(id: "week", name: "周限额", usedPercent: 100, windowDurationMins: 10_080, resetsAt: Date(timeIntervalSince1970: 1_300))
        let expiredSnapshot = QuotaSnapshot(profile: "a", windows: [expiredReset], availability: .available, updatedAt: updatedAt)
        let futureSnapshot = QuotaSnapshot(profile: "b", windows: [futureReset], availability: .available, updatedAt: updatedAt)

        XCTAssertTrue(expiredSnapshot.requiresAutomaticRefresh(at: Date(timeIntervalSince1970: 1_200)))
        XCTAssertFalse(futureSnapshot.requiresAutomaticRefresh(at: Date(timeIntervalSince1970: 1_200)))

        let missingCreditDetails = QuotaSnapshot(
            profile: "c",
            windows: [futureReset],
            availability: .available,
            updatedAt: updatedAt,
            availableResetCreditCount: 2
        )
        XCTAssertTrue(missingCreditDetails.requiresAutomaticRefresh(at: Date(timeIntervalSince1970: 1_200)))
    }

    func testRetriesOnlyTransientUsageTransportFailures() {
        XCTAssertTrue(AppServerClient.isTransient(.server("codex rate limits: error sending request for url (https://chatgpt.com/backend-api/wham/usage)")))
        XCTAssertFalse(AppServerClient.isTransient(.server("authentication required")))
    }

    func testDoesNotTreatRevokedOAuthTokenAsTransientUsageFailure() {
        let error = QuotaError.server("failed to fetch codex rate limits: GET https://chatgpt.com/backend-api/wham/usage failed: 401 Unauthorized; code=token_revoked")

        XCTAssertFalse(AppServerClient.isTransient(error))
        XCTAssertEqual(AppServerClient.displayMessage(for: error), "登录已失效，请重新登录此账号")
        XCTAssertTrue(QuotaSnapshot(profile: "sample", availability: .failed, errorMessage: AppServerClient.displayMessage(for: error)).requiresRelogin)

        let authenticationRequired = QuotaError.server("codex account authentication required to read rate limits")
        XCTAssertEqual(AppServerClient.displayMessage(for: authenticationRequired), "登录已失效，请重新登录此账号")
        XCTAssertTrue(QuotaSnapshot(profile: "sample", availability: .failed, errorMessage: authenticationRequired.localizedDescription).requiresRelogin)
    }

    func testValidatesProfileNamesBeforeCreatingAccounts() {
        XCTAssertTrue(CXProfileManager.isValidProfileName("work-2026"))
        XCTAssertTrue(CXProfileManager.isValidProfileName("personal.dev"))
        XCTAssertFalse(CXProfileManager.isValidProfileName("work account"))
        XCTAssertFalse(CXProfileManager.isValidProfileName("-work"))
    }

    func testIgnoresProfileDirectoriesWithNonprivatePermissions() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let profile = root.appendingPathComponent("private")
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertEqual(ProfileDiscovery.profiles(in: root).map(\.name), ["private"])

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: profile.path)
        XCTAssertTrue(ProfileDiscovery.profiles(in: root).isEmpty)
    }

    func testAcceptsOnlySuccessfulResetOutcomes() throws {
        let success = "{\"id\":1,\"result\":{\"outcome\":\"reset\"}}".data(using: .utf8)!
        let unavailable = "{\"id\":1,\"result\":{\"outcome\":\"noCredit\"}}".data(using: .utf8)!

        XCTAssertNoThrow(try AppServerClient.validateResetOutcome(success))
        XCTAssertThrowsError(try AppServerClient.validateResetOutcome(unavailable))
    }

    func testFetchesLiveProfileWhenExplicitlySelected() async throws {
        guard let requestedProfile = ProcessInfo.processInfo.environment["CX_QUOTA_LIVE_PROFILE"] else {
            throw XCTSkip("Set CX_QUOTA_LIVE_PROFILE to run the local official app-server integration check.")
        }
        guard let profile = ProfileDiscovery.profiles().first(where: { $0.name == requestedProfile }) else {
            throw XCTSkip("Requested local profile does not exist.")
        }

        let snapshot = await AppServerClient.fetch(profile: profile)

        XCTAssertNotEqual(snapshot.availability, .failed, snapshot.errorMessage ?? "Live app-server query failed.")
    }
}
