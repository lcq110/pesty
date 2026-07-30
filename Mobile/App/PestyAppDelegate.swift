import CloudKit
import UIKit

@MainActor
final class PestyAppDelegate: NSObject, UIApplicationDelegate {
    private var cloudChangeHandler: (() async -> Void)?
    private var shareHandler: ((CKShare.Metadata) async -> Void)?
    private var pendingCloudCompletions: [(UIBackgroundFetchResult) -> Void] = []
    private var pendingShares: [CKShare.Metadata] = []

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        guard let cloudChangeHandler else {
            pendingCloudCompletions.append(completionHandler)
            return
        }

        Task {
            await cloudChangeHandler()
            completionHandler(.newData)
        }
    }

    func application(
        _ application: UIApplication,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        guard let shareHandler else {
            pendingShares.append(cloudKitShareMetadata)
            return
        }

        Task {
            await shareHandler(cloudKitShareMetadata)
        }
    }

    func connect(
        onCloudChange: @escaping () async -> Void,
        onAcceptedShare: @escaping (CKShare.Metadata) async -> Void
    ) {
        cloudChangeHandler = onCloudChange
        shareHandler = onAcceptedShare

        let completions = pendingCloudCompletions
        let shares = pendingShares
        pendingCloudCompletions = []
        pendingShares = []

        Task {
            if !completions.isEmpty {
                await onCloudChange()
                completions.forEach { $0(.newData) }
            }
            for metadata in shares {
                await onAcceptedShare(metadata)
            }
        }
    }
}

actor MobileCloudSubscriptionService {
    private static let subscriptionID = "PestyPrivateDatabaseChanges"
    private let database: CKDatabase

    init(containerIdentifier: String) {
        database = CKContainer(identifier: containerIdentifier).privateCloudDatabase
    }

    func prepare() async throws {
        do {
            _ = try await database.subscription(for: Self.subscriptionID)
            return
        } catch let error as CKError where error.code == .unknownItem {
            let subscription = CKDatabaseSubscription(subscriptionID: Self.subscriptionID)
            let notificationInfo = CKSubscription.NotificationInfo()
            notificationInfo.shouldSendContentAvailable = true
            subscription.notificationInfo = notificationInfo

            let result = try await database.modifySubscriptions(
                saving: [subscription],
                deleting: []
            )
            _ = try result.saveResults[Self.subscriptionID]!.get()
        }
    }
}
