// Copyright (C) 2026 Florian Loitsch.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trio_sprint/data.dart';
import 'package:trio_sprint/game.dart';
import 'package:trio_sprint/leaderboard.dart';

class LeaderboardApi extends OnlineApi {
  final queries = <Map<String, String>>[];
  var totalRequests = 0;
  var failTotals = false;
  List<Map<String, dynamic>> totals = [
    {'name': 'Alice', 'sets': 120},
    {'name': 'Bob', 'sets': 1},
  ];
  @override
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    if (path == '/scores/total-sets') {
      totalRequests++;
      if (failTotals) throw Exception('Offline');
      return {'scores': totals};
    }
    if (path == '/scores') {
      queries.add(query!);
      return {
        'scores': [
          {
            'name': 'Sprinter',
            'seed': '1m-1234abcd',
            'milliseconds': 45000,
            'mistakes': 0,
            'sets': 6,
          },
        ],
      };
    }
    throw StateError('Unexpected path $path');
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'total sets ranks players without run controls and refreshes independently',
    (tester) async {
      final api = LeaderboardApi();
      final player = await PlayerData.load();
      await tester.pumpWidget(
        MaterialApp(
          home: LeaderboardScreen(
            player: player,
            mode: RunMode.oneMinute,
            seed: '1m-1234abcd',
            api: api,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Sprinter'), findsOneWidget);
      expect(find.text('Only each player’s best'), findsOneWidget);
      await tester.tap(find.text('Total sets'));
      await tester.pumpAndSettle();
      expect(api.totalRequests, 1);
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('120 sets'), findsOneWidget);
      expect(find.text('1 set'), findsOneWidget);
      expect(find.text('Choose seed'), findsNothing);
      expect(find.text('Only each player’s best'), findsNothing);
      final firstRow = tester.widget<ListTile>(
        find.ancestor(of: find.text('Alice'), matching: find.byType(ListTile)),
      );
      expect(firstRow.onTap, isNull);
      await tester.tap(find.byTooltip('Refresh scores'));
      await tester.pumpAndSettle();
      expect(api.totalRequests, 2);
      await tester.tap(find.text('1 min'));
      await tester.pumpAndSettle();
      expect(find.text('Only each player’s best'), findsOneWidget);
      expect(api.queries.last['seed'], '1m-1234abcd');
      expect(api.queries.last['mode'], '1m');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('total sets shows empty and offline states', (tester) async {
    final api = LeaderboardApi()..totals = [];
    await tester.pumpWidget(
      MaterialApp(home: LeaderboardScreen(player: null, api: api)),
    );
    await tester.tap(find.text('Total sets'));
    await tester.pumpAndSettle();
    expect(
      find.text('No solved sets yet. Solve a set and sync to join!'),
      findsOneWidget,
    );
    api.failTotals = true;
    await tester.tap(find.byTooltip('Refresh scores'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not load scores.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('total sets and run tabs fit a narrow phone', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = LeaderboardApi();
    final player = await PlayerData.load();
    await tester.pumpWidget(
      MaterialApp(
        home: LeaderboardScreen(player: player, api: api),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Total sets'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Alice').hitTestable(), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
