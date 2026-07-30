import SwiftUI

struct RootView: View {
    @Environment(MobileClipboardStore.self) private var store

    var body: some View {
        @Bindable var store = store

        TabView(selection: $store.selectedTab) {
            NavigationStack {
                HistoryView()
            }
            .tabItem {
                Label("History", systemImage: "clock.arrow.circlepath")
            }
            .tag(MobileTab.history)

            NavigationStack {
                PinboardsView()
            }
            .tabItem {
                Label("Pinboards", systemImage: "pin.fill")
            }
            .tag(MobileTab.pinboards)

            NavigationStack {
                StackView()
            }
            .tabItem {
                Label("Stack", systemImage: "square.stack.3d.up.fill")
            }
            .badge(store.stack.count)
            .tag(MobileTab.stack)

            NavigationStack {
                MobileSettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape.fill")
            }
            .tag(MobileTab.settings)
        }
        .tint(PestyTheme.tint)
    }
}
