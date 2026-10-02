import CXQuotaCore
import SwiftUI

struct ResetCreditCard: View {
    let snapshot: QuotaSnapshot
    let isConsuming: Bool
    let onConsume: (ResetCredit?) -> Void
    @State private var selectedCredit: ResetCredit?
    @State private var showsConsumeConfirmation = false

    var body: some View {
        Button {
            selectedCredit = earliestCredit
            showsConsumeConfirmation = true
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(snapshot.profile).font(.headline)
                    Spacer()
                    if snapshot.needsReset {
                        Label("建议重置", systemImage: "exclamationmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 10) {
                        QuotaStatusColumn(label: "5H", window: snapshot.fiveHourWindow)
                        QuotaStatusColumn(label: "W", window: snapshot.weeklyWindow)
                    }
                    .frame(width: 44, alignment: .leading)
                    Divider()
                    resetCreditRows.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!canConsume || isConsuming)
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
        .background(snapshot.needsReset ? Color.orange.opacity(0.13) : Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.primary.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
        .confirmationDialog("确认使用重置卡？", isPresented: $showsConsumeConfirmation, titleVisibility: .visible) {
            Button("确认重置", role: .destructive) {
                onConsume(selectedCredit)
                selectedCredit = nil
            }
            Button("取消", role: .cancel) { selectedCredit = nil }
        } message: {
            Text(confirmationDetails(for: selectedCredit))
        }
    }

    @ViewBuilder
    private var resetCreditRows: some View {
        let credits = snapshot.resetCredits ?? []
        if credits.isEmpty, snapshot.resetCreditCount == 0 {
            Text("无重置卡").font(.subheadline).foregroundStyle(.secondary)
        } else if credits.isEmpty {
            Text("到期日未提供").font(.subheadline).foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(credits.enumerated()), id: \.element.id) { index, credit in
                    Text("\(index + 1)   \(QuotaCountdown.compactText(until: credit.expiresAt))")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
        }
    }

    private var canConsume: Bool { snapshot.resetCreditCount > 0 }

    private var earliestCredit: ResetCredit? {
        (snapshot.resetCredits ?? []).min { ($0.expiresAt ?? .distantFuture) < ($1.expiresAt ?? .distantFuture) }
    }

    private func confirmationDetails(for credit: ResetCredit?) -> String {
        [
            "账号：\(snapshot.profile)",
            resetCreditDetail(credit),
            quotaDetail(label: "5H", window: snapshot.fiveHourWindow),
            quotaDetail(label: "周", window: snapshot.weeklyWindow),
        ].joined(separator: "\n")
    }

    private func resetCreditDetail(_ credit: ResetCredit?) -> String {
        guard let credit else { return "重置卡到期：官方服务未提供；将选择下一张可用重置卡" }
        return "重置卡到期：\(QuotaCountdown.text(until: credit.expiresAt))"
    }

    private func quotaDetail(label: String, window: QuotaWindow?) -> String {
        guard let window else { return "\(label) 限额：未提供" }
        return "\(label) 限额：剩余 \(window.remainingPercent)%；\(QuotaCountdown.text(until: window.resetsAt))重置"
    }
}

struct QuotaStatusColumn: View {
    let label: String
    let window: QuotaWindow?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(remainingText).font(.caption.monospacedDigit())
            Text(QuotaCountdown.compactText(until: window?.resetsAt))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private var remainingText: String {
        guard let window else { return "\(label) —" }
        return "\(label) \(window.remainingPercent)%"
    }
}
