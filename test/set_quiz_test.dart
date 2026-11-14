// Copyright (C) 2026 Florian Loitsch.
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trio_sprint/card_view.dart';
import 'package:trio_sprint/game.dart';
import 'package:trio_sprint/main.dart';
import 'package:trio_sprint/data.dart';
import 'package:trio_sprint/quiz_leaderboard.dart';
import 'package:trio_sprint/set_quiz.dart';

void main() {
  for (final difficult in [false, true]) {
    test(
      'balanced, distinct trios with correct answers, difficult=$difficult',
      () {
        final random = Random(4711);
        var valid = 0;
        final seen = <String>{};
        for (var i = 0; i < 4000; i++) {
          final exercise = SetQuizExercise(
            difficultOnly: difficult,
            random: random,
          );
          expect(exercise.cards.map((c) => c.id).toSet(), hasLength(3));
          expect(exercise.cards.every((c) => c.id >= 0 && c.id < 81), isTrue);
          expect(isSet(exercise.cards), exercise.answer);
          if (exercise.answer) valid++;
          seen.add(exercise.cards.map((c) => c.id).join(','));
          if (difficult) {
            final same = List.generate(4, (i) => i)
                .where(
                  (i) =>
                      exercise.cards
                          .map((c) => c.attributes[i])
                          .toSet()
                          .length ==
                      1,
                )
                .length;
            expect(same, lessThanOrEqualTo(1));
          }
        }
        expect(valid, inInclusiveRange(1800, 2200));
        expect(seen.length, greaterThan(1000));
      },
    );
  }

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> startRace(WidgetTester tester) async {
    await tester.scrollUntilVisible(find.text('Start race'), 120);
    await tester.tap(find.text('Start race'));
    await tester.pump();
    expect(find.byType(CardView), findsNothing);
    expect(find.text('Yes'), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('1'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(CardView), findsNWidgets(3));
  }

  List<SetCard> cards(WidgetTester tester) => tester
      .widgetList<CardView>(find.byType(CardView))
      .map((view) => view.card)
      .toList();

  testWidgets('start screen opens the recognition race', (tester) async {
    await tester.pumpWidget(const TrioSprintApp());
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Yes / No'));
    await tester.tap(find.text('Yes / No'));
    await tester.pumpAndSettle();
    expect(find.text('Difficult only'), findsOneWidget);
    expect(find.text('30 s'), findsOneWidget);
    expect(find.text('1 min'), findsNWidgets(2));
    expect(find.text('3 min'), findsNWidgets(2));
    await tester.ensureVisible(find.text('Start run'));
    await tester.tap(find.text('Start run'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('quiz-countdown')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  for (final size in [const Size(320, 480), const Size(740, 360)]) {
    testWidgets('integrated Yes / No selector and leaderboard fit at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const TrioSprintApp());
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Yes / No'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yes / No'));
      await tester.pumpAndSettle();
      expect(find.text('30 s'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(
        MaterialApp(home: QuizLeaderboardScreen(api: QuizTestApi())),
      );
      await tester.pumpAndSettle();
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
    'a completed 30-second race persists its personal best and upload payload',
    (tester) async {
      final player = await PlayerData.load();
      await tester.pumpWidget(MaterialApp(home: SetQuizScreen(player: player)));
      await startRace(tester);
      final current = cards(tester);
      await tester.tap(find.text(isSet(current) ? 'Yes' : 'No'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 30));
      await tester.pump();
      final restored = await PlayerData.load();
      expect(restored.quizBest(30, false), 1);
      expect(restored.pendingScores, 1);
      expect(restored.savedQuizScores.single['answers'], [
        [...current.map((c) => c.id), isSet(current)],
      ]);
      expect(find.text('New personal best!'), findsOneWidget);
      expect(find.text('30 s'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final size in [const Size(320, 480), const Size(740, 360)]) {
    testWidgets('race advances immediately with distinct haptics at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final haptics = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            haptics.add(call.arguments as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(const MaterialApp(home: SetQuizScreen()));
      await tester.scrollUntilVisible(find.byType(Checkbox), 120);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await startRace(tester);
      for (var round = 0; round < 4; round++) {
        final current = cards(tester);
        final same = List.generate(4, (i) => i)
            .where(
              (i) => current.map((c) => c.attributes[i]).toSet().length == 1,
            )
            .length;
        expect(same, lessThanOrEqualTo(1));
        final chooseCorrect = round.isEven;
        await tester.tap(
          find.text(isSet(current) == chooseCorrect ? 'Yes' : 'No'),
        );
        await tester.pump();
        expect(
          haptics.last,
          chooseCorrect
              ? 'HapticFeedbackType.selectionClick'
              : 'HapticFeedbackType.heavyImpact',
        );
        expect(haptics, hasLength(round + 1));
        expect(find.text('Score: ${chooseCorrect ? 1 : 0}'), findsOneWidget);
        expect(find.text('Yes').hitTestable(), findsOneWidget);
        expect(find.text('No').hitTestable(), findsOneWidget);
        expect(find.text('Next trio'), findsNothing);
        expect(find.text(explainTrio(current)), findsNothing);
        for (final element in find.byType(CardView).evaluate()) {
          final rect = tester.getRect(find.byWidget(element.widget));
          expect(rect.width, greaterThan(0));
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(size.width));
          expect(rect.top, greaterThanOrEqualTo(56));
          expect(
            rect.bottom,
            lessThanOrEqualTo(tester.getTopLeft(find.text('Yes')).dy),
          );
        }
        expect(tester.takeException(), isNull);
      }
      final lateAnswer = tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Yes'))
          .onPressed!;
      await tester.pump(const Duration(seconds: 30));
      expect(find.text('Time’s up.'), findsOneWidget);
      expect(find.text('2 correct · 2 wrong'), findsOneWidget);
      expect(find.byType(CardView), findsNothing);
      lateAnswer();
      await tester.pump();
      expect(haptics, hasLength(4));
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Race again'),
            )
            .onPressed,
        isNull,
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.ensureVisible(find.text('Race again'));
      await tester.tap(find.text('Race again'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Score: 0'), findsOneWidget);
      expect(find.byType(CardView), findsNWidgets(3));
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
    'three-minute race runs in the background and allows settings changes',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SetQuizScreen()));
      await tester.tap(find.text('3 min'));
      await tester.pump();
      await startRace(tester);
      await tester.pump(const Duration(minutes: 1));
      expect(find.text('Time’s up.'), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(minutes: 2));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.text('Time’s up.'), findsOneWidget);
      expect(find.text('0 correct · 0 wrong'), findsOneWidget);
      expect(find.text('3 min'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Change settings'));
      await tester.pumpAndSettle();
      expect(find.text('Difficult only'), findsOneWidget);
      expect(find.text('Start race'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'recognition leaderboard loads and filters duration, difficulty and player best',
    (tester) async {
      final api = QuizTestApi();
      await tester.pumpWidget(
        MaterialApp(home: QuizLeaderboardScreen(api: api)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
      expect(api.queries.last, {
        'seconds': '30',
        'difficult': 'false',
        'unique': 'true',
      });
      await tester.tap(find.text('3 min'));
      await tester.pumpAndSettle();
      expect(api.queries.last['seconds'], '180');
      await tester.tap(find.text('Difficult only'));
      await tester.pumpAndSettle();
      expect(api.queries.last['difficult'], 'true');
      await tester.tap(find.text('Only each player’s best'));
      await tester.pumpAndSettle();
      expect(api.queries.last['unique'], 'false');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('leaving during countdown cancels pending timers', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SetQuizScreen()));
    await tester.tap(find.text('Start race'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 4));
    expect(tester.takeException(), isNull);
  });
}

class QuizTestApi extends OnlineApi {
  final queries = <Map<String, String>>[];
  @override
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    if (path != '/quiz-scores') throw StateError(path);
    queries.add(query!);
    return {
      'scores': [
        {'name': 'Alice', 'score': 7, 'correct': 9, 'mistakes': 2},
      ],
    };
  }
}
