// Copyright (C) 2026 Florian Loitsch.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:trio_sprint/card_view.dart';
import 'package:trio_sprint/data.dart';
import 'package:trio_sprint/race.dart';
import 'package:trio_sprint/race_board.dart';

class TestChannel implements WebSocketChannel {
  final incoming = StreamController<dynamic>(sync: true);
  final sent = <Map<String, dynamic>>[];
  @override
  Stream<dynamic> get stream => incoming.stream;
  @override
  Future<void> get ready async {}
  @override
  late final WebSocketSink sink = TestSink(sent);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestSink implements WebSocketSink {
  TestSink(this.sent);
  final List<Map<String, dynamic>> sent;
  @override
  void add(dynamic event) =>
      sent.add(jsonDecode(event as String) as Map<String, dynamic>);
  @override
  Future<void> close([int? code, String? reason]) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestApi extends OnlineApi {
  @override
  Uri uri(String path, [Map<String, String>? query]) =>
      Uri.https('example.test', path, query);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final players = [
    {'name': 'Alice', 'progress': 0, 'connected': true, 'ready': true},
    {'name': 'Bob', 'progress': 0, 'connected': true, 'ready': true},
  ];
  for (final size in [
    const Size(320, 480),
    const Size(390, 844),
    const Size(740, 360),
  ]) {
    testWidgets('race cards fill the viewport and remain tappable at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var picked = -1;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(title: const Text('1 vs 1')),
            body: RaceBoard(
              board: List.generate(12, (i) => i),
              players: players,
              you: 0,
              selected: const {},
              onPick: (id) => picked = id,
              countdown: 0,
              feedback: '',
            ),
          ),
        ),
      );
      final cards = find.byType(CardView);
      expect(cards, findsNWidgets(12));
      var area = 0.0;
      for (final element in cards.evaluate()) {
        final card = find.byWidget(element.widget);
        final rect = tester.getRect(card);
        expect(rect.top, greaterThanOrEqualTo(56));
        expect(rect.bottom, lessThanOrEqualTo(size.height));
        expect(card.hitTestable(), findsOneWidget);
        area += rect.width * rect.height;
      }
      expect(
        area / (size.width * (size.height - 56)),
        greaterThan(size.width > size.height ? .4 : .55),
      );
      await tester.tap(cards.last);
      expect(picked, 11);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'Play again requests a rematch in the same room and clears the old result',
    (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final player = await PlayerData.load();
      final channel = TestChannel();
      await tester.pumpWidget(
        MaterialApp(
          home: RaceScreen(
            player: player,
            room: 'ABC123',
            api: TestApi(),
            connectChannel: (_) => channel,
          ),
        ),
      );
      await tester.pump();
      final result = <String, dynamic>{
        'type': 'state',
        'mode': 'shared',
        'now': DateTime.now().millisecondsSinceEpoch,
        'startAt': 1,
        'ended': true,
        'winner': 0,
        'you': 0,
        'seed': 's2-1234abcd',
        'round': 5,
        'board': [],
        'players': players,
      };
      channel.incoming.add(jsonEncode(result));
      await tester.pumpAndSettle();
      expect(find.text('Play again').hitTestable(), findsOneWidget);
      await tester.tap(find.text('Play again'));
      expect(channel.sent.last, {'type': 'rematch', 'seed': 's2-1234abcd'});
      channel.incoming.add(
        jsonEncode({
          ...result,
          'players': [
            {...players[0], 'rematchReady': true},
            players[1],
          ],
        }),
      );
      await tester.pump();
      expect(find.text('Waiting for friend…'), findsOneWidget);
      channel.incoming.add(
        jsonEncode({
          ...result,
          'ended': false,
          'winner': null,
          'seed': null,
          'round': 0,
          'board': List.generate(12, (i) => i),
        }),
      );
      await tester.pump();
      expect(find.byType(CardView), findsNWidgets(12));
      expect(find.text('You win!'), findsNothing);
      expect(find.text('Create room'), findsNothing);
      for (final id in [0, 1, 2]) {
        await tester.tap(find.byKey(ValueKey('card-$id')));
        await tester.pump();
      }
      final submissions = channel.sent.length;
      channel.incoming.add(
        jsonEncode({
          ...result,
          'ended': false,
          'winner': null,
          'seed': null,
          'round': 0,
          'board': List.generate(12, (i) => i),
          'validationAt': DateTime.now().millisecondsSinceEpoch + 1200,
        }),
      );
      await tester.pump();
      expect(find.text('Checking answer…'), findsOneWidget);
      expect(
        tester
            .widgetList<CardView>(find.byType(CardView))
            .where((c) => c.selected),
        hasLength(3),
      );
      await tester.tap(find.byKey(const ValueKey('card-3')));
      await tester.pump();
      expect(channel.sent.length, submissions);
      await tester.pumpWidget(const SizedBox());
      unawaited(channel.incoming.close());
      await tester.pump();
    },
  );
}
