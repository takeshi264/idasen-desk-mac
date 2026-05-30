# IDASEN Desk

A small macOS menu bar app for IKEA IDASEN sit/stand desks.

The idea is simple: I wanted the desk to move to my sitting or standing height without holding the physical switch the whole way. IDASEN Desk keeps those presets on the Mac, talks to the desk over Bluetooth, and gives the controls a permanent home in the menu bar.

This is not an official IKEA app. It is just a native macOS tool for people who spend most of the day at the same desk as their Mac.

## Why This Exists

The IDASEN desk is good hardware, but the stock controller is very literal: hold up to go up, hold down to go down. That works, but it also means changing posture is still a small interruption.

This app removes a bit of that friction. Click Sit, click Stand, or use the physical handle double tap while the app is connected. The desk still moves like an IDASEN desk; the app just makes the common actions less tedious.

## What Works

- Menu bar control for live height, Sit, Stand, Up, Down, reconnect, and settings.
- Saved sitting and standing presets.
- A SwiftUI settings window with height tuning, unit selection, device management, reminders, gestures, language, and health stats.
- Multiple saved desks, with one active desk receiving commands at a time.
- Physical-handle double tap for sit/stand presets while the app is connected.
- Standing reminders that ask first instead of silently moving the desk.
- Local health stats based on desk connection time and reported height.
- English, Japanese, and Traditional Chinese.
- AppleScript commands for small automations.

## The Important Limitation

The original IDASEN control panel does not store memory positions. This app cannot teach the stock panel your saved heights.

Saved heights, double tap, reminders, AppleScript, and health stats all depend on the Mac app being open and connected to the desk. When the app is not running, the desk goes back to being a normal IDASEN desk.

If you want preset heights without relying on a computer, you probably want a separate always-on Bluetooth controller, for example a Home Assistant bridge, an ESP32 project, or another small helper device. That is a different kind of project.

## Requirements

- macOS 13 or newer.
- Xcode 15 or newer if you want to build it yourself.
- Bluetooth permission.
- An IKEA IDASEN sit/stand desk with Bluetooth.

## Build From Source

Open the project:

```sh
open "IDASEN Desk.xcodeproj"
```

Select the `IDASEN Desk` scheme and run it.

Release build from Terminal:

```sh
xcodebuild \
  -project "IDASEN Desk.xcodeproj" \
  -scheme "IDASEN Desk" \
  -configuration Release \
  -derivedDataPath .derivedData \
  build
```

The app will be built at:

```text
.derivedData/Build/Products/Release/IDASEN Desk.app
```

I usually run the analyzer before sharing changes:

```sh
xcodebuild \
  -project "IDASEN Desk.xcodeproj" \
  -scheme "IDASEN Desk" \
  -configuration Debug \
  -derivedDataPath .derivedData \
  analyze
```

## Using The App

On first launch, give the app Bluetooth permission and connect to your desk. After that, the menu bar popover is the daily control surface.

The settings window is where the slower decisions live:

- set sitting and standing heights
- choose centimeters or inches
- manage saved desks
- tune standing reminders
- enable or disable handle double tap
- choose app language
- view local posture stats
- launch the app at login

If more than one saved desk is connected, the active desk is the one that receives menu bar commands, AppleScript commands, double-tap actions, and reminders.

## Double Tap

Double tap is app-assisted. The desk reports a short physical movement, the app recognizes two taps in the same direction, and then the app sends the preset command.

So the feature is useful, but it is not magic firmware memory. It works only while IDASEN Desk is connected.

## Standing Reminders

The standing rhythm is intentionally prompt-first. When it is time to stand, the app shows a small window and lets you stand now, snooze, or skip.

The app also checks recent keyboard and mouse activity, so it does not immediately nag you after you have been away from the Mac.

## Health Stats

Health stats are local estimates. The app looks at connection time and reported desk height to estimate sitting time, standing time, stand-up transitions, and daily rhythm.

Treat these numbers as a useful mirror, not medical advice.

## AppleScript

Move to the standing preset:

```applescript
tell application "IDASEN Desk"
    move "stand"
end tell
```

Move to a specific height:

```applescript
tell application "IDASEN Desk"
    move to "110cm"
end tell
```

Supported movement commands:

- `stand`
- `sit`
- `up`
- `down`
- `to-stand`
- `to-sit`

Heights can use `cm` or `in`. A bare number uses the unit selected in Settings.

## Project Layout

```text
IDASEN Desk/
  AppDelegate.swift
  BluetoothManager.swift
  DeskControlView.swift
  AutoStand.swift
  HealthStats.swift
  HeightValueReadout.swift
  Core/
    DeskPeripheral.swift
    DeskMotionController.swift
  Preferences/
    Preferences.swift
    PreferencesView.swift
  AppleScript Commands/
    IDASENDesk.sdef
    MoveDeskCommand.swift
    MoveDeskToHeightCommand.swift
```

## Privacy

The app stores preferences and health stats locally with `UserDefaults`.

It does not upload analytics, desk data, Bluetooth identifiers, or health data.

See [PRIVACY.md](PRIVACY.md).

## Contributing

Small, careful changes are welcome. This app controls real hardware, so movement behavior should be treated conservatively.

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT. See [LICENSE.md](LICENSE.md).
