import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'card_view.dart';
import 'game.dart';

void main() => runApp(const SetApp());

class SetApp extends StatelessWidget {
  const SetApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Set Sprint',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      fontFamily: 'SetSans',
      scaffoldBackgroundColor: paper,
      colorScheme: ColorScheme.fromSeed(seedColor: accent, surface: paper),
      textTheme: ThemeData.light().textTheme.apply(
        fontFamily: 'SetSans',
        bodyColor: ink,
        displayColor: ink,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: ink,
          foregroundColor: Colors.white,
          minimumSize: const Size(180, 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
      ),
    ),
    home: const GameScreen(),
  );
}

enum Phase { ready, countdown, playing, finished }

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  final game = SetGame();
  final watch = Stopwatch();
  final elapsed = ValueNotifier(Duration.zero);
  Timer? ticker;
  Timer? countdownTimer;
  Phase phase = Phase.ready;
  int countdown = 2;
  Duration? best;
  bool newBest = false;
  String feedback = 'Find a set. Find your rhythm.';

  void start() {
    ticker?.cancel();
    countdownTimer?.cancel();
    watch
      ..stop()
      ..reset();
    elapsed.value = Duration.zero;
    setState(() {
      game.restart();
      countdown = 2;
      phase = Phase.countdown;
      feedback = 'Pick three cards that make a set.';
    });
    countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (countdown == 2) {
        setState(() => countdown = 1);
      } else {
        timer.cancel();
        watch.start();
        setState(() => phase = Phase.playing);
        ticker = Timer.periodic(const Duration(milliseconds: 33), (_) {
          elapsed.value = watch.elapsed;
        });
      }
    });
  }

  void pick(SetCard card) {
    if (phase != Phase.playing) return;
    setState(() {
      final result = game.pick(card.id);
      switch (result) {
        case PickResult.wrong:
          feedback = 'Not a set. Keep going!';
          HapticFeedback.lightImpact();
        case PickResult.correct:
          feedback = '${game.streak} down. ${5 - game.streak} to go.';
          HapticFeedback.selectionClick();
        case PickResult.finished:
          watch.stop();
          ticker?.cancel();
          newBest = best == null || watch.elapsed < best!;
          if (newBest) best = watch.elapsed;
          phase = Phase.finished;
          HapticFeedback.mediumImpact();
        case PickResult.selected:
        case PickResult.deselected:
          feedback = game.selected.isEmpty
              ? 'Pick three cards that make a set.'
              : '${game.selected.length} of 3 selected';
      }
    });
  }

  @override
  void dispose() {
    ticker?.cancel();
    countdownTimer?.cancel();
    watch.stop();
    elapsed.dispose();
    super.dispose();
  }

  void showRules() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 0, 28, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Same. Or all different.',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 16),
              const Text(
                'Choose three cards. For EACH of the four features, the cards must be all the same or all different.',
                style: TextStyle(fontSize: 17, height: 1.5),
              ),
              const SizedBox(height: 16),
              const Text(
                'NUMBER   ·   SHAPE   ·   COLOR   ·   FILL',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 124,
                child: Row(
                  children: [
                    for (final id in [0, 1, 2])
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(3),
                          child: CardView(card: SetCard(id)),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'A set: different numbers, same shape, color and fill.',
                style: TextStyle(height: 1.5),
              ),
              const SizedBox(height: 20),
              const Text(
                'Get five sets in a row as fast as you can. A wrong trio counts as a mistake; the clock keeps running.',
                style: TextStyle(fontSize: 16, height: 1.5),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Got it'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      const Text(
                        'set',
                        style: TextStyle(
                          fontSize: 38,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -2,
                        ),
                      ),
                      const Text(
                        '.',
                        style: TextStyle(
                          fontSize: 38,
                          fontWeight: FontWeight.w900,
                          color: accent,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'SPRINT',
                            style: TextStyle(
                              fontSize: 11,
                              letterSpacing: 3,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      if (phase == Phase.playing || phase == Phase.countdown)
                        IconButton(
                          tooltip: 'Restart run',
                          onPressed: start,
                          icon: const Icon(Icons.refresh_rounded),
                        )
                      else
                        IconButton(
                          tooltip: 'How to play',
                          onPressed: showRules,
                          icon: const Icon(Icons.help_outline_rounded),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: switch (phase) {
                    Phase.ready => landing(),
                    Phase.countdown => countdownView(),
                    Phase.playing => playing(),
                    Phase.finished => results(),
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget centeredPage(List<Widget> children) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: constraints.maxHeight),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: children,
        ),
      ),
    ),
  );

  Widget landing() => centeredPage([
    const Text(
      'A LITTLE PATTERN. A LITTLE PACE.',
      style: TextStyle(
        color: accent,
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.8,
      ),
    ),
    const SizedBox(height: 22),
    const Text(
      'Five sets.\nOne good run.',
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 46,
        height: 1.08,
        letterSpacing: -2,
        fontWeight: FontWeight.w800,
      ),
    ),
    const SizedBox(height: 24),
    const Text(
      'Find five sets in a row.\nSee how fast your eyes can go.',
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 17, height: 1.5, color: Color(0xFF68717B)),
    ),
    const SizedBox(height: 36),
    ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 350),
      child: SizedBox(
        height: 148,
        child: Row(
          children: [
            for (final id in [0, 40, 80])
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Transform.rotate(
                    angle: (id - 40) * .0015,
                    child: CardView(card: SetCard(id)),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
    const SizedBox(height: 36),
    FilledButton.icon(
      onPressed: start,
      iconAlignment: IconAlignment.end,
      icon: const Icon(Icons.arrow_forward_rounded),
      label: const Text('Start run'),
    ),
    const SizedBox(height: 10),
    TextButton(onPressed: showRules, child: const Text('How to play')),
    const SizedBox(height: 24),
  ]);

  Widget countdownView() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'EYES READY',
          style: TextStyle(
            fontSize: 12,
            letterSpacing: 3,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          '$countdown',
          key: const ValueKey('countdown'),
          style: const TextStyle(
            fontSize: 144,
            height: 1.4,
            fontWeight: FontWeight.w800,
            color: accent,
          ),
        ),
        const Text(
          'Five sets. You’ve got this.',
          style: TextStyle(fontSize: 17),
        ),
      ],
    ),
  );

  Widget playing() => Column(
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.bottomLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'YOUR STREAK',
                    style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 1.7,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${game.streak} / 5',
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.bottomRight,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    'TIME',
                    style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 1.7,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  ValueListenableBuilder<Duration>(
                    valueListenable: elapsed,
                    builder: (context, value, child) => Text(
                      formatTime(value),
                      key: const ValueKey('timer'),
                      style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w600,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Row(
        children: List.generate(
          5,
          (i) => Expanded(
            child: Container(
              margin: EdgeInsets.only(right: i == 4 ? 0 : 6),
              height: 5,
              decoration: BoxDecoration(
                color: i < game.streak ? accent : const Color(0xFFDEDED5),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ),
      ),
      SizedBox(
        height: 56,
        child: Center(
          child: Semantics(
            liveRegion: true,
            child: Text(
              feedback,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ),
      ),
      Expanded(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth > 500 ? 4 : 3;
            final rows = (game.board.length / columns).ceil();
            final tileHeight =
                ((constraints.maxHeight - (rows - 1) * 10) / rows).clamp(
                  96.0,
                  210.0,
                );
            final gridWidth =
                (columns * tileHeight * 2 / 3 + (columns - 1) * 10).clamp(
                  0.0,
                  constraints.maxWidth,
                );
            final gridHeight =
                rows * (gridWidth - (columns - 1) * 10) / columns * 3 / 2 +
                (rows - 1) * 10;
            return Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: gridWidth,
                child: GridView.builder(
                  padding: EdgeInsets.zero,
                  physics: gridHeight <= constraints.maxHeight + 0.01
                      ? const NeverScrollableScrollPhysics()
                      : const ClampingScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    childAspectRatio: 2 / 3,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: game.board.length,
                  itemBuilder: (context, index) {
                    final card = game.board[index];
                    return CardView(
                      key: ValueKey('card-${card.id}'),
                      card: card,
                      selected: game.selected.contains(card.id),
                      onTap: () => pick(card),
                    );
                  },
                ),
              ),
            );
          },
        ),
      ),
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 14),
        child: Text(
          'Each feature: all the same or all different.',
          style: TextStyle(fontSize: 12, color: Color(0xFF68717B)),
        ),
      ),
    ],
  );

  Widget results() => centeredPage([
    Container(
      padding: const EdgeInsets.all(18),
      decoration: const BoxDecoration(
        color: Color(0xFFE3ECDD),
        shape: BoxShape.circle,
      ),
      child: const Icon(
        Icons.check_rounded,
        size: 38,
        color: Color(0xFF377548),
      ),
    ),
    const SizedBox(height: 24),
    const Text(
      'Five in a row.',
      style: TextStyle(
        fontSize: 38,
        letterSpacing: -1.5,
        fontWeight: FontWeight.w800,
      ),
    ),
    const SizedBox(height: 12),
    FittedBox(
      child: Text(
        formatTime(watch.elapsed),
        key: const ValueKey('result-time'),
        style: const TextStyle(
          fontSize: 78,
          letterSpacing: -3,
          fontWeight: FontWeight.w700,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    ),
    const Text(
      'YOUR TIME',
      style: TextStyle(
        fontSize: 11,
        letterSpacing: 2,
        fontWeight: FontWeight.w700,
      ),
    ),
    const SizedBox(height: 24),
    Text(
      newBest
          ? 'Your best run this session.'
          : 'Session best  ${formatTime(best!)}',
      style: const TextStyle(
        color: accent,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
    ),
    const SizedBox(height: 8),
    Text(
      game.mistakes == 0
          ? 'Clean run. Every set counted.'
          : '${game.mistakes} ${game.mistakes == 1 ? 'mistake' : 'mistakes'}. You got there.',
      style: const TextStyle(color: Color(0xFF68717B)),
    ),
    const SizedBox(height: 36),
    FilledButton.icon(
      onPressed: start,
      icon: const Icon(Icons.refresh_rounded),
      label: const Text('Play again'),
    ),
    const SizedBox(height: 12),
    TextButton(
      onPressed: () => setState(() => phase = Phase.ready),
      child: const Text('Back to start'),
    ),
    const SizedBox(height: 24),
  ]);
}
