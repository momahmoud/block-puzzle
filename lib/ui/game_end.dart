part of 'game_screen.dart';

/// The end-of-game overlay: first a second-chance offer with a countdown
/// (when one is available), then the results.
extension _EndViews on _GameScreenState {
  Widget _endOverlay(GameTheme theme) {
    final t = _results.value.clamp(0.0, 1.0);
    final pop = Curves.easeOutBack.transform(_results.value);
    final card = switch (_end) {
      _End.offer => _offerCard(theme),
      _ => _game.isLevel ? _levelResults(theme) : _classicResults(theme),
    };
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.62 * t),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
            child: Opacity(
              opacity: t,
              child: Transform.scale(
                scale: 0.75 + 0.25 * pop,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 340),
                  child: card,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// A card with a ribbon title across its top edge.
  Widget _shell(
      {required String ribbon,
      required List<Color> colors,
      required Widget child}) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 26),
          child: GameCard(
            padding: const EdgeInsets.fromLTRB(22, 46, 22, 18),
            child: SizedBox(width: double.infinity, child: child),
          ),
        ),
        Ribbon(ribbon, colors: colors),
      ],
    );
  }

  Widget _secondaryButton(
          String label, IconData icon, VoidCallback onPressed) =>
      ChunkyButton(
        label: label,
        icon: icon,
        fontSize: 17,
        expand: true,
        color: Color.lerp(GameTheme.of(context).sheet, Colors.white, 0.2),
        onPressed: onPressed,
      );

  // ---------------------------------------------------------------- offer

  Widget _offerCard(GameTheme theme) {
    final moves = _game.canAddMoves;
    final withAd = _game.canRevive || _game.canAddMoves;
    final adReady = widget.app.ads.rewardedReady;
    final undos = widget.app.boosters.count(Booster.undo);
    final canUndo = _game.canUndo && undos > 0;
    final left = ((1 - _offer.value) * _GameScreenState._offerSeconds).ceil();

    return _shell(
      ribbon: moves ? 'Out of moves!' : 'Out of space!',
      colors: const [Color(0xFFFFB13B), Color(0xFFFF6A3D)],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            moves
                ? 'Get ${GameController.extraMoves} more moves?'
                : 'Keep going?',
            style: const TextStyle(
                fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: 128,
            height: 128,
            child: CustomPaint(
              painter:
                  _CountdownPainter(1 - _offer.value, const Color(0xFFFFB13B)),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      moves ? Icons.more_time_rounded : Icons.favorite_rounded,
                      size: 38,
                      color: moves ? Colors.white : const Color(0xFFFF5A7A),
                    ),
                    Semantics(
                      label: '$left seconds left',
                      excludeSemantics: true,
                      child: OutlinedText('$left', size: 32),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          if (withAd)
            ChunkyButton(
              label: moves ? '+${GameController.extraMoves} Moves' : 'Revive',
              subtitle: adReady ? 'Watch an ad' : 'Ad loading…',
              icon: Icons.ondemand_video_rounded,
              color: const Color(0xFFFF8A00),
              expand: true,
              onPressed: adReady && !_watchingAd
                  ? (moves ? _addMoves : _revive)
                  : () {},
            ),
          if (canUndo) ...[
            const SizedBox(height: 10),
            withAd
                ? _secondaryButton(
                    'Undo  ($undos left)', Icons.undo_rounded, _undoFromResults)
                : ChunkyButton(
                    label: 'Undo last move',
                    subtitle: '$undos left',
                    icon: Icons.undo_rounded,
                    expand: true,
                    onPressed: _undoFromResults,
                  ),
          ],
          const SizedBox(height: 6),
          TextButton(
            onPressed: _declineOffer,
            child: const Text(
              'No thanks',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white60),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- classic

  Widget _classicResults(GameTheme theme) {
    final newBest = _game.isNewBest;
    return _shell(
      ribbon: newBest ? 'New Best!' : 'Game Over',
      colors: newBest
          ? const [Color(0xFFFFE07A), Color(0xFFFFA92E)]
          : [Color.lerp(theme.button, Colors.white, 0.2)!, theme.button],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (newBest) ...[
            const CrownIcon(size: 46),
            const SizedBox(height: 4),
          ],
          const Text(
            'SCORE',
            style: TextStyle(
                fontSize: 13,
                letterSpacing: 2,
                fontWeight: FontWeight.w700,
                color: Colors.white60),
          ),
          TweenAnimationBuilder<int>(
            tween: IntTween(begin: 0, end: _game.score),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) => OutlinedText(
              '$value',
              size: 62,
              colors: newBest
                  ? const [Color(0xFFFFF6C8), Color(0xFFFFC23E)]
                  : const [Colors.white, Colors.white],
            ),
          ),
          const SizedBox(height: 6),
          if (!newBest)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kGold.withValues(alpha: 0.5)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CrownIcon(size: 18),
                  const SizedBox(width: 6),
                  Text(
                    'Best ${_game.best}',
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: kGold),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              StatPill(
                  icon: Icons.view_week_rounded,
                  label: 'Lines',
                  value: '${_game.linesThisGame}'),
              StatPill(
                icon: Icons.local_fire_department_rounded,
                label: 'Combo',
                value: '${_game.bestComboThisGame}',
                color: const Color(0xFFFF8A00),
              ),
            ],
          ),
          const SizedBox(height: 22),
          ChunkyButton(
            label: 'Play Again',
            icon: Icons.replay_rounded,
            expand: true,
            onPressed: () {
              _sfx.tap();
              _restart();
            },
          ),
          const SizedBox(height: 10),
          _secondaryButton('Home', Icons.home_rounded, _goHome),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- levels

  Widget _levelResults(GameTheme theme) {
    final level = _game.level!;
    final won = _game.won;
    final hasNext = level.number < LevelSpec.count && !level.isDaily;
    final title = level.isDaily ? 'Daily Challenge' : 'Level ${level.number}';

    if (!won) {
      return _shell(
        ribbon: 'Level failed',
        colors: const [Color(0xFFFF7A8A), Color(0xFFE53950)],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title.toUpperCase(),
              style: const TextStyle(
                  fontSize: 13,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w700,
                  color: Colors.white60),
            ),
            const SizedBox(height: 4),
            Text(
              _game.endReason == EndReason.outOfMoves
                  ? 'You ran out of moves'
                  : 'No space left for your pieces',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.white),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [for (final g in level.goals) _goalChip(g)],
            ),
            const SizedBox(height: 22),
            ChunkyButton(
              label: 'Try Again',
              icon: Icons.replay_rounded,
              expand: true,
              onPressed: () {
                _sfx.tap();
                _restart();
              },
            ),
            const SizedBox(height: 10),
            _secondaryButton(
                level.isDaily ? 'Home' : 'Levels',
                level.isDaily ? Icons.home_rounded : Icons.map_rounded,
                _goHome),
          ],
        ),
      );
    }

    final daily = widget.app.daily;
    return _shell(
      ribbon: level.isDaily ? 'Daily done!' : 'Complete!',
      colors: const [Color(0xFF8BF0A0), Color(0xFF34B95A)],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
                fontSize: 13,
                letterSpacing: 2,
                fontWeight: FontWeight.w700,
                color: Colors.white60),
          ),
          const SizedBox(height: 10),
          if (!level.isDaily)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < 3; i++) _resultStar(i, _game.stars)
              ],
            )
          else ...[
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.local_fire_department_rounded,
                    color: Color(0xFFFF8A00), size: 40),
                const SizedBox(width: 4),
                OutlinedText('${daily.streak}', size: 40),
              ],
            ),
            Text(
              daily.streak == 1 ? 'day streak' : 'days in a row',
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.white70),
            ),
            if (_dailyReward != null) ...[
              const SizedBox(height: 10),
              StatPill(
                icon: Icons.card_giftcard_rounded,
                label: 'Reward',
                value: '+1 ${boosterName(_dailyReward!)}',
                color: theme.accent,
              ),
            ],
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              StatPill(
                  icon: Icons.star_rounded,
                  label: 'Score',
                  value: '${_game.score}',
                  color: kGold),
              StatPill(
                  icon: Icons.touch_app_rounded,
                  label: 'Moves left',
                  value: '${_game.movesLeft}'),
            ],
          ),
          const SizedBox(height: 22),
          if (hasNext) ...[
            ChunkyButton(
              label: 'Next Level',
              icon: Icons.arrow_forward_rounded,
              expand: true,
              onPressed: () => _openLevel(level.number + 1),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _secondaryButton('Replay', Icons.replay_rounded, () {
                    _sfx.tap();
                    _restart();
                  }),
                ),
                const SizedBox(width: 10),
                Expanded(
                    child:
                        _secondaryButton('Levels', Icons.map_rounded, _goHome)),
              ],
            ),
          ] else ...[
            ChunkyButton(
              label: 'Play Again',
              icon: Icons.replay_rounded,
              expand: true,
              onPressed: () {
                _sfx.tap();
                _restart();
              },
            ),
            const SizedBox(height: 10),
            _secondaryButton(
                level.isDaily ? 'Home' : 'Levels',
                level.isDaily ? Icons.home_rounded : Icons.map_rounded,
                _goHome),
          ],
        ],
      ),
    );
  }

  Widget _resultStar(int i, int stars) {
    final appear = Curves.elasticOut
        .transform(((_results.value - 0.25 - i * 0.18) / 0.5).clamp(0.0, 1.0));
    final lit = i < stars;
    return Transform.translate(
      offset: Offset(0, i == 1 ? -10 : 0),
      child: Transform.scale(
        scale: lit ? appear : 1,
        child: Icon(
          Icons.star_rounded,
          size: i == 1 ? 76 : 60,
          color: lit ? kGold : Colors.white.withValues(alpha: 0.16),
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
}

/// A ring that empties as the second-chance offer runs out.
class _CountdownPainter extends CustomPainter {
  const _CountdownPainter(this.left, this.color);

  /// Fraction of time left, 1..0.
  final double left;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 8;
    canvas.drawCircle(center, radius + 6,
        Paint()..color = Colors.black.withValues(alpha: 0.25));
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..color = Colors.white.withValues(alpha: 0.12),
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      math.pi * 2 * left.clamp(0.0, 1.0),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _CountdownPainter old) =>
      old.left != left || old.color != color;
}
