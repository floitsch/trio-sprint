import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'practice.dart';

import 'attempt_stub.dart'
    if (dart.library.js_interop) 'attempt_web.dart'
    as attempts;

String randomId() => List.generate(
  24,
  (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
).join();

String? normalizeDeviceCode(String value) {
  final trimmed = value.trim();
  final raw = Uri.tryParse(trimmed)?.queryParameters['link'] ?? trimmed;
  final code = raw.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
  if (RegExp(r'^[A-HJ-NP-Z2-9]{6}$').hasMatch(code)) return code;
  // Retain support for codes copied before short pairing codes were introduced.
  return RegExp(r'^[A-F0-9]{48}$').hasMatch(code) ? code.toLowerCase() : null;
}

class PlayerData {
  PlayerData(this.preferences);
  final SharedPreferences preferences;
  static Future<PlayerData> load() async {
    final data = PlayerData(await SharedPreferences.getInstance());
    if (data.preferences.getString('player') == null) {
      if (!await data.preferences.setString('player', randomId())) {
        throw StateError('Could not remember this device.');
      }
    }
    return data;
  }

  String get player => preferences.getString('player')!;
  String get nickname => preferences.getString('nickname') ?? '';
  int? get best => preferences.getInt('best-s2');
  int? bestForSeed(String seed) =>
      preferences.getInt(seed.startsWith('s1-') ? 'best' : 'best-s2');
  bool get unique => preferences.getBool('unique') ?? true;
  Future<void> setNickname(String name) async {
    await preferences.setString('nickname', name.trim());
  }

  Future<void> setUnique(bool value) async {
    await preferences.setBool('unique', value);
  }

  Future<void> saveBest(int milliseconds, {String seed = 's2-'}) async {
    final previous = bestForSeed(seed);
    if (previous == null || milliseconds < previous) {
      await preferences.setInt(
        seed.startsWith('s1-') ? 'best' : 'best-s2',
        milliseconds,
      );
    }
  }

  Future<bool> claimSeed(String seed) async {
    // Record at START, not at submission: abandoned runs count as attempts.
    return attempts.claimSeed(preferences, seed);
  }

  /// Whether this device has started [seed] before, without claiming it.
  Future<bool> hasAttempted(String seed) =>
      attempts.hasAttempted(preferences, seed);

  List<PracticeBoard> get practiceHistory {
    final boards = <PracticeBoard>[];
    for (final raw
        in preferences.getStringList('practice-history-v1') ?? <String>[]) {
      try {
        boards.add(
          PracticeBoard.fromJson(jsonDecode(raw) as Map<String, dynamic>),
        );
      } catch (_) {
        // One damaged entry must not prevent playing or reviewing other boards.
      }
    }
    return boards;
  }

  List<PracticeBoard> get slowBoards {
    final boards = practiceHistory
      ..sort((a, b) => b.difficulty.compareTo(a.difficulty));
    return boards.take(20).toList();
  }

  Future<void> recordPractice(PracticeBoard board) async {
    final boards = practiceHistory..removeWhere((old) => old.key == board.key);
    boards.insert(0, board);
    if (!await preferences.setStringList(
      'practice-history-v1',
      boards.take(100).map((entry) => jsonEncode(entry.toJson())).toList(),
    )) {
      throw StateError('Could not save practice history.');
    }
  }
}

class Score {
  Score.fromJson(Map<String, dynamic> json)
    : name = json['name'] as String,
      seed = json['seed'] as String,
      milliseconds = json['milliseconds'] as int,
      mistakes = json['mistakes'] as int;
  final String name;
  final String seed;
  final int milliseconds;
  final int mistakes;
}

class OnlineApi {
  static const baseUrl = String.fromEnvironment('API_URL');
  bool get configured => baseUrl.isNotEmpty;
  Uri uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: query);

  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    if (!configured) throw Exception('Online play is not configured yet.');
    final response =
        await (body == null
                ? http.get(uri(path, query))
                : http.post(
                    uri(path),
                    headers: {'Content-Type': 'application/json'},
                    body: jsonEncode(body),
                  ))
            .timeout(const Duration(seconds: 12));
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 400) {
      throw Exception(json['error'] ?? 'Request failed');
    }
    return json;
  }

  Future<List<Score>> scores({required bool unique, String? seed}) async {
    final response = await request(
      '/scores',
      query: {'unique': '$unique', 'seed': ?seed},
    );
    return (response['scores'] as List)
        .map((e) => Score.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> submit({
    required PlayerData player,
    required String seed,
    required int milliseconds,
    required int mistakes,
    required List<List<int>> solutions,
  }) async {
    await request(
      '/scores',
      body: {
        'player': player.player,
        'name': player.nickname,
        'seed': seed,
        'milliseconds': milliseconds,
        'mistakes': mistakes,
        'solutions': solutions,
      },
    );
  }
}

String shareLink(String key, String value) {
  final base = Uri.base;
  final web = base.scheme == 'http' || base.scheme == 'https';
  return (web ? base : Uri.parse('https://trio-sprint.floitsch.workers.dev/'))
      .replace(queryParameters: {key: value}, fragment: '')
      .toString();
}
