import CXQuotaCore
import Foundation
import SwiftUI

@MainActor
final class QuotaStore: ObservableObject {
    private static let pausedProfilesKey = "pausedProfiles"

    @Published private(set) var snapshots: [QuotaSnapshot]
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefreshStartedAt: Date?
    @Published private(set) var pausedProfiles: Set<String>
    @Published private(set) var isConsumingReset = false
    @Published private(set) var actionError: String?

    init(snapshots: [QuotaSnapshot] = QuotaCache.load(), pausedProfiles: Set<String>? = nil) {
        self.snapshots = snapshots.sorted { $0.profile.localizedStandardCompare($1.profile) == .orderedAscending }
        self.pausedProfiles = pausedProfiles ?? Set(UserDefaults.standard.stringArray(forKey: Self.pausedProfilesKey) ?? [])
    }

    func isRefreshPaused(for profile: String) -> Bool {
        pausedProfiles.contains(profile)
    }

    func setRefreshPaused(_ paused: Bool, for profile: String) {
        if paused {
            pausedProfiles.insert(profile)
        } else {
            pausedProfiles.remove(profile)
        }
        UserDefaults.standard.set(pausedProfiles.sorted(), forKey: Self.pausedProfilesKey)
    }

    func logoutAndRemove(profile: String) {
        Task {
            switch await CXProfileManager.logoutAndRemove(profile: profile) {
            case .success:
                snapshots.removeAll { $0.profile == profile }
                pausedProfiles.remove(profile)
                UserDefaults.standard.set(pausedProfiles.sorted(), forKey: Self.pausedProfilesKey)
                try? QuotaCache.save(snapshots)
            case let .failure(error):
                merge(QuotaSnapshot(profile: profile, availability: .failed, errorMessage: error.localizedDescription))
            }
        }
    }

    func consumeReset(profile: String, credit: ResetCredit?) {
        guard !isConsumingReset,
              let account = ProfileDiscovery.profiles().first(where: { $0.name == profile }) else {
            actionError = "账号配置不可用"
            return
        }
        isConsumingReset = true
        Task {
            switch await AppServerClient.consumeReset(profile: account, creditID: credit?.id) {
            case .success:
                isConsumingReset = false
                refresh()
            case let .failure(error):
                isConsumingReset = false
                actionError = error.localizedDescription
            }
        }
    }

    func clearActionError() {
        actionError = nil
    }

    func refresh() {
        refresh(profiles: ProfileDiscovery.profiles())
    }

    func refreshOnOpen() {
        let profiles = ProfileDiscovery.profiles()
        if profiles.isEmpty {
            snapshots = [QuotaSnapshot(profile: "cx", availability: .failed, errorMessage: "\u{672A}\u{627E}\u{5230} cx \u{914D}\u{7F6E}")]
            return
        }
        ensureSnapshots(for: profiles)
        let profilesNeedingRefresh = profiles.filter { profile in
            guard let snapshot = snapshots.first(where: { $0.profile == profile.name }) else { return true }
            return snapshot.requiresAutomaticRefresh()
        }
        refresh(profiles: profilesNeedingRefresh)
    }

    private func refresh(profiles: [CodexProfile]) {
        guard !isRefreshing else { return }
        if profiles.isEmpty { return }
        isRefreshing = true
        lastRefreshStartedAt = Date()
        ensureSnapshots(for: profiles)
        let refreshableProfiles = profiles.filter { !isRefreshPaused(for: $0.name) }
        if refreshableProfiles.isEmpty {
            isRefreshing = false
            return
        }

        Task {
            for batch in refreshableProfiles.chunked(into: 2) {
                await withTaskGroup(of: QuotaSnapshot.self) { group in
                    for profile in batch {
                        group.addTask { await AppServerClient.fetch(profile: profile) }
                    }
                    for await snapshot in group {
                        merge(snapshot)
                    }
                }
            }
            isRefreshing = false
            try? QuotaCache.save(snapshots)
        }
    }

    private func merge(_ incoming: QuotaSnapshot) {
        guard !isRefreshPaused(for: incoming.profile) else { return }
        if let index = snapshots.firstIndex(where: { $0.profile == incoming.profile }) {
            if incoming.availability == .failed, let previous = snapshots[index].updatedAt {
                snapshots[index] = snapshots[index].failing(with: incoming.errorMessage ?? "\u{67E5}\u{8BE2}\u{5931}\u{8D25}")
                if snapshots[index].updatedAt == nil {
                    snapshots[index] = QuotaSnapshot(profile: incoming.profile, availability: .failed, updatedAt: previous, errorMessage: incoming.errorMessage)
                }
            } else {
                snapshots[index] = incoming
            }
        } else {
            snapshots.append(incoming)
        }
        snapshots.sort { $0.profile.localizedStandardCompare($1.profile) == .orderedAscending }
    }

    private func ensureSnapshots(for profiles: [CodexProfile]) {
        for profile in profiles where !snapshots.contains(where: { $0.profile == profile.name }) {
            snapshots.append(QuotaSnapshot(profile: profile.name, availability: .unavailable))
        }
        snapshots.sort { $0.profile.localizedStandardCompare($1.profile) == .orderedAscending }
    }
}

private extension Array {
    func chunked(into size: Int) -> [ArraySlice<Element>] {
        stride(from: 0, to: count, by: size).map { self[$0..<Swift.min($0 + size, count)] }
    }
}
