import SwiftUI
import UIKit

final class ShareViewController: UIViewController {
    private var model: ShareModel?

    override func viewDidLoad() {
        super.viewDidLoad()

        let providers = extensionContext?.inputItems
            .compactMap { $0 as? NSExtensionItem }
            .flatMap { $0.attachments ?? [] }
            ?? []

        let model = ShareModel(providers: providers)
        let rootView = ShareRootView(
            model: model,
            onCancel: { [weak self] in
                self?.cancel()
            },
            onSave: { [weak self] in
                self?.save()
            }
        )

        let hostingController = UIHostingController(rootView: rootView)
        addChild(hostingController)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        hostingController.didMove(toParent: self)

        self.model = model
        model.load()
    }

    private func cancel() {
        let error = NSError(
            domain: NSCocoaErrorDomain,
            code: NSUserCancelledError
        )
        extensionContext?.cancelRequest(withError: error)
    }

    private func save() {
        do {
            try model?.save()
            extensionContext?.completeRequest(returningItems: nil)
        } catch {
            model?.errorMessage = error.localizedDescription
        }
    }
}
