import CXQuotaCore
import SwiftUI

struct ProfileCard: View {
    let snapshot: QuotaSnapshot
    let isRefreshPaused: Bool
    let onPauseChange: (Bool) -> Void
    let onLogout: () -> Void
    @State private var showsLogoutConfirmation = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button { onPauseChange(!isRefreshPaused) } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(snapshot.profile).font(.headline)
                        if isRefreshPaused { Text("已暂停").font(.caption) }
                    }
                    if snapshot.windows.isEmpty {
                        Text(snapshot.availability == .failed ? (snapshot.errorMessage ?? "查询失败") : "额度未提供")
                            .font(.caption)
                            .foregroundStyle(snapshot.availability == .failed ? .red : .secondary)
                    } else {
                        HStack(alignment: .top, spacing: 8) {
                            ForEach(snapshot.windows) { window in
                                QuotaRing(window: window).frame(maxWidth: .infinity)
                            }
                        }
                        if snapshot.availability == .failed, let error = snapshot.errorMessage {
                            Text("本次刷新失败：\(error)").font(.caption).foregroundStyle(.red)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isRefreshPaused ? "\(snapshot.profile)，已暂停刷新，点按恢复" : "\(snapshot.profile)，点按暂停刷新")
            Menu {
                Button("退出", role: .destructive) { showsLogoutConfirmation = true }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help("账号操作")
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 130, maxHeight: 130, alignment: .topLeading)
        .foregroundStyle(isRefreshPaused ? .secondary : .primary)
        .grayscale(isRefreshPaused ? 1 : 0)
        .background(isRefreshPaused ? Color.gray.opacity(0.28) : Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.primary.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
        .confirmationDialog("退出 \(snapshot.profile)？", isPresented: $showsLogoutConfirmation, titleVisibility: .visible) {
            Button("退出", role: .destructive) { onLogout() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这会执行官方退出，并删除该账号的本地认证、配置、会话和缓存。")
        }
    }
}

struct QuotaRing: View {
    let window: QuotaWindow

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle().stroke(.quaternary, lineWidth: 7)
                Circle()
                    .trim(from: 0, to: Double(window.remainingPercent) / 100)
                    .stroke(window.remainingPercent < 20 ? .red : .green, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(window.remainingPercent)%").font(.caption.weight(.semibold).monospacedDigit())
            }
            .frame(width: 58, height: 58)
            Text(window.name).font(.caption.weight(.medium))
            Text(QuotaCountdown.text(until: window.resetsAt))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}
