import SwiftUI

@main
struct KeyBloomApp: App {
    @StateObject private var store = StatsStore()

    var body: some Scene {
        MenuBarExtra {
            DashboardView()
                .environmentObject(store)
        } label: {
            Image(systemName: "keyboard")
        }
        .menuBarExtraStyle(.window)
    }
}
