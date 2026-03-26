import SwiftUI

@main
struct DesktopIconPositionApp: App {
    @State private var viewModel = AppViewModel()

    var body: some Scene {
        MenuBarExtra("Desktop Icons", systemImage: "desktopcomputer") {
            MenuBarView(viewModel: viewModel)
        }
    }

    init() {
        // Delay start until app is ready
        DispatchQueue.main.async { [self] in
            viewModel.start()
        }
    }
}
