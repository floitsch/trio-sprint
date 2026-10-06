import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trio_sprint/card_view.dart';
import 'package:trio_sprint/data.dart';
import 'package:trio_sprint/game.dart';
import 'package:trio_sprint/main.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('timed seeds are recognized and carry their mode', () {
    expect(normalizeSeed('1M-1234ABCD'), '1m-1234abcd');
    expect(
      normalizeSeed('https://example.com/?seed=3m-1234abcd'),
      '3m-1234abcd',
    );
    expect(normalizeSeed('2m-1234abcd'), isNull);
    expect(RunMode.of('1m-1234abcd'), RunMode.oneMinute);
    expect(RunMode.of('3m-1234abcd'), RunMode.threeMinutes);
    expect(RunMode.of('s1-1234abcd'), RunMode.sprint);
    expect(RunMode.of(newSeed(RunMode.threeMinutes)), RunMode.threeMinutes);
  });

  test('timed runs match server fixtures and keep dealing after five', () {
    final fixtures = jsonDecode(
      File('test/timed_run_fixtures.json').readAsStringSync(),
    ) as List;
    for (final fixture in fixtures) {
      final game = SetGame(seed: fixture['seed'] as String);
      final boards = fixture['boards'] as List;
      for (var round = 0; round < boards.length; round++) {
        expect(game.board.map((c) => c.id), boards[round]);
        final solution = (fixture['solutions'][round] as List).cast<int>();
        PickResult? result;
        for (final id in solution.reversed) {
          result = game.pick(id);
        }
        expect(result, PickResult.correct);
        expect(game.finished, isFalse);
      }
      expect(game.streak, boards.length);
    }
  });

  test('the same digits deal different boards in each mode', () {
    final boards = {
      for (final prefix in ['s2', '1m', '3m'])
        SetGame(seed: '$prefix-1234abcd').board.map((c) => c.id).join(','),
    };
    expect(boards, hasLength(3));
  });

  test(
    'timed personal bests prefer more sets, then an earlier last set',
    () async {
      SharedPreferences.setMockInitialValues({'best-s2': 9000});
      final player = await PlayerData.load();
      expect(player.timedBest(RunMode.oneMinute), isNull);
      await player.saveTimedBest(RunMode.oneMinute, const TimedScore(8, 55000));
      await player.saveTimedBest(RunMode.oneMinute, const TimedScore(7, 30000));
      expect(player.timedBest(RunMode.oneMinute)!.sets, 8);
      await player.saveTimedBest(RunMode.oneMinute, const TimedScore(8, 50000));
      expect(player.timedBest(RunMode.oneMinute)!.milliseconds, 50000);
      expect(player.timedBest(RunMode.threeMinutes), isNull);
      // The sprint best is untouched.
      expect(player.best, 9000);
    },
  );

  Future<void> findSets(WidgetTester tester, int count) async {
    for (var round = 0; round < count; round++) {
      final cards = tester
          .widgetList<CardView>(find.byType(CardView))
          .map((view) => view.card)
          .toList();
      for (final card in findSet(cards)!) {
        await tester.tap(find.byKey(ValueKey('card-${card.id}')));
        await tester.pump();
      }
    }
  }

  testWidgets('a one-minute run counts sets until the time is up', (
    tester,
  ) async {
    await tester.pumpWidget(const TrioSprintApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('1 min'));
    await tester.pump();
    expect(find.text('One minute.\nEvery set counts.'), findsOneWidget);
    await tester.tap(find.text('Start run'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    final seed = tester
        .widgetList<Text>(find.byType(Text))
        .map((text) => text.data ?? '')
        .singleWhere((text) => text.startsWith('First attempt · '))
        .split(' · ')
        .last;
    expect(RunMode.of(seed), RunMode.oneMinute);
    await findSets(tester, 6);
    expect(find.text('6'), findsOneWidget);
    expect(find.text('Time’s up.'), findsNothing);
    await tester.pump(const Duration(seconds: 61));
    expect(find.text('Time’s up.'), findsOneWidget);
    expect(find.byKey(const ValueKey('result-time')), findsOneWidget);
    expect(find.text('SETS IN ONE MINUTE'), findsOneWidget);
    expect(find.text('Your best run.'), findsOneWidget);
    expect(find.text('Submit high score'), findsOneWidget);
    final player = await PlayerData.load();
    expect(player.timedBest(RunMode.oneMinute)!.sets, 6);
    expect(player.mode, RunMode.oneMinute);
    // Play again stays in the same mode.
    await tester.ensureVisible(find.text('Play again'));
    await tester.tap(find.text('Play again'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('6'), findsNothing);
    expect(find.text('0'), findsOneWidget);
    await tester.tap(find.text('Abandon'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a timed run without a set cannot be submitted', (tester) async {
    await tester.pumpWidget(const TrioSprintApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('3 min'));
    await tester.tap(find.text('Start run'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(minutes: 3));
    expect(find.text('Time’s up.'), findsOneWidget);
    expect(find.text('SETS IN THREE MINUTES'), findsOneWidget);
    expect(
      find.text('Find at least one set to enter the high scores.'),
      findsOneWidget,
    );
    expect(find.text('Submit high score'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
