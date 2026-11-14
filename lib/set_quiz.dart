// Copyright (C) 2026 Florian Loitsch.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'card_board.dart';
import 'game.dart';

class SetQuizScreen extends StatefulWidget {
  const SetQuizScreen({super.key});

  @override
  State<SetQuizScreen> createState() => _SetQuizScreenState();
}

enum _RacePhase { setup, countdown, playing, finished }

class _SetQuizScreenState extends State<SetQuizScreen>
    with WidgetsBindingObserver {
  bool difficultOnly = false;
  Duration limit = const Duration(minutes: 1);
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

  int get score => correct - mistakes;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    setState(() {
      phase = _RacePhase.countdown;
      countdown = 2;
      correct = 0;
      mistakes = 0;
      remaining = limit;
      exercise = null;
      resultsLocked = false;
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
      Text('${limit.inMinutes} min${difficultOnly ? ' · Difficult only' : ''}'),
      const SizedBox(height: 24),
      FilledButton(
        onPressed: resultsLocked ? null : start,
        child: const Text('Race again'),
      ),
      TextButton(
        onPressed: resultsLocked
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
