import CXQuotaCore
import SwiftUI

struct AddAccountSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var profileName = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    let onComplete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("添加 Codex 账号")
                .font(.headline)
            Text("输入一个新配置名。随后会打开官方浏览器登录流程。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            TextField("配置名，例如 work", text: $profileName)
                .textFieldStyle(.roundedBorder)
                .disabled(isWorking)
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .disabled(isWorking)
                Button(isWorking ? "等待登录完成" : "创建并登录") {
                    createAndLogin()
                }
                .disabled(profileName.isEmpty || isWorking)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    private func createAndLogin() {
        isWorking = true
        errorMessage = nil
        let name = profileName
        Task {
            switch await CXProfileManager.createAndLogin(profile: name) {
            case .success:
                onComplete()
                dismiss()
            case let .failure(error):
                errorMessage = error.localizedDescription
                isWorking = false
            }
        }
    }
}
