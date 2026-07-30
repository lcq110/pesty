import SwiftUI

@main
struct PestyMobileApp: App {
    @UIApplicationDelegateAdaptor(PestyAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = MobileClipboardStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .task {
                    appDelegate.connect(
                        onCloudChange: {
                            await store.refreshFromCloud()
                        },
                        onAcceptedShare: { metadata in
                            await store.acceptShare(metadata)
                        }
                    )
                    store.setForegroundCaptureActive(scenePhase == .active)
                    await store.start()
                }
                .onOpenURL { url in
                    store.handle(url)
                }
                .onChange(of: scenePhase) { _, phase in
                    store.setForegroundCaptureActive(phase == .active)
                    guard phase == .active else { return }
                    store.consumeShareOutbox()
                    guard store.syncState != .syncing else { return }
                    Task {
                        await store.refreshFromCloud()
                    }
                }
        }
    }
}
