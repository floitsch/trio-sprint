// Copyright (C) 2026 Florian Loitsch.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'card_board.dart';
import 'game.dart';
import 'data.dart';
import 'leaderboard.dart';
import 'quiz_leaderboard.dart';

class SetQuizScreen extends StatefulWidget {
  const SetQuizScreen({
    super.key,
    this.player,
    this.seconds = 30,
    this.difficult = false,
    this.autoStart = false,
  });
  final PlayerData? player;
  final int seconds;
  final bool difficult;
  final bool autoStart;

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
  bool saving = false;
  bool saveFailed = false;
  int? previousBest;

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
    if (player == null || answers.isEmpty) return;
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

  void start() {
    stopTimers();
    watch.reset();
    runId = randomId();
    answers.clear();
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
          exercise = SetQuizExercise(difficultOnly: difficultOnly);
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
      exercise = SetQuizExercise(difficultOnly: difficultOnly);
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
        onSelectionChanged: (value) => setState(() => limit = value.single),
      ),
      const SizedBox(height: 16),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Difficult only'),
        subtitle: const Text(
          'At most one property is the same across all three cards, for both valid and invalid trios.',
        ),
        value: difficultOnly,
        onChanged: (value) => setState(() => difficultOnly = value!),
      ),
      const SizedBox(height: 16),
      FilledButton(onPressed: start, child: const Text('Start race')),
      TextButton(onPressed: highScores, child: const Text('High scores')),
    ],
  );

  Widget playing() => Column(
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
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => answer(false),
                child: const Text('No'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: () => answer(true),
                child: const Text('Yes'),
              ),
            ),
          ],
        ),
      ),
    ],
  );

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
          widget.player != null)
        const Text('New personal best!'),
      if (saving)
        const Text('Saving score…')
      else if (saveFailed) ...[
        const Text('Could not save this score.'),
        TextButton(onPressed: saveResult, child: const Text('Retry saving')),
      ] else if (answers.isEmpty)
        const Text('Answer at least one trio to enter the high scores.')
      else if (widget.player == null)
        const Text('Device storage is unavailable; this score cannot be saved.')
      else
        const Text(
          'Saved on this device. Scores sync automatically when online.',
        ),
      if (answers.isNotEmpty &&
          widget.player != null &&
          widget.player!.nickname.isEmpty)
        TextButton(
          onPressed: () async {
            await editNickname(context, widget.player!);
            if (mounted) setState(() {});
          },
          child: const Text('Set nickname'),
        ),
      TextButton(
        onPressed: resultsLocked ? null : highScores,
        child: const Text('High scores'),
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
            _RacePhase.finished => results(),
          },
        ),
      ),
    ),
  );
}
