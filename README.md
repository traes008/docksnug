# DockSnug

A macOS menu bar app that keeps maximised windows fitted around the Dock when it jumps between monitors. Native Swift port of `~/Developer/DockFit.spoon`.

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

The build is signed to run locally, which needs no Apple account. macOS may ask for Accessibility permission again after each rebuild.

## Layout

- `DockSnug/DockGeometry.swift`: all the decisions, as pure functions. Start here.
- `DockSnug/DockSnugEngine.swift`: the timer, Dock repair and edge push.
- `DockSnug/WindowEvents.swift`: notices windows moving or reappearing.
- `DockSnug/Spaces.swift`: full-screen check through a private API, looked up at runtime so it can't crash the app. This rules out the App Store, as does resizing other apps' windows.
- `site/`: the website, a single static page. It's published at https://traes008.github.io/docksnug/ from the separate public repo `traes008/docksnug`, which holds only that page. This repo stays private: copy `site/index.html` there to update the site.
