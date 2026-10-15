import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/widgets.dart';

import 'settings.dart';

/// The background music loop. Plays while the app is in front, music is
/// on in settings, and nothing (like an ad) is holding it.
class Music with WidgetsBindingObserver {
  Music(this.settings);

  final Settings settings;
  AudioPlayer? _player;
  bool _foreground = true;
  int _holds = 0;
  bool _playing = false;

  static const double volume = 0.3;

  Future<void> init() async {
    try {
      final player = AudioPlayer();
      await player.setReleaseMode(ReleaseMode.loop);
      await player.setVolume(volume);
      await player.setSource(AssetSource('sounds/music.wav'));
      _player = player;
      settings.addListener(_apply);
      WidgetsBinding.instance.addObserver(this);
      _apply();
    } catch (e) {
      debugPrint('Music: not available: $e');
    }
  }

  /// Pauses the music until [release] (used around ads).
  void hold() {
    _holds++;
    _apply();
  }

  void release() {
    if (_holds > 0) _holds--;
    _apply();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _apply();
  }

  void _apply() {
    final player = _player;
    if (player == null) return;
    final should = settings.music && _foreground && _holds == 0;
    if (should == _playing) return;
    _playing = should;
    (should ? player.resume() : player.pause()).catchError((Object e) {
      debugPrint('Music: $e');
    });
  }
}
