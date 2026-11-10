// Copyright (C) 2026 Florian Loitsch.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trio_sprint/run_timeline.dart';

void main() {
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
