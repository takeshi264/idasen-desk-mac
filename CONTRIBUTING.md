# Contributing

Thanks for taking a look at IDASEN Desk.

The project is small, but it controls a real desk, so I care more about boring, predictable behavior than clever code. A polished UI is welcome; surprising movement is not.

## Development

Use Xcode 15 or newer on macOS 13 or newer.

```sh
open "IDASEN Desk.xcodeproj"
```

Before opening a pull request, please run:

```sh
xcodebuild -project "IDASEN Desk.xcodeproj" -scheme "IDASEN Desk" -configuration Release -derivedDataPath .derivedData build
xcodebuild -project "IDASEN Desk.xcodeproj" -scheme "IDASEN Desk" -configuration Debug -derivedDataPath .derivedData analyze
```

## What To Be Careful With

- Bluetooth reconnect behavior should stay calm and predictable.
- Movement cancellation should always be easy to reason about.
- Automatic standing should ask first.
- Health stats should stay local.
- UI controls should look like what they do. If something is not draggable, do not make it look draggable.

## Code Style

- Prefer SwiftUI-native controls.
- Keep Bluetooth, motion state, settings, and UI responsibilities separated.
- Avoid force unwraps in runtime paths.
- Keep user-facing text short.
- Add comments for non-obvious behavior, not for line-by-line narration.

## Pull Requests

Please include:

- what changed
- why it changed
- how you tested it
- any desk hardware or Bluetooth assumptions
