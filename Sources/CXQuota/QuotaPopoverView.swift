import CXQuotaCore
import SwiftUI

struct QuotaPopoverView: View {
    @ObservedObject var store: QuotaStore
    @State private var showsAddAccount = false
    @State private var showsResetCredits = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            if store.snapshots.isEmpty {
                ContentUnavailableView("尚未刷新", systemImage: "gauge.with.dots.needle.33percent", description: Text("点击刷新读取 cx 配置的额度"))
                    .frame(maxWidth: .infinity, minHeight: 190)
            } else {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                        ForEach(displayedSnapshots) { snapshot in
                            if showsResetCredits {
                                ResetCreditCard(
                                    snapshot: snapshot,
                                    isConsuming: store.isConsumingReset,
                                    onConsume: { store.consumeReset(profile: snapshot.profile, credit: $0) }
                                )
                            } else {
                                ProfileCard(
                                    snapshot: snapshot,
                                    isRefreshPaused: store.isRefreshPaused(for: snapshot.profile),
                                    onPauseChange: { store.setRefreshPaused($0, for: snapshot.profile) },
                                    onLogout: { store.logoutAndRemove(profile: snapshot.profile) }
                                )
                            }
                        }
                    }
                }
                .frame(minHeight: 270, maxHeight: 270)
                .transaction { $0.animation = nil }
            }
            Divider()
            HStack {
                if store.isRefreshing {
                    ProgressView().controlSize(.small)
                    Text("正在刷新").font(.caption).foregroundStyle(.secondary)
                } else if let latestUpdateText {
                    Text(latestUpdateText).font(.caption).foregroundStyle(.secondary)
                }
                Button { store.refresh() } label: {
                    Label(store.isRefreshing ? "正在刷新" : "刷新", systemImage: "arrow.clockwise")
                }
                .disabled(store.isRefreshing)
                Button { showsResetCredits.toggle() } label: {
                    Label(showsResetCredits ? "返回额度" : "重置次数", systemImage: showsResetCredits ? "gauge.with.dots.needle.33percent" : "arrow.counterclockwise")
                }
                .disabled(store.isRefreshing)
                Spacer()
                Button("退出") { NSApplication.shared.terminate(nil) }
            }
        }
        .padding(16)
        .frame(width: 560)
        .sheet(isPresented: $showsAddAccount) {
            AddAccountSheet { store.refresh() }
        }
        .alert(
            "重置失败",
            isPresented: Binding(get: { store.actionError != nil }, set: { if !$0 { store.clearActionError() } })
        ) {
            Button("好") { store.clearActionError() }
        } message: {
            Text(store.actionError ?? "")
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Label("CX 额度", systemImage: "gauge.with.dots.needle.33percent")
                .font(.headline)
            Spacer()
            Button { showsAddAccount = true } label: {
                Image(systemName: "plus")
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help("添加账号")
            .accessibilityLabel("添加账号")
        }
    }

    private var latestUpdateText: String? {
        guard let date = store.snapshots.compactMap(\.updatedAt).max() else { return nil }
        let minutes = max(0, Int(Date().timeIntervalSince(date) / 60))
        if minutes < 1 { return "刚刚刷新" }
        if minutes < 60 { return "\(minutes)分前刷新" }
        let hours = minutes / 60
        return "\(hours)小时\(minutes % 60)分前刷新"
    }

    private var displayedSnapshots: [QuotaSnapshot] {
        guard showsResetCredits else { return store.snapshots }
        return store.snapshots.sorted {
            if $0.needsReset != $1.needsReset { return $0.needsReset }
            return $0.profile.localizedStandardCompare($1.profile) == .orderedAscending
        }
    }
}
