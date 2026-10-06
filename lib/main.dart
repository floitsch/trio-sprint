import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'card_view.dart';
import 'card_board.dart';
import 'game.dart';
import 'data.dart';
import 'devices.dart';
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
  RunMode mode = RunMode.sprint;
  // When the last set of a timed run was found.
  Duration lastSet = Duration.zero;

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
    if (pendingSeed != null) mode = RunMode.of(pendingSeed!);
    loading = loadPlayer();
  }

  Future<void> loadPlayer() async {
    try {
      final loaded = await PlayerData.load();
      if (!mounted) return;
      setState(() {
        player = loaded;
        if (loaded.best != null) best = Duration(milliseconds: loaded.best!);
        if (pendingSeed == null) mode = loaded.mode;
      });
      final link = normalizeDeviceCode(Uri.base.queryParameters['link'] ?? '');
      final room = Uri.base.queryParameters['room'];
      if (link != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => DevicesScreen(player: loaded, initialCode: link),
            ),
          );
        });
      } else if (room != null && RegExp(r'^[A-Z0-9]{6}$').hasMatch(room)) {
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
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 's2-1234abcd or a shared link',
          ),
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
    return await editNickname(context, player!) && mounted;
  }

  Future<void> openLeaderboard({String? seed}) async {
    final chosen = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            LeaderboardScreen(player: player, seed: seed, mode: mode),
      ),
    );
    if (chosen != null && mounted) await start(seed: chosen);
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

  /// Uploads an eligible run. Automatic uploads happen silently once a
  /// nickname is known; otherwise the results button asks for one.
  Future<void> submitScore({bool automatic = false}) async {
    if (!canSubmit || submitted || submitting || player == null) return;
    if (!OnlineApi().configured) {
      if (!automatic) message('Online scores are not configured yet.');
      return;
    }
    if (automatic && player!.nickname.isEmpty) return;
    final seed = game.seed!;
    final milliseconds = game.mode.timed
        ? lastSet.inMilliseconds
        : watch.elapsedMilliseconds;
    final mistakes = game.mistakes;
    final solved = [...solutions];
    setState(() => submitting = true);
    try {
      if (player!.nickname.isEmpty && !await askName()) return;
      await OnlineApi().submit(
        player: player!,
        seed: seed,
        milliseconds: milliseconds,
        mistakes: mistakes,
        solutions: solved,
      );
      if (mounted) setState(() => submitted = true);
    } catch (error) {
      if (mounted) message('Could not submit. You can retry: $error');
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  /// Asks whether a seed that did not originate here is new to the player.
  /// Returns null if they would rather not run it.
  Future<bool?> confirmFirstAttempt(String seed) => showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('First time on this seed?'),
      content: Text(
        'Only your first run of $seed, on any device, can enter the high scores. Have you played it before?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Played before'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('First time'),
        ),
      ],
    ),
  );

  final watch = Stopwatch();
  final elapsed = ValueNotifier(Duration.zero);
  Timer? ticker;
  Timer? countdownTimer;
  Timer? deadline;
  Phase phase = Phase.ready;
  int countdown = 2;
  Duration? best;
  TimedScore? timedBest;
  bool newBest = false;

  /// Timed runs without a set have nothing to enter into the high scores.
  bool get canSubmit => eligible && (!game.mode.timed || game.streak > 0);

  void stopClocks() {
    ticker?.cancel();
    countdownTimer?.cancel();
    deadline?.cancel();
    watch.stop();
  }

  String feedback = 'Find a set. Find your rhythm.';

  Future<void> start({String? seed}) async {
    if (starting || submitting) return;
    starting = true;
    final generation = ++runGeneration;
    if (boardClock.milliseconds >= 10000 || boardMistakes > 0) rememberBoard();
    boardClock.stop();
    boardMistakes = 0;
    stopClocks();
    await loading;
    if (!mounted || generation != runGeneration) return;
    final chosenSeed = seed ?? pendingSeed ?? newSeed(mode);
    // A seed generated right here cannot have been run anywhere else. Others
    // (typed, linked or from the high scores) might have been, so ask, unless
    // this device already knows it is a replay.
    var firstTime = seed == null && pendingSeed == null;
    if (!firstTime && player != null) {
      var known = false;
      try {
        known = await player!.hasAttempted(chosenSeed);
      } catch (_) {
        // Claiming below still fails closed if storage is unusable.
      }
      if (!mounted || generation != runGeneration) return;
      if (!known) {
        final answer = await confirmFirstAttempt(chosenSeed);
        if (!mounted || generation != runGeneration) return;
        if (answer == null) {
          starting = false;
          return;
        }
        firstTime = answer;
      }
    }
    pendingSeed = null;
    var firstAttempt = false;
    try {
      // Claim even when not first: the seed is now attempted on this device.
      final claimed = await player?.claimSeed(chosenSeed) ?? false;
      firstAttempt = claimed && firstTime;
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
    lastSet = Duration.zero;
    stopClocks();
    watch.reset();
    elapsed.value = Duration.zero;
    setState(() {
      game = SetGame(seed: chosenSeed);
      mode = game.mode;
      final previousBest = player?.bestForSeed(chosenSeed);
      best = previousBest == null ? null : Duration(milliseconds: previousBest);
      timedBest = mode.timed ? player?.timedBest(mode) : null;
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
        final limit = game.mode.limit;
        if (limit != null) deadline = Timer(limit, endTimedRun);
        ticker = Timer.periodic(const Duration(milliseconds: 33), (_) {
          elapsed.value = watch.elapsed;
          // Timers may be late while the app is in the background.
          if (limit != null && watch.elapsed >= limit) endTimedRun();
        });
      }
    });
  }

  void abandon() {
    runGeneration++;
    starting = false;
    stopClocks();
    if (boardClock.milliseconds >= 10000 || boardMistakes > 0) rememberBoard();
    boardClock.stop();
    setState(() => phase = Phase.ready);
  }

  void endTimedRun() {
    if (phase != Phase.playing || !game.mode.timed) return;
    stopClocks();
    elapsed.value = game.mode.limit!;
    if (boardClock.milliseconds >= 10000 || boardMistakes > 0) rememberBoard();
    boardClock.stop();
    final score = TimedScore(game.streak, lastSet.inMilliseconds);
    setState(() {
      newBest = canSubmit && score.beats(timedBest);
      if (newBest) {
        timedBest = score;
        player?.saveTimedBest(game.mode, score);
      }
      game.selected.clear();
      phase = Phase.finished;
    });
    HapticFeedback.mediumImpact();
    unawaited(submitScore(automatic: true));
  }

  void pick(SetCard card) {
    if (phase != Phase.playing || starting) return;
    final limit = game.mode.limit;
    if (limit != null && watch.elapsed >= limit) {
      endTimedRun();
      return;
    }
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
          lastSet = watch.elapsed;
          feedback = game.mode.timed
              ? '${game.streak} found. Keep going!'
              : '${game.streak} down. ${5 - game.streak} to go.';
          HapticFeedback.selectionClick();
        case PickResult.finished:
          stopClocks();
          newBest = eligible && (best == null || watch.elapsed < best!);
          if (newBest) best = watch.elapsed;
          if (eligible) {
            player?.saveBest(watch.elapsedMilliseconds, seed: game.seed!);
          }
          phase = Phase.finished;
          HapticFeedback.mediumImpact();
          unawaited(submitScore(automatic: true));
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
    stopClocks();
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
              const SizedBox(height: 12),
              const Text(
                'Or race the clock: find as many sets as you can in one or three minutes. Ties go to whoever found their last set first.',
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

  bool get inRun => phase == Phase.playing || phase == Phase.countdown;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: inRun ? 12 : 22),
            child: Column(
              children: [
                Padding(
                  padding: EdgeInsets.symmetric(vertical: inRun ? 2 : 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'trio',
                                style: TextStyle(
                                  fontSize: inRun ? 24 : 38,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -2,
                                ),
                              ),
                              Text(
                                '.',
                                style: TextStyle(
                                  fontSize: inRun ? 24 : 38,
                                  fontWeight: FontWeight.w900,
                                  color: accent,
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Text(
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
                          onPressed: start,
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
    // Scale down rather than wrap the longer headlines on narrow phones.
    FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        mode.timed
            ? '${mode.label}.\nEvery set counts.'
            : 'Five sets.\nOne good run.',
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 46,
          height: 1.08,
          letterSpacing: -2,
          fontWeight: FontWeight.w800,
        ),
      ),
    ),
    const SizedBox(height: 24),
    Text(
      mode.timed
          ? 'Find as many sets as you can\nbefore the clock runs out.'
          : 'Find five sets in a row.\nSee how fast your eyes can go.',
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 17, height: 1.5, color: Color(0xFF68717B)),
    ),
    const SizedBox(height: 28),
    ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 350),
      child: SizedBox(
        height: 124,
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
    const SizedBox(height: 24),
    SegmentedButton<RunMode>(
      showSelectedIcon: false,
      segments: [
        for (final mode in RunMode.values)
          ButtonSegment(value: mode, label: Text(mode.shortLabel)),
      ],
      selected: {mode},
      onSelectionChanged: (selection) {
        final chosen = selection.single;
        setState(() {
          mode = chosen;
          // A pending seed belongs to one mode.
          if (pendingSeed != null && RunMode.of(pendingSeed!) != chosen) {
            pendingSeed = null;
          }
        });
        player?.setMode(chosen).catchError((Object _) {});
      },
    ),
    const SizedBox(height: 12),
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
            final seed = pendingSeed ?? newSeed(mode);
            setState(() => pendingSeed = seed);
            await copySeed(seed);
          },
          child: const Text('Share a seed'),
        ),
        TextButton(
          onPressed: openLeaderboard,
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
          onPressed: () async {
            await loading;
            if (!mounted) return;
            if (player == null) {
              message('Device storage is needed to link devices.');
              return;
            }
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => DevicesScreen(player: player!)),
            );
          },
          child: const Text('Link devices'),
        ),
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
    child: FittedBox(
      fit: BoxFit.scaleDown,
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
          Text(
            game.mode.timed
                ? '${game.mode.label}. Every set counts.'
                : 'Five sets. You’ve got this.',
            style: const TextStyle(fontSize: 17),
          ),
        ],
      ),
    ),
  );

  Widget playing() => LayoutBuilder(
    builder: (context, constraints) {
      final status = runStatus();
      final board = Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: CardBoard(
          cards: game.board.map((card) => card.id).toList(),
          selected: game.selected,
          onTap: pick,
        ),
      );
      if (constraints.maxWidth > 500 &&
          constraints.maxWidth > constraints.maxHeight * 1.5) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 176, child: status),
            const SizedBox(width: 16),
            Expanded(child: board),
          ],
        );
      }
      return Column(
        children: [
          status,
          Expanded(child: board),
        ],
      );
    },
  );

  /// The time left in a timed run, or null for a sprint.
  Duration? remaining(Duration elapsed) {
    final limit = game.mode.limit;
    if (limit == null) return null;
    return elapsed >= limit ? Duration.zero : limit - elapsed;
  }

  Widget runStatus() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  Text(
                    game.mode.timed ? '${game.streak}' : '${game.streak} / 5',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text('sets', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: ValueListenableBuilder<Duration>(
                valueListenable: elapsed,
                builder: (context, value, child) => Text(
                  formatTime(remaining(value) ?? value),
                  key: const ValueKey('timer'),
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            eligible
                ? 'First attempt · ${game.seed}'
                : 'Practice replay · ${game.seed}',
            style: const TextStyle(fontSize: 11, color: Color(0xFF68717B)),
          ),
        ),
      ),
      if (game.seed!.startsWith('s1-'))
        const Text(
          'Legacy seed · new board after each set',
          style: TextStyle(fontSize: 11),
        ),
      if (game.mode.timed)
        ValueListenableBuilder<Duration>(
          valueListenable: elapsed,
          builder: (context, value, child) => ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value:
                  remaining(value)!.inMilliseconds /
                  game.mode.limit!.inMilliseconds,
              minHeight: 4,
              color: accent,
              backgroundColor: const Color(0xFFDEDED5),
            ),
          ),
        )
      else
        Row(
          children: List.generate(
            5,
            (i) => Expanded(
              child: Container(
                margin: EdgeInsets.only(right: i == 4 ? 0 : 6),
                height: 4,
                decoration: BoxDecoration(
                  color: i < game.streak ? accent : const Color(0xFFDEDED5),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
        ),
      SizedBox(
        height: 32,
        child: Center(
          child: Semantics(
            liveRegion: true,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                feedback,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ),
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
      child: Icon(
        game.mode.timed ? Icons.timer_outlined : Icons.check_rounded,
        size: 38,
        color: const Color(0xFF377548),
      ),
    ),
    const SizedBox(height: 24),
    Text(
      game.mode.timed ? 'Time’s up.' : 'Five in a row.',
      style: const TextStyle(
        fontSize: 38,
        letterSpacing: -1.5,
        fontWeight: FontWeight.w800,
      ),
    ),
    const SizedBox(height: 12),
    FittedBox(
      child: Text(
        game.mode.timed ? '${game.streak}' : formatTime(watch.elapsed),
        key: const ValueKey('result-time'),
        style: const TextStyle(
          fontSize: 78,
          letterSpacing: -3,
          fontWeight: FontWeight.w700,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    ),
    Text(
      game.mode.timed
          ? '${game.streak == 1 ? 'SET' : 'SETS'} IN ${game.mode.label.toUpperCase()}'
          : 'YOUR TIME',
      style: const TextStyle(
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
          : !game.mode.timed
          ? 'Personal best  ${formatTime(best!)}'
          : timedBest == null
          ? 'No personal best yet.'
          : 'Personal best  ${setCount(timedBest!.sets)}',
      style: const TextStyle(
        color: accent,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
    ),
    const SizedBox(height: 8),
    Text(
      game.mode.timed
          ? [
              if (game.streak > 0) 'Last set at ${formatTime(lastSet)}.',
              game.mistakes == 0
                  ? 'No mistakes.'
                  : '${game.mistakes} ${game.mistakes == 1 ? 'mistake' : 'mistakes'}.',
            ].join(' ')
          : game.mistakes == 0
          ? 'Clean run. Every set counted.'
          : '${game.mistakes} ${game.mistakes == 1 ? 'mistake' : 'mistakes'}. You got there.',
      style: const TextStyle(color: Color(0xFF68717B)),
    ),
    const SizedBox(height: 16),
    Text('Seed: ${game.seed}'),
    Padding(
      padding: const EdgeInsets.all(8),
      child: Text(
        !eligible
            ? 'Practice replay. Only your first attempt can enter the leaderboard.'
            : !canSubmit
            ? 'Find at least one set to enter the high scores.'
            : submitted
            ? 'Score submitted as ${player!.nickname}.'
            : submitting
            ? 'Submitting your score…'
            : 'First attempt. It can enter the high scores.',
        textAlign: TextAlign.center,
      ),
    ),
    if (canSubmit && !submitted && !submitting)
      OutlinedButton(
        onPressed: submitScore,
        child: const Text('Submit high score'),
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
          onPressed: () => openLeaderboard(seed: game.seed),
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

String setCount(int sets) => '$sets ${sets == 1 ? 'set' : 'sets'}';
