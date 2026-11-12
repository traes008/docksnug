<img src="icon.png" width="96" alt="">

# DockSnug

A small Mac app that keeps your windows fitted around the Dock when the Dock moves between monitors.

Website: https://traes008.github.io/docksnug/

## The problem

With more than one monitor and **Displays have separate Spaces** turned on, the Dock jumps to whichever screen you push the pointer against. macOS doesn't resize your windows when that happens, so they end up hidden under the Dock or stopping short with an empty strip below.

## What it does

- **Windows follow the Dock.** Maximised and half-screen windows grow when the Dock leaves their screen and make room when it arrives, flush against it.
- **Clears the gap that won't go away.** Sometimes macOS keeps space reserved for a Dock that has already left, often after leaving a full-screen app while the Dock is on the other screen. No window can grow into that space, so DockSnug restarts the Dock, which makes macOS recalculate it, and puts the Dock back on the screen it was on.
- **Brings the Dock when macOS ignores you.** If you push against a screen's edge and the Dock doesn't come, DockSnug moves it there.
- **Stays cheap.** About 0.03% of one CPU core while the mouse is still and about 0.1% while it moves.

Windows in native full screen are left alone.

## Install

There is no ready-made download yet, so you build it yourself. You need a Mac with [Xcode](https://apps.apple.com/app/xcode/id497799835) (free).

1. Download this repository (the green **Code** button, then **Download ZIP**) or clone it.
2. Open `DockSnug.xcodeproj` in Xcode.
3. Click the project in the sidebar, pick the **DockSnug** target, open **Signing & Capabilities** and choose your own team. A free Apple account works; add it under Xcode → Settings → Accounts.
4. Choose **Product → Archive**, or just press Run to try it.
5. Move the built app to your Applications folder and open it.
6. Allow it under System Settings → Privacy & Security → Accessibility when asked.

Signing with your own team matters: macOS then recognises new builds as the same app and keeps the permission.

The app has no menu bar icon. Open it again to reach its settings, including **Open at Login**.

## Good to know

- Clearing the stuck space restarts the Dock, so it flickers for a second and the pointer jumps briefly while the Dock is put back.
- Resting the pointer on the bottom row of a screen without the Dock for about a second brings the Dock over.
- It has been used daily on one setup: two displays with the Dock at the bottom. A Dock on the left or right is written but untested.
- It can't be in the Mac App Store, because it resizes other apps' windows and reads full-screen state through a private macOS function.

## How it works

macOS sends no notification when the Dock jumps between monitors, so DockSnug reads the Dock's position through the Accessibility API: four times a second while the pointer moves or the Dock is changing, and once a second otherwise. From that it works out the free area of each screen and resizes windows that filled the old area.

- `DockSnug/DockGeometry.swift`: all the decisions, as pure functions. Start here.
- `DockSnug/DockSnugEngine.swift`: the timer, the Dock repair and the edge push.
- `DockSnug/WindowEvents.swift`: notices windows moving or reappearing.
- `DockSnug/Spaces.swift`: the full-screen check, looked up at runtime so it can't crash the app if Apple removes it.
- `scripts/check.sh`: runs the logic checks in `Tests/main.swift`. It needs only the command-line Swift tools.
- `scripts/make-icon.swift`: draws the app icon.
- `index.html`: the website.

## Notes for contributors

- Each check costs about 0.28 ms of CPU, and nearly all of that is the wake-up itself, so waking less often is what saves energy. Keep the faster rate while the pointer moves: it is what makes windows follow the Dock promptly.
- To test Dock moves, park the pointer on a screen's bottom edge with `CGWarpMouseCursorPosition`, which sends no mouse events. DockSnug's edge push should bring the Dock over within about 2 seconds. On the setup above this always worked toward the secondary display, but toward the main display macOS ignored the push unless the real mouse had moved in the last few seconds.

## Licence

MIT, see [LICENSE](LICENSE).
