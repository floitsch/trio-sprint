# Set Sprint

A Flutter Set game: find **five sets in a row**, with a two-second countdown
before the cards appear and the stopwatch starts. Tap **Play again** for a fresh
run. No accounts, ads, network requests, or runtime dependencies.

For each feature — number, shape, color, fill — the three selected cards must be
all the same or all different. A wrong trio counts as a mistake while the clock
keeps running. Tap a selected card again to deselect it. The board always has 12
cards and at least one set. Your best time is kept for the current app session.
Leaving the app does not pause the stopwatch.

## Run

The Flutter SDK, Android Studio, Android SDK and build caches live in the ignored
`.tooling/` folder. The launchers configure their paths for this project.

```sh
./toolw flutter run -d chrome
# Or connect an Android phone with USB debugging enabled:
./toolw flutter run
# Open this project in Android Studio:
./studio
```

Select `.tooling/flutter` as the Flutter SDK in the IDE if prompted. The Flutter
IDE plugin can be installed from Android Studio's Plugins settings.

## Check and build

```sh
./toolw flutter analyze
./toolw flutter test
./toolw flutter build apk --debug --target-platform android-arm,android-arm64
./toolw flutter build web --no-web-resources-cdn
```

The Android debug APK for ARM phones is written to
`build/app/outputs/flutter-apk/app-debug.apk`. Omit `--target-platform` to also
include x86_64 emulator support.
The browser build is written to `build/web/`; serve it over HTTP rather than
opening `index.html` directly.

`lib/game.dart` contains the deck, rules, streak and solvability logic.
`lib/card_view.dart` draws the cards, and `lib/main.dart` contains the screens,
countdown and stopwatch.
