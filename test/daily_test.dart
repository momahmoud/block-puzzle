import 'package:block_puzzle/game/levels.dart';
import 'package:block_puzzle/services/daily_challenge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('the daily level is the same for everyone on a day, and changes daily',
      () {
    final a = LevelSpec.daily(300);
    final b = LevelSpec.daily(300);
    final c = LevelSpec.daily(301);
    expect(a.cells, b.cells);
    expect(a.goals.map((g) => g.target), b.goals.map((g) => g.target));
    expect(a.cells == c.cells && a.number == c.number, isFalse);
    expect(a.isDaily, isTrue);
  });

  test('streaks grow on consecutive days and reset after a missed day',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    var now = DateTime.utc(2026, 10, 15, 9);
    final daily = DailyChallenge(prefs, clock: () => now);

    expect(daily.streak, 0);
    expect(daily.complete(), isTrue);
    expect(daily.complete(), isFalse); // once a day
    expect(daily.streak, 1);

    now = DateTime.utc(2026, 10, 16, 20);
    expect(daily.doneToday, isFalse);
    expect(daily.streak, 1); // still alive today
    daily.complete();
    expect(daily.streak, 2);

    now = DateTime.utc(2026, 10, 18, 8); // skipped the 17th
    expect(daily.streak, 0);
    daily.complete();
    expect(daily.streak, 1);
    expect(daily.bestStreak, 2);
  });
}
