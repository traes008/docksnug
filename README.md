<img src="icon.png" width="96" alt="">

# DockSnug

Keeps your windows fitted around the Dock when it moves between monitors.

https://traes008.github.io/docksnug/

- Windows grow when the Dock leaves their screen and shrink when it arrives.
- Fixes the gap macOS sometimes leaves after full screen, by restarting the Dock.
- Brings the Dock over if macOS ignores your push against a screen edge.

## Install

No download yet. Build it in Xcode:

1. Open `DockSnug.xcodeproj`.
2. Under Signing & Capabilities, pick your own team (a free Apple account works).
3. Run, then move the app to Applications.
4. Allow it under Privacy & Security → Accessibility.

No menu bar icon. Open the app again for its settings.

## Notes

- Only used with two displays and the Dock at the bottom.
- Needs "Displays have separate Spaces" on, which is the default.
- `scripts/check.sh` runs the logic tests. Start reading at `DockSnug/DockGeometry.swift`.

MIT licence.
