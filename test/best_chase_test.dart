// Copyright (C) 2026 Florian Loitsch.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trio_sprint/card_view.dart';
import 'package:trio_sprint/data.dart';
import 'package:trio_sprint/game.dart';
import 'package:trio_sprint/main.dart';
import 'package:trio_sprint/practice.dart';

import 'support/controlled_stopwatch.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'best-s2': 10000}));

  Future<ControlledStopwatch> begin(
    WidgetTester tester, {
    bool chase = true,
  }) async {
    final watch = ControlledStopwatch();
    await tester.pumpWidget(MaterialApp(home: GameScreen(stopwatch: watch)));
    await tester.pumpAndSettle();
    if (chase) {
      await tester.ensureVisible(find.text('Beat my best'));
      await tester.tap(find.text('Beat my best'));
      await tester.pump();
      expect(find.text('Beat 10.00 · auto-reset at 12.00'), findsOneWidget);
    }
    await tester.ensureVisible(find.text('Start run'));
    await tester.tap(find.text('Start run'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(CardView), findsNWidgets(12));
    return watch;
  }

  String seed(WidgetTester tester) => tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data ?? '')
      .singleWhere((t) => t.startsWith('First attempt · '))
      .split(' · ')
      .last;

  Future<void> finish(WidgetTester tester) async {
    for (var round = 0; round < 5; round++) {
      final cards = tester
          .widgetList<CardView>(find.byType(CardView))
          .map((c) => c.card)
          .toList();
      for (final card in findSet(cards)!) {
        await tester.tap(find.byKey(ValueKey('card-${card.id}')));
        await tester.pump();
      }
    }
    await tester.pump();
  }

  testWidgets(
    'resets at exactly 1.2 times the best and records the slow board',
    (tester) async {
      final watch = await begin(tester);
      final original = seed(tester);
      watch.value = const Duration(milliseconds: 11999);
      await tester.pump(const Duration(milliseconds: 11999));
      expect(seed(tester), original);
      watch.value = const Duration(seconds: 12);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      expect(find.byKey(const ValueKey('countdown')), findsOneWidget);
      expect(find.byType(CardView), findsNothing);
      final player = await PlayerData.load();
      expect(player.best, 10000);
      expect(player.savedScores, isEmpty);
      expect(player.runHistory.single.completed, isFalse);
      expect(player.runHistory.single.milliseconds, 12000);
      expect(player.attemptsHistory.single.outcome, AttemptOutcome.restarted);
      await tester.pump(const Duration(seconds: 2));
      expect(seed(tester), isNot(original));
      expect(watch.elapsed, Duration.zero);
      expect(find.text('Stop'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final milliseconds in [10000, 11000, 11999]) {
    testWidgets(
      'a completed ${milliseconds}ms attempt retries until the best is beaten',
      (tester) async {
        final watch = await begin(tester);
        final original = seed(tester);
        watch.value = Duration(milliseconds: milliseconds);
        await finish(tester);
        expect(find.byKey(const ValueKey('countdown')), findsOneWidget);
        final player = await PlayerData.load();
        expect(player.best, 10000);
        expect(player.runHistory.single.completed, isTrue);
        expect(player.runHistory.single.milliseconds, milliseconds);
        expect(player.savedScore(original)!['milliseconds'], milliseconds);
        expect(player.savedScore(original)!['solutions'], hasLength(5));
        await tester.pump(const Duration(seconds: 2));
        expect(seed(tester), isNot(original));
        expect(find.text('Beat 10.00 · auto-reset at 12.00'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('a strictly faster run stops the loop and saves the new best', (
    tester,
  ) async {
    final watch = await begin(tester);
    final original = seed(tester);
    watch.value = const Duration(milliseconds: 9999);
    await finish(tester);
    expect(find.text('Your best run.'), findsOneWidget);
    expect(find.byKey(const ValueKey('countdown')), findsNothing);
    final player = await PlayerData.load();
    expect(player.best, 9999);
    expect(player.savedScore(original)!['milliseconds'], 9999);
    await tester.pump(const Duration(minutes: 1));
    expect(find.text('Your best run.'), findsOneWidget);
    expect(find.text('Seed: $original'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Stop cancels the next attempt without further automatic restarts',
    (tester) async {
      final watch = await begin(tester);
      watch.value = const Duration(seconds: 11);
      await finish(tester);
      await tester.pump();
      expect(find.byKey(const ValueKey('countdown')), findsOneWidget);
      await tester.tap(find.text('Stop'));
      await tester.pumpAndSettle();
      expect(find.text('Start run'), findsOneWidget);
      await tester.pump(const Duration(minutes: 1));
      expect(find.byType(CardView), findsNWidgets(3));
      expect(find.text('Start run'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('background time does not create repeated unseen attempts', (
    tester,
  ) async {
    final watch = await begin(tester);
    final original = seed(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    watch.value = const Duration(minutes: 1);
    await tester.pump(const Duration(minutes: 1));
    expect(seed(tester), original);
    expect((await PlayerData.load()).runHistory, isEmpty);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 33));
    await tester.pump();
    expect(find.byKey(const ValueKey('countdown')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('ordinary five-set runs keep showing results without chasing', (
    tester,
  ) async {
    final watch = await begin(tester, chase: false);
    watch.value = const Duration(seconds: 11);
    await finish(tester);
    expect(find.byKey(const ValueKey('result-time')), findsOneWidget);
    expect(find.byKey(const ValueKey('countdown')), findsNothing);
    expect(find.text('Personal best  10.00'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an explicit seed does not inherit automatic retries', (
    tester,
  ) async {
    await tester.pumpWidget(const TrioSprintApp());
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Beat my best'));
    await tester.tap(find.text('Beat my best'));
    await tester.pump();
    await tester.ensureVisible(find.text('Run a seed'));
    await tester.tap(find.text('Run a seed'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 's2-1234abcd');
    await tester.tap(find.text('Run seed'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('First time'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Stop'), findsNothing);
    expect(find.text('Abandon'), findsOneWidget);
    await tester.pump(const Duration(seconds: 13));
    expect(seed(tester), 's2-1234abcd');
    expect(find.byType(CardView), findsNWidgets(12));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the target and every card fit on a compact phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 34);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    await begin(tester);
    expect(find.text('Beat 10.00 · auto-reset at 12.00'), findsOneWidget);
    expect(find.text('Stop').hitTestable(), findsOneWidget);
    for (final element in find.byType(CardView).evaluate()) {
      final card = find.byWidget(element.widget);
      final rect = tester.getRect(card);
      expect(rect.top, greaterThanOrEqualTo(24));
      expect(rect.bottom, lessThanOrEqualTo(446));
      expect(card.hitTestable(), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the option appears only when a five-set personal best exists', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const TrioSprintApp());
    await tester.pumpAndSettle();
    expect(find.text('Beat my best'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    SharedPreferences.setMockInitialValues({'best-s2': 10000});
    await tester.pumpWidget(const TrioSprintApp());
    await tester.pumpAndSettle();
    expect(find.text('Beat my best'), findsOneWidget);
    await tester.tap(find.text('1 min'));
    await tester.pumpAndSettle();
    expect(find.text('Beat my best'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
