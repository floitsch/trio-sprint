// Copyright (C) 2026 Florian Loitsch.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trio_sprint/run_timeline.dart';
import 'package:trio_sprint/card_view.dart';
import 'package:trio_sprint/practice.dart';
import 'package:trio_sprint/game.dart';
import 'package:trio_sprint/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('sprint results retain every board before replacement', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const TrioSprintApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start run'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    final boards = <List<int>>[];
    final chosen = <List<int>>[];
    for (var i = 0; i < 5; i++) {
      final cards = tester
          .widgetList<CardView>(find.byType(CardView))
          .map((c) => c.card)
          .toList();
      boards.add(cards.map((c) => c.id).toList());
      final solution = findSet(cards)!;
      chosen.add(solution.map((c) => c.id).toList());
      for (final card in solution) {
        await tester.tap(find.byKey(ValueKey('card-${card.id}')));
        await tester.pump();
      }
    }
    final timeline = tester.widget<RunTimeline>(find.byType(RunTimeline));
    expect(timeline.boards.map((b) => b.cards), boards);
    expect(timeline.boards.map((b) => b.solutionCards), chosen);
    expect(timeline.setTimes, hasLength(5));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('each interval opens its original board and actual chosen set', (
    tester,
  ) async {
    final boards = [
      PracticeBoard(
        cards: List.generate(12, (i) => i),
        solutionCards: [9, 10, 11],
      ),
      PracticeBoard(
        cards: List.generate(12, (i) => i + 12),
        solutionCards: [12, 13, 14],
      ),
    ];
    final unfinished = PracticeBoard(cards: List.generate(12, (i) => i + 24));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RunTimeline(
            setTimes: const [Duration(seconds: 2), Duration(seconds: 3)],
            boards: boards,
            unfinished: const Duration(seconds: 55),
            unfinishedBoard: unfinished,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('run-timeline')));
    await tester.pumpAndSettle();
    for (var i = 0; i < 3; i++) {
      await tester.ensureVisible(
        find.text(i < 2 ? 'Set ${i + 1}' : 'Unsolved board'),
      );
      await tester.tap(find.text(i < 2 ? 'Set ${i + 1}' : 'Unsolved board'));
      await tester.pumpAndSettle();
      final cards = tester.widgetList<CardView>(find.byType(CardView));
      expect(
        cards.map((view) => view.card.id),
        i < 2 ? boards[i].cards : unfinished.cards,
      );
      expect(
        cards.where((view) => view.selected).map((view) => view.card.id),
        i < 2 ? boards[i].solutionCards : isEmpty,
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('bar proportions match intervals and clicking shows every time', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RunTimeline(
            setTimes: [Duration(seconds: 2), Duration(seconds: 6)],
            unfinished: Duration(seconds: 52),
          ),
        ),
      ),
    );
    final segments = find.descendant(
      of: find.byKey(const ValueKey('run-timeline')),
      matching: find.byType(Tooltip),
    );
    expect(segments, findsNWidgets(3));
    expect(
      tester.getSize(segments.at(1)).width /
          tester.getSize(segments.first).width,
      closeTo(3, 0.001),
    );
    await tester.tap(find.byKey(const ValueKey('run-timeline')));
    await tester.pumpAndSettle();
    for (final label in [
      'Set 1',
      'Set 2',
      'Unsolved board',
      '2.00 s',
      '6.00 s',
      '52.00 s',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('a zero-set timed run shows its full unfinished interval', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RunTimeline(setTimes: [], unfinished: Duration(minutes: 3)),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('run-timeline')));
    await tester.pumpAndSettle();
    expect(find.text('Unsolved board'), findsOneWidget);
    expect(find.text('3:00.00 s'), findsOneWidget);
    expect(find.text('Set 1'), findsNothing);
  });
}
