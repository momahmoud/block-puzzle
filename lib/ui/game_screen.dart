import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../game/game_controller.dart';
import '../game/grid.dart';
import '../game/levels.dart';
import '../game/piece.dart';
import '../services/app_services.dart';
import '../services/boosters.dart';
import '../services/level_progress.dart';
import '../services/stats.dart';
import '../services/settings.dart';
import '../services/sfx.dart';
import 'board_painter.dart';
import 'level_map_screen.dart';
import 'palette.dart';
import 'piece_view.dart';
import 'banner_slot.dart';
import 'remove_ads.dart';
import 'settings_sheet.dart';
import 'theme.dart';
import 'tips.dart';
import 'widgets.dart';

part 'game_end.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({
    super.key,
    required this.controller,
    required this.app,
  });

  final GameController controller;
  final AppServices app;

  Settings get settings => app.settings;
  Sfx get sfx => app.sfx;
  LevelProgress get levels => app.levels;
  Stats get stats => app.stats;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with TickerProviderStateMixin {
  /// How far above the finger the dragged piece floats, so it stays visible.
  static const double _liftPx = 72;

  /// Tray pieces are drawn at this fraction of the board square size.
  static const double _trayScale = 0.55;

  final GlobalKey _stackKey = GlobalKey();
  final GlobalKey _boardKey = GlobalKey();
  final List<GlobalKey> _slotKeys =
      List.generate(GameController.trayCount, (_) => GlobalKey());
  final math.Random _rng = math.Random();

  double _cell = 40; // board square size, set in _buildLayout

  // Dragging.
  int? _dragIndex;
  int? _pointer;
  Offset? _finger; // global coordinates
  Offset _dragStart = Offset.zero;
  late final AnimationController _lift = _anim(120);

  // A piece flying back to the tray after a drop that did not fit.
  int? _returnIndex;
  Offset _returnFrom = Offset.zero; // global top-left
  double _returnFromCell = 0;
  late final AnimationController _return = _anim(220);

  // Squares that bounce after a placement.
  Set<int> _popCells = const {};
  late final AnimationController _pop = _anim(220, done: true);

  // Line clear burst.
  List<ClearedCell> _cleared = const [];
  List<int> _clearGems = const [];
  List<int> _clearIce = const [];
  List<Particle> _particles = const [];
  Offset _clearOrigin = Offset.zero;
  bool _shake = false;
  late final AnimationController _clear = _anim(750, done: true);

  // "Great!", "Combo 3" and "+120" labels.
  String? _praise;
  String? _comboLabel;
  int _points = 0;
  Offset _pointsAt = Offset.zero; // in board squares
  late final AnimationController _labels = _anim(1300, done: true);

  // New pieces popping into the tray.
  int _seenDeal = -1;
  late final AnimationController _spawn = _anim(480, done: true);

  // "New Best!" banner, shown once per game when the old best is passed.
  bool _bestCelebrated = false;
  late final AnimationController _bestBanner = _anim(1800, done: true);

  // Last snap square while dragging, to tick when it changes.
  ({int row, int col})? _lastSnap;

  // First-launch hint: a hand dragging a piece onto the board.
  late final AnimationController _hint = _anim(2000);

  // Boosters: bomb waits for a tap on the board, rotate for a tap on a
  // tray piece.
  _Mode _mode = _Mode.none;
  bool _watchingAd = false;

  // Daily challenge reward, once won.
  Booster? _dailyReward;

  // Game over: the board greys out, then the results card appears.
  bool _overStarted = false;
  _End _end = _End.none;
  bool get _showResults => _end != _End.none;

  /// Counts down the second-chance offer, then moves on to the results.
  late final AnimationController _offer = _anim(_offerSeconds * 1000);
  static const int _offerSeconds = 6;
  Timer? _overTimer;
  late final AnimationController _over = _anim(1400);
  late final AnimationController _results = _anim(400);

  GameController get _game => widget.controller;
  Sfx get _sfx => widget.sfx;
  bool get _showHint =>
      !widget.settings.tutorialDone && !_game.gameOver && _dragIndex == null;
  double get _trayCell => _cell * _trayScale;

  AnimationController _anim(int ms, {bool done = false}) {
    final c =
        AnimationController(vsync: this, duration: Duration(milliseconds: ms));
    if (done) c.value = 1;
    return c;
  }

  @override
  void initState() {
    super.initState();
    _seenDeal = _game.dealCount;
    _spawn.forward(from: 0);
    _game.addListener(_onGameChanged);
    _bestCelebrated = _game.bestAtStart == 0 || _game.score > _game.bestAtStart;
    if (!widget.settings.tutorialDone) _hint.repeat();
    if (_game.gameOver) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _startGameOver());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowTip());
  }

  /// Built once so the banner is not reloaded on every frame.
  late final Widget _banner = _BannerArea(app: widget.app);

  @override
  void dispose() {
    _game.removeListener(_onGameChanged);
    _overTimer?.cancel();
    for (final c in [
      _lift,
      _return,
      _pop,
      _clear,
      _labels,
      _spawn,
      _over,
      _results,
      _bestBanner,
      _hint,
      _offer,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _onGameChanged() {
    if (_game.dealCount != _seenDeal) {
      _seenDeal = _game.dealCount;
      _spawn.forward(from: 0);
    }
    if (_game.gameOver) _startGameOver();
  }

  // ---------------------------------------------------------------- dragging

  double get _floatCell =>
      lerpDouble(_trayCell, _cell, Curves.easeOut.transform(_lift.value))!;

  /// Top-left corner of the floating piece, in global coordinates.
  Offset _floatTopLeft(Piece piece, Offset finger) {
    final cell = _floatCell;
    final lift = _liftPx * Curves.easeOut.transform(_lift.value);
    return finger - Offset(piece.cols * cell / 2, piece.rows * cell + lift);
  }

  /// The board square the dragged piece would snap to, or null if it does
  /// not fit near there. Picks the closest fitting square within reach, so
  /// drops do not need to be pixel perfect.
  ({int row, int col})? _snap(Piece piece) {
    final finger = _finger;
    final box = _boardKey.currentContext?.findRenderObject() as RenderBox?;
    if (finger == null || box == null || !box.hasSize) return null;
    final local = box.globalToLocal(_floatTopLeft(piece, finger));
    final fr = local.dy / _cell;
    final fc = local.dx / _cell;

    ({int row, int col})? best;
    var bestDist = 0.75;
    for (final r in {fr.floor(), fr.ceil()}) {
      for (final c in {fc.floor(), fc.ceil()}) {
        final d = Offset(fr - r, fc - c).distance;
        if (d < bestDist && _game.grid.canPlace(piece, r, c)) {
          best = (row: r, col: c);
          bestDist = d;
        }
      }
    }
    return best;
  }

  void _pointerDown(int index, PointerDownEvent e) {
    if (_mode == _Mode.rotate && _game.tray[index] != null) {
      if (widget.app.boosters.use(Booster.rotate)) {
        _game.rotate(index);
        _sfx.pick();
        if (!_game.gameOver) _resumeFromOver();
      }
      setState(() => _mode = _Mode.none);
      return;
    }
    if (_mode == _Mode.bomb) return;
    if (_game.gameOver || _dragIndex != null || _game.tray[index] == null) {
      return;
    }
    if (_returnIndex == index) return;
    _sfx.pick();
    setState(() {
      _pointer = e.pointer;
      _dragIndex = index;
      _finger = e.position;
      _dragStart = e.position;
    });
    _lift.forward(from: 0);
  }

  void _pointerMove(PointerMoveEvent e) {
    if (e.pointer != _pointer) return;
    setState(() => _finger = e.position);
    final index = _dragIndex;
    final piece = index == null ? null : _game.tray[index];
    if (piece == null) return;
    final snap = _snap(piece);
    if (snap != null && snap != _lastSnap) _sfx.tick();
    _lastSnap = snap;
  }

  void _pointerUp(PointerEvent e, {required bool drop}) {
    if (e.pointer != _pointer) return;
    final index = _dragIndex;
    final finger = _finger;
    final piece = index == null ? null : _game.tray[index];
    if (index == null || piece == null || finger == null) {
      _resetDrag();
      return;
    }

    final snap = drop ? _snap(piece) : null;
    if (snap != null && _game.place(index, snap.row, snap.col)) {
      _resetDrag();
      _celebrate(_game.lastMove!);
      return;
    }

    // Fly back to the tray.
    if (drop && (finger - _dragStart).distance > 24) _sfx.fail();
    _returnIndex = index;
    _returnFrom = _floatTopLeft(piece, finger);
    _returnFromCell = _floatCell;
    _resetDrag();
    _return.forward(from: 0).whenComplete(() {
      if (mounted) setState(() => _returnIndex = null);
    });
  }

  void _resetDrag() {
    _lastSnap = null;
    setState(() {
      _dragIndex = null;
      _pointer = null;
      _finger = null;
    });
  }

  // ---------------------------------------------------------------- effects

  void _celebrate(MoveResult move) {
    _sfx.place();
    if (!widget.settings.tutorialDone) {
      widget.settings.tutorialDone = true;
      _hint.stop();
    }
    if (!_bestCelebrated && _game.score > _game.bestAtStart) {
      _bestCelebrated = true;
      _sfx.newBest();
      _bestBanner.forward(from: 0);
    }
    _popCells = {
      for (final c in move.piece.cells)
        (move.row + c.row) * Grid.size + move.col + c.col,
    };
    _pop.forward(from: 0);

    if (move.lines == 0) return;

    final center = Offset(
      move.col + move.piece.cols / 2 - 0.5,
      move.row + move.piece.rows / 2 - 0.5,
    );
    _sfx.clear(lines: move.lines, combo: move.combo, allClear: move.allClear);
    _cleared = move.clear.cells;
    _clearGems = move.gems;
    _clearIce = move.ice;
    if (move.gems.isNotEmpty) _sfx.gem();
    if (move.ice.isNotEmpty) _sfx.ice();
    _clearOrigin = center;
    _particles = [
      for (final c in _cleared)
        for (var i = 0; i < 2; i++) _particle(c, GameTheme.of(context)),
    ];
    _shake = move.lines >= 3 || move.allClear;
    _clear.forward(from: 0);

    _praise = move.allClear ? 'All Clear!' : _praiseFor(move.lines);
    _comboLabel = move.combo >= 2 ? 'Combo ${move.combo}' : null;
    _points = move.points;
    _pointsAt = center;
    _labels.forward(from: 0);
  }

  Particle _particle(ClearedCell c, GameTheme theme) {
    final angle = _rng.nextDouble() * math.pi * 2;
    final speed = 0.8 + _rng.nextDouble() * 1.6;
    return Particle(
      origin: Offset(c.col + 0.5, c.row + 0.5),
      velocity: Offset(math.cos(angle), math.sin(angle) - 0.6) * speed,
      color: theme.block(c.colorId),
      size: 0.16 + _rng.nextDouble() * 0.2,
      spin: (_rng.nextDouble() - 0.5) * 8,
    );
  }

  static String? _praiseFor(int lines) => switch (lines) {
        <= 1 => null,
        2 => 'Good!',
        3 => 'Great!',
        4 => 'Excellent!',
        5 => 'Amazing!',
        _ => 'Unbelievable!',
      };

  void _startGameOver() {
    if (_overStarted) return;
    _overStarted = true;
    // Let the last clear finish first.
    _overTimer =
        Timer(Duration(milliseconds: _clear.isAnimating ? 700 : 350), () {
      if (!mounted) return;
      final level = _game.level;
      if (level != null && _game.won) {
        if (level.isDaily) {
          _dailyReward = widget.app.afterDailyWin();
        } else {
          widget.app.afterLevelWin(level.number, _game.stars);
        }
        _sfx.levelComplete();
      } else {
        _sfx.gameOver();
      }
      _over.forward(from: 0).whenComplete(() {
        if (!mounted || !_game.gameOver) return;
        if (_hasSecondChance) {
          setState(() => _end = _End.offer);
          _results.forward(from: 0);
          _offer.forward(from: 0).whenComplete(() {
            if (mounted && _end == _End.offer && _offer.value >= 1) {
              _showFinalResults();
            }
          });
        } else {
          _showFinalResults();
        }
      });
    });
  }

  bool get _hasSecondChance =>
      !_game.won &&
      (_game.canRevive ||
          _game.canAddMoves ||
          (_game.canUndo && widget.app.boosters.count(Booster.undo) > 0));

  void _showFinalResults() {
    _offer.stop();
    setState(() => _end = _End.results);
    _results.forward(from: 0);
    if (!_game.isLevel && _game.isNewBest && _game.bestAtStart == 0) {
      _sfx.newBest();
    }
  }

  void _declineOffer() {
    _sfx.tap();
    _showFinalResults();
  }

  /// After a finished game, shows an interstitial now and then.
  Future<void> _betweenGames() async {
    if (!_game.gameOver) return;
    final app = widget.app;
    app.music.hold();
    try {
      await app.ads.gameFinished();
    } finally {
      app.music.release();
    }
  }

  Future<void> _restart() async {
    await _betweenGames();
    if (!mounted) return;
    _mode = _Mode.none;
    _dailyReward = null;
    _overTimer?.cancel();
    _overStarted = false;
    _end = _End.none;
    _offer.reset();
    _over.reset();
    _results.reset();
    _clear.value = 1;
    _labels.value = 1;
    _pop.value = 1;
    _returnIndex = null;
    _bestBanner.value = 1;
    _game.newGame();
    _bestCelebrated = _game.bestAtStart == 0;
  }

  Future<void> _goHome() async {
    _sfx.tap();
    await _betweenGames();
    if (mounted) Navigator.of(context).maybePop();
  }

  /// Levels: opens level [number] in place of this one.
  Future<void> _openLevel(int number) async {
    _sfx.tap();
    await _betweenGames();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      levelRoute(number: number, app: widget.app),
    );
  }

  // ---------------------------------------------------------------- boosters

  /// Hides the game-over overlay after a revive, undo or booster.
  void _resumeFromOver() {
    if (_game.gameOver) return;
    _overTimer?.cancel();
    setState(() {
      _overStarted = false;
      _end = _End.none;
      _dailyReward = null;
    });
    _offer.reset();
    _over.reset();
    _results.reset();
  }

  /// Watches a rewarded ad; true if the reward was earned.
  Future<bool> _watchAd() async {
    if (_watchingAd) return false;
    setState(() => _watchingAd = true);
    _offer.stop();
    final ok = await widget.app.watchAd();
    if (!mounted) return false;
    setState(() => _watchingAd = false);
    if (!ok && _end == _End.offer) {
      _offer.forward().whenComplete(() {
        if (mounted && _end == _End.offer && _offer.value >= 1) {
          _showFinalResults();
        }
      });
    }
    if (!ok) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
            content:
                Text('No reward this time. Please try again in a moment.')),
      );
    }
    return ok;
  }

  Future<void> _tapBooster(Booster b) async {
    final boosters = widget.app.boosters;
    if (_game.won) return;
    _sfx.tap();
    if (boosters.count(b) == 0) {
      if (await _watchAd()) boosters.add(b);
      return;
    }
    switch (b) {
      case Booster.undo:
        if (_game.canUndo && boosters.use(Booster.undo)) {
          _game.undo();
          _popCells = const {};
          _labels.value = 1;
          _resumeFromOver();
        }
      case Booster.bomb:
        setState(() => _mode = _mode == _Mode.bomb ? _Mode.none : _Mode.bomb);
      case Booster.rotate:
        setState(
            () => _mode = _mode == _Mode.rotate ? _Mode.none : _Mode.rotate);
    }
  }

  void _boardTapped(TapUpDetails d) {
    if (_mode != _Mode.bomb) return;
    final row = (d.localPosition.dy / _cell).floor().clamp(0, Grid.size - 1);
    final col = (d.localPosition.dx / _cell).floor().clamp(0, Grid.size - 1);
    if (!widget.app.boosters.use(Booster.bomb)) return;
    final removed = _game.bomb(row, col);
    _sfx.bomb();
    _cleared = removed;
    _clearGems = const [];
    _clearIce = const [];
    _clearOrigin = Offset(col.toDouble(), row.toDouble());
    _particles = [
      for (final c in removed)
        for (var i = 0; i < 4; i++) _particle(c, GameTheme.of(context)),
    ];
    _shake = true;
    _clear.forward(from: 0);
    setState(() => _mode = _Mode.none);
    _resumeFromOver();
  }

  Future<void> _revive() async {
    if (await _watchAd() && _game.revive()) {
      _sfx.clear(lines: 4, combo: 1, allClear: false);
      _resumeFromOver();
    }
  }

  Future<void> _addMoves() async {
    if (await _watchAd() && _game.addMoves()) {
      _sfx.levelComplete();
      _resumeFromOver();
    }
  }

  void _undoFromResults() {
    if (_game.canUndo && widget.app.boosters.use(Booster.undo)) {
      _game.undo();
      _resumeFromOver();
    }
  }

  /// The first level with gems, and the first with ice, explain them.
  void _maybeShowTip() {
    final level = _game.level;
    if (level == null || !mounted) return;
    final settings = widget.settings;
    String? tip;
    if (level.ice.isNotEmpty && !settings.tipShown('ice')) {
      tip = 'ice';
    } else if (level.gems.isNotEmpty && !settings.tipShown('gems')) {
      tip = 'gems';
    }
    if (tip == null) return;
    settings.markTipShown(tip);
    showTipDialog(context, tip);
  }

  void _openMenu() {
    _sfx.tap();
    showSettingsSheet(
      context,
      app: widget.app,
      onRestart: _restart,
      onHome: _goHome,
    );
  }

  // ---------------------------------------------------------------- layout

  @override
  Widget build(BuildContext context) {
    final theme = GameTheme.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: theme.backgroundBottom,
      ),
      child: Scaffold(
        body: AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          decoration: BoxDecoration(gradient: theme.background),
          child: AnimatedBuilder(
            animation: Listenable.merge(
              [
                _game,
                _lift,
                _return,
                _pop,
                _clear,
                _labels,
                _spawn,
                _over,
                _results,
                _offer,
                _bestBanner,
                _hint,
                widget.app.boosters,
                widget.app.ads,
              ],
            ),
            builder: (context, _) => Column(
              children: [
                // The end-of-game overlay stops above the banner: ads may
                // not be covered.
                Expanded(
                  child: Stack(
                    children: [
                      SafeArea(
                          bottom: false,
                          child: LayoutBuilder(builder: _buildLayout)),
                      if (_showResults)
                        Positioned.fill(child: _endOverlay(theme)),
                    ],
                  ),
                ),
                _banner,
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLayout(BuildContext context, BoxConstraints box) {
    const hudHeight = 150.0;
    const boosterHeight = 72.0;
    final theme = GameTheme.of(context);
    final trayRows = 5 * _trayScale;
    _cell = math
        .min(
          (box.maxWidth - 40) / Grid.size,
          (box.maxHeight - hudHeight - boosterHeight - 48) /
              (Grid.size + trayRows + 0.6),
        )
        .clamp(16.0, 64.0);
    final boardSide = _cell * Grid.size;

    final dragIndex = _dragIndex;
    final dragged = dragIndex == null ? null : _game.tray[dragIndex];
    final snap = dragged == null ? null : _snap(dragged);

    return Stack(
      key: _stackKey,
      children: [
        Positioned.fill(
          child: Column(
            children: [
              SizedBox(
                  height: hudHeight,
                  child: _game.isLevel ? _levelHud(theme) : _hud()),
              Expanded(
                child: Center(
                  child: Transform.translate(
                    offset: _shakeOffset(),
                    child: _board(theme, boardSide, dragged, snap),
                  ),
                ),
              ),
              SizedBox(height: boosterHeight, child: _boosterBar(theme)),
              SizedBox(
                height: _trayCell * 5 + 32,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Row(
                    children: [
                      for (var i = 0; i < GameController.trayCount; i++)
                        Expanded(child: _slot(i)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_showHint)
          ..._hintWidgets(
              stackBox:
                  _stackKey.currentContext?.findRenderObject() as RenderBox?),
        ..._floatingPiece(dragged),
        if (_bestBanner.isAnimating) _newBestBanner(),
      ],
    );
  }

  Offset _shakeOffset() {
    if (!_shake || !_clear.isAnimating) return Offset.zero;
    final t = _clear.value;
    final strength = (1 - t / 0.5).clamp(0.0, 1.0) * _cell * 0.12;
    return Offset(
        math.sin(t * 70) * strength, math.cos(t * 55) * strength * 0.6);
  }

  Widget _hud() {
    final best = _game.best;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
      child: Stack(
        children: [
          Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CrownIcon(size: 26),
                  const SizedBox(width: 6),
                  Text(
                    '$best',
                    style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: kGold),
                  ),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.topRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                RemoveAdsButton(app: widget.app),
                IconButton(
                  tooltip: 'Pause',
                  iconSize: 32,
                  color: Colors.white,
                  onPressed: _openMenu,
                  icon: const GameIcon('pause', size: 36),
                ),
              ],
            ),
          ),
          Align(alignment: Alignment.bottomCenter, child: _comboBadge()),
          Align(
            alignment: const Alignment(0, 0.1),
            child: TweenAnimationBuilder<int>(
              tween: IntTween(end: _game.score),
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeOut,
              builder: (context, value, _) => Semantics(
                label: 'Score $value',
                child: OutlinedText('$value', size: 54),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _board(GameTheme theme, double side, Piece? dragged,
      ({int row, int col})? snap) {
    final labelT = _labels.value;
    final labelsOn = _labels.isAnimating;
    final overT = _over.value;

    return GestureDetector(
      onTapUp: _mode == _Mode.bomb ? _boardTapped : null,
      child: SizedBox(
        key: _boardKey,
        width: side,
        height: side,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            if (_mode == _Mode.bomb)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(_cell * 0.3),
                      border:
                          Border.all(color: const Color(0xFFFF6B3D), width: 3),
                    ),
                  ),
                ),
              ),
            Positioned.fill(
              child: CustomPaint(
                painter: BoardPainter(
                  theme: theme,
                  cells: _game.grid.cells,
                  ghost: snap == null ? null : dragged,
                  ghostRow: snap?.row ?? 0,
                  ghostCol: snap?.col ?? 0,
                  popCells: _popCells,
                  popT: _pop.value,
                  greyT: _game.won
                      ? 0
                      : Curves.easeIn.transform((overT / 0.7).clamp(0.0, 1.0)),
                  gems: _game.gems,
                  ice: _game.grid.ice,
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: ClearEffectPainter(
                    theme: theme,
                    gems: _clearGems,
                    ice: _clearIce,
                    cleared: _cleared,
                    particles: _particles,
                    origin: _clearOrigin,
                    t: _clear.value,
                  ),
                ),
              ),
            ),
            if (labelsOn) ..._labelWidgets(side, labelT),
            if (_overStarted && !_showResults && overT > 0)
              Center(
                child: Opacity(
                  opacity: (overT / 0.2).clamp(0.0, 1.0),
                  child: Transform.scale(
                    scale: 0.8 +
                        0.2 *
                            Curves.easeOutBack
                                .transform((overT / 0.3).clamp(0.0, 1.0)),
                    child: OutlinedText(
                      switch (_game.endReason) {
                        EndReason.won => 'Level Complete!',
                        EndReason.outOfMoves => 'Out of moves',
                        _ => 'No more space',
                      },
                      size: 38,
                      colors: _game.won
                          ? const [Color(0xFFEFFFF0), Color(0xFF5FE37A)]
                          : const [Color(0xFFFFF3C4), Color(0xFFFFB13B)],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _labelWidgets(double side, double t) {
    final fade = t < 0.75 ? 1.0 : 1 - (t - 0.75) / 0.25;
    final pop = Curves.elasticOut.transform((t / 0.45).clamp(0.0, 1.0));
    final rise = Curves.easeOut.transform(t);
    final pointsPos = (_pointsAt + const Offset(0.5, 0.5)) * _cell;

    return [
      if (_praise != null || _comboLabel != null)
        Positioned(
          left: -40,
          right: -40,
          top: side * 0.3 - rise * _cell * 0.6,
          child: IgnorePointer(
            child: Opacity(
              opacity: fade.clamp(0.0, 1.0),
              child: Transform.scale(
                scale: 0.4 + 0.6 * pop,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_praise != null)
                      OutlinedText(
                        _praise!,
                        size: _cell * 1.05,
                        colors: const [Color(0xFFFFF6C8), Color(0xFFFFA92E)],
                      ),
                    if (_comboLabel != null)
                      OutlinedText(
                        _comboLabel!,
                        size: _cell * 0.7,
                        colors: const [Color(0xFFE6FBFF), Color(0xFF3FD3F0)],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      Positioned(
        left: pointsPos.dx - 80,
        width: 160,
        top: pointsPos.dy - _cell * 0.5 - rise * _cell * 1.4,
        child: IgnorePointer(
          child: Opacity(
            opacity: fade.clamp(0.0, 1.0),
            child: Center(child: OutlinedText('+$_points', size: _cell * 0.6)),
          ),
        ),
      ),
    ];
  }

  Widget _slot(int index) {
    final piece = _game.tray[index];
    if (piece == null) return const SizedBox.expand();

    final hidden = _dragIndex == index || _returnIndex == index;
    final usable = _game.canUse(index);
    final spawnT = ((_spawn.value - index * 0.12) / 0.64).clamp(0.0, 1.0);

    Widget view = PieceView(piece: piece, cell: _trayCell);
    if (!usable && _mode != _Mode.rotate) {
      view = Opacity(
        opacity: 0.55,
        child: ColorFiltered(colorFilter: _greyscale, child: view),
      );
    }

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) => _pointerDown(index, e),
      onPointerMove: _pointerMove,
      onPointerUp: (e) => _pointerUp(e, drop: true),
      onPointerCancel: (e) => _pointerUp(e, drop: false),
      child: Center(
        child: Opacity(
          opacity: hidden ? 0 : 1,
          child: Transform.scale(
            scale: Curves.easeOutBack.transform(spawnT),
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                SizedBox(key: _slotKeys[index], child: view),
                if (_mode == _Mode.rotate)
                  const IgnorePointer(
                    child: CircleAvatar(
                      radius: 16,
                      backgroundColor: Color(0xCC000000),
                      child: GameIcon('rotate', size: 24),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _boosterBar(GameTheme theme) {
    final boosters = widget.app.boosters;
    final hint = switch (_mode) {
      _Mode.bomb => 'Tap the board to drop the bomb',
      _Mode.rotate => 'Tap a piece to turn it',
      _Mode.none => null,
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (final (b, icon, label) in const [
              (Booster.bomb, GameIcon('bomb', size: 32), 'Bomb'),
              (Booster.rotate, GameIcon('rotate', size: 30), 'Rotate'),
              (Booster.undo, GameIcon('replay', size: 30, flip: true), 'Undo'),
            ])
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: _BoosterButton(
                  icon: icon,
                  label: label,
                  count: boosters.count(b),
                  active: (b == Booster.bomb && _mode == _Mode.bomb) ||
                      (b == Booster.rotate && _mode == _Mode.rotate),
                  enabled: !_game.won &&
                      !_watchingAd &&
                      (b != Booster.undo ||
                          _game.canUndo ||
                          boosters.count(b) == 0),
                  accent: theme.accent,
                  onTap: () => _tapBooster(b),
                ),
              ),
          ],
        ),
        if (hint != null)
          Text(hint,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Colors.white)),
      ],
    );
  }

  static const ColorFilter _greyscale = ColorFilter.matrix([
    0.33, 0.33, 0.33, 0, 0, //
    0.33, 0.33, 0.33, 0, 0, //
    0.33, 0.33, 0.33, 0, 0, //
    0, 0, 0, 1, 0,
  ]);

  List<Widget> _floatingPiece(Piece? dragged) {
    final stackBox = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (stackBox == null || !stackBox.hasSize) return const [];

    final finger = _finger;
    if (dragged != null && finger != null) {
      final local = stackBox.globalToLocal(_floatTopLeft(dragged, finger));
      return [
        Positioned(
          left: local.dx,
          top: local.dy,
          child:
              IgnorePointer(child: PieceView(piece: dragged, cell: _floatCell)),
        ),
      ];
    }

    final ri = _returnIndex;
    final returning = ri == null ? null : _game.tray[ri];
    final slotBox = ri == null
        ? null
        : _slotKeys[ri].currentContext?.findRenderObject() as RenderBox?;
    if (returning != null && slotBox != null && slotBox.hasSize) {
      final t = Curves.easeOutCubic.transform(_return.value);
      final to = slotBox.localToGlobal(Offset.zero);
      final local = stackBox.globalToLocal(Offset.lerp(_returnFrom, to, t)!);
      return [
        Positioned(
          left: local.dx,
          top: local.dy,
          child: IgnorePointer(
            child: PieceView(
                piece: returning,
                cell: lerpDouble(_returnFromCell, _trayCell, t)!),
          ),
        ),
      ];
    }
    return const [];
  }

  Widget _comboBadge() {
    final combo = _game.combo;
    final left = GameController.comboGrace - _game.movesSinceClear;
    return AnimatedScale(
      scale: combo >= 1 ? 1 : 0,
      duration: const Duration(milliseconds: 250),
      curve: combo >= 1 ? Curves.easeOutBack : Curves.easeIn,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.fromLTRB(10, 4, 14, 4),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [Color(0xFFFF8A00), Color(0xFFFF3D6E)]),
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [
            BoxShadow(
                color: Colors.black26, blurRadius: 6, offset: Offset(0, 3))
          ],
        ),
        child: Semantics(
          label: 'Combo $combo, $left moves left',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.local_fire_department_rounded,
                  color: Colors.white, size: 20),
              const SizedBox(width: 4),
              Text(
                'Combo ${math.max(combo, 1)}',
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: Colors.white),
              ),
              const SizedBox(width: 8),
              for (var i = 0; i < GameController.comboGrace; i++)
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(left: 3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < left ? Colors.white : Colors.white30,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _newBestBanner() {
    final t = _bestBanner.value;
    final inT = Curves.easeOutBack.transform((t / 0.2).clamp(0.0, 1.0));
    final fade = t < 0.8 ? 1.0 : 1 - (t - 0.8) / 0.2;
    return Positioned(
      left: 0,
      right: 0,
      top: 150,
      child: IgnorePointer(
        child: Opacity(
          opacity: fade.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: 0.5 + 0.5 * inT,
            child: const Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CrownIcon(size: 34),
                  SizedBox(width: 8),
                  OutlinedText('New Best!',
                      size: 34, colors: [Color(0xFFFFF6C8), Color(0xFFFFB62E)]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// A ghost piece and a hand showing how to drag, until the first move.
  List<Widget> _hintWidgets({RenderBox? stackBox}) {
    final boardBox = _boardKey.currentContext?.findRenderObject() as RenderBox?;
    if (stackBox == null || boardBox == null || !boardBox.hasSize) {
      return const [];
    }
    final index = _game.tray.indexWhere((p) => p != null);
    if (index < 0) return const [];
    final slotBox =
        _slotKeys[index].currentContext?.findRenderObject() as RenderBox?;
    if (slotBox == null || !slotBox.hasSize) return const [];
    final piece = _game.tray[index]!;

    final t = _hint.value;
    final move = Curves.easeInOut.transform(((t - 0.15) / 0.5).clamp(0.0, 1.0));
    final fade = t < 0.1 ? t / 0.1 : (t > 0.85 ? (1 - t) / 0.15 : 1.0);

    final from = stackBox
        .globalToLocal(slotBox.localToGlobal(slotBox.size.center(Offset.zero)));
    final to = stackBox.globalToLocal(
        boardBox.localToGlobal(boardBox.size.center(Offset.zero)));
    final at = Offset.lerp(from, to, move)!;
    final cell = lerpDouble(_trayCell, _cell, move)!;
    final pieceSize = Size(piece.cols * cell, piece.rows * cell);

    return [
      Positioned(
        left: at.dx - pieceSize.width / 2,
        top: at.dy - pieceSize.height / 2,
        child: IgnorePointer(
          child: Opacity(
            opacity: (fade * 0.6).clamp(0.0, 1.0),
            child: PieceView(piece: piece, cell: cell),
          ),
        ),
      ),
      Positioned(
        left: at.dx - 6,
        top: at.dy + pieceSize.height / 2 - 14,
        child: IgnorePointer(
          child: Opacity(
            opacity: fade.clamp(0.0, 1.0),
            child: const Icon(
              Icons.touch_app_rounded,
              size: 56,
              color: Colors.white,
              shadows: [Shadow(color: Colors.black54, blurRadius: 8)],
            ),
          ),
        ),
      ),
      Positioned(
        left: 0,
        right: 0,
        top: stackBox.globalToLocal(slotBox.localToGlobal(Offset.zero)).dy -
            _cell * 1.4,
        child: const IgnorePointer(
          child: Center(
              child: OutlinedText('Drag a piece onto the board', size: 20)),
        ),
      ),
    ];
  }

  // ---------------------------------------------------------------- levels

  Widget _levelHud(GameTheme theme) {
    final level = _game.level!;
    final moves = _game.movesLeft;
    final low = moves <= 3 && !_game.gameOver;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
      child: Column(
        children: [
          Row(
            children: [
              Flexible(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    level.isDaily ? 'Daily Challenge' : 'Level ${level.number}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: Colors.white),
                  ),
                ),
              ),
              const Spacer(),
              RemoveAdsButton(app: widget.app),
              IconButton(
                tooltip: 'Pause',
                iconSize: 32,
                color: Colors.white,
                onPressed: _openMenu,
                icon: const GameIcon('pause', size: 36),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Semantics(
                label: '$moves moves left',
                excludeSemantics: true,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TweenAnimationBuilder<double>(
                      tween: Tween(end: low ? 1.0 : 0.0),
                      duration: const Duration(milliseconds: 300),
                      builder: (context, t, _) => OutlinedText(
                        '$moves',
                        size: 46,
                        colors: [
                          Color.lerp(Colors.white, const Color(0xFFFFC2C2), t)!,
                          Color.lerp(Colors.white, const Color(0xFFFF5A5A), t)!,
                        ],
                      ),
                    ),
                    const Text(
                      'MOVES',
                      style: TextStyle(
                          fontSize: 11,
                          letterSpacing: 1.5,
                          fontWeight: FontWeight.w800,
                          color: Colors.white70),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 18),
              Flexible(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [for (final g in level.goals) _goalChip(g)],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _goalChip(LevelGoal goal) {
    final value = math.min(_game.progress(goal), goal.target);
    final done = value >= goal.target;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
      decoration: BoxDecoration(
        color: done
            ? const Color(0xFF3FBF5F)
            : Colors.black.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: done ? Colors.white54 : Colors.white12),
      ),
      child: Semantics(
        label: '${goalName(goal.type)} $value of ${goal.target}',
        excludeSemantics: true,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            done
                ? const Icon(Icons.check_circle_rounded,
                    color: Colors.white, size: 22)
                : GoalIcon(goal.type, size: 22),
            const SizedBox(width: 6),
            Text(
              '$value/${goal.target}',
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}

enum _Mode { none, bomb, rotate }

/// What the end-of-game overlay shows.
enum _End { none, offer, results }

String boosterName(Booster b) => switch (b) {
      Booster.bomb => 'Bomb',
      Booster.rotate => 'Rotate',
      Booster.undo => 'Undo',
    };

class _BoosterButton extends StatelessWidget {
  const _BoosterButton({
    required this.icon,
    required this.label,
    required this.count,
    required this.active,
    required this.enabled,
    required this.accent,
    required this.onTap,
  });

  final Widget icon;
  final String label;
  final int count;
  final bool active;
  final bool enabled;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      label:
          count > 0 ? '$label, $count left' : '$label, watch an ad to get one',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.4,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active ? accent : Colors.white.withValues(alpha: 0.16),
                  border: Border.all(
                      color: active ? Colors.white : Colors.white24, width: 2),
                ),
                child: Center(child: icon),
              ),
              Positioned(
                right: -6,
                top: -4,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 22),
                  height: 22,
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  decoration: BoxDecoration(
                    color: count > 0
                        ? const Color(0xFFE53950)
                        : const Color(0xFF3FBF5F),
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  alignment: Alignment.center,
                  child: count > 0
                      ? Text('$count',
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              color: Colors.white))
                      : const GameIcon('watch_ad', size: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The banner when ads are allowed; nothing otherwise.
class _BannerArea extends StatelessWidget {
  const _BannerArea({required this.app});

  final AppServices app;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([app.ads, app.purchases]),
      builder: (context, child) =>
          app.ads.bannerAllowed ? child! : const SizedBox.shrink(),
      child: BannerSlot(app: app),
    );
  }
}
