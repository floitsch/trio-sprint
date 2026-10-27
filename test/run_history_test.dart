// Copyright (C) 2026 Toit contributors.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trio_sprint/data.dart';
import 'package:trio_sprint/game.dart';
import 'package:trio_sprint/practice.dart';
import 'package:trio_sprint/run_history.dart';
import 'package:trio_sprint/statistics.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  PracticeBoard board(
    String seed,
    AttemptOutcome outcome, {
    String? runId,
    String? source,
    int? recordedAt,
  }) {
    final cards = SetGame(seed: seed).board;
    return PracticeBoard(
      cards: cards.map((c) => c.id).toList(),
      seed: seed,
      source: source ?? seed.split('-').first,
      outcome: outcome,
      solutionCards: outcome == AttemptOutcome.solved
          ? findSet(cards)!.map((c) => c.id).toList()
          : [],
      milliseconds: 2000,
      runId: runId,
      recordedAt: recordedAt,
    );
  }

  test(
    'old timed runs count solves, retain zeroes and exclude abandonments',
    () {
      final runs = restoreRunHistory([], [
        board('1m-1234abcd', AttemptOutcome.solved),
        board('1m-1234abcd', AttemptOutcome.solved),
        board('1m-1234abcd', AttemptOutcome.timedOut),
        board('3m-1234abcd', AttemptOutcome.timedOut),
        board('1m-1234abcd', AttemptOutcome.solved, source: 'replay'),
        board('1m-1234abcd', AttemptOutcome.interrupted, source: 'replay'),
        board('1m-1234abcd', AttemptOutcome.solved, source: 'replay'),
        board('1m-1234abcd', AttemptOutcome.timedOut, source: 'replay'),
        board('1m-00000000', AttemptOutcome.solved),
      ], []);
      expect(runs, hasLength(5));
      expect(runs.where((r) => r.completed).map((r) => r.sets), [2, 0, 1]);
      expect(runs.where((r) => !r.completed), hasLength(2));
      expect(
        runs.where((r) => !r.completed).map(runScore),
        everyElement('Abandoned'),
      );
    },
  );

  test('old sprint scores use saved time and otherwise label active time', () {
    final runs = restoreRunHistory(
      [],
      [
        for (var i = 0; i < 5; i++) board('s2-1234abcd', AttemptOutcome.solved),
        for (var i = 0; i < 5; i++)
          board('s2-1234abcd', AttemptOutcome.solved, source: 'replay'),
      ],
      [
        {
          'seed': 's2-1234abcd',
          'milliseconds': 15000,
          'mistakes': 0,
          'solutions': List.filled(5, [0, 1, 2]),
        },
      ],
    );
    expect(runs, hasLength(2));
    expect(runs.every((r) => r.completed), isTrue);
    expect(runs.first.milliseconds, 15000);
    expect(runs.first.activeTimeOnly, isFalse);
    expect(runs.last.milliseconds, 10000);
    expect(runs.last.activeTimeOnly, isTrue);
  });

  test(
    'run records survive reload and do not duplicate their board history',
    () async {
      final player = await PlayerData.load();
      await Future.wait([
        player.recordPractice(
          board('1m-1234abcd', AttemptOutcome.solved, runId: 'first'),
        ),
        player.recordPractice(
          board('1m-1234abcd', AttemptOutcome.timedOut, runId: 'first'),
        ),
        player.recordRun(
          const RunRecord(
            id: 'first',
            seed: '1m-1234abcd',
            source: '1m',
            completed: true,
            sets: 1,
            mistakes: 2,
            milliseconds: 4321,
            recordedAt: 100,
          ),
        ),
        player.recordRun(
          const RunRecord(
            id: 'replay',
            seed: '1m-1234abcd',
            source: 'replay',
            completed: true,
            sets: 3,
            mistakes: 0,
            milliseconds: 50000,
            recordedAt: 200,
          ),
        ),
        player.recordRun(
          const RunRecord(
            id: 'countdown',
            seed: '3m-1234abcd',
            source: '3m',
            completed: false,
            sets: 0,
            mistakes: 0,
            recordedAt: 300,
          ),
        ),
      ]);
      final reloaded = await PlayerData.load();
      final runs = reloaded.runHistory;
      expect(runs.map((r) => r.id), ['countdown', 'replay', 'first']);
      expect(runScore(runs.first), 'Abandoned');
      expect(runScore(runs[1]), '3 sets');
      expect(runs.last.milliseconds, 4321);
      expect(runs.last.mistakes, 2);
      expect(reloaded.attemptsHistory.first.runId, 'first');
    },
  );

  test(
    'saved scores without board history remain available with unknown dates',
    () async {
      final player = await PlayerData.load();
      await player.queueScore(
        seed: '1m-1234abcd',
        milliseconds: 45000,
        mistakes: 1,
        solutions: [
          [0, 1, 2],
          [3, 4, 5],
        ],
      );
      final run = player.runHistory.single;
      expect(run.completed, isTrue);
      expect(run.recordedAt, isNull);
      expect(run.sets, 2);
      expect(runScore(run), '2 sets');
    },
  );
}
