# Notch Player

Shows what's playing on your Mac around the MacBook notch. Works with any app
that shows up in macOS's Now Playing controls (Spotify, Apple Music, browsers…).

- **Closed:** album art on the left of the notch, an equalizer on the right.
- **Hover:** expands into a player with title, artist, a seekable progress bar
  and previous / play-pause / next, plus battery, today's weather, and a
  scrolling list of the week's events and your unfinished reminders grouped
  by day (Today, Tomorrow, weekdays, Later, No date).
- **Alerts:** volume and brightness changes (replacing the macOS pop-up),
  plugging in the charger, low battery (20% and 10%), and sound switching to
  another output such as AirPods briefly take over the notch.
- **Notifications:** other apps' notifications (Messages, Claude, Slack…)
  drop down from the notch with the sender and a line of the message.
  Hovering opens the list of recent ones; clicking one opens it. Unread ones
  show as a blue dot on the artwork, or an app icon and count with nothing
  playing. The list scrolls with the trackpad or mouse wheel.
  "Message Previews" in the right-click menu hides the text.
  "Hide macOS Pop-ups" (on by default) closes the macOS banner as soon as
  the notch has it, so notifications show in one place. The banner still
  flashes for about half a second (macOS ignores Close while it slides in),
  and closed notifications don't stay in Notification Center.
- **Click the artwork** to open the playing app. **Right-click** for
  "Open at Login", turning Calendar / Weather / Volume & Brightness on or off,
  and "Quit".

## Claude Code and Cursor

`notch-notify` (bundled at `NotchPlayer.app/Contents/Resources/notch-notify`)
sends a hook event straight to the notch. That works while the app is in
front and needs no Accessibility access. It reads the hook's JSON on stdin.

- Claude Code, in `~/.claude/settings.json`: run
  `/Applications/NotchPlayer.app/Contents/Resources/notch-notify claude` on
  `Stop` ("Claude finished") and `Notification` ("Claude needs you"). The
  notification carries the icon of the app Claude Code runs in (the Claude
  app, Cursor, a terminal), found by walking up the process tree, and
  clicking it opens that app.
- Cursor, in `~/.cursor/hooks.json`: run
  `/Applications/NotchPlayer.app/Contents/Resources/notch-notify cursor` on
  `stop` ("Cursor finished"). Cursor has no hook for "needs approval"; turn on
  Settings → Notifications → System Notifications in Cursor and the notch
  picks those up from the banner (only while Cursor isn't in front).

A banner from the same app within 10 seconds of a direct notification is
treated as a duplicate.

## Permissions

macOS asks once for each:

- **Calendar:** to list upcoming events (Calendar app accounts, read only).
- **Reminders:** to list your unfinished reminders (read only).
- **Location:** for the weather, from [Open-Meteo](https://open-meteo.com)
  (free, no account). The location is rounded to about 1 km before it's sent.
- **Accessibility:** to catch the volume and brightness keys, and to read
  notification banners (there's no public API for other apps'
  notifications). Without it the keys work as usual with the macOS pop-up
  and notifications don't show in the notch. Only notifications that pop up
  as banners are seen: not ones silenced by Focus, or apps set to None.

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
layout. Debug builds (`CONFIG=debug ./scripts/build-app.sh`) also take
`--sample-data[=empty|long|notification|notifications]`, which fills the
notch with made-up content instead of real media, calendar, weather and
notifications, so no permissions are needed.

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
