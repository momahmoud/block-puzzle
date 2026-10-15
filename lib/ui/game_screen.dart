import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../game/game_controller.dart';
import '../game/grid.dart';
import '../game/levels.dart';
import '../game/piece.dart';
import '../services/level_progress.dart';
import '../services/settings.dart';
import '../services/sfx.dart';
import 'board_painter.dart';
import 'level_map_screen.dart';
import 'palette.dart';
import 'piece_view.dart';
import 'settings_sheet.dart';
import 'theme.dart';
import 'widgets.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({
    super.key,
    required this.controller,
    required this.settings,
    required this.sfx,
    this.levels,
  });

  final GameController controller;
  final Settings settings;
  final Sfx sfx;

  /// Needed when [controller] plays a level, to save stars and open the
  /// next one.
  final LevelProgress? levels;

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

  // Game over: the board greys out, then the results card appears.
  bool _overStarted = false;
  bool _showResults = false;
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
  }

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
      _hint
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
        widget.levels?.record(level.number, _game.stars);
        _sfx.levelComplete();
      } else {
        _sfx.gameOver();
      }
      _over.forward(from: 0).whenComplete(() {
        if (!mounted || !_game.gameOver) return;
        setState(() => _showResults = true);
        _results.forward(from: 0);
        if (!_game.isLevel && _game.isNewBest && _game.bestAtStart == 0) {
          _sfx.newBest();
        }
      });
    });
  }

  void _restart() {
    _overTimer?.cancel();
    _overStarted = false;
    _showResults = false;
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

  void _goHome() {
    _sfx.tap();
    Navigator.of(context).maybePop();
  }

  /// Levels: opens level [number] in place of this one.
  void _openLevel(int number) {
    final levels = widget.levels;
    if (levels == null) return;
    _sfx.tap();
    Navigator.of(context).pushReplacement(
      levelRoute(
          number: number, settings: widget.settings, sfx: _sfx, levels: levels),
    );
  }

  void _openMenu() {
    _sfx.tap();
    showSettingsSheet(
      context,
      settings: widget.settings,
      sfx: _sfx,
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
          child: SafeArea(
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
                  _bestBanner,
                  _hint
                ],
              ),
              builder: (context, _) => LayoutBuilder(builder: _buildLayout),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLayout(BuildContext context, BoxConstraints box) {
    const hudHeight = 150.0;
    final theme = GameTheme.of(context);
    final trayRows = 5 * _trayScale;
    _cell = math
        .min(
          (box.maxWidth - 40) / Grid.size,
          (box.maxHeight - hudHeight - 48) / (Grid.size + trayRows + 0.6),
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
        if (_showResults)
          Positioned.fill(
              child: _game.isLevel
                  ? _levelResultsCard(theme)
                  : _resultsCard(theme)),
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
            child: IconButton(
              tooltip: 'Pause',
              iconSize: 32,
              color: Colors.white,
              onPressed: _openMenu,
              icon: const Icon(Icons.pause_circle_filled_rounded),
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

    return SizedBox(
      key: _boardKey,
      width: side,
      height: side,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
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
    if (!usable) {
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
            child: SizedBox(key: _slotKeys[index], child: view),
          ),
        ),
      ),
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

  Widget _resultsCard(GameTheme theme) {
    final t = Curves.easeOutBack.transform(_results.value);
    final newBest = _game.isNewBest;
    return ColoredBox(
      color:
          Colors.black.withValues(alpha: 0.55 * _results.value.clamp(0.0, 1.0)),
      child: Center(
        child: Transform.scale(
          scale: 0.7 + 0.3 * t,
          child: Opacity(
            opacity: _results.value.clamp(0.0, 1.0),
            child: Container(
              width: 310,
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color.lerp(theme.sheet, Colors.white, 0.08)!,
                    theme.sheet
                  ],
                ),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: Colors.white24, width: 2),
                boxShadow: const [
                  BoxShadow(
                      color: Colors.black45,
                      blurRadius: 24,
                      offset: Offset(0, 10))
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (newBest) ...[
                    const CrownIcon(size: 48),
                    const SizedBox(height: 4),
                    const OutlinedText('New Best!',
                        size: 34,
                        colors: [Color(0xFFFFF6C8), Color(0xFFFFB62E)]),
                  ] else
                    const OutlinedText('Game Over', size: 34),
                  const SizedBox(height: 18),
                  const Text(
                    'SCORE',
                    style: TextStyle(
                        fontSize: 14,
                        letterSpacing: 2,
                        fontWeight: FontWeight.w800,
                        color: Colors.white70),
                  ),
                  TweenAnimationBuilder<int>(
                    tween: IntTween(begin: 0, end: _game.score),
                    duration: const Duration(milliseconds: 900),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, _) =>
                        OutlinedText('$value', size: 52),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CrownIcon(size: 22),
                      const SizedBox(width: 6),
                      Text(
                        'Best ${_game.best}',
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: kGold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      StatTile(value: '${_game.linesThisGame}', label: 'LINES'),
                      StatTile(
                          value: '${_game.bestComboThisGame}',
                          label: 'BEST COMBO'),
                    ],
                  ),
                  const SizedBox(height: 22),
                  ChunkyButton(
                    label: 'Play Again',
                    icon: Icons.replay_rounded,
                    onPressed: () {
                      _sfx.tap();
                      _restart();
                    },
                  ),
                  const SizedBox(height: 6),
                  TextButton.icon(
                    onPressed: _goHome,
                    icon: const Icon(Icons.home_rounded, color: Colors.white70),
                    label: const Text(
                      'Home',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Colors.white70),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
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
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Level ${level.number}',
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Colors.white),
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Pause',
                iconSize: 32,
                color: Colors.white,
                onPressed: _openMenu,
                icon: const Icon(Icons.pause_circle_filled_rounded),
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

  Widget _levelResultsCard(GameTheme theme) {
    final level = _game.level!;
    final won = _game.won;
    final stars = _game.stars;
    final t = Curves.easeOutBack.transform(_results.value);
    final hasNext = level.number < LevelSpec.count;

    Widget star(int i) {
      final appear = Curves.elasticOut.transform(
          ((_results.value - 0.25 - i * 0.18) / 0.5).clamp(0.0, 1.0));
      final lit = i < stars;
      return Transform.translate(
        offset: Offset(0, i == 1 ? -12 : 0),
        child: Transform.scale(
          scale: lit ? appear : 1,
          child: Icon(
            Icons.star_rounded,
            size: i == 1 ? 72 : 58,
            color: lit ? kGold : Colors.white.withValues(alpha: 0.18),
            shadows: lit
                ? const [
                    Shadow(
                        color: Colors.black38,
                        blurRadius: 8,
                        offset: Offset(0, 3))
                  ]
                : null,
          ),
        ),
      );
    }

    return ColoredBox(
      color:
          Colors.black.withValues(alpha: 0.55 * _results.value.clamp(0.0, 1.0)),
      child: Center(
        child: Transform.scale(
          scale: 0.7 + 0.3 * t,
          child: Opacity(
            opacity: _results.value.clamp(0.0, 1.0),
            child: Container(
              width: 310,
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color.lerp(theme.sheet, Colors.white, 0.08)!,
                    theme.sheet
                  ],
                ),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: Colors.white24, width: 2),
                boxShadow: const [
                  BoxShadow(
                      color: Colors.black45,
                      blurRadius: 24,
                      offset: Offset(0, 10))
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'LEVEL ${level.number}',
                    style: const TextStyle(
                        fontSize: 14,
                        letterSpacing: 2,
                        fontWeight: FontWeight.w800,
                        color: Colors.white70),
                  ),
                  const SizedBox(height: 4),
                  if (won) ...[
                    const OutlinedText('Complete!',
                        size: 36,
                        colors: [Color(0xFFEFFFF0), Color(0xFF5FE37A)]),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [star(0), star(1), star(2)],
                    ),
                  ] else ...[
                    OutlinedText(
                      _game.endReason == EndReason.outOfMoves
                          ? 'Out of moves'
                          : 'No more space',
                      size: 32,
                      colors: const [Color(0xFFFFF3C4), Color(0xFFFFB13B)],
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      alignment: WrapAlignment.center,
                      children: [for (final g in level.goals) _goalChip(g)],
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    'Score ${_game.score}',
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Colors.white),
                  ),
                  const SizedBox(height: 20),
                  if (won && hasNext)
                    ChunkyButton(
                      label: 'Next Level',
                      icon: Icons.arrow_forward_rounded,
                      onPressed: () => _openLevel(level.number + 1),
                    )
                  else
                    ChunkyButton(
                      label: won ? 'Play Again' : 'Try Again',
                      icon: Icons.replay_rounded,
                      onPressed: () {
                        _sfx.tap();
                        _restart();
                      },
                    ),
                  const SizedBox(height: 6),
                  Wrap(
                    alignment: WrapAlignment.center,
                    children: [
                      if (won && hasNext)
                        TextButton.icon(
                          onPressed: () {
                            _sfx.tap();
                            _restart();
                          },
                          icon: const Icon(Icons.replay_rounded,
                              color: Colors.white70),
                          label: const Text(
                            'Replay',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: Colors.white70),
                          ),
                        ),
                      TextButton.icon(
                        onPressed: _goHome,
                        icon: const Icon(Icons.map_rounded,
                            color: Colors.white70),
                        label: const Text(
                          'Levels',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Colors.white70),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
