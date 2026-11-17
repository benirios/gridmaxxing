import AppKit
import Combine
import ApplicationServices
import GridCore
import PrivateBridge
import OSLog

private weak var touchRecipient: Controller?
private let log = Logger(subsystem: "local.MissionGrid", category: "handoff")

@MainActor final class Controller: ObservableObject {
    @Published var enabled = false
    @Published var status = "Checking desktop setup…"
    @Published var currentIndex = 0
    @Published var capturedCount = 0
    @Published var canStart = false
    @Published var desktopCount = 0
    @Published var gridColumns = 2
    @Published var gridRows = 2
    @Published var startIssue: String?
    @Published var gesturesConfirmed = false
    @Published var lastHandoff = "No transition tested yet."
    @Published var accessibility = false
    @Published var recording = false
    @Published var layoutReady = false
    var menuChanged: (() -> Void)?

    private let spaces = Spaces()
    private let snapshots = Snapshots()
    private let verticalOverlay = VerticalOverlay()
    private var grid: Grid { Grid(desktopCount: layout.count) }
    private var layout: [UInt64] = []
    private var tracker = SwipeTracker()
    private var originIndex: Int?
    private var settling = false
    private var tick: Timer?
    private var lift: DispatchWorkItem?
    private var generation = 0
    private var captureEpoch = 0
    private var escapeLocal: Any?
    private var escapeGlobal: Any?
    private var lastRefreshError: String?
    private var lastSample: SwipeSample?
    private var verticalAnimationFinished = false
    private var verticalHandoffFinished = false
    private var pendingVerticalResult: (target: Int, milliseconds: Int, restored: Bool)?
    @Published private(set) var starting = false
    private var awaitingLift = false

    func launch() {
        touchRecipient = self
        tick = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(displayChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(spaceChanged), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(sleeping), name: NSWorkspace.willSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(sleeping), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        workspace.addObserver(self, selector: #selector(sleeping), name: NSWorkspace.screensDidSleepNotification, object: nil)
        Task { await refresh() }
    }

    @objc private func displayChanged() {
        captureEpoch += 1; pause(); layout = []; snapshots.reset(); capturedCount = 0
        status = "Display changed. Check setup again."
    }
    @objc private func sleeping() { captureEpoch += 1; pause(); snapshots.reset(); capturedCount = 0; status = "Paused after sleep or session lock. Start again when ready." }
    @objc private func spaceChanged() {
        captureEpoch += 1
        if originIndex != nil && !settling { pause(); status = "A Space changed during the swipe. Start again." }
    }

    private func preference(_ key: String, domain: String) -> Any? {
        CFPreferencesCopyAppValue(key as CFString, domain as CFString)
    }
    private func setupError() -> String? {
        if !accessibility { return "Grant Accessibility access, then return here." }
        if !recording { return "Grant Screen Recording access, then relaunch if macOS requests it." }
        if !MGTouchAvailable() { return "No supported trackpad or MultitouchSupport API is available." }
        let rearranges = preference("mru-spaces", domain: "com.apple.dock") as? Bool ?? true
        if rearranges { return "Turn off ‘Automatically rearrange Spaces based on most recent use’ in Desktop & Dock." }
        let followsFocus = preference("workspaces-auto-swoosh", domain: "com.apple.dock") as? Bool ?? true
        if !followsFocus { return "Enable ‘When switching to an application, switch to a Space with open windows’ in Desktop & Dock." }
        for domain in ["com.apple.AppleMultitouchTrackpad", "com.apple.driver.AppleBluetoothMultitouch.trackpad"] {
            for key in ["TrackpadThreeFingerHorizSwipeGesture", "TrackpadThreeFingerVertSwipeGesture", "TrackpadThreeFingerDrag"] {
                if let value = preference(key, domain: domain) as? NSNumber, value.intValue != 0 {
                    return "Move Mission Control, App Exposé, and desktop switching to four fingers or disable them. Disable three-finger dragging too."
                }
            }
        }
        if ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 {
            let fourFingerSpaces = ["com.apple.AppleMultitouchTrackpad", "com.apple.driver.AppleBluetoothMultitouch.trackpad"]
                .compactMap { preference("TrackpadFourFingerHorizSwipeGesture", domain: $0) as? NSNumber }
            if !fourFingerSpaces.contains(where: { $0.intValue != 0 }) {
                return "Enable four-finger desktop switching in Trackpad settings for vertical navigation."
            }
        }
        return nil
    }

    func refresh() async {
        for domain in ["com.apple.dock", "com.apple.AppleMultitouchTrackpad", "com.apple.driver.AppleBluetoothMultitouch.trackpad"] {
            CFPreferencesAppSynchronize(domain as CFString)
        }
        accessibility = AXIsProcessTrusted()
        recording = CGPreflightScreenCaptureAccess()
        do {
            let state = try spaces.read()
            layoutReady = true
            if layout != state.ids {
                pause(); layout = state.ids; snapshots.reset(); capturedCount = 0
            }
            desktopCount = state.ids.count
            gridColumns = grid.columns
            gridRows = grid.rows
            currentIndex = state.ids.firstIndex(of: state.current) ?? 0
            if let issue = setupError() {
                if enabled { pause() }
                canStart = false; status = issue; menuChanged?(); return
            }
            if originIndex == nil && !settling && !verticalOverlay.isVisible {
                spaces.rememberFocus(on: state.current)
                let epoch = captureEpoch
                try await snapshots.capture(state) { [weak self] in
                    guard let self else { return false }
                    return self.captureEpoch == epoch && self.originIndex == nil && !self.settling &&
                        (try? self.spaces.read().current) == state.current && self.layout == state.ids
                }
            }
            capturedCount = snapshots.images.count
            canStart = capturedCount == desktopCount
            lastRefreshError = nil
            status = enabled ? "Active · Desktop \(currentIndex + 1)" :
                (canStart ? "Ready. Start to enable three-finger navigation." : "Previews \(capturedCount)/\(desktopCount). Visit each desktop using Mission Control or Control–Left/Right; wait a second on each.")
        } catch {
            layoutReady = false
            if enabled { pause() }
            canStart = false
            status = error.localizedDescription
            if lastRefreshError != status { log.error("Setup: \(self.status, privacy: .public)"); lastRefreshError = status }
        }
        menuChanged?()
    }

    func start() {
        guard !enabled, !starting else { return }
        starting = true
        let requestGeneration = generation
        Task {
            defer { starting = false }
            await refresh()
            guard requestGeneration == generation else { return }
            guard canStart, gesturesConfirmed else {
                startIssue = canStart ? "Confirm the three-finger gesture setup first." : status
                return
            }
            do {
                let state = try spaces.read()
                guard state.ids == layout else { throw GridFailure("Desktop layout changed. Refresh setup and try again.") }
                try spaces.prepare(state)
                generation += 1
                tracker.reset()
                awaitingLift = false
                enabled = true
                guard MGStartTouches({ count, identity, x, y, time in
                    DispatchQueue.main.async {
                        touchRecipient?.touch(count: Int(count), identity: identity, x: x, y: y, time: time)
                    }
                }) else { throw GridFailure("Could not start the trackpad listener. Pause other gesture tools and try again.") }
                installEscape()
                status = "Active · Desktop \(currentIndex + 1)"
            } catch { pause(); status = error.localizedDescription; startIssue = status }
            menuChanged?()
        }
    }

    func pause() {
        enabled = false; generation += 1; lift?.cancel(); lift = nil
        MGStopTouches(); tracker.reset(); verticalOverlay.hide(); settling = false; originIndex = nil
        verticalAnimationFinished = false; verticalHandoffFinished = false; pendingVerticalResult = nil
        spaces.clear(); lastSample = nil; awaitingLift = false
        if let escapeLocal { NSEvent.removeMonitor(escapeLocal) }; escapeLocal = nil
        if let escapeGlobal { NSEvent.removeMonitor(escapeGlobal) }; escapeGlobal = nil
        status = "Paused."
        menuChanged?()
    }

    private func installEscape() {
        // Escape cancels a swipe. Control–Option–Escape pauses from any app.
        escapeLocal = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.escape(event); return event
        }
        escapeGlobal = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in self?.escape(event) }
    }
    private func escape(_ event: NSEvent) {
        guard event.keyCode == 53 else { return }
        if event.modifierFlags.contains([.control, .option]) { pause(); return }
        if originIndex != nil { pause(); status = "Swipe cancelled. Start to resume." }
    }

    private func touch(count: Int, identity: UInt64, x: Double, y: Double, time: Double) {
        if count == 0 { awaitingLift = false }
        guard !awaitingLift else { return }
        guard enabled, !settling else { return }
        lift?.cancel(); lift = nil
        if count < 3 {
            // Fingers rarely lift in exactly the same frame. Coalesce the release
            // tail rather than turning every normal lift into a cancellation.
            guard tracker.sample != nil else {
                if count == 0 { tracker.reset() }
                return
            }
            let token = generation
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.enabled, self.generation == token else { return }
                self.awaitingLift = count != 0
                self.endSwipe(self.tracker.finish(count: count == 0 ? 0 : count, time: time))
            }
            lift = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: work)
            return
        }
        guard let sample = tracker.update(count: count, identity: identity, x: x, y: y, time: time) else {
            if originIndex != nil { awaitingLift = true; endSwipe(nil) }
            return
        }
        lastSample = sample
        do {
            if originIndex == nil {
                let state = try spaces.read()
                guard state.ids == layout, setupError() == nil else { throw GridFailure("Setup changed. Pause and check desktop and gesture settings.") }
                guard let index = layout.firstIndex(of: state.current) else { throw GridFailure("The active desktop is not in the grid.") }
                spaces.rememberFocus(on: state.current)
                originIndex = index
            }
        } catch { pause(); status = error.localizedDescription }
    }

    private func endSwipe(_ release: SwipeSample?) {
        guard let originIndex else { tracker.reset(); return }
        let sample = release ?? lastSample ?? SwipeSample(horizontal: true, displacement: 0, velocity: 0)
        // A nil release is a cancellation, regardless of displacement.
        let target = grid.neighbor(of: originIndex, toward: sample.direction)
        let commit = release != nil && sample.commits && target != nil
        tracker.reset()
        lastSample = nil
        guard commit, let target else { self.originIndex = nil; return }
        settling = true
        let token = generation
        if !sample.horizontal && ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 {
            guard let screen = NSScreen.screens.first,
                  let source = snapshots.images[layout[originIndex]],
                  let destination = snapshots.images[layout[target]] else {
                pause(); status = "A desktop preview is missing. Visit every desktop and start again."
                return
            }
            let movingUp = sample.displacement > 0
            verticalOverlay.show(screen: screen, source: source, target: destination, movingUp: movingUp)
            verticalAnimationFinished = false
            verticalHandoffFinished = false
            pendingVerticalResult = nil
            verticalOverlay.animate(movingUp: movingUp) { [weak self] in
                Task { @MainActor in
                    guard let self, self.enabled, self.generation == token else { return }
                    self.verticalAnimationFinished = true
                    self.finishVerticalIfReady()
                }
            }
            // Let the overlay render before the one-frame native Space switch.
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(40))
                guard let self, self.enabled, self.generation == token else { return }
                self.handoff(to: target, token: token, instant: true)
            }
        } else {
            handoff(to: target, token: token, instant: false)
        }
    }

    private func handoff(to target: Int, token: Int, instant: Bool) {
        let id = layout[target]
        let began = ProcessInfo.processInfo.systemUptime
        do {
            let state = try spaces.read()
            guard state.ids == layout, let originIndex, state.current == layout[originIndex] else {
                throw GridFailure("The desktop changed before handoff. Switching was cancelled.")
            }
            if instant {
                try spaces.switchInstantly(from: originIndex, to: target)
            } else {
                try spaces.switchTo(id)
            }
        }
        catch { pause(); status = error.localizedDescription; return }
        Task {
            var reached = false
            for _ in 0..<150 {
                guard enabled, generation == token else { return }
                guard let state = try? spaces.read(), state.ids == layout else {
                    pause(); status = "Desktop layout changed during handoff."; return
                }
                if state.current == id { reached = true; break }
                try? await Task.sleep(for: .milliseconds(20))
            }
            guard enabled, generation == token else { return }
            guard reached else {
                pause(); lastHandoff = "Failed: macOS did not activate the destination within 3 seconds."
                status = "Handoff failed. Check application-to-Space switching in Desktop & Dock."
                return
            }
            let requestedFocus = spaces.restoreFocus(on: id)
            try? await Task.sleep(for: .milliseconds(100))
            guard enabled, generation == token else { return }
            guard (try? spaces.read().current) == id else {
                pause(); lastHandoff = "Failed: restoring application focus changed the desktop."; return
            }
            let restored = spaces.hasFocusedWindow(on: id)
            if requestedFocus && !restored {
                pause(); lastHandoff = "Failed: the destination was reached, but application window focus could not be confirmed."
                return
            }
            let elapsed = (ProcessInfo.processInfo.systemUptime - began) * 1000
            if instant {
                verticalHandoffFinished = true
                pendingVerticalResult = (target, Int(elapsed), restored)
                finishVerticalIfReady()
            } else {
                completeHandoff(target: target, milliseconds: Int(elapsed), restored: restored)
            }
        }
    }

    private func finishVerticalIfReady() {
        guard verticalAnimationFinished, verticalHandoffFinished, let result = pendingVerticalResult else { return }
        pendingVerticalResult = nil
        completeHandoff(target: result.target, milliseconds: result.milliseconds, restored: result.restored)
    }

    private func completeHandoff(target: Int, milliseconds: Int, restored: Bool) {
        verticalOverlay.hide(); settling = false; originIndex = nil; currentIndex = target
        lastHandoff = "Desktop \(target + 1) reached in \(milliseconds) ms · \(restored ? "window focus confirmed" : "no application window focused")."
        log.info("Destination \(target + 1) confirmed; handoff \(milliseconds) ms; focus restored \(restored)")
        status = "Active · Desktop \(target + 1)"
        menuChanged?()
    }

    func requestAccessibility() {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        openSettings("Privacy_Accessibility")
    }
    func requestRecording() { CGRequestScreenCaptureAccess(); openSettings("Privacy_ScreenCapture") }
    func openSettings(_ anchor: String) {
        let base = anchor.hasPrefix("Privacy_") ? "com.apple.preference.security" : anchor
        let suffix = anchor.hasPrefix("Privacy_") ? "?\(anchor)" : ""
        if let url = URL(string: "x-apple.systempreferences:\(base)\(suffix)") { NSWorkspace.shared.open(url) }
    }
}
