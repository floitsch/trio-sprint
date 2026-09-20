import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:set_sprint/card_view.dart';
import 'package:set_sprint/game.dart';
import 'package:set_sprint/main.dart';

void main() {
  testWidgets('three moving fingers can select a set simultaneously', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const SetApp());
    await tester.tap(find.text('Start run'));
    await tester.pump(const Duration(seconds: 2));
    final cards = tester
        .widgetList<CardView>(find.byType(CardView))
        .map((view) => view.card)
        .toList();
    final solution = findSet(cards)!;
    final gestures = <TestGesture>[];
    for (var i = 0; i < solution.length; i++) {
      final card = find.byKey(ValueKey('card-${solution[i].id}'));
      gestures.add(
        await tester.startGesture(
          tester.getCenter(card),
          pointer: i + 1,
          kind: PointerDeviceKind.touch,
        ),
      );
    }
    for (final gesture in gestures) {
      await gesture.moveBy(const Offset(28, 8));
    }
    for (final gesture in gestures) {
      await gesture.up();
    }
    await tester.pump();
    expect(find.text('1 / 5'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('card clicks survive clock ticks and small trackpad scrolls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const SetApp());
    await tester.tap(find.text('Start run'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    final scrollable = tester.state<ScrollableState>(
      find.descendant(
        of: find.byType(GridView),
        matching: find.byType(Scrollable),
      ),
    );
    expect(scrollable.position.maxScrollExtent, closeTo(0, 0.01));
    final first = find.byType(CardView).first;
    final second = find.byType(CardView).at(1);
    final originalRect = tester.getRect(first);
    final originalWidget = tester.widget<CardView>(first);
    await tester.pump(const Duration(milliseconds: 100));
    expect(identical(tester.widget<CardView>(first), originalWidget), isTrue);
    for (var i = 0; i < 8; i++) {
      for (final card in [first, second]) {
        final point = tester.getTopLeft(card) + const Offset(10, 10);
        await tester.sendEventToBinding(
          PointerScrollEvent(position: point, scrollDelta: const Offset(0, 2)),
        );
        final mouse = await tester.startGesture(
          point,
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump(const Duration(milliseconds: 50));
        await mouse.moveBy(const Offset(3, 2));
        await mouse.up();
        await tester.pump();
        expect(tester.widget<CardView>(card).selected, i.isEven);
        expect(tester.getRect(first), originalRect);
      }
      expect(
        find.text(
          i.isEven ? '2 of 3 selected' : 'Pick three cards that make a set.',
        ),
        findsOneWidget,
      );
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('two-second countdown, five sets, frozen result, quick replay', (
    tester,
  ) async {
    await tester.pumpWidget(const SetApp());
    await tester.tap(find.text('Start run'));
    await tester.pump();
    expect(find.text('2'), findsOneWidget);
    expect(find.byType(CardView), findsNothing);
    expect(find.byKey(const ValueKey('timer')), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('1'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 999));
    expect(find.byKey(const ValueKey('timer')), findsNothing);
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.byKey(const ValueKey('timer')), findsOneWidget);
    for (var i = 0; i < 5; i++) {
      final cards = tester
          .widgetList<CardView>(find.byType(CardView))
          .map((view) => view.card)
          .toList();
      final solution = findSet(cards)!;
      for (final card in solution) {
        await tester.ensureVisible(find.byKey(ValueKey('card-${card.id}')));
        await tester.tap(find.byKey(ValueKey('card-${card.id}')));
        await tester.pump();
      }
    }
    expect(find.text('Five in a row.'), findsOneWidget);
    final result = tester
        .widget<Text>(find.byKey(const ValueKey('result-time')))
        .data;
    await tester.pump(const Duration(seconds: 3));
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('result-time'))).data,
      result,
    );
    await tester.tap(find.text('Play again'));
    await tester.pump();
    expect(find.text('2'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('0 / 5'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('restarting during countdown cancels the previous start', (
    tester,
  ) async {
    await tester.pumpWidget(const SetApp());
    await tester.tap(find.text('Start run'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byTooltip('Restart run'));
    await tester.pump();
    expect(find.text('2'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('1'), findsOneWidget);
    expect(find.byKey(const ValueKey('timer')), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const ValueKey('timer')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'cards stay portrait on phones, landscape and desktop without overflow',
    (tester) async {
      for (final size in [
        const Size(320, 568),
        const Size(740, 360),
        const Size(1280, 900),
      ]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(const SetApp());
        expect(tester.takeException(), isNull);
        expectPortraitCards(tester);
        await tester.ensureVisible(find.text('Start run'));
        await tester.tap(find.text('Start run'));
        await tester.pump();
        expect(tester.takeException(), isNull);
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));
        expect(tester.takeException(), isNull);
        expectPortraitCards(tester);
        await tester.pumpWidget(const SizedBox());
      }
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );
}

void expectPortraitCards(WidgetTester tester) {
  for (final element in find.byType(CardView).evaluate()) {
    final material = find
        .descendant(
          of: find.byWidget(element.widget),
          matching: find.byType(Material),
        )
        .first;
    final size = tester.getSize(material);
    expect(size.width / size.height, closeTo(2 / 3, 0.001));
  }
}
