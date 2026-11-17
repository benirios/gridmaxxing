import AppKit
import ImageIO
import ScreenCaptureKit
import PrivateBridge

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
        let missing = state.ids.filter { images[$0] == nil }
        let stale = state.ids.filter { $0 != state.current && now - (lastCapture[$0] ?? 0) > 15 }
        let currentDue = now - (lastCapture[state.current] ?? 0) > 1
        guard currentDue || !missing.isEmpty || !stale.isEmpty else { return }
        capturing = true
        defer { capturing = false }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard stillCurrent(), let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) else { return }
        let scale = CGFloat(display.width) / display.frame.width

        if currentDue || images[state.current] == nil {
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

        guard !missing.isEmpty || !stale.isEmpty else { return }
        let info = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
        let byID = Dictionary(uniqueKeysWithValues: content.windows.map { ($0.windowID, $0) })
        let windows = info.compactMap { item -> SCWindow? in
            guard let id = item[kCGWindowNumber as String] as? UInt32,
                  let layer = item[kCGWindowLayer as String] as? Int, layer == 0,
                  let window = byID[id], window.owningApplication?.processID != getpid(),
                  window.frame.width > 1, window.frame.height > 1 else { return nil }
            return window
        }
        let wallpaper = desktopImage()
        for id in state.ids where id != state.current && (images[id] == nil || now - (lastCapture[id] ?? 0) > 15) {
            guard stillCurrent() else { return }
            let members = windows.filter { MGWindowInSpace($0.windowID, id) }
            let image = await composite(members, display: display, scale: scale, wallpaper: wallpaper)
            guard stillCurrent() else { return }
            images[id] = image
            lastCapture[id] = ProcessInfo.processInfo.systemUptime
        }
    }

    private func desktopImage() -> CGImage? {
        guard let screen = NSScreen.screens.first,
              let url = NSWorkspace.shared.desktopImageURL(for: screen),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private func composite(_ windows: [SCWindow], display: SCDisplay, scale: CGFloat, wallpaper: CGImage?) async -> CGImage {
        let width = display.width, height = display.height
        let space = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: 0, space: space, bitmapInfo: bitmapInfo)!
        let canvas = CGRect(x: 0, y: 0, width: width, height: height)
        context.setFillColor(NSColor.black.cgColor)
        context.fill(canvas)
        if let wallpaper {
            let factor = max(CGFloat(width) / CGFloat(wallpaper.width), CGFloat(height) / CGFloat(wallpaper.height))
            let size = CGSize(width: CGFloat(wallpaper.width) * factor, height: CGFloat(wallpaper.height) * factor)
            context.draw(wallpaper, in: CGRect(x: (canvas.width - size.width) / 2,
                                               y: (canvas.height - size.height) / 2,
                                               width: size.width, height: size.height))
        }
        // CGWindowListCopyWindowInfo is front to back. Paint the backmost window first.
        for window in windows.reversed() {
            let config = SCStreamConfiguration()
            config.width = max(1, Int(window.frame.width * scale))
            config.height = max(1, Int(window.frame.height * scale))
            config.showsCursor = false
            let filter = SCContentFilter(desktopIndependentWindow: window)
            guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) else { continue }
            let rect = CGRect(x: (window.frame.minX - display.frame.minX) * scale,
                              y: (display.frame.maxY - window.frame.maxY) * scale,
                              width: window.frame.width * scale,
                              height: window.frame.height * scale)
            context.draw(image, in: rect)
        }
        return context.makeImage()!
    }
}
