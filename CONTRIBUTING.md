# Contributing

Thanks for taking a look at IDASEN Desk.

The project is small, but it controls a real desk, so I care more about boring, predictable behavior than clever code. A polished UI is welcome; surprising movement is not.

## Development

Use Xcode 16 or newer. The app targets macOS 14 or newer.

```sh
open "IDASEN Desk.xcodeproj"
```

Before opening a pull request, please run:

```sh
xcodebuild -project "IDASEN Desk.xcodeproj" -scheme "IDASEN Desk" -configuration Release -derivedDataPath .derivedData build
xcodebuild -project "IDASEN Desk.xcodeproj" -scheme "IDASEN Desk" -configuration Debug -derivedDataPath .derivedData analyze
xcodebuild -project "IDASEN Desk.xcodeproj" -scheme "IDASEN Desk" -derivedDataPath .derivedData test
```

For UI changes, render the screens with sample data and look at them in light and dark mode:

```sh
".derivedData/Build/Products/Debug/IDASEN Desk.app/Contents/MacOS/IDASEN Desk" --render-previews /tmp/previews
```

The project uses folder-synchronized groups, so new files only need to be added to the right folder. User-facing strings live in `Localizable.xcstrings`; please add translations for every language when you add a string.

## What To Be Careful With

- Bluetooth reconnect behavior should stay calm and predictable.
- Movement cancellation should always be easy to reason about.
- Nothing moves the desk without a direct action from the person: a click, a shortcut, a handle gesture, or a reminder button.
- Health stats should stay local.
- UI controls should look like what they do. If something is not draggable, do not make it look draggable.

## Code Style

- Prefer SwiftUI-native controls.
- Keep Bluetooth, motion state, settings, and UI responsibilities separated.
- Keep decision logic (like `TargetMove`, `PostureTracker`, `HandleGestureDetector`) free of CoreBluetooth and UI so it can be unit tested.
- Avoid force unwraps in runtime paths.
- Keep user-facing text short.
- Add comments for non-obvious behavior, not for line-by-line narration.

## Pull Requests

Please include:

- what changed
- why it changed
- how you tested it
- any desk hardware or Bluetooth assumptions
