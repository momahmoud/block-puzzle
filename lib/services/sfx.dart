import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'settings.dart';

/// Sound effects and haptics, both respecting [Settings].
class Sfx {
  Sfx(this.settings);

  final Settings settings;
  final Map<String, AudioPool> _pools = {};

  static const _sounds = [
    'pick',
    'place',
    'fail',
    'praise',
    'all_clear',
    'game_over',
    'best',
    'ice',
    'clear_1',
    'clear_2',
    'clear_3',
    'clear_4',
    'clear_5',
    'clear_6',
  ];

  /// Loads the sounds. Sound is optional, so failures are only logged.
  Future<void> init() async {
    try {
      // Mix with the player's own music, and stay quiet on silent mode.
      await AudioPlayer.global.setAudioContext(AudioContext(
        iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
        android: const AudioContextAndroid(
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.game,
          audioFocus: AndroidAudioFocus.none,
        ),
      ));
    } catch (e) {
      debugPrint('Sfx: audio context not set: $e');
    }
    for (final name in _sounds) {
      try {
        _pools[name] = await AudioPool.createFromAsset(
          path: 'sounds/$name.wav',
          maxPlayers: 3,
          playerMode: PlayerMode.lowLatency,
        );
      } catch (e) {
        debugPrint('Sfx: could not load $name: $e');
      }
    }
  }

  void _play(String name, {double volume = 1}) {
    if (!settings.sound) return;
    _pools[name]?.start(volume: volume).catchError((Object e) {
      debugPrint('Sfx: could not play $name: $e');
      return () async {};
    });
  }

  void pick() {
    _play('pick', volume: 0.6);
    if (settings.haptics) HapticFeedback.selectionClick();
  }

  void place() {
    _play('place');
    if (settings.haptics) HapticFeedback.lightImpact();
  }

  void fail() => _play('fail', volume: 0.7);

  /// A line clear; the pitch rises with the combo.
  void clear({required int lines, required int combo, required bool allClear}) {
    _play('clear_${math.min(math.max(combo, 1), 6)}');
    if (allClear) {
      _play('all_clear');
    } else if (lines >= 2) {
      _play('praise', volume: 0.8);
    }
    if (settings.haptics) {
      lines >= 3 || allClear
          ? HapticFeedback.heavyImpact()
          : HapticFeedback.mediumImpact();
    }
  }

  void gameOver() {
    _play('game_over');
    if (settings.haptics) HapticFeedback.heavyImpact();
  }

  void newBest() => _play('best');

  void levelComplete() {
    _play('best');
    if (settings.haptics) HapticFeedback.heavyImpact();
  }

  void gem() => _play('praise', volume: 0.6);

  void ice() => _play('ice', volume: 0.8);

  void bomb() {
    _play('clear_3');
    _play('ice', volume: 0.6);
    if (settings.haptics) HapticFeedback.heavyImpact();
  }

  void tap() {
    if (settings.haptics) HapticFeedback.selectionClick();
  }

  /// The dragged piece moved to a new square.
  void tick() {
    if (settings.haptics) HapticFeedback.selectionClick();
  }
}
