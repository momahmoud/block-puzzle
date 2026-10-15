import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Player preferences, saved between launches.
class Settings extends ChangeNotifier {
  Settings(this._prefs)
      : _sound = _prefs.getBool(_soundKey) ?? true,
        _haptics = _prefs.getBool(_hapticsKey) ?? true,
        _themeId = _prefs.getString(_themeKey) ?? 'neon',
        _tutorialDone = _prefs.getBool(_tutorialKey) ?? false;

  static const _soundKey = 'sound';
  static const _hapticsKey = 'haptics';
  static const _themeKey = 'theme';
  static const _tutorialKey = 'tutorialDone';

  final SharedPreferences _prefs;
  bool _sound;
  bool _haptics;
  String _themeId;
  bool _tutorialDone;

  bool get sound => _sound;
  bool get haptics => _haptics;
  String get themeId => _themeId;

  /// True once the player has placed their first piece.
  bool get tutorialDone => _tutorialDone;

  set sound(bool value) {
    _sound = value;
    _prefs.setBool(_soundKey, value);
    notifyListeners();
  }

  set haptics(bool value) {
    _haptics = value;
    _prefs.setBool(_hapticsKey, value);
    notifyListeners();
  }

  set themeId(String value) {
    _themeId = value;
    _prefs.setString(_themeKey, value);
    notifyListeners();
  }

  set tutorialDone(bool value) {
    if (_tutorialDone == value) return;
    _tutorialDone = value;
    _prefs.setBool(_tutorialKey, value);
    notifyListeners();
  }
}
