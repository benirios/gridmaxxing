# Mission Grid

A local macOS prototype: 4–16 real Spaces arranged in an automatically sized grid, selected with three-finger swipes. Vertical swipes use a custom vertical preview on macOS 27; left and right use the native macOS transition. Swift + AppKit + ScreenCaptureKit. No third-party packages, Dock injection, or SIP changes.

## Build and open

Requires Apple Silicon, macOS 14+, and Swift 6 / Command Line Tools. The initial target is the Mac on which this was developed; private API compatibility on other releases is not guaranteed.

```sh
zsh build.sh
open 'dist/Mission Grid.app'
```

Keep the app in this folder while testing. It is ad-hoc signed, not notarized. Rebuilding may require re-enabling its privacy permissions. Mission Grid registers itself to open at login on first launch; use its menu bar’s **Open at Login** item to turn that off or back on. macOS may require approval in System Settings → General → Login Items.

## First run

The app opens a setup window and places a grid icon in the menu bar. Start remains clickable and explains any missing setup step in an alert. Follow the checks there:

1. Use one display and use 4–16 ordinary desktops in Mission Control. Full-screen and Split View Spaces are not supported in this milestone.
2. Grant Accessibility and Screen Recording access using the app’s buttons. Relaunch if macOS requests it.
3. In **Desktop & Dock → Mission Control**, disable automatic Space rearranging and enable switching to an application’s Space.
4. Reserve three-finger swipes: set desktop switching to four fingers on macOS 27. Move Mission Control and App Exposé to four fingers or disable them. Disable three-finger dragging. Check the confirmation box in Mission Grid. Other gesture utilities must not bind this gesture either.
5. Visit each desktop with Control–Left/Right or Mission Control. Stay a second on each to collect its preview. Once all previews are ready, click **Start navigation**.

The app does not change your system preferences. No changes are needed to SIP. Previews remain in RAM and are never written or uploaded.

## Movement

Desktops are numbered in Mission Control order. Four desktops form a 2×2 grid (shown below); six form 3×2. Incomplete final rows stop at their last desktop:

```text
┌───────────┬───────────┐
│ Desktop 1 │ Desktop 2 │
├───────────┼───────────┤
│ Desktop 3 │ Desktop 4 │
└───────────┴───────────┘
```

Swipe left to select the desktop to the right; swipe upward to select the desktop below. Swipe downward to select the desktop above. Both vertical swipes animate the cached previews in the swipe direction on macOS 27. Left and right use the native horizontal Space transition. Roughly one-third of the trackpad is a full swipe. Gestures lock to one axis and support reversal; grid edges do not wrap.

A release beyond 25% of the screen commits. A directional flick of at least one screen per second also commits after a small dead zone. Short swipes return. Two-finger scrolling is left to the foreground app. Adding a fourth finger or changing contacts cancels. Finger-lift tails are coalesced for 60 ms.

**Escape** cancels an active swipe and pauses. **Control–Option–Escape** pauses globally. Pause and Quit are also available in the menu bar. Sleep, session lock, display changes, permission loss, and unsupported layouts pause navigation. Mission Control remains available through **Control–Up**.

## Transition behavior

On macOS 27, vertical swipes animate cached source and destination images up or down for 240 ms. After the overlay has rendered, the app posts a fast Dock Space switch during that animation, then keeps the overlay until both the animation and destination confirmation finish. Left and right focus an invisible anchor window on the selected Space and let macOS own the native horizontal transition. The setup window reports destination confirmation time. Visual smoothness of both vertical handoffs needs a physical trackpad check on this Mac.

## Verification

```sh
zsh test.sh
'dist/Mission Grid.app/Contents/MacOS/MissionGrid' --diagnose
```

Diagnostics are read-only: they check symbols, permissions, and layout without requesting access, starting a gesture listener, creating anchors, capturing images, or switching desktops. Tests cover grid edges, axis locking, reversals, contact changes, flick thresholds, expired velocity, cancellation, and two-finger input.

Manual hardware checks:

- Swipe all four directions from each cell. Check the destination and correct application focus, then type/click in that application.
- Try partial swipes, flicks, diagonal starts, reversals, grid edges, and a fourth finger. Cancellation must leave the original desktop selected.
- Confirm ordinary scrolling and native four-finger gestures still work; Mission Control must not also open during a three-finger swipe.
- Confirm that upward and downward swipes animate vertically without an extra sideways flick, while left and right show the native transition.
- Change the Space layout, connect a display, pause mid-swipe, and sleep/wake. Navigation must stop safely.
- Check a desktop containing multiple windows of the same app across different Spaces: focus restoration must not pull you away from the destination.

Handoff timing and errors use macOS unified logging under subsystem `local.MissionGrid`. Window contents and touch coordinates are not logged.

## Implementation

- `GridCore`: deterministic layout and gesture rules, independent of AppKit.
- `PrivateBridge`: runtime-loaded SkyLight and MultitouchSupport symbols; all private ABI assumptions stay here. Symbol checks do not prove ABI compatibility with a future macOS release.
- `MissionGrid`: permission/setup checks, in-memory previews for vertical swipes, anchors, and destination validation.

The prototype is designed for local testing, not Mac App Store distribution. See [THIRD_PARTY.md](THIRD_PARTY.md) for research references and ABI attribution.
