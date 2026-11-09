# DockSnug

A macOS background app that keeps maximised windows fitted around the Dock when it jumps between monitors. Native Swift port of `~/Developer/DockFit.spoon`.

## Status

Running and tested live on 2026-11-09: windows follow the Dock in both directions and the edge push works on both screens. The window and Dock logic is checked by `scripts/check.sh`. The stuck-reservation repair has not yet fired for real in this version. Never run this and the Hammerspoon version at once: they would fight over the same windows.

## Building

The first time, accept the Xcode license:

```sh
sudo xcodebuild -license
```

Then open `DockSnug.xcodeproj` in Xcode and press Run, or from the terminal:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project DockSnug.xcodeproj -target DockSnug -configuration Release build
```

Signed with a free personal Apple Development certificate (set in the project), so macOS keeps the Accessibility permission across rebuilds.

## Layout

- `DockSnug/DockGeometry.swift`: all the decisions, as pure functions. Start here.
- `DockSnug/DockSnugEngine.swift`: the timer, Dock repair and edge push.
- `DockSnug/WindowEvents.swift`: notices windows moving or reappearing.
- `DockSnug/Spaces.swift`: full-screen check through a private API, looked up at runtime so it can't crash the app. This rules out the App Store, as does resizing other apps' windows.
- `site/`: the website, a single static page. It's published at https://traes008.github.io/docksnug/ from the separate public repo `traes008/docksnug`, which holds only that page. This repo stays private: copy `site/index.html` there to update the site.

## Performance notes

Measured on 2026-11-10 with the kernel's per-process counters (`proc_pid_rusage`):

- Each check costs about 0.28 ms of CPU, and nearly all of that is the wake-up itself; the work inside is about 0.03 ms. So the app checks 4 times a second only while the pointer is moving or the Dock is changing, and once a second otherwise (`nextPollInterval`).
- Mouse still: about 0.03% of a core and 1 wakeup a second. Mouse moving: about 0.1% and 4 a second. Before, it was about 0.15% and 4 a second all the time.
- Don't trade the 4-a-second rate while the pointer moves for more savings: it is what makes windows follow the Dock promptly.

## Testing Dock moves

Park the pointer on a screen's bottom edge with `CGWarpMouseCursorPosition` (it sends no mouse events, so macOS doesn't react) and DockSnug's edge push should bring the Dock over within about 2 seconds. This works toward the MacBook every time. Toward the Dell (the main display) the push is ignored by macOS unless the real mouse moved in the last few seconds; the previous build behaves the same, so it comes from macOS or the test, not from the app. In real use the push only happens while the user is pushing the mouse themselves.

