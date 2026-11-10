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
        paste([item], into: targetApp, monitor: monitor, mode: mode)
    }

    static func paste(_ items: [ClipItem],
                      into targetApp: NSRunningApplication?,
                      monitor: ClipboardMonitor,
                      mode: PasteMode = .formatted) {
        guard let first = items.first else { return }

        guard let target = targetApp, !target.isTerminated else {
            prepare(first, monitor: monitor, mode: mode)
            return
        }

        #if MAS
        prepare(first, monitor: monitor, mode: mode)
        target.activate()
        #else
        guard Settings.shared.pasteDirectly else {
            prepare(first, monitor: monitor, mode: mode)
            return
        }
        guard AXIsProcessTrusted() else {
            prepare(first, monitor: monitor, mode: mode)
            ensureAccessibility(prompt: true)
            return
        }
        target.activate()
        pasteWhenReady(items, at: 0, into: target, monitor: monitor, mode: mode, attempts: 100)
        #endif
    }

    private static func prepare(_ item: ClipItem,
                                monitor: ClipboardMonitor,
                                mode: PasteMode) {
        let change = copy(item, mode: mode)
        monitor.suppressUntilChangeCount = change
        if Settings.shared.playSound { NSSound(named: "Pop")?.play() }
    }

    #if !MAS
    private static func pasteWhenReady(_ items: [ClipItem],
                                       at index: Int,
                                       into app: NSRunningApplication,
                                       monitor: ClipboardMonitor,
                                       mode: PasteMode,
                                       attempts: Int) {
        guard !app.isTerminated else { return }
        let isFrontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
            == app.processIdentifier
        if !isFrontmost {
            guard attempts > 0 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                pasteWhenReady(items, at: index, into: app, monitor: monitor,
                               mode: mode, attempts: attempts - 1)
            }
            return
        }

        if CGEventSource.flagsState(.combinedSessionState).contains(.maskShift) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                pasteWhenReady(items, at: index, into: app, monitor: monitor,
                               mode: mode, attempts: attempts)
            }
            return
        }
        prepare(items[index], monitor: monitor, mode: mode)
        sendCommandV()

        let next = index + 1
        if next < items.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                pasteWhenReady(items, at: next, into: app, monitor: monitor,
                               mode: mode, attempts: 100)
            }
        }
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
