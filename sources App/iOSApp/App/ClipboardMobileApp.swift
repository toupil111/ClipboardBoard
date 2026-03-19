import SwiftUI

@main
struct ClipboardMobileApp: App {
    @StateObject private var viewModel = ClipboardListViewModel()

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                ClipboardListView(viewModel: viewModel)
            }
            .onOpenURL { url in
                viewModel.handleDeepLink(url)
            }
        }
    }
}
