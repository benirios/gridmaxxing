import AppKit
import ApplicationServices
import PrivateBridge

struct GridFailure: LocalizedError {
    let message: String
    let transient: Bool
    init(_ message: String, transient: Bool = false) { self.message = message; self.transient = transient }
    var errorDescription: String? { message }
}

struct DesktopState {
    let ids: [UInt64]
    let current: UInt64
}

final class AnchorWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

/// Private calls are symbol-checked in PrivateBridge; never injects into the Dock.
final class Spaces {
    private var anchors: [UInt64: AnchorWindow] = [:]
    private var rememberedWindows: [UInt64: AXUIElement] = [:]

    func read() throws -> DesktopState {
        var displayCount: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &displayCount) == .success, displayCount > 0 else {
            throw GridFailure("Cannot access the desktop session right now.", transient: true)
        }
        guard displayCount == 1 else { throw GridFailure("Connect only one display for this prototype.") }
        guard MGSpacesAvailable() else { throw GridFailure("This macOS version does not expose the required Spaces APIs.") }
        guard let displays = MGCopyDisplays() as? [[String: Any]], displays.count == 1,
              let display = displays.first,
              let entries = display["Spaces"] as? [[String: Any]],
              let current = display["Current Space"] as? [String: Any],
              let currentID = number(current) else { throw GridFailure("Cannot read this display’s Spaces layout right now.", transient: true) }
        let ordinaryCount = entries.filter { ($0["type"] as? NSNumber)?.intValue == 0 }.count
        guard ordinaryCount == entries.count else {
            throw GridFailure("Found \(ordinaryCount) desktops and \(entries.count - ordinaryCount) full-screen or unsupported Spaces. Exit full-screen apps first.")
        }
        guard (4...16).contains(entries.count) else {
            throw GridFailure("Found \(entries.count) desktops. This prototype supports 4–16 ordinary desktops; add desktops in Mission Control.")
        }
        let ids = entries.compactMap(number)
        guard ids.count == entries.count, Set(ids).count == entries.count, ids.contains(currentID) else {
            throw GridFailure("Spaces returned an unsupported layout. Switching is disabled.")
        }
        return DesktopState(ids: ids, current: currentID)
    }

    private func number(_ entry: [String: Any]) -> UInt64? {
        ((entry["ManagedSpaceID"] ?? entry["id64"]) as? NSNumber)?.uint64Value
    }

    func prepare(_ state: DesktopState) throws {
        clear()
        guard let screen = NSScreen.screens.first else { throw GridFailure("No display found.") }
        for id in state.ids {
            let window = AnchorWindow(contentRect: NSRect(x: screen.frame.midX, y: screen.frame.midY, width: 1, height: 1),
                                      styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.alphaValue = 0.01
            window.ignoresMouseEvents = true
            window.collectionBehavior = [.ignoresCycle]
            window.title = "MissionGrid anchor"
            window.orderFront(nil)
            anchors[id] = window
            guard MGMoveWindow(UInt32(window.windowNumber), id) else {
                clear(); throw GridFailure("macOS refused to place a desktop anchor. Switching is disabled.")
            }
        }
    }

    func rememberFocus(on id: UInt64) {
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != getpid() else { return }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &value) == .success,
           let value, CFGetTypeID(value) == AXUIElementGetTypeID() {
            let window = value as! AXUIElement
            if MGWindowInSpace(MGAXWindowID(window), id) { rememberedWindows[id] = window }
        }
    }

    func switchTo(_ id: UInt64) throws {
        guard let window = anchors[id], MGWindowInSpace(UInt32(window.windowNumber), id) else {
            throw GridFailure("The destination anchor is missing. Pause and start again.")
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func switchInstantly(from source: Int, to target: Int) throws {
        guard source != target, (1...4).contains(abs(target - source)),
              MGInstantSwitch(Int32(abs(target - source)), target > source) else {
            throw GridFailure("Could not prepare the vertical Space switch. Navigation was paused.")
        }
    }

    /// Raise a verified window on the destination before activating its owner,
    /// preventing activation of an unrelated window on another Space.
    func restoreFocus(on id: UInt64) -> Bool {
        if let window = rememberedWindows[id], focus(window, on: id) { return true }
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for info in windows where (info[kCGWindowLayer as String] as? Int) == 0 {
            guard let pid = info[kCGWindowOwnerPID as String] as? Int32, pid != getpid(),
                  let number = info[kCGWindowNumber as String] as? UInt32,
                  MGWindowInSpace(number, id) else { continue }
            var value: CFTypeRef?
            let app = AXUIElementCreateApplication(pid)
            guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
                  let candidates = value as? [AXUIElement] else { continue }
            for candidate in candidates where MGAXWindowID(candidate) == number {
                if focus(candidate, on: id) { rememberedWindows[id] = candidate; return true }
            }
        }
        // An empty desktop should accept keyboard commands in Finder.
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first?.activate(options: [])
        return false
    }

    private func focus(_ window: AXUIElement, on id: UInt64) -> Bool {
        guard MGWindowInSpace(MGAXWindowID(window), id) else { return false }
        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success,
              AXUIElementPerformAction(window, kAXRaiseAction as CFString) == .success else { return false }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(app, kAXFocusedWindowAttribute as CFString, window)
        return NSRunningApplication(processIdentifier: pid)?.activate(options: []) ?? false
    }

    func hasFocusedWindow(on id: UInt64) -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != getpid() else { return false }
        var value: CFTypeRef?
        let element = AXUIElementCreateApplication(app.processIdentifier)
        guard AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return false }
        return MGWindowInSpace(MGAXWindowID(value), id)
    }

    func clear() {
        anchors.values.forEach { $0.close() }
        anchors.removeAll()
        rememberedWindows.removeAll()
    }
}
