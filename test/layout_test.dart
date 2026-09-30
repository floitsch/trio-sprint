import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trio_sprint/card_board.dart';
import 'package:trio_sprint/card_view.dart';
import 'package:trio_sprint/main.dart';

void expectWholeBoard(
  WidgetTester tester,
  Size screen, {
  double top = 0,
  double bottom = 0,
}) {
  final cards = find.byType(CardView);
  expect(cards, findsNWidgets(12));
  final board = tester.getRect(find.byType(CardBoard));
  var area = 0.0;
  for (final element in cards.evaluate()) {
    final card = find.byWidget(element.widget);
    final rect = tester.getRect(card);
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(screen.width + .01));
    expect(rect.top, greaterThanOrEqualTo(top));
    expect(rect.bottom, lessThanOrEqualTo(screen.height - bottom + .01));
    expect(rect.bottom, lessThanOrEqualTo(board.bottom + .01));
    expect(rect.width / rect.height, closeTo(2 / 3, .001));
    expect(card.hitTestable(), findsOneWidget);
    area += rect.width * rect.height;
  }
  // Cards should occupy most of their allocated board, not a small central strip.
  expect(area / (board.width * board.height), greaterThan(.6));
  for (final scroll in tester.stateList<ScrollableState>(
    find.byType(Scrollable),
  )) {
    expect(scroll.position.maxScrollExtent, closeTo(0, .01));
  }
  expect(tester.takeException(), isNull);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final size in [
    const Size(320, 480),
    const Size(320, 568),
    const Size(390, 600),
    const Size(393, 660),
    const Size(390, 844),
    const Size(740, 360),
    const Size(844, 300),
    const Size(1280, 900),
  ]) {
    testWidgets('all 12 cards fit and can be tapped at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 34);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);
      await tester.pumpWidget(const TrioSprintApp());
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Start run'));
      await tester.tap(find.text('Start run'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));
      expectWholeBoard(tester, size, top: 24, bottom: 34);
      final card = find.byType(CardView).last;
      await tester.tap(card);
      await tester.pump();
      expect(tester.widget<CardView>(card).selected, isTrue);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
    'browser toolbar resizing keeps the whole board and selection visible',
    (tester) async {
      tester.view.physicalSize = const Size(390, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const TrioSprintApp());
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Start run'));
      await tester.tap(find.text('Start run'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));
      final original = tester
          .widgetList<CardView>(find.byType(CardView))
          .map((v) => v.card.id)
          .toList();
      final selected = find.byKey(ValueKey('card-${original.last}'));
      await tester.tap(selected);
      await tester.pump();
      for (final height in [560.0, 660.0, 740.0]) {
        tester.view.physicalSize = Size(390, height);
        await tester.pump();
        expectWholeBoard(tester, Size(390, height));
        expect(
          tester
              .widgetList<CardView>(find.byType(CardView))
              .map((v) => v.card.id),
          original,
        );
        expect(tester.widget<CardView>(selected).selected, isTrue);
      }
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('larger phone text still leaves every card visible', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 600);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(const TrioSprintApp());
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Start run'));
    await tester.tap(find.text('Start run'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    expectWholeBoard(tester, const Size(390, 600));
    await tester.pumpWidget(const SizedBox());
  });
}
