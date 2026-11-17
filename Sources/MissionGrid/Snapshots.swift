import AppKit
import ScreenCaptureKit

@MainActor final class Snapshots {
    private(set) var images: [UInt64: CGImage] = [:]
    private var lastCapture: [UInt64: TimeInterval] = [:]
    private var capturing = false

    func reset() {
        images.removeAll()
        lastCapture.removeAll()
    }

    func capture(_ state: DesktopState, stillCurrent: @escaping () -> Bool) async throws {
        guard !capturing, stillCurrent() else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if images[state.current] != nil && now - (lastCapture[state.current] ?? 0) < 1 { return }
        capturing = true
        defer { capturing = false }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard stillCurrent(), let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) else { return }
        let ownApps = content.applications.filter { $0.processID == getpid() }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.width = display.width
        config.height = display.height
        config.showsCursor = false
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        guard stillCurrent() else { return }
        images[state.current] = image
        lastCapture[state.current] = ProcessInfo.processInfo.systemUptime
    }
}
