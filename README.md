# Block Puzzle

An 8x8 block-placement puzzle in plain Flutter (no game engine needed), in
the style of the classic mode of Block Blast!. Runs on iOS and Android
(portrait only).

## Run

```
flutter pub get
flutter test
flutter run            # pick an iOS simulator / Android emulator or device
```

## How it plays

- Drag a piece from the tray onto the board. It grows to board size, floats
  above your finger and snaps to the nearest square that fits, with a preview.
  Rows and columns the drop would clear light up in the piece's colour.
- Full rows and columns clear. Score: 1 point per square placed, plus
  `10 × n(n+1)/2` for clearing n lines at once, multiplied by the combo step.
- Combo: each placement that clears a line raises it. It survives two
  placements without a clear and ends on the third.
- Emptying the board gives an All Clear bonus (+300).
- Pieces that cannot fit anywhere are greyed out. The game ends when none of
  the remaining pieces fit.
- Progress is saved after every move, so closing the app resumes the game.

## Levels mode

200 levels in 10 chapters of 20 (Warm Up, Gem Mine, Ice Cave, … Grand
Master). Each level starts with a patterned board (stairs, pyramid, frame,
diamond, skyline, mirrored shapes and more), has a move limit, and one or two
goals: reach a score, clear lines, collect gems (clear the line a gem sits in)
or break ice (frozen blocks survive one clear). Gems start at level 6 and ice
at level 41. Winning gives 1–3 stars by moves left and unlocks the next level.

Difficulty rises across the game and within each chapter, every tenth level
is a marked Hard level, and the level after it is a breather.

Layouts come from `lib/game/levels.dart` and `lib/game/level_patterns.dart`
(the same level number always gives the same level). Move limits and target
sizes come from `lib/game/level_tuning.dart`, which is generated:

```
flutter test tool/calibrate_levels_test.dart
```

The calibrator has a bot (`test/support/level_bot.dart`) play every level 24
times. It sizes the goals so levels take a sensible number of moves, then sets
each move limit so the bot wins about 95% of the time on the easiest levels
down to about 35% on the hardest. Rerun it after changing level generation;
`test/levels_test.dart` checks the table covers every level and that the bot
can beat each one within its limit.

## Layout

- `lib/game/` rules only (no widgets): `piece.dart` (shapes and their deal
  weights), `grid.dart`, `dealer.dart` (picks tray pieces that can all be
  placed), `game_controller.dart` (scoring, combos, save/restore, level
  goals), `levels.dart` (level layouts and goals)
- `lib/services/` settings and sound/haptics
- `lib/ui/` drawing, drag handling and effects
- `test/` rule tests (`game_test.dart`) and widget tests (`screen_test.dart`)
- `tool/generate_assets.py` makes the sound effects and icon in `assets/`

To change the icon or sounds, edit and run the generator, then regenerate the
platform icons and splash:

```
python3 tool/generate_assets.py
dart run flutter_launcher_icons
dart run flutter_native_splash:create
```

## Before releasing

1. **App ID.** Replace the placeholder `com.example...`:
   - Android: `namespace` and `applicationId` in `android/app/build.gradle.kts`
     (and move `MainActivity.kt` to the matching package folder).
   - iOS: Bundle Identifier in Xcode (Runner target → General).
2. **Android signing.** Create an upload key and `android/key.properties`
   (see the comment in `android/app/build.gradle.kts`), then
   `flutter build appbundle`.
3. **iOS signing.** Open `ios/Runner.xcworkspace`, choose your team under
   Signing & Capabilities, then `flutter build ipa`.
4. Bump `version:` in `pubspec.yaml` for each store upload.
