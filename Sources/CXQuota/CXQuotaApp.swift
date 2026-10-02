import SwiftUI

@main
struct CXQuotaApp: App {
    @NSApplicationDelegateAdaptor(StatusBarController.self) private var statusBarController

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
