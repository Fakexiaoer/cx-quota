import SwiftUI

struct RefreshOverlay: View {
    let text: String

    init(_ text: String = "正在刷新") {
        self.text = text
    }

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor).opacity(0.72)
            VStack(spacing: 8) {
                ProgressView().controlSize(.regular)
                Text(text).font(.caption.weight(.medium))
            }
            .foregroundStyle(.secondary)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityLabel(text)
    }
}
