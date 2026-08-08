import AppKit
import Carbon.HIToolbox

@MainActor
enum PasteService {
    enum PasteMode {
        case formatted
        case plainText
    }

    @discardableResult
    static func copy(_ item: ClipItem,
                     mode: PasteMode = .formatted,
                     to pasteboard: NSPasteboard = .general) -> Int {
        if item.type == .image {
            guard let img = ClipboardStore.shared.loadImage(for: item) else {
                return pasteboard.changeCount
            }
            pasteboard.clearContents()
            pasteboard.writeObjects([img])
            return pasteboard.changeCount
        }
        pasteboard.clearContents()
        switch item.type {
        case .image:
            break
        case .file:
            let urls = ClipboardStore.shared.resolvedFileURLs(for: item)
            if !urls.isEmpty { pasteboard.writeObjects(urls as [NSURL]) }
            if let t = item.text { pasteboard.setString(t, forType: .string) }
        case .color:
            if let hex = item.colorHex, let c = NSColor(hex: hex) {
                pasteboard.writeObjects([c])
                pasteboard.setString(hex, forType: .string)
            }
        case .richText:
            if mode == .formatted {
                if let rtf = item.rtfData {
                    pasteboard.setData(rtf, forType: .rtf)
                }
                if let html = item.htmlData ?? convertedHTML(from: item.rtfData) {
                    pasteboard.setData(html, forType: .html)
                    pasteboard.setData(html, forType: .legacyHTML)
                }
            }
            if let t = item.text { pasteboard.setString(t, forType: .string) }
        case .text, .link:
            if let t = item.text { pasteboard.setString(t, forType: .string) }
        }
        return pasteboard.changeCount
    }

    static func paste(_ item: ClipItem,
                      into targetApp: NSRunningApplication?,
                      monitor: ClipboardMonitor,
                      mode: PasteMode = .formatted) {
        let change = copy(item, mode: mode)
        monitor.suppressUntilChangeCount = change
        if Settings.shared.playSound { NSSound(named: "Pop")?.play() }

        guard let target = targetApp, !target.isTerminated else { return }

        #if MAS
        // Mac App Store (sandboxed) build: copy the clip and return focus to the
        // app the user came from so they can paste with ⌘V. No Accessibility
        // APIs and no synthetic keystrokes are used.
        target.activate()
        #else
        // Direct-download build: optionally paste straight into the active app by
        // synthesizing ⌘V. This requires the user's Accessibility grant.
        guard Settings.shared.pasteDirectly else { return }
        guard AXIsProcessTrusted() else {
            ensureAccessibility(prompt: true)
            return
        }
        target.activate()
        pasteWhenReady(target, attempts: 100)
        #endif
    }

    #if !MAS
    private static func pasteWhenReady(_ app: NSRunningApplication, attempts: Int) {
        guard !app.isTerminated else { return }
        let isFrontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
            == app.processIdentifier
        if !isFrontmost {
            guard attempts > 0 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                pasteWhenReady(app, attempts: attempts - 1)
            }
            return
        }

        if CGEventSource.flagsState(.combinedSessionState).contains(.maskShift) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                pasteWhenReady(app, attempts: attempts)
            }
            return
        }
        sendCommandV()
    }

    private static func sendCommandV() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let v = CGKeyCode(kVK_ANSI_V)
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: false) else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    @discardableResult
    static func ensureAccessibility(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let opts = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }
    #endif

    private static func convertedHTML(from rtfData: Data?) -> Data? {
        guard let rtfData,
              let attributed = try? NSAttributedString(
                data: rtfData,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
              ) else { return nil }
        return try? attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.html]
        )
    }
}
