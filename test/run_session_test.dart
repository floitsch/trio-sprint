// Copyright (C) 2026 Florian Loitsch.
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trio_sprint/run_scores.dart';
import 'package:trio_sprint/run_session.dart';

import 'support/controlled_stopwatch.dart';

void main() {
  testWidgets('a deadline delayed in the background expires once on resume', (
    tester,
  ) async {
    final watch = ControlledStopwatch();
    final session = RunSession(stopwatch: watch);
    var completions = 0;
    var foreground = false;
    session.start(
      limit: const Duration(seconds: 30),
      canExpire: () => foreground,
      onLimit: () {
        completions++;
        session.finish(
          lockInput: true,
          shownElapsed: const Duration(seconds: 30),
        );
      },
    );
    await tester.pump(const Duration(seconds: 2));
    watch.value = const Duration(seconds: 40);
    await tester.pump(const Duration(seconds: 40));
    expect(session.phase, RunPhase.playing);
    expect(completions, 0);
    foreground = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(completions, 1);
    expect(session.phase, RunPhase.finished);
    expect(session.elapsed.value, const Duration(seconds: 30));
    expect(session.remaining, Duration.zero);
    expect(session.checkLimit(), isFalse);
    await tester.pump(const Duration(seconds: 1));
    expect(completions, 1);
    expect(session.resultsLocked, isFalse);
    session.dispose();
  });

  testWidgets(
    'restarting invalidates old countdowns, deadlines and result locks',
    (tester) async {
      final session = RunSession();
      var expired = 0;
      void start(Duration limit) => session.start(
        limit: limit,
        onLimit: () {
          expired++;
          session.finish(lockInput: true);
        },
      );
      start(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      session.reset();
      start(const Duration(seconds: 10));
      await tester.pump(const Duration(seconds: 2));
      expect(session.phase, RunPhase.playing);
      await tester.pump(const Duration(seconds: 1));
      expect(expired, 0);
      session.finish(lockInput: true);
      await tester.pump(const Duration(milliseconds: 500));
      start(const Duration(seconds: 10));
      await tester.pump(const Duration(seconds: 2));
      session.finish(lockInput: true);
      await tester.pump(const Duration(milliseconds: 999));
      expect(session.resultsLocked, isTrue);
      await tester.pump(const Duration(milliseconds: 1));
      expect(session.resultsLocked, isFalse);
      start(const Duration(seconds: 1));
      session.dispose();
      await tester.pump(const Duration(minutes: 1));
      expect(expired, 0);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'failed local saves can retry without duplicating an in-flight save',
    () async {
      final submission = RunScoreSubmission();
      final gate = Completer<void>();
      final pending = submission.save(() => gate.future);
      var writes = 0;
      expect(await submission.save(() async => writes++), isFalse);
      gate.completeError(StateError('Storage unavailable'));
      expect(await pending, isFalse);
      expect(submission.busy, isFalse);
      expect(submission.error, isA<StateError>());
      expect(await submission.save(() async => writes++), isTrue);
      expect(writes, 1);
      expect(submission.error, isNull);
      submission.dispose();
    },
  );

  test('a local save may finish after its screen is disposed', () async {
    final submission = RunScoreSubmission();
    final gate = Completer<void>();
    var notifications = 0;
    submission.addListener(() => notifications++);
    final pending = submission.save(() => gate.future);
    submission.dispose();
    gate.complete();
    expect(await pending, isTrue);
    expect(notifications, 1);
  });
}
