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
import 'package:trio_sprint/run_history.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final cards = SetGame(seed: 's2-1234abcd').board.map((c) => c.id).toList();
  PracticeBoard attempt(
    int ms, {
    AttemptOutcome outcome = AttemptOutcome.solved,
    String source = 's2',
    bool assisted = false,
    int? recordedAt,
  }) => PracticeBoard(
    cards: cards,
    milliseconds: ms,
    source: source,
    outcome: outcome,
    assisted: assisted,
    recordedAt: recordedAt,
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
    await tester.ensureVisible(find.text('Fastest ever set (unassisted)'));
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

  String tileValue(WidgetTester tester, String title) {
    final tile = tester.widget<ListTile>(
      find.ancestor(of: find.text(title), matching: find.byType(ListTile)),
    );
    return (tile.trailing! as Text).data!;
  }

  Future<void> selectPeriod(WidgetTester tester, String label) async {
    final dropdown = find.byType(DropdownButton<StatisticsPeriod>);
    if (dropdown.evaluate().isEmpty) {
      await tester.scrollUntilVisible(dropdown, -400);
    }
    await tester.ensureVisible(dropdown);
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  testWidgets('period and mode filters update totals, medians and run scores', (
    tester,
  ) async {
    final player = await PlayerData.load();
    final today = DateUtils.dateOnly(DateTime.now());
    final recent = today.millisecondsSinceEpoch;
    final old = DateTime(
      today.year,
      today.month,
      today.day - 40,
    ).millisecondsSinceEpoch;
    await player.recordPractice(attempt(1000, source: '1m', recordedAt: old));
    await player.recordPractice(
      attempt(6000, source: '1m', recordedAt: recent),
    );
    await player.recordPractice(
      attempt(3000, source: '1m', recordedAt: recent, assisted: true),
    );
    await player.recordPractice(attempt(500, source: '3m', recordedAt: recent));
    for (final run in [
      RunRecord(
        id: 'old',
        seed: '1m-1234abcd',
        source: '1m',
        completed: true,
        sets: 2,
        mistakes: 0,
        recordedAt: old,
      ),
      RunRecord(
        id: 'recent',
        seed: '1m-00000000',
        source: '1m',
        completed: true,
        sets: 5,
        mistakes: 0,
        milliseconds: 55000,
        recordedAt: recent,
      ),
      RunRecord(
        id: 'abandoned',
        seed: '1m-00000001',
        source: '1m',
        completed: false,
        sets: 50,
        mistakes: 0,
        recordedAt: recent,
      ),
      RunRecord(
        id: 'other-mode',
        seed: '3m-1234abcd',
        source: '3m',
        completed: true,
        sets: 8,
        mistakes: 0,
        recordedAt: recent,
      ),
      const RunRecord(
        id: 'undated',
        seed: '1m-00000002',
        source: '1m',
        completed: true,
        sets: 4,
        mistakes: 0,
      ),
    ]) {
      await player.recordRun(run);
    }
    await tester.pumpWidget(
      MaterialApp(home: StatisticsScreen(player: player)),
    );
    expect(tileValue(tester, 'Completed runs'), '4');
    expect(tileValue(tester, '1 minute · average score'), '3.7 sets');
    await selectPeriod(tester, 'Today');
    expect(tileValue(tester, 'Completed runs'), '2');
    expect(tileValue(tester, 'Solved sets'), '3');
    expect(tileValue(tester, '1 minute · average score'), '5.0 sets');
    await tester.tap(find.widgetWithText(ChoiceChip, '1 minute'));
    await tester.pumpAndSettle();
    expect(tileValue(tester, 'Completed runs'), '1');
    expect(tileValue(tester, 'Solved sets'), '2');
    expect(tileValue(tester, 'Solved with hints'), '1');
    expect(tileValue(tester, 'Median solving time (unassisted)'), '6.00 s');
    expect(find.text('Fastest set (unassisted)'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Recent runs'), 400);
    expect(find.text('5 sets'), findsOneWidget);
    expect(find.text('Abandoned'), findsOneWidget);
    expect(find.text('2 sets'), findsNothing);
    expect(find.text('8 sets'), findsNothing);
    expect(find.text('4 sets'), findsNothing);
    await selectPeriod(tester, 'All time');
    expect(tileValue(tester, 'Completed runs'), '3');
    expect(tileValue(tester, 'Solved sets'), '3');
    expect(tileValue(tester, 'Median solving time (unassisted)'), '3.50 s');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('custom dates include both full days and can be cancelled', (
    tester,
  ) async {
    final player = await PlayerData.load();
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day - 10);
    final end = DateTime(now.year, now.month, now.day - 8);
    for (final date in [
      start.subtract(const Duration(milliseconds: 1)),
      start,
      DateTime(end.year, end.month, end.day, 23, 59, 59, 999),
      DateTime(end.year, end.month, end.day + 1),
    ]) {
      await player.recordPractice(
        attempt(2000, recordedAt: date.millisecondsSinceEpoch),
      );
    }
    await tester.pumpWidget(
      MaterialApp(home: StatisticsScreen(player: player)),
    );
    await selectPeriod(tester, 'Custom dates');
    final localizations = MaterialLocalizations.of(
      tester.element(find.byType(DateRangePickerDialog)),
    );
    await tester.tap(find.byTooltip(localizations.inputDateModeButtonLabel));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).at(0),
      localizations.formatCompactDate(start),
    );
    await tester.enterText(
      find.byType(TextField).at(1),
      localizations.formatCompactDate(end),
    );
    await tester.tap(find.text(localizations.okButtonLabel));
    await tester.pumpAndSettle();
    expect(tileValue(tester, 'Solved sets'), '2');
    await selectPeriod(tester, 'Custom dates');
    await tester.tap(find.byTooltip(localizations.closeButtonTooltip));
    await tester.pumpAndSettle();
    expect(tileValue(tester, 'Solved sets'), '2');
    await tester.pumpWidget(const SizedBox());
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
