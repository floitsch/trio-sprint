// Copyright (C) 2026 Florian Loitsch.
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'card_board.dart';
import 'game.dart';
import 'data.dart';
import 'leaderboard.dart';
import 'quiz_leaderboard.dart';
import 'quiz_review.dart';
import 'quiz_seed.dart';
import 'sync.dart';

class SetQuizScreen extends StatefulWidget {
  const SetQuizScreen({
    super.key,
    this.player,
    this.sync,
    this.seconds = 30,
    this.difficult = false,
    this.autoStart = false,
    this.seed,
  });
  final PlayerData? player;
  final SyncService? sync;
  final int seconds;
  final bool difficult;
  final bool autoStart;
  final String? seed;

  @override
  State<SetQuizScreen> createState() => _SetQuizScreenState();
}

enum _RacePhase { setup, countdown, playing, finished }

class _SetQuizScreenState extends State<SetQuizScreen>
    with WidgetsBindingObserver {
  late bool difficultOnly = widget.difficult;
  late Duration limit = Duration(seconds: widget.seconds);
  _RacePhase phase = _RacePhase.setup;
  SetQuizExercise? exercise;
  int correct = 0;
  int mistakes = 0;
  int countdown = 2;
  final watch = Stopwatch();
  Duration remaining = const Duration(minutes: 1);
  Timer? countdownTimer;
  Timer? ticker;
  Timer? deadline;
  Timer? resultsLock;
  bool resultsLocked = false;
  String runId = '';
  final answers = <List<Object>>[];
  List<int>? unfinishedCards;
  bool saving = false;
  bool saveFailed = false;
  int? previousBest;
  late QuizSeed? pendingSeed = QuizSeed.parse(widget.seed ?? '');
  QuizSeed? activeSeed;
  Random? random;
  bool practice = false;

  Future<void> copySeed() async {
    await Clipboard.setData(
      ClipboardData(text: shareLink('quiz', activeSeed!.value)),
    );
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Seed link copied.')));
    }
  }

  Future<void> enterSeed() async {
    var input = '';
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Run a seed'),
        content: TextField(
          onChanged: (value) => input = value,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'q1-30-n-1234abcd or a shared link',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, input),
            child: const Text('Run seed'),
          ),
        ],
      ),
    );
    if (!mounted || result == null) return;
    final parsed = QuizSeed.parse(result);
    if (parsed == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a recognition seed such as q1-30-n-1234abcd.'),
        ),
      );
      return;
    }
    start(seed: parsed.value);
  }

  Future<void> highScores() => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => QuizLeaderboardScreen(
        player: widget.player,
        seconds: limit.inSeconds,
        difficult: difficultOnly,
      ),
    ),
  );

  Future<void> saveResult() async {
    final player = widget.player;
    if (player == null || answers.isEmpty || practice) return;
    setState(() {
      saving = true;
      saveFailed = false;
    });
    try {
      await player.queueQuizScore(
        id: runId,
        seconds: limit.inSeconds,
        difficult: difficultOnly,
        correct: correct,
        mistakes: mistakes,
        answers: List.of(answers),
      );
    } catch (_) {
      if (mounted) setState(() => saveFailed = true);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  int get score => correct - mistakes;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (pendingSeed case final seed?) {
      limit = Duration(seconds: seed.seconds);
      difficultOnly = seed.difficult;
    }
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) start();
      });
    }
  }

  void stopTimers() {
    countdownTimer?.cancel();
    ticker?.cancel();
    deadline?.cancel();
    resultsLock?.cancel();
    watch.stop();
  }

  void start({String? seed}) {
    final chosen =
        QuizSeed.parse(seed ?? '') ??
        pendingSeed ??
        QuizSeed.create(limit.inSeconds, difficultOnly);
    practice = seed != null || pendingSeed != null;
    pendingSeed = null;
    activeSeed = chosen;
    random = chosen.random();
    limit = Duration(seconds: chosen.seconds);
    difficultOnly = chosen.difficult;
    stopTimers();
    watch.reset();
    runId = randomId();
    answers.clear();
    unfinishedCards = null;
    previousBest = widget.player?.quizBest(limit.inSeconds, difficultOnly);
    setState(() {
      phase = _RacePhase.countdown;
      countdown = 2;
      correct = 0;
      mistakes = 0;
      remaining = limit;
      exercise = null;
      resultsLocked = false;
      saveFailed = false;
    });
    countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (countdown > 1) {
        setState(() => countdown--);
      } else {
        timer.cancel();
        setState(() {
          exercise = SetQuizExercise(
            difficultOnly: difficultOnly,
            random: random,
          );
          phase = _RacePhase.playing;
          watch.start();
        });
        deadline = Timer(limit, finish);
        ticker = Timer.periodic(
          const Duration(milliseconds: 100),
          (_) => tick(),
        );
      }
    });
  }

  void tick() {
    if (phase != _RacePhase.playing) return;
    if (watch.elapsed >= limit) {
      finish();
    } else {
      setState(() => remaining = limit - watch.elapsed);
    }
  }

  void finish() {
    if (phase != _RacePhase.playing) return;
    stopTimers();
    setState(() {
      unfinishedCards = exercise!.cards.map((card) => card.id).toList();
      phase = _RacePhase.finished;
      remaining = Duration.zero;
      exercise = null;
      resultsLocked = true;
    });
    unawaited(saveResult());
    resultsLock = Timer(const Duration(seconds: 1), () {
      if (mounted) setState(() => resultsLocked = false);
    });
  }

  void answer(bool value) {
    if (phase != _RacePhase.playing) return;
    // Reject late taps even when the deadline timer was delayed in the background.
    if (watch.elapsed >= limit) {
      finish();
      return;
    }
    answers.add([...exercise!.cards.map((card) => card.id), value]);
    final right = value == exercise!.answer;
    if (right) {
      HapticFeedback.selectionClick();
    } else {
      HapticFeedback.heavyImpact();
    }
    setState(() {
      if (right) {
        correct++;
      } else {
        mistakes++;
      }
      exercise = SetQuizExercise(difficultOnly: difficultOnly, random: random);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) tick();
  }

  @override
  void dispose() {
    stopTimers();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Widget setup() => ListView(
    padding: const EdgeInsets.all(22),
    children: [
      Text(
        'Three cards. Yes or no?',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 12),
      const Text(
        'Race against the clock. Correct answers earn 1 point; wrong answers lose 1 point. Each answer immediately brings a new trio. About half are valid sets.',
      ),
      const SizedBox(height: 16),
      SegmentedButton<Duration>(
        segments: const [
          ButtonSegment(value: Duration(seconds: 30), label: Text('30 s')),
          ButtonSegment(value: Duration(minutes: 1), label: Text('1 min')),
          ButtonSegment(value: Duration(minutes: 3), label: Text('3 min')),
        ],
        selected: {limit},
        onSelectionChanged: (value) => setState(() {
          limit = value.single;
          pendingSeed = null;
        }),
      ),
      const SizedBox(height: 16),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Difficult only'),
        subtitle: const Text(
          'At most one property is the same across all three cards, for both valid and invalid trios.',
        ),
        value: difficultOnly,
        onChanged: (value) => setState(() {
          difficultOnly = value!;
          pendingSeed = null;
        }),
      ),
      const SizedBox(height: 16),
      if (pendingSeed case final seed?) Text('Seed: ${seed.value} · Practice'),
      FilledButton(onPressed: start, child: const Text('Start race')),
      TextButton(onPressed: enterSeed, child: const Text('Run a seed')),
      TextButton(onPressed: highScores, child: const Text('High scores')),
    ],
  );

  Widget playing() => LayoutBuilder(
    builder: (context, constraints) => Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Score: $score'),
              Text(
                formatTime(remaining),
                key: const ValueKey('quiz-time'),
                style: const TextStyle(
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: CardBoard(
              cards: exercise!.cards.map((card) => card.id).toList(),
              columns: 3,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 32),
          child: SizedBox(
            height: (constraints.maxHeight * .2).clamp(80.0, 112.0).toDouble(),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => answer(false),
                    child: const Text(
                      'No',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: FilledButton(
                    onPressed: () => answer(true),
                    child: const Text(
                      'Yes',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  void reviewTrios() {
    final trios = [
      for (final entry in answers)
        QuizReviewTrio(
          cards: entry.take(3).cast<int>().toList(),
          answer: entry[3] as bool,
        ),
      if (unfinishedCards case final cards?) QuizReviewTrio(cards: cards),
    ];
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => QuizReviewScreen(trios: trios)),
    );
  }

  String get scoreSyncStatus {
    final saved = widget.player?.savedQuizScore(runId);
    if (saved?['status'] == 'synced') {
      return 'Score submitted as ${saved!['name']}.';
    }
    if (saved?['status'] == 'rejected') {
      return 'Score not accepted: ${saved!['error']}';
    }
    if ((saved?['name'] as String? ?? '').isEmpty &&
        widget.player!.nickname.isEmpty) {
      return 'Saved on this device. Add a nickname to publish your score.';
    }
    final sync = widget.sync;
    if (sync != null && !sync.api.configured) {
      return 'Saved on this device. Online scores are not configured in this build.';
    }
    if (sync?.busy == true) return 'Uploading score…';
    if (sync?.error != null) {
      return 'Upload pending. Saved on this device; retrying automatically.';
    }
    return 'Saved on this device. Upload pending.';
  }

  Widget results() => ListView(
    padding: const EdgeInsets.all(22),
    children: [
      Text('Time’s up.', style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 16),
      Text('Score: $score', style: Theme.of(context).textTheme.headlineLarge),
      const SizedBox(height: 8),
      Text('$correct correct · $mistakes wrong'),
      Text(
        '${quizDurationLabel(limit.inSeconds)}${difficultOnly ? ' · Difficult only' : ''}',
      ),
      if (previousBest != null) Text('Previous personal best: $previousBest'),
      if (answers.isNotEmpty &&
          (previousBest == null || score > previousBest!) &&
          !saveFailed &&
          !saving &&
          widget.player != null &&
          !practice)
        const Text('New personal best!'),
      if (practice)
        const Text(
          'Practice replay. Personal best and high scores are unchanged.',
        )
      else if (saving)
        const Text('Saving score…')
      else if (saveFailed) ...[
        const Text('Could not save this score.'),
        TextButton(onPressed: saveResult, child: const Text('Retry saving')),
      ] else if (answers.isEmpty)
        const Text('Answer at least one trio to enter the high scores.')
      else if (widget.player == null)
        const Text('Device storage is unavailable; this score cannot be saved.')
      else
        Semantics(liveRegion: true, child: Text(scoreSyncStatus)),
      if (!practice &&
          answers.isNotEmpty &&
          widget.player != null &&
          widget.player!.nickname.isEmpty)
        TextButton(
          onPressed: () async {
            await editNickname(context, widget.player!);
            if (mounted) setState(() {});
          },
          child: const Text('Set nickname'),
        ),
      if (answers.isNotEmpty || unfinishedCards != null)
        OutlinedButton.icon(
          onPressed: resultsLocked ? null : reviewTrios,
          icon: const Icon(Icons.view_carousel_outlined),
          label: const Text('Review trios'),
        ),
      TextButton(
        onPressed: resultsLocked ? null : highScores,
        child: const Text('High scores'),
      ),
      SelectableText('Seed: ${activeSeed!.value}'),
      TextButton.icon(
        onPressed: resultsLocked ? null : copySeed,
        icon: const Icon(Icons.copy),
        label: const Text('Copy seed link'),
      ),
      TextButton(
        onPressed: resultsLocked || saving
            ? null
            : () => start(seed: activeSeed!.value),
        child: const Text('Replay seed (practice)'),
      ),
      const SizedBox(height: 24),
      FilledButton(
        onPressed: resultsLocked || saving ? null : start,
        child: const Text('Race again'),
      ),
      TextButton(
        onPressed: resultsLocked || saving
            ? null
            : () => setState(() => phase = _RacePhase.setup),
        child: const Text('Change settings'),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Is this a set?')),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: switch (phase) {
            _RacePhase.setup => setup(),
            _RacePhase.countdown => Center(
              child: Text(
                '$countdown',
                key: const ValueKey('quiz-countdown'),
                style: Theme.of(context).textTheme.displayLarge,
              ),
            ),
            _RacePhase.playing => playing(),
            _RacePhase.finished =>
              widget.sync == null
                  ? results()
                  : ListenableBuilder(
                      listenable: widget.sync!,
                      builder: (context, _) => results(),
                    ),
          },
        ),
      ),
    ),
  );
}
