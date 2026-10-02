import SwiftUI

struct LoginOverlay: View {
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor).opacity(0.78)
            VStack(spacing: 8) {
                ProgressView().controlSize(.regular)
                Text("等待登录完成").font(.caption.weight(.medium))
                Button("取消登录", role: .cancel, action: onCancel)
                    .controlSize(.small)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityLabel("等待登录完成，可取消登录")
    }
}
