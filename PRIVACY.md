# Privacy

IDASEN Desk is a local Mac app. It does not have accounts, analytics, telemetry, or cloud sync.

## What Is Stored

The app stores a few values on your Mac:

- saved desk identifiers and display names
- height presets and the calibrated base height
- unit, menu bar, gesture, reminder and keyboard shortcut settings
- daily totals of sitting time, standing time and stand-ups

Daily totals only count time while the desk is connected and you're using your Mac (recent keyboard or mouse input, screen unlocked). The app reads how long ago the last input happened; it never reads what was typed.

These values are stored with `UserDefaults`.

## Bluetooth

Bluetooth is used to find, connect to, and control IDASEN desks.

Once a saved desk is connected, the app does not scan for other devices. While no saved desk is connected it keeps a pending connection request, which macOS completes when the desk comes into range.

## Notifications

Posture reminders are local notifications. Nothing is sent to a server.

## Network

The app does not upload analytics, health data, Bluetooth identifiers, desk names, or desk usage data.
