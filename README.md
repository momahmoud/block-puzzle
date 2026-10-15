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

## Monetisation, boosters and daily challenge

- **Boosters** (`lib/services/boosters.dart`): bomb (clears 3x3, collects
  gems, smashes ice), rotate (turns a tray piece) and undo. Players start with
  2 of each; an empty booster can be refilled with a rewarded ad, and the
  daily challenge gives one.
- **Second chances**: Classic and levels that run out of space can revive
  once (clears the two fullest rows and columns) by watching an ad; levels
  that run out of moves can get +5 moves once.
- **Ads** (`lib/services/ads.dart`, `lib/ui/banner_slot.dart`): Google's
  consent form (UMP) runs first; then rewarded ads, an interstitial every 3
  finished games (`AppConfig.interstitialEveryGames`) and an anchored
  adaptive banner along the bottom of the game screen (never covered by the
  game-over overlay). Buying "Remove ads" turns off the interstitial and the
  banner; rewarded ads stay, since players choose them.
- **Daily challenge** (`lib/services/daily_challenge.dart`): one level per
  UTC day, the same for everyone; the move limit is tuned on the device by
  the level bot. Streak counter and a booster reward.
- **Leaderboards and achievements** (`lib/services/game_services.dart`):
  Classic best and total level stars, plus 12 achievements. Off until
  configured (below).

All ids live in `lib/config.dart`.

## Before releasing

Already done: app id `com.fluxylabs.blockPuzzle` (Android and iOS), and an
Android upload key. The key is at `~/keystores/fluxylabs-block-puzzle-upload.jks`
with its password in `android/key.properties` (git-ignored). **Back both up
somewhere safe**: Play Console needs the same upload key for every update
(it can be reset through Play support, but that takes days).

1. **AdMob**: create the app and three ad units (rewarded, interstitial, banner) at
   https://admob.google.com. Put the unit ids in `lib/config.dart` and the
   app id in `android/app/src/main/AndroidManifest.xml`
   (`com.google.android.gms.ads.APPLICATION_ID`) and `ios/Runner/Info.plist`
   (`GADApplicationIdentifier`). The current ones are Google's test ids.
   Also set up the GDPR and IDFA messages under Privacy & messaging.
2. **Remove ads**: in Play Console > Monetize > In-app products, create a
   one-time product with id `remove_ads`.
3. **Play Games Services**: in Play Console > Play Games Services, create the
   project, add credentials (the upload key's SHA-1, and later the Play app
   signing key's SHA-1), create the 2 leaderboards and 12 achievements (see
   `Award` in `lib/services/game_services.dart`). Replace
   `android/app/src/main/res/values/games-ids.xml` with the generated one,
   fill the Android ids in `lib/config.dart` and `Award`, and set
   `AppConfig.gameServicesEnabled = true`.
4. **Store listing**: privacy policy
   https://momahmoud.github.io/Fluxy-Labs/privacy-policy.html (also linked in
   Settings). Declare in the Data safety form that the app uses AdMob
   (advertising ID, diagnostics) and in-app purchases. Content rating: the
   game itself has no violence; ads mean "Contains ads" must be ticked.
5. Build: `flutter build appbundle` and upload
   `build/app/outputs/bundle/release/app-release.aab`.
6. Bump `version:` in `pubspec.yaml` for each upload.
