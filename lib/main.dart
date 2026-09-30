import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'card_view.dart';
import 'game.dart';
import 'data.dart';
import 'leaderboard.dart';
import 'training.dart';
import 'race.dart';
import 'install.dart';
import 'practice.dart';

void main() => runApp(const TrioSprintApp());

class TrioSprintApp extends StatelessWidget {
  const TrioSprintApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Trio Sprint',
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
  SetGame game = SetGame();
  PlayerData? player;
  late final Future<void> loading;
  String? pendingSeed;
  bool starting = false;
  int runGeneration = 0;
  bool eligible = false;
  bool submitted = false;
  bool submitting = false;
  final solutions = <List<int>>[];
  final boardClock = BoardClock();
  int boardMistakes = 0;

  void rememberBoard() {
    if (!boardClock.active) return;
    boardClock.stop();
    player
        ?.recordPractice(
          PracticeBoard(
            cards: game.board.map((card) => card.id).toList(),
            milliseconds: boardClock.milliseconds,
            mistakes: boardMistakes,
          ),
        )
        .catchError((Object error) {
          /* History must not interrupt a sprint. */
        });
  }

  @override
  void initState() {
    super.initState();
    pendingSeed = normalizeSeed(Uri.base.queryParameters['seed'] ?? '');
    loading = loadPlayer();
  }

  Future<void> loadPlayer() async {
    try {
      final loaded = await PlayerData.load();
      if (!mounted) return;
      setState(() {
        player = loaded;
        if (loaded.best != null) best = Duration(milliseconds: loaded.best!);
      });
      final room = Uri.base.queryParameters['room'];
      if (room != null && RegExp(r'^[A-Z0-9]{6}$').hasMatch(room)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) openRace(room: room);
        });
      }
    } catch (_) {
      if (mounted) {
        message(
          'Device storage is unavailable. You can play, but scores cannot be submitted.',
        );
      }
    }
  }

  void message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> copySeed(String seed) async {
    await Clipboard.setData(ClipboardData(text: shareLink('seed', seed)));
    if (mounted) message('Seed link copied: $seed');
  }

  Future<void> enterSeed() async {
    final controller = TextEditingController(text: pendingSeed ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Run a seed'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 's2-1234abcd or a shared link',
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Only submit a score the first time you ever run a seed. Restarts and unfinished attempts count too.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Run seed'),
          ),
        ],
      ),
    );
    if (!mounted || result == null) return;
    final seed = normalizeSeed(result);
    if (seed == null) {
      message('Enter a seed such as s2-1234abcd.');
      return;
    }
    await start(seed: seed);
  }

  Future<bool> askName() async {
    if (player == null) {
      message('Device storage is needed for online play.');
      return false;
    }
    final controller = TextEditingController(text: player!.nickname);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Your nickname'),
        content: TextField(
          controller: controller,
          maxLength: 24,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'What should your friends see?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(context, controller.text.trim());
              }
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (name == null || !mounted) return false;
    await player!.setNickname(name);
    return mounted;
  }

  Future<void> openRace({String? room}) async {
    if (!OnlineApi().configured) {
      message('Online play is not configured yet.');
      return;
    }
    if (!await askName() || !mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RaceScreen(player: player!, room: room),
      ),
    );
  }

  Future<void> submitScore() async {
    if (!eligible || submitted || submitting || player == null) return;
    if (!OnlineApi().configured) {
      message('Online scores are not configured yet.');
      return;
    }
    setState(() => submitting = true);
    try {
      if (!await askName() || !mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Submit this first attempt?'),
          content: const Text(
            'Only submit if this was the FIRST time you ever ran this seed, including on other devices. Replays are practice, even if you clear browser data.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('My first attempt'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      await OnlineApi().submit(
        player: player!,
        seed: game.seed!,
        milliseconds: watch.elapsedMilliseconds,
        mistakes: game.mistakes,
        solutions: solutions,
      );
      if (mounted) {
        setState(() => submitted = true);
        message('Score submitted!');
      }
    } catch (error) {
      if (mounted) message('Could not submit. You can retry: $error');
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  final watch = Stopwatch();
  final elapsed = ValueNotifier(Duration.zero);
  Timer? ticker;
  Timer? countdownTimer;
  Phase phase = Phase.ready;
  int countdown = 2;
  Duration? best;
  bool newBest = false;
  String feedback = 'Find a set. Find your rhythm.';

  Future<void> start({String? seed}) async {
    if (starting || submitting) return;
    starting = true;
    final generation = ++runGeneration;
    if (boardClock.milliseconds >= 10000 || boardMistakes > 0) rememberBoard();
    boardClock.stop();
    boardMistakes = 0;
    ticker?.cancel();
    countdownTimer?.cancel();
    watch.stop();
    await loading;
    if (!mounted || generation != runGeneration) return;
    final chosenSeed = seed ?? pendingSeed ?? newSeed();
    pendingSeed = null;
    var firstAttempt = false;
    try {
      firstAttempt = await player?.claimSeed(chosenSeed) ?? false;
    } catch (_) {
      if (mounted) {
        message('Could not remember this attempt. This run is practice only.');
      }
    }
    if (!mounted || generation != runGeneration) return;
    starting = false;
    eligible = firstAttempt;
    submitted = false;
    solutions.clear();
    ticker?.cancel();
    countdownTimer?.cancel();
    watch
      ..stop()
      ..reset();
    elapsed.value = Duration.zero;
    setState(() {
      game = SetGame(seed: chosenSeed);
      final previousBest = player?.bestForSeed(chosenSeed);
      best = previousBest == null ? null : Duration(milliseconds: previousBest);
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
        boardClock.start();
        setState(() => phase = Phase.playing);
        ticker = Timer.periodic(const Duration(milliseconds: 33), (_) {
          elapsed.value = watch.elapsed;
        });
      }
    });
  }

  void abandon() {
    runGeneration++;
    starting = false;
    ticker?.cancel();
    countdownTimer?.cancel();
    watch.stop();
    if (boardClock.milliseconds >= 10000 || boardMistakes > 0) rememberBoard();
    boardClock.stop();
    setState(() => phase = Phase.ready);
  }

  void pick(SetCard card) {
    if (phase != Phase.playing || starting) return;
    setState(() {
      final attempt = [...game.selected, card.id];
      if (attempt.length == 3 && isSet(attempt.map(SetCard.new).toList())) {
        rememberBoard();
      }
      final result = game.pick(card.id);
      if (result == PickResult.correct || result == PickResult.finished) {
        solutions.add(attempt);
      }
      switch (result) {
        case PickResult.wrong:
          boardMistakes++;
          feedback = 'Not a set. Keep going!';
          HapticFeedback.lightImpact();
        case PickResult.correct:
          boardMistakes = 0;
          boardClock.start();
          feedback = '${game.streak} down. ${5 - game.streak} to go.';
          HapticFeedback.selectionClick();
        case PickResult.finished:
          watch.stop();
          ticker?.cancel();
          newBest = eligible && (best == null || watch.elapsed < best!);
          if (newBest) best = watch.elapsed;
          if (eligible) {
            player?.saveBest(watch.elapsedMilliseconds, seed: game.seed!);
          }
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
    boardClock.dispose();
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
                      const Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'trio',
                                style: TextStyle(
                                  fontSize: 38,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -2,
                                ),
                              ),
                              Text(
                                '.',
                                style: TextStyle(
                                  fontSize: 38,
                                  fontWeight: FontWeight.w900,
                                  color: accent,
                                ),
                              ),
                              SizedBox(width: 12),
                              Text(
                                'SPRINT',
                                style: TextStyle(
                                  fontSize: 11,
                                  letterSpacing: 3,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (phase == Phase.playing ||
                          phase == Phase.countdown) ...[
                        TextButton(
                          onPressed: abandon,
                          child: const Text('Abandon'),
                        ),
                        IconButton(
                          tooltip: 'Restart run',
                          onPressed: () => start(seed: game.seed),
                          icon: const Icon(Icons.refresh_rounded),
                        ),
                      ] else
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
    if (pendingSeed != null)
      Padding(
        padding: const EdgeInsets.all(8),
        child: Text('Seed: $pendingSeed', textAlign: TextAlign.center),
      ),
    const SizedBox(height: 10),
    Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      children: [
        TextButton(onPressed: enterSeed, child: const Text('Run a seed')),
        TextButton(
          onPressed: () async {
            final seed = pendingSeed ?? newSeed();
            setState(() => pendingSeed = seed);
            await copySeed(seed);
          },
          child: const Text('Share a seed'),
        ),
        TextButton(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => LeaderboardScreen(player: player),
            ),
          ),
          child: const Text('High scores'),
        ),
        TextButton(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => TrainingScreen(player: player)),
          ),
          child: const Text('Training'),
        ),
        TextButton(onPressed: () => openRace(), child: const Text('1 vs 1')),
        TextButton(
          onPressed: () => showInstall(context),
          child: const Text('Install app'),
        ),
      ],
    ),
    TextButton(onPressed: showRules, child: const Text('How to play')),
    const SizedBox(height: 16),
    const Text(
      'Unofficial game. Not affiliated with PlayMonster or the SET® card game.',
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 11, color: Color(0xFF68717B)),
    ),
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
      Text(
        eligible
            ? 'First attempt · ${game.seed}'
            : 'Practice replay · ${game.seed}',
        style: const TextStyle(fontSize: 11),
      ),
      if (game.seed!.startsWith('s1-'))
        const Text(
          'Legacy seed · new board after each set',
          style: TextStyle(fontSize: 11),
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
      !eligible
          ? 'Practice run'
          : newBest
          ? 'Your best run.'
          : 'Personal best  ${formatTime(best!)}',
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
    const SizedBox(height: 16),
    Text('Seed: ${game.seed}'),
    Padding(
      padding: const EdgeInsets.all(8),
      child: Text(
        eligible
            ? 'Only submit a score the first time you ever run this seed.'
            : 'Practice replay. Only your first attempt can enter the leaderboard.',
        textAlign: TextAlign.center,
      ),
    ),
    if (eligible)
      OutlinedButton(
        onPressed: submitted || submitting ? null : submitScore,
        child: Text(
          submitted
              ? 'Score submitted'
              : submitting
              ? 'Submitting…'
              : 'Submit high score',
        ),
      ),
    Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      children: [
        TextButton(
          onPressed: () => copySeed(game.seed!),
          child: const Text('Share seed'),
        ),
        TextButton(
          onPressed: submitting ? null : () => start(seed: game.seed),
          child: const Text('Replay seed (practice)'),
        ),
        TextButton(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  LeaderboardScreen(player: player, seed: game.seed),
            ),
          ),
          child: const Text('Seed high scores'),
        ),
      ],
    ),
    const SizedBox(height: 16),
    FilledButton.icon(
      onPressed: submitting ? null : start,
      icon: const Icon(Icons.refresh_rounded),
      label: const Text('Play again'),
    ),
    const SizedBox(height: 12),
    TextButton(
      onPressed: submitting ? null : () => setState(() => phase = Phase.ready),
      child: const Text('Back to start'),
    ),
    const SizedBox(height: 24),
  ]);
}
