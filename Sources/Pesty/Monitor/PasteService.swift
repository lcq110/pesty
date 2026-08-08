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
            if mode == .formatted, let rtf = item.rtfData {
                pasteboard.setData(rtf, forType: .rtf)
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
        waitForFrontmost(target, attempts: 20)
        #endif
    }

    #if !MAS
    private static func waitForFrontmost(_ app: NSRunningApplication, attempts: Int) {
        guard attempts > 0, !app.isTerminated else { return }
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier {
            waitForShiftRelease()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
            waitForFrontmost(app, attempts: attempts - 1)
        }
    }

    private static func waitForShiftRelease() {
        if CGEventSource.flagsState(.combinedSessionState).contains(.maskShift) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                waitForShiftRelease()
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
}
