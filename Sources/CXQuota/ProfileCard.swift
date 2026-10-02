import CXQuotaCore
import SwiftUI

struct ProfileCard: View {
    let snapshot: QuotaSnapshot
    let isRefreshPaused: Bool
    let isRefreshing: Bool
    let isLoggingIn: Bool
    let onPauseChange: (Bool) -> Void
    let onRelogin: () -> Void
    let onCancelLogin: () -> Void
    let onLogout: () -> Void
    @State private var showsLogoutConfirmation = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(snapshot.profile).font(.headline)
                    if isLoggingIn {
                        Text("等待登录").font(.caption)
                    } else if isRefreshPaused {
                        Text("已暂停").font(.caption)
                    }
                }
                if snapshot.windows.isEmpty {
                    Text(snapshot.availability == .failed ? "本次未获得额度数据" : "额度未提供")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(snapshot.windows) { window in
                            QuotaRing(
                                window: window,
                                isMuted: snapshot.requiresRelogin,
                                isRefreshPaused: isRefreshPaused,
                                isPauseControlEnabled: !snapshot.requiresRelogin && !isLoggingIn,
                                onTogglePause: { onPauseChange(!isRefreshPaused) }
                            )
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
                Spacer(minLength: 0)
                errorFooter
            }
            HStack(spacing: 4) {
                if snapshot.requiresRelogin {
                    Button("重新登录", action: onRelogin)
                        .controlSize(.small)
                        .buttonStyle(.bordered)
                        .disabled(isRefreshing || isLoggingIn)
                }
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
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 170, maxHeight: 170, alignment: .topLeading)
        .foregroundStyle(isRefreshPaused || isRefreshing || isLoggingIn ? .secondary : .primary)
        .grayscale(isRefreshPaused || isRefreshing || isLoggingIn ? 1 : 0)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(snapshot.requiresRelogin ? .red.opacity(0.32) : .primary.opacity(0.12), lineWidth: 1))
        .overlay {
            if isLoggingIn { LoginOverlay(onCancel: onCancelLogin) }
            else if isRefreshing { RefreshOverlay().allowsHitTesting(false) }
        }
        .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
        .confirmationDialog("退出 \(snapshot.profile)？", isPresented: $showsLogoutConfirmation, titleVisibility: .visible) {
            Button("退出", role: .destructive) { onLogout() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这会执行官方退出，并删除该账号的本地认证、配置、会话和缓存。")
        }
    }

    @ViewBuilder
    private var errorFooter: some View {
        if snapshot.availability == .failed, let error = snapshot.errorMessage {
            HStack(alignment: .top, spacing: 4) {
                Image(systemName: snapshot.requiresRelogin ? "person.crop.circle.badge.exclamationmark" : "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 1) {
                    Text(error).lineLimit(2)
                        .foregroundStyle(snapshot.requiresRelogin ? Color.primary : Color.red)
                }
            }
            .font(.caption2)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var cardBackground: Color {
        if snapshot.requiresRelogin { return .red.opacity(0.07) }
        if isRefreshPaused { return .gray.opacity(0.28) }
        return Color(nsColor: .windowBackgroundColor)
    }

}

struct QuotaRing: View {
    let window: QuotaWindow
    let isMuted: Bool
    let isRefreshPaused: Bool
    let isPauseControlEnabled: Bool
    let onTogglePause: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            Button(action: onTogglePause) {
                ZStack {
                    Circle().stroke(.quaternary, lineWidth: 7)
                    Circle()
                        .trim(from: 0, to: Double(window.remainingPercent) / 100)
                        .stroke(isMuted ? .gray : (window.remainingPercent < 20 ? .red : .green), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("\(window.remainingPercent)%").font(.caption.weight(.semibold).monospacedDigit())
                        Text(QuotaCountdown.compactText(until: window.resetsAt))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 64, height: 64)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!isPauseControlEnabled)
            .help(isRefreshPaused ? "点击恢复该账号刷新" : "点击暂停该账号刷新")
            .accessibilityLabel("\(window.name)，\(isRefreshPaused ? "已暂停，点按恢复刷新" : "点按暂停刷新")")
            Text(window.name == "5H 限额" ? QuotaCountdown.timeOfDay(until: window.resetsAt) : QuotaCountdown.monthDayHour(until: window.resetsAt))
                .font(.caption.weight(.medium).monospacedDigit())
        }
    }
}
