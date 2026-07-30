import SwiftUI
import UIKit
import UniformTypeIdentifiers

final class KeyboardViewController: UIInputViewController {
    private let store = KeyboardStore()
    private var hostingController: UIHostingController<KeyboardRootView>?

    override func viewDidLoad() {
        super.viewDidLoad()

        let rootView = KeyboardRootView(
            store: store,
            hasFullAccess: hasFullAccess,
            onAdvanceToNextKeyboard: { [weak self] in
                self?.advanceToNextInputMode()
            },
            onCommit: { [weak self] clip in
                self?.commit(clip) ?? "Pesty is unavailable."
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
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            view.heightAnchor.constraint(equalToConstant: 340)
        ])
        hostingController.didMove(toParent: self)
        self.hostingController = hostingController
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        store.reload()
    }

    private func commit(_ clip: KeyboardClip) -> String {
        if clip.type == "text" || clip.type == "link" {
            guard let text = clip.text, !text.isEmpty else {
                return "This clip has no text."
            }
            textDocumentProxy.insertText(text)
            return clip.type == "link" ? "Link inserted." : "Text inserted."
        }

        guard hasFullAccess else {
            return "Enable Full Access to copy this clip."
        }

        switch clip.type {
        case "richText":
            var pasteboardItem: [String: Any] = [:]
            if let rtfData = clip.rtfData {
                pasteboardItem[UTType.rtf.identifier] = rtfData
            }
            if let text = clip.text {
                pasteboardItem[UTType.plainText.identifier] = text
            }
            UIPasteboard.general.setItems([pasteboardItem])
            return "Rich text copied. Tap Paste in the app."

        case "image":
            guard let fileName = clip.imageFileName,
                  let image = UIImage(
                    contentsOfFile: KeyboardSharedPaths.images
                        .appendingPathComponent(fileName)
                        .path
                  ) else {
                return "The cached image is unavailable."
            }
            UIPasteboard.general.image = image
            return "Image copied. Tap Paste in the app."

        case "file":
            UIPasteboard.general.urls = clip.resolvedFileURLs
            return "File reference copied. Tap Paste in the app."

        case "color":
            UIPasteboard.general.string = clip.colorHex
            return "Color copied. Tap Paste in the app."

        default:
            UIPasteboard.general.string = clip.text
            return "Clip copied. Tap Paste in the app."
        }
    }
}
