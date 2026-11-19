# Prototype verification

## Verified locally

- Release app builds with Swift 6.2.4 and Command Line Tools.
- Eight dependency-free checks pass, including automatic grids for 4–16 desktops, incomplete-row edges, gesture thresholds, cancellation, and contact changes.
- The app bundle is ad-hoc signed; signature verification and Info.plist validation pass.
- Read-only diagnostics find the required SkyLight and MultitouchSupport symbols and an available trackpad device.
- Diagnostics handle an inaccessible desktop session without crashing.

## Not verified on hardware

The execution sandbox cannot access the logged-in display session. Accessibility and Screen Recording are not granted to the diagnostic process. The native computer-use service also failed to start, so the setup UI could not be inspected through it.

Consequently, continuous physical trackpad input, Space anchor placement, destination focus restoration, overlay rendering at the display refresh rate, and visual handoff smoothness remain unverified. Successful compilation and symbol availability do not establish these behaviors.

Open `dist/Mission Grid.app` in the logged-in desktop session, complete the setup checklist, and follow the manual checks in README.md. Use the in-app handoff result controls to record whether the compositor exposes a native horizontal transition or flicker. No system preferences or privacy permissions were changed by the implementation session.

## Start-button follow-up

The native computer-use service became available during follow-up. The running app’s setup UI confirmed both privacy permissions and the gesture confirmation checkbox were granted, but its fixed four-desktop layout guard rejected the desktop configuration. Saved Spaces configuration showed six ordinary desktops. System Settings also showed automatic Space reordering on and native desktop switching still assigned to three fingers.

The updated app supports 4–16 desktops (six become 3×2) and Start now displays the exact remaining setup issue in an alert. The release build, signature verification, plist validation, and all eight checks pass. Physical swipes and the visual compositor handoff remain unverified.

## Vertical flick follow-up (macOS 27.2)

Down, left, and right swipes request the destination Space through an anchor window and use only macOS's native transition. For an upward three-finger swipe on macOS 27, the app captures source and destination previews, animates them upward, and posts a rapid Space-switch gesture beneath the overlay. The release build and eight grid checks pass. A physical upward trackpad swipe is still required to verify the visual result and check for any compositor flick.

After a user reported that the upward transition still appeared sideways, the Dock gesture's horizontal progress was reduced from 0.1 to 0.03 and the overlay was raised to the maximum public window level. The release build, eight checks, and signature verification pass. The rebuilt app has lost Accessibility and Screen Recording grants, so this visual change remains unverified until those are re-enabled and an upward swipe is tested.

The 0.03 progress still exposed a sideways frame during an upward swipe. The current build uses the smallest nonzero 16.16 gesture progress (0.000016) and includes the additional macOS 27 gesture fields used by InstantSpaceSwitcher. This is an experimental handoff on macOS 27.2; the app must be tested on the physical trackpad for both correct landing and black-frame regressions.

## Downward swipe follow-up

The downward swipe previously bypassed the preview overlay and used the native horizontal Space transition. Both vertical directions now use the overlay and rapid Space handoff. A downward swipe places the destination preview above the source and moves both images downward; an upward swipe retains the existing upward movement. Left and right still use the native transition. The release app builds, all eight grid checks pass, and its signature verifies. The rebuilt app was reopened, but its setup UI currently reports denied Accessibility and Screen Recording access, so the physical downward animation remains unverified.

## Launch at login

Mission Grid now registers its main app with macOS ServiceManagement when launched, with an **Open at Login** menu item for changing that setting. After rebuilding and reopening, `SMAppService.mainApp.status` reported enabled and `sfltool dumpbtm` listed `local.MissionGrid` as an enabled, allowed login item pointing to `dist/Mission Grid.app`. The eight grid checks and strict code-signature verification pass. An actual logout/login cycle was not performed.

## Automatic inactive-desktop previews

On this Mac, ScreenCaptureKit listed normal windows on all six Spaces without switching desktops. A desktop-independent capture of an inactive Finder window returned its real contents. A full-display filter for an inactive Space failed, so Mission Grid now composes each inactive preview from its individually captured windows over the current wallpaper. A diagnostic run produced six previews from six Spaces without moving the active Space; the composed preview was visually inspected. Empty Spaces receive a wallpaper preview. Full-screen or protected window content, per-Space wallpapers, and the handoff animation still need a physical trackpad check.

The updated signed build was copied to `/Applications/Mission Grid.app`, which is the path registered as the login item. The installed app reopened and displays the automatic-preview instructions. Its setup UI currently reports that Accessibility and Screen Recording access need to be granted again for the rebuilt signature, so automatic capture has not yet run inside that installed app session.

## Automatic navigation stop follow-up

Unified logs from November 18–19 repeatedly showed temporary failures to access the desktop session while the Mac slept or its session was unavailable. The controller previously treated one such read failure, or one ScreenCaptureKit preview error, as a permanent pause. It now suspends during desktop-session interruptions and automatically restarts navigation when the session and previews return. Preview errors leave active navigation running and retry on later refreshes. A failed handoff cancels only that swipe; focus confirmation failure no longer disables navigation after a successful Space switch. Manual Pause and Escape still disable automatic restart.

The app also persists the user's gesture confirmation and whether navigation was active. It resumes after login if it had been active before the process stopped; a manual Pause or Quit clears that choice.

The release build, eight grid checks, and strict signature verification passed. The new build was installed in `/Applications` and reopened as a single process. Its setup UI reports Accessibility and Screen Recording denied after the ad-hoc signature changed, so an active-navigation or real sleep/wake test could not be completed in this session.
