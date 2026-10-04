# Notch Player

Shows what's playing on your Mac around the MacBook notch. Works with any app
that shows up in macOS's Now Playing controls (Spotify, Apple Music, browsers…).

- **Closed:** album art on the left of the notch, an equalizer on the right.
- **Hover:** expands into a player with title, artist, a seekable progress bar
  and previous / play-pause / next, plus battery, today's weather and your
  next events.
- **Alerts:** volume and brightness changes (replacing the macOS pop-up),
  plugging in the charger, low battery (20% and 10%), and sound switching to
  another output such as AirPods briefly take over the notch.
- **Click the artwork** to open the playing app. **Right-click** for
  "Open at Login", turning Calendar / Weather / Volume & Brightness on or off,
  and "Quit".

## Permissions

macOS asks once for each:

- **Calendar:** to list upcoming events (Calendar app accounts, read only).
- **Location:** for the weather, from [Open-Meteo](https://open-meteo.com)
  (free, no account). The location is rounded to about 1 km before it's sent.
- **Accessibility:** to catch the volume and brightness keys. Without it the
  keys work as usual with the macOS pop-up.

macOS ties these to the app's signature. Builds are signed ad hoc unless a
signing identity is found (e.g. "Apple Development", free by signing into
Xcode with an Apple ID), and an ad-hoc signature changes on every build, so
permissions have to be granted again after rebuilding. For Accessibility,
remove the old Notch Player entry in System Settings first.

## Build & run

Requires Xcode (Swift 5.9+) and macOS 14+.

```bash
git submodule update --init
make run
```

`make build` puts the app at `build/NotchPlayer.app`; `make stop` quits it.
Pass `--pin-expanded` to keep the panel open while working on the layout:

```bash
open build/NotchPlayer.app --args --pin-expanded
```

`--demo-activities` plays each alert once after launch, for working on their
layout.

## How it works

Since macOS 15.4, only Apple-signed processes can read the private
MediaRemote framework. [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter)
(vendored as a submodule) works around this by loading a small framework into
`/usr/bin/perl`, which streams Now Playing updates as JSON lines. The app
bundles the script and framework and reads that stream
(`Sources/NotchPlayer/NowPlayingService.swift`).

The overlay is a borderless panel above the menu bar
(`NotchPanel.swift` / `NotchController.swift`). It ignores the mouse
everywhere outside the visible shape, so clicks pass through to the menu bar
and apps underneath.
