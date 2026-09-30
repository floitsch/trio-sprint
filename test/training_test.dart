import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trio_sprint/card_view.dart';
import 'package:trio_sprint/data.dart';
import 'package:trio_sprint/game.dart';
import 'package:trio_sprint/main.dart';
import 'package:trio_sprint/practice.dart';
import 'package:trio_sprint/training.dart';

List<int> visibleCards(WidgetTester tester) => tester
    .widgetList<CardView>(find.byType(CardView))
    .where((view) => view.onTap != null)
    .map((view) => view.card.id)
    .toList();

Future<void> solve(WidgetTester tester, PracticeBoard board) async {
  for (final card in board.solution!) {
    if (board.anchors.contains(card.id)) continue;
    await tester.tap(find.byKey(ValueKey('training-card-${card.id}')));
    await tester.pump();
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'history persists, prioritizes difficulty and updates repeat boards',
    () async {
      final player = await PlayerData.load();
      final boards = seededBoards('s1-1234abcd');
      PracticeBoard record(
        int i,
        int ms, {
        int mistakes = 0,
        bool assisted = false,
      }) => PracticeBoard(
        cards: boards[i].map((c) => c.id).toList(),
        milliseconds: ms,
        mistakes: mistakes,
        assisted: assisted,
      );
      await player.recordPractice(record(0, 15000));
      await player.recordPractice(record(1, 4000, mistakes: 3));
      await player.recordPractice(record(2, 8000, assisted: true));
      final reloaded = await PlayerData.load();
      expect(reloaded.slowBoards.map((b) => b.cards), [
        boards[2].map((c) => c.id).toList(),
        boards[1].map((c) => c.id).toList(),
        boards[0].map((c) => c.id).toList(),
      ]);
      await reloaded.recordPractice(record(2, 1000));
      expect(reloaded.practiceHistory.length, 3);
      expect(reloaded.slowBoards.last.milliseconds, 1000);
      final raw = reloaded.preferences.getStringList('practice-history-v1')!;
      await reloaded.preferences.setStringList('practice-history-v1', [
        ...raw,
        'bad json',
        jsonEncode({
          'cards': [99],
        }),
      ]);
      expect(reloaded.slowBoards.length, 3);
    },
  );

  test('history is bounded and preserves pair training constraints', () async {
    final player = await PlayerData.load();
    for (var i = 0; i < 110; i++) {
      final board = seededBoards('s1-${i.toRadixString(16).padLeft(8, '0')}')
          .first;
      await player.recordPractice(
        PracticeBoard(cards: board.map((c) => c.id).toList(), milliseconds: i),
      );
    }
    expect(player.practiceHistory.length, 100);
    expect(player.slowBoards.length, 20);
    final exercise = TrainingExercise(differences: 2, completePair: true);
    final pair = PracticeBoard(
      cards: exercise.board.map((c) => c.id).toList(),
      anchors: exercise.solution.take(2).map((c) => c.id).toList(),
      differences: 2,
    );
    await player.recordPractice(pair);
    final saved = (await PlayerData.load()).practiceHistory.first;
    expect(saved.anchors, pair.anchors);
    expect(saved.differences, 2);
    expect(saved.accepts(saved.solution!), isTrue);
    expect(saved.solution!.last.id, exercise.solution.last.id);
  });

  testWidgets(
    'training advances indefinitely, remembers boards and cancels on quit',
    (tester) async {
      final player = await PlayerData.load();
      await tester.pumpWidget(
        MaterialApp(home: TrainingScreen(player: player)),
      );
      await tester.tap(find.text('Start training'));
      await tester.pump();
      for (var round = 0; round < 7; round++) {
        final cards = visibleCards(tester);
        await solve(tester, PracticeBoard(cards: cards, differences: 4));
        expect(find.text('${round + 1} completed'), findsOneWidget);
        expect(find.text('Yes! Next board…'), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 500));
        expect(visibleCards(tester), cards);
        await tester.pump(const Duration(milliseconds: 150));
        expect(visibleCards(tester), isNot(cards));
      }
      expect(player.practiceHistory.length, 7);
      await tester.tap(find.text('Hint'));
      await tester.pump();
      await tester.tap(find.text('Skip'));
      await tester.pump();
      expect(player.practiceHistory.first.assisted, isTrue);
      final cards = visibleCards(tester);
      await solve(tester, PracticeBoard(cards: cards, differences: 4));
      await tester.tap(find.text('Quit'));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Start training'), findsOneWidget);
      expect(find.byType(CardView), findsNothing);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('review preserves saved pair and full-board rules and loops', (
    tester,
  ) async {
    final player = await PlayerData.load();
    final pair = TrainingExercise(differences: 1, completePair: true);
    await player.recordPractice(
      PracticeBoard(
        cards: pair.board.map((c) => c.id).toList(),
        anchors: pair.solution.take(2).map((c) => c.id).toList(),
        differences: 1,
        milliseconds: 50000,
      ),
    );
    final cards = seededBoards('s1-1234abcd').first.map((c) => c.id).toList();
    await player.recordPractice(
      PracticeBoard(cards: cards, milliseconds: 30000),
    );
    final review = player.slowBoards;
    await tester.pumpWidget(MaterialApp(home: TrainingScreen(player: player)));
    await tester.scrollUntilVisible(find.text('Practice these cards'), 180);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Practice these cards'));
    await tester.pump();
    expect(find.byType(CardView), findsNWidgets(8));
    await solve(tester, review[0]);
    await tester.pump(const Duration(milliseconds: 650));
    expect(visibleCards(tester), cards);
    expect(find.text('Find any set on this board.'), findsOneWidget);
    await solve(tester, review[1]);
    await tester.pump(const Duration(milliseconds: 650));
    expect(visibleCards(tester), review[0].cards);
    expect(player.practiceHistory.length, 2);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('sprints remember the solved board rather than the next one', (
    tester,
  ) async {
    await tester.pumpWidget(const TrioSprintApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start run'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    final cards = visibleCards(tester);
    for (final card in findSet(cards.map(SetCard.new).toList())!) {
      await tester.tap(find.byKey(ValueKey('card-${card.id}')));
      await tester.pump();
    }
    final saved = (await PlayerData.load()).practiceHistory;
    expect(saved.length, 1);
    expect(saved.single.cards, cards);
    expect(visibleCards(tester), isNot(cards));
    await tester.pumpWidget(const SizedBox());
  });

  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(740, 360),
    const Size(1280, 900),
  ]) {
    for (final pair in [false, true]) {
      testWidgets('all training cards fit at $size, pair=$pair', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(const MaterialApp(home: TrainingScreen()));
        if (pair) {
          await tester.scrollUntilVisible(find.byType(Switch), 120);
          await tester.pumpAndSettle();
          await tester.tap(find.byType(Switch));
          await tester.pump();
        }
        await tester.scrollUntilVisible(find.text('Start training'), 120);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Start training'));
        await tester.pumpAndSettle();
        expect(find.byType(CardView), findsNWidgets(pair ? 8 : 12));
        final controlsTop = tester.getTopLeft(find.text('0 completed')).dy;
        for (final element in find.byType(CardView).evaluate()) {
          final rect = tester.getRect(find.byWidget(element.widget));
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(size.width));
          expect(rect.top, greaterThanOrEqualTo(56));
          expect(rect.bottom, lessThanOrEqualTo(controlsTop));
          expect(rect.width / rect.height, closeTo(2 / 3, .01));
        }
        for (final scroll in tester.stateList<ScrollableState>(
          find.byType(Scrollable),
        )) {
          expect(scroll.position.maxScrollExtent, closeTo(0, .01));
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
