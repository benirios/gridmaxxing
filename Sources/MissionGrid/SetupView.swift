import SwiftUI

struct SetupView: View {
    @ObservedObject var controller: Controller

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("MISSION GRID / PROTOTYPE").font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(.secondary)
                        Text("A little more space.").font(.system(size: 32, weight: .semibold))
                        Text("Your desktops. Two dimensions. Three fingers.").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "square.grid.2x2").font(.system(size: 34, weight: .light)).foregroundStyle(.mint)
                }
                HStack(spacing: 18) {
                    grid
                    VStack(alignment: .leading, spacing: 8) {
                        Label(controller.enabled ? "Navigation active" : "Navigation paused", systemImage: controller.enabled ? "circle.fill" : "pause.circle")
                            .font(.headline).foregroundStyle(controller.enabled ? .mint : .secondary)
                        Text(controller.status).font(.callout).fixedSize(horizontal: false, vertical: true)
                        Text("Previews \(controller.capturedCount)/\(controller.desktopCount) · one display")
                            .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                    }
                }
                .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 14) {
                    Text("Before your first swipe").font(.headline)
                    permission("Accessibility", detail: "Switch desktops and restore window focus.", granted: controller.accessibility, action: controller.requestAccessibility)
                    permission("Screen Recording", detail: "Keep desktop previews in memory for vertical swipes.", granted: controller.recording, action: controller.requestRecording)
                    Divider()
                    Text("1. Use 4–16 desktops in Mission Control. They’ll form a grid automatically: six desktops become 3×2. Exit full-screen apps and use one display.")
                    Text("2. In Desktop & Dock → Mission Control, turn off automatic Space rearranging. Enable switching to an application’s Space.")
                    Button("Open Desktop & Dock") { controller.openSettings("com.apple.Desktop-Settings.extension") }
                    Text("3. In Trackpad → More Gestures, set desktop switching to four fingers on macOS 27. Move Mission Control and App Exposé to four fingers or turn them off. Disable three-finger dragging in Accessibility → Pointer Control if enabled.")
                    Button("Open Trackpad settings") { controller.openSettings("com.apple.Trackpad-Settings.extension") }
                    Toggle("I have reserved three-finger swipes for Mission Grid.", isOn: $controller.gesturesConfirmed)
                        .disabled(controller.enabled)
                    Text("4. Mission Grid collects window previews from every desktop automatically. Wait until all previews are ready, then start navigation.")
                }
                .font(.callout)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Vertical animation").font(.headline)
                    }
                    Text("Three-finger swipes up and down animate the cached previews in the same direction, while Spaces switch underneath. Left and right use the normal macOS transition. Vertical animation is available on macOS 27.")
                    Text(controller.lastHandoff).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                }
                .font(.callout).padding(16)
                .background(.mint.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))

                HStack {
                    Button("Refresh checks") { Task { await controller.refresh() } }
                    Spacer()
                    if controller.enabled {
                        Button("Pause navigation", action: controller.pause).keyboardShortcut(".", modifiers: .command)
                    } else {
                        Button(controller.starting ? "Checking setup…" : "Start navigation", action: controller.start)
                            .buttonStyle(.borderedProminent).tint(.mint)
                            .disabled(controller.starting)
                    }
                }
                Text("Swipe with three fingers in any direction. Short swipes and grid edges stay on the current desktop. Escape cancels a swipe. Control–Option–Escape pauses globally. Mission Control remains available with Control–Up.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(28)
        }
        .frame(minWidth: 640, idealWidth: 680, minHeight: 600, idealHeight: 850)
        .preferredColorScheme(.dark)
        .alert("Navigation isn’t ready", isPresented: Binding(
            get: { controller.startIssue != nil },
            set: { if !$0 { controller.startIssue = nil } }
        )) {
            Button("OK", role: .cancel) { controller.startIssue = nil }
        } message: {
            Text(controller.startIssue ?? "Check the setup status.")
        }
    }

    private var grid: some View {
        VStack(spacing: 5) {
            ForEach(0..<controller.gridRows, id: \.self) { row in
                HStack(spacing: 5) {
                    ForEach(0..<controller.gridColumns, id: \.self) { col in
                        let index = row * controller.gridColumns + col
                        Text("\(index + 1)")
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .frame(width: 40, height: 32)
                            .background(controller.currentIndex == index ? Color.mint.opacity(0.24) : Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(controller.currentIndex == index ? Color.mint : Color.clear))
                            .opacity(index < controller.desktopCount ? 1 : 0)
                    }
                }
            }
        }.accessibilityLabel("\(controller.gridColumns) by \(controller.gridRows) desktop grid. Current desktop \(controller.currentIndex + 1)")
    }

    private func permission(_ name: String, detail: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle").foregroundStyle(granted ? .mint : .secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(name).fontWeight(.medium)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(granted ? "Settings" : "Allow", action: action)
        }
    }
}
