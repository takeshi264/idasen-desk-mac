# Changelog

## 2.0.0

A rewrite of the Bluetooth, motion and reminder code, and a new interface.

### Safer and more precise movement

- Moves now use the controller's reference input (`99FA0031`). The desk eases in and out and stops within millimetres, instead of the app sending up/down pulses and cutting power about half a centimetre early.
- Hold-to-move keeps sending commands while pressed. Before, a single command was sent, so the desk stopped after about a second even if the button was still held.
- Using the handle against an in-progress move cancels it. A move that stops short is reported instead of hidden by rounding the display.
- The command loop opts out of App Nap while the desk is moving.

### Reminders no longer move the desk on their own

- 1.x lowered the desk to the sitting preset at the top of every hour while reminders were on, whether or not anyone was there. That's gone: nothing moves the desk without a click, shortcut, handle gesture, or reminder button.
- Reminders are now based on continuous sitting time measured from the desk's height, paused while you're away from the Mac, and reset by a real break. There's an optional reminder to sit after standing for a long time.
- Reminders arrive as notifications with Stand Up and Snooze buttons. If notifications are off, a small panel appears that never takes keyboard focus.

### Connection

- Automatic reconnection after sleep, Bluetooth restarts and range loss, using CoreBluetooth's non-expiring connection requests. 1.x usually needed a manual Reconnect after the Mac woke up.
- With several saved desks, the app connects to whichever is in range, preferring the last one used.
- First-run setup explains pairing mode and lists nearby desks right in the menu.

### Interface

- A new menu bar popover and a standard macOS Settings window.
- The menu bar icon is drawn from the desk's real height, and can show the height as text.
- Up to four extra named presets.
- Calibration against a tape measure. Presets keep their physical positions when you calibrate.
- Activity history with a chart, counting only time you're actually at the Mac.
- Simplified Chinese added; English, Traditional Chinese and Japanese updated.
- The in-app language picker is gone. Use System Settings → General → Language & Region → Applications to run the app in a different language.

### Automation

- Global keyboard shortcuts for Sit, Stand and Toggle.
- Shortcuts and Siri actions: Stand Up, Sit Down, Toggle Sit/Stand, Move Desk to Height, Get Desk Height.
- AppleScript gains `toggle` and `stop`. `move` and `move to` previously shared an Apple event code, so `move to` could be routed to the wrong command.

### Project

- Requires macOS 14. Universal binary (Apple silicon and Intel).
- Folder-synchronized Xcode groups, String Catalogs, and a unit test target.
- Debug builds can render every screen with sample data (`--render-previews`).

### Upgrading from 1.x

Sitting and standing heights, saved desks, units, the double-tap setting and activity history carry over. If 1.x showed a height offset, it becomes the new calibration so the numbers you're used to don't change.
