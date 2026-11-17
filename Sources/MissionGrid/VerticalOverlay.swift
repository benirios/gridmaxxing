import AppKit
import QuartzCore

/// Covers the display for a committed vertical swipe. It shows cached pixels;
/// macOS's real Space switch happens after this animation, beneath the overlay.
@MainActor final class VerticalOverlay {
    private var window: NSWindow?
    private var sourceLayer: CALayer?
    private var targetLayer: CALayer?
    var isVisible: Bool { window != nil }

    func show(screen: NSScreen, source: CGImage, target: CGImage, movingUp: Bool) {
        hide()
        let frame = screen.frame
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        window.ignoresMouseEvents = true
        window.isOpaque = true
        window.backgroundColor = .black
        window.hasShadow = false
        let view = NSView(frame: NSRect(origin: .zero, size: frame.size))
        view.wantsLayer = true
        view.layer?.masksToBounds = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        window.contentView = view

        func tile(_ image: CGImage, y: CGFloat) -> CALayer {
            let layer = CALayer()
            layer.contents = image
            layer.contentsGravity = .resize
            layer.frame = CGRect(x: 0, y: y, width: frame.width, height: frame.height)
            view.layer?.addSublayer(layer)
            return layer
        }
        targetLayer = tile(target, y: movingUp ? -frame.height : frame.height)
        sourceLayer = tile(source, y: 0)
        self.window = window
        window.orderFrontRegardless()
    }

    func animate(movingUp: Bool, completion: @escaping () -> Void) {
        guard let sourceLayer, let targetLayer, let window else { completion(); return }
        let height = window.frame.height
        CATransaction.begin()
        CATransaction.setCompletionBlock(completion)
        CATransaction.setDisableActions(true)
        let delta = movingUp ? height : -height
        for layer in [sourceLayer, targetLayer] {
            let startY = layer.position.y
            let animation = CABasicAnimation(keyPath: "position.y")
            animation.fromValue = startY
            animation.toValue = startY + delta
            animation.duration = 0.24
            animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.position.y = startY + delta
            layer.add(animation, forKey: "vertical")
        }
        CATransaction.commit()
    }

    func hide() {
        sourceLayer = nil
        targetLayer = nil
        window?.orderOut(nil)
        window?.close()
        window = nil
    }
}
