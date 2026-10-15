import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'dealer.dart';
import 'grid.dart';
import 'levels.dart';
import 'piece.dart';

/// What one placement did, for the UI to animate.
class MoveResult {
  const MoveResult({
    required this.piece,
    required this.row,
    required this.col,
    required this.clear,
    required this.combo,
    required this.points,
    required this.allClear,
    this.gems = const [],
    this.ice = const [],
  });

  final Piece piece;
  final int row;
  final int col;
  final ClearResult clear;

  /// Combo count after this move (0 if no streak is running).
  final int combo;

  /// Points this move scored in total.
  final int points;

  /// True if the move left the board completely empty.
  final bool allClear;

  /// Gem squares (row * 8 + col) collected by this move.
  final List<int> gems;

  /// Frozen squares (row * 8 + col) whose ice this move broke.
  final List<int> ice;

  int get lines => clear.lines;
}

/// Why a game ended.
enum EndReason { none, noSpace, outOfMoves, won }

/// Game state and rules. No widgets in here, so it is easy to test.
///
/// Without a [level] this is Classic: endless, until no piece fits. With a
/// [level] the board starts from the level's layout, only [LevelSpec.moves]
/// placements are allowed, and the game is won as soon as every goal is met.
class GameController extends ChangeNotifier {
  GameController({math.Random? random, this.best = 0, this.level})
      : _dealer = Dealer(random ?? math.Random()) {
    newGame();
  }

  final LevelSpec? level;
  bool get isLevel => level != null;

  static const int trayCount = 3;

  /// A combo survives this many placements in a row without a clear
  /// (one tray's worth), and ends on the next one.
  static const int comboGrace = 3;

  static const int allClearBonus = 300;

  /// Points for clearing [lines] lines at once while on combo step [combo]
  /// (1 for the first clear of a streak). Several lines at once are worth
  /// more than the same lines one at a time, and a streak multiplies it.
  static int lineScore(int lines, int combo) =>
      lines == 0 ? 0 : 10 * lines * (lines + 1) ~/ 2 * math.max(1, combo);

  final Dealer _dealer;

  Grid grid = Grid();
  List<Piece?> tray = [];
  int score = 0;
  int best;
  int combo = 0;
  bool gameOver = false;
  ClearResult lastClear = ClearResult.none;
  MoveResult? lastMove;

  /// Placements since the last line clear.
  int movesSinceClear = 0;

  /// Goes up each time the tray is refilled, so the UI can animate new pieces.
  int dealCount = 0;

  /// Best score when this game started, to tell if this game set a new one.
  int bestAtStart = 0;

  /// Lines cleared and longest combo in this game.
  int linesThisGame = 0;
  int bestComboThisGame = 0;

  /// Levels only: placements left, gems still on the board, gems collected.
  int movesLeft = 0;
  Set<int> gems = {};
  int gemsCollected = 0;
  int iceBroken = 0;

  EndReason endReason = EndReason.none;
  bool get won => endReason == EndReason.won;

  /// How far the player is towards [goal].
  int progress(LevelGoal goal) => switch (goal.type) {
        GoalType.score => score,
        GoalType.lines => linesThisGame,
        GoalType.gems => gemsCollected,
        GoalType.ice => iceBroken,
      };

  bool get goalsMet =>
      level?.goals.every((g) => progress(g) >= g.target) ?? false;

  /// Stars earned, 0 unless the level was won.
  int get stars => won ? level!.starsFor(movesLeft) : 0;

  /// Called whenever the best score goes up (use it to save it).
  void Function(int best)? onNewBest;

  /// Called after every change that should be saved.
  VoidCallback? onSave;

  /// Called after every placement.
  void Function(MoveResult move)? onMove;

  /// Called when a game ends, either at game over or when a game in
  /// progress is abandoned for a new one.
  VoidCallback? onGameEnd;

  bool get isNewBest => score > bestAtStart && score == best;

  /// True if there is an unfinished game worth continuing.
  bool get hasProgress => !gameOver && (score > 0 || !grid.isEmpty);

  void newGame() {
    if (hasProgress && !_endReported) onGameEnd?.call();
    _endReported = false;
    _undo = null;
    revived = false;
    extraMovesUsed = false;
    grid = Grid();
    final lv = level;
    if (lv != null) {
      for (var r = 0; r < Grid.size; r++) {
        for (var c = 0; c < Grid.size; c++) {
          grid.cells[r][c] = lv.cells[r][c];
        }
      }
    }
    gems = {...?lv?.gems};
    grid.ice.addAll(lv?.ice ?? const {});
    gemsCollected = 0;
    iceBroken = 0;
    movesLeft = lv?.moves ?? 0;
    endReason = EndReason.none;
    score = 0;
    combo = 0;
    movesSinceClear = 0;
    gameOver = false;
    lastClear = ClearResult.none;
    lastMove = null;
    bestAtStart = best;
    linesThisGame = 0;
    bestComboThisGame = 0;
    _refillTray();
    onSave?.call();
    notifyListeners();
  }

  // ---------------------------------------------------------------- boosters

  /// Revive and extra moves can each be used once per game.
  bool revived = false;
  bool extraMovesUsed = false;
  bool _endReported = false;
  _Snapshot? _undo;

  static const int extraMoves = 5;

  bool get canUndo => _undo != null;
  bool get canRevive => gameOver && endReason == EndReason.noSpace && !revived;
  bool get canAddMoves =>
      gameOver && endReason == EndReason.outOfMoves && !extraMovesUsed;

  /// Takes back the last placement, even one that ended the game.
  bool undo() {
    final snap = _undo;
    if (snap == null) return false;
    _undo = null;
    snap.restoreInto(this);
    endReason = EndReason.none;
    gameOver = false;
    lastMove = null;
    lastClear = ClearResult.none;
    dealCount++;
    onSave?.call();
    notifyListeners();
    return true;
  }

  /// Squares a bomb dropped at ([row], [col]) would hit: the 3x3 around it.
  static List<int> bombArea(int row, int col) => [
        for (var r = row - 1; r <= row + 1; r++)
          for (var c = col - 1; c <= col + 1; c++)
            if (r >= 0 && r < Grid.size && c >= 0 && c < Grid.size)
              r * Grid.size + c,
      ];

  /// Blows up the 3x3 around ([row], [col]). Frozen blocks go too, and gems
  /// in the blast are collected. Does not use a move. Returns the squares
  /// that held a block, with their colours.
  List<ClearedCell> bomb(int row, int col) {
    if (gameOver && endReason == EndReason.won) return const [];
    final removed = <ClearedCell>[];
    var gemsHit = 0;
    for (final i in bombArea(row, col)) {
      final r = i ~/ Grid.size, c = i % Grid.size;
      if (grid.cells[r][c] == 0) continue;
      removed.add((row: r, col: c, colorId: grid.cells[r][c]));
      grid.cells[r][c] = 0;
      if (grid.ice.remove(i)) iceBroken++;
      if (gems.remove(i)) gemsHit++;
    }
    gemsCollected += gemsHit;
    score += removed.length;
    _undo = null;
    _settleAfterBooster();
    return removed;
  }

  /// Turns tray piece [index] a quarter turn.
  bool rotate(int index) {
    final piece = index >= 0 && index < tray.length ? tray[index] : null;
    if (piece == null || (gameOver && endReason == EndReason.won)) return false;
    tray[index] = piece.rotated();
    _settleAfterBooster();
    return true;
  }

  /// A second chance after running out of space: clears the two fullest
  /// rows and the two fullest columns and deals fresh pieces.
  bool revive() {
    if (!canRevive) return false;
    revived = true;
    int filled(Iterable<int> squares) => squares
        .where((i) => grid.cells[i ~/ Grid.size][i % Grid.size] != 0)
        .length;
    final rows = List.generate(Grid.size, (r) => r)
      ..sort((a, b) =>
          filled(List.generate(Grid.size, (c) => b * Grid.size + c)).compareTo(
              filled(List.generate(Grid.size, (c) => a * Grid.size + c))));
    final cols = List.generate(Grid.size, (c) => c)
      ..sort((a, b) =>
          filled(List.generate(Grid.size, (r) => r * Grid.size + b)).compareTo(
              filled(List.generate(Grid.size, (r) => r * Grid.size + a))));
    for (final r in rows.take(2)) {
      for (var c = 0; c < Grid.size; c++) {
        _wipe(r, c);
      }
    }
    for (final c in cols.take(2)) {
      for (var r = 0; r < Grid.size; r++) {
        _wipe(r, c);
      }
    }
    _undo = null;
    _refillTray();
    _settleAfterBooster();
    return true;
  }

  /// Levels: [extraMoves] more moves after running out.
  bool addMoves() {
    if (!canAddMoves) return false;
    extraMovesUsed = true;
    movesLeft += extraMoves;
    _settleAfterBooster();
    return true;
  }

  void _wipe(int r, int c) {
    final i = r * Grid.size + c;
    if (grid.cells[r][c] == 0) return;
    grid.cells[r][c] = 0;
    if (grid.ice.remove(i)) iceBroken++;
    if (gems.remove(i)) gemsCollected++;
  }

  /// Re-checks win and game over after a booster changed the board.
  void _settleAfterBooster() {
    endReason = EndReason.none;
    _evaluateEnd();
    if (score > best) {
      best = score;
      onNewBest?.call(best);
    }
    onSave?.call();
    notifyListeners();
  }

  void _evaluateEnd() {
    final stuck = !tray.any((p) => p != null && grid.canFitAnywhere(p));
    if (isLevel) {
      if (goalsMet) {
        endReason = EndReason.won;
      } else if (movesLeft <= 0) {
        endReason = EndReason.outOfMoves;
      } else if (stuck) {
        endReason = EndReason.noSpace;
      }
    } else if (stuck) {
      endReason = EndReason.noSpace;
    }
    gameOver = endReason != EndReason.none;
    // A game counts as finished the first time it ends, even if the player
    // then revives or undoes.
    if (gameOver && !_endReported) {
      _endReported = true;
      onGameEnd?.call();
    }
  }

  void _refillTray() {
    tray = List<Piece?>.of(_dealer.deal(grid, trayCount));
    dealCount++;
  }

  /// True if tray piece [index] fits somewhere on the board.
  bool canUse(int index) {
    final piece = tray[index];
    return piece != null && grid.canFitAnywhere(piece);
  }

  /// Places tray piece [index] with its top-left square at ([row], [col]).
  /// Returns false if it does not fit.
  bool place(int index, int row, int col) {
    if (gameOver || index < 0 || index >= tray.length) return false;
    final piece = tray[index];
    if (piece == null || !grid.canPlace(piece, row, col)) return false;

    _undo = _Snapshot.of(this);
    grid.place(piece, row, col);
    var points = piece.size;

    final clear = grid.clearLines();
    lastClear = clear;
    if (clear.lines > 0) {
      combo++;
      movesSinceClear = 0;
      linesThisGame += clear.lines;
      bestComboThisGame = math.max(bestComboThisGame, combo);
      points += lineScore(clear.lines, combo);
    } else {
      movesSinceClear++;
      if (movesSinceClear >= comboGrace) combo = 0;
    }

    final allClear = clear.lines > 0 && grid.isEmpty;
    if (allClear) points += allClearBonus;
    score += points;

    final collected = <int>[
      for (final c in clear.cells)
        if (gems.remove(c.row * Grid.size + c.col)) c.row * Grid.size + c.col,
    ];
    gemsCollected += collected.length;
    iceBroken += clear.iceBroken.length;

    lastMove = MoveResult(
      piece: piece,
      row: row,
      col: col,
      clear: clear,
      combo: combo,
      points: points,
      allClear: allClear,
      gems: collected,
      ice: clear.iceBroken,
    );

    tray[index] = null;
    if (tray.every((p) => p == null)) _refillTray();

    if (isLevel) movesLeft--;
    _evaluateEnd();

    if (score > best) {
      best = score;
      onNewBest?.call(best);
    }
    onMove?.call(lastMove!);
    onSave?.call();
    notifyListeners();
    return true;
  }

  Map<String, Object?> toJson() => {
        'grid': grid.toJson(),
        'tray': [for (final p in tray) p?.toJson()],
        'score': score,
        'combo': combo,
        'movesSinceClear': movesSinceClear,
        'bestAtStart': bestAtStart,
        'lines': linesThisGame,
        'bestCombo': bestComboThisGame,
        'gameOver': gameOver,
      };

  /// Continues a saved game. Returns false (and changes nothing) if [json]
  /// is not a usable save.
  bool restore(Map<String, dynamic> json) {
    try {
      final savedGrid = Grid.fromJson(json['grid'] as List);
      final savedTray = [
        for (final p in json['tray'] as List)
          p == null ? null : Piece.fromJson(p as Map<String, dynamic>),
      ];
      if (savedTray.length != trayCount || savedTray.every((p) => p == null)) {
        return false;
      }
      if (json['gameOver'] == true) return false;

      grid = savedGrid;
      tray = savedTray;
      score = json['score'] as int;
      combo = json['combo'] as int;
      movesSinceClear = json['movesSinceClear'] as int;
      bestAtStart = json['bestAtStart'] as int;
      linesThisGame = json['lines'] as int? ?? 0;
      bestComboThisGame = json['bestCombo'] as int? ?? 0;
      if (score > best) best = score;
      lastClear = ClearResult.none;
      lastMove = null;
      gameOver = !tray.any((p) => p != null && grid.canFitAnywhere(p));
      endReason = gameOver ? EndReason.noSpace : EndReason.none;
      dealCount++;
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }
}

/// Everything a placement can change, for undo.
class _Snapshot {
  _Snapshot.of(GameController g)
      : cells = [for (final row in g.grid.cells) List.of(row)],
        ice = {...g.grid.ice},
        tray = List.of(g.tray),
        score = g.score,
        combo = g.combo,
        movesSinceClear = g.movesSinceClear,
        lines = g.linesThisGame,
        bestCombo = g.bestComboThisGame,
        gems = {...g.gems},
        gemsCollected = g.gemsCollected,
        iceBroken = g.iceBroken,
        movesLeft = g.movesLeft;

  final List<List<int>> cells;
  final Set<int> ice;
  final List<Piece?> tray;
  final int score, combo, movesSinceClear, lines, bestCombo;
  final Set<int> gems;
  final int gemsCollected, iceBroken, movesLeft;

  void restoreInto(GameController g) {
    for (var r = 0; r < Grid.size; r++) {
      g.grid.cells[r].setAll(0, cells[r]);
    }
    g.grid.ice
      ..clear()
      ..addAll(ice);
    g.tray = List.of(tray);
    g.score = score;
    g.combo = combo;
    g.movesSinceClear = movesSinceClear;
    g.linesThisGame = lines;
    g.bestComboThisGame = bestCombo;
    g.gems = {...gems};
    g.gemsCollected = gemsCollected;
    g.iceBroken = iceBroken;
    g.movesLeft = movesLeft;
  }
}
