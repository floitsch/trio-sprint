// Copyright (C) 2026 Toit contributors.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trio_sprint/data.dart';
import 'package:trio_sprint/game.dart';
import 'package:trio_sprint/practice.dart';
import 'package:trio_sprint/statistics.dart';
import 'package:trio_sprint/card_view.dart';
import 'package:trio_sprint/main.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final cards = SetGame(seed: 's2-1234abcd').board.map((c) => c.id).toList();
  PracticeBoard attempt(
    int ms, {
    AttemptOutcome outcome = AttemptOutcome.solved,
    String source = 's2',
    bool assisted = false,
  }) => PracticeBoard(
    cards: cards,
    milliseconds: ms,
    source: source,
    outcome: outcome,
    assisted: assisted,
    solutionCards: outcome == AttemptOutcome.solved
        ? findSet(cards.map(SetCard.new).toList())!.map((c) => c.id).toList()
        : [],
  );

  test('retains repeated solves and interrupted records without training pollution', () async {
    final player = await PlayerData.load();
    await Future.wait([
      player.recordPractice(attempt(2000)),
      player.recordPractice(attempt(4000)),
      player.recordPractice(
        attempt(120000, outcome: AttemptOutcome.interrupted),
      ),
    ]);
    final reloaded = await PlayerData.load();
    expect(reloaded.attemptsHistory.length, 3);
    expect(reloaded.practiceHistory.single.milliseconds, 4000);
    expect(reloaded.benchmarkMedian, 3000);
    expect(reloaded.attemptsHistory.first.solutionCards, isNotEmpty);
    await reloaded.recordPractice(
      attempt(60000, outcome: AttemptOutcome.timedOut),
    );
    expect(reloaded.slowBoards.single.outcome, AttemptOutcome.timedOut);
    await reloaded.recordPractice(
      attempt(100, outcome: AttemptOutcome.restarted),
    );
    expect(reloaded.slowBoards.single.difficulty, 15100);
    expect(reloaded.benchmarkMedian, 3000);
  });

  test('benchmark excludes hints, replays and unfinished attempts', () async {
    final player = await PlayerData.load();
    for (final record in [
      attempt(3000),
      attempt(1000, assisted: true),
      attempt(1000, source: 'replay'),
      attempt(100, outcome: AttemptOutcome.skipped),
    ]) {
      await player.recordPractice(record);
    }
    expect(player.benchmarkMedian, 3000);
    expect(player.benchmarkCount, 1);
    expect(medianMilliseconds([]), isNull);
    expect(medianMilliseconds([9, 1, 4]), 4);
  });

  testWidgets('fastest layout opens without a solution and can reveal it', (
    tester,
  ) async {
    final player = await PlayerData.load();
    await player.recordPractice(attempt(2000));
    await tester.pumpWidget(
      MaterialApp(home: StatisticsScreen(player: player)),
    );
    await tester.tap(find.text('Fastest ever set (unassisted)'));
    await tester.pumpAndSettle();
    expect(
      tester.widgetList<CardView>(find.byType(CardView)).map((c) => c.card.id),
      cards,
    );
    expect(
      tester
          .widgetList<CardView>(find.byType(CardView))
          .where((c) => c.selected),
      isEmpty,
    );
    await tester.tap(find.text('Show solution'));
    await tester.pump();
    expect(
      tester
          .widgetList<CardView>(find.byType(CardView))
          .where((c) => c.selected)
          .length,
      3,
    );
    expect(player.attemptsHistory.length, 1);
  });

  testWidgets('restart and Too slow retain unfinished boards for training', (
    tester,
  ) async {
    await tester.pumpWidget(const TrioSprintApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start run'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.byTooltip('Restart run'));
    await tester.pumpAndSettle();
    final player = await PlayerData.load();
    expect(player.attemptsHistory.single.outcome, AttemptOutcome.restarted);
    await tester.pump();
    expect(player.slowBoards.single.difficulty, greaterThanOrEqualTo(15000));
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.text('Abandon'));
    await tester.pump();
    await tester.tap(find.text('Too slow'));
    await tester.pumpAndSettle();
    expect(player.attemptsHistory.length, 2);
    expect(
      player.attemptsHistory.every(
        (a) => a.outcome == AttemptOutcome.restarted,
      ),
      isTrue,
    );
    expect(player.benchmarkMedian, isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'timeout records unfinished board and review does not add a solve',
    (tester) async {
      await tester.pumpWidget(const TrioSprintApp());
      await tester.pumpAndSettle();
      await tester.tap(find.text('1 min'));
      await tester.tap(find.text('Start run'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      final board = tester
          .widgetList<CardView>(find.byType(CardView))
          .map((v) => v.card.id)
          .toList();
      await tester.pump(const Duration(minutes: 1));
      await tester.pump();
      final player = await PlayerData.load();
      expect(player.attemptsHistory.single.outcome, AttemptOutcome.timedOut);
      expect(player.benchmarkMedian, isNull);
      await tester.pump(const Duration(seconds: 1));
      await tester.ensureVisible(find.text('Review last unsolved board'));
      await tester.tap(find.text('Review last unsolved board'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<CardView>(find.byType(CardView))
            .map((v) => v.card.id),
        board,
      );
      await tester.tap(find.text('Show solution'));
      await tester.pump();
      expect(player.attemptsHistory.length, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
