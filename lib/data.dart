import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'game.dart';
import 'practice.dart';
import 'run_history.dart';

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
  void Function()? onRecordsChanged;
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
    await _serialize(() async {
      if (!await preferences.setString('nickname', name.trim())) {
        throw StateError('Could not save nickname.');
      }
    });
    onRecordsChanged?.call();
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

  /// The best first attempt of a timed mode.
  TimedScore? timedBest(RunMode mode) {
    final sets = preferences.getInt('best-${mode.prefix}-sets');
    final milliseconds = preferences.getInt('best-${mode.prefix}-ms');
    if (sets == null || milliseconds == null) return null;
    return TimedScore(sets, milliseconds);
  }

  Future<void> saveTimedBest(RunMode mode, TimedScore score) async {
    if (!score.beats(timedBest(mode))) return;
    await preferences.setInt('best-${mode.prefix}-sets', score.sets);
    await preferences.setInt('best-${mode.prefix}-ms', score.milliseconds);
  }

  RunMode get mode => RunMode.values.firstWhere(
    (mode) => mode.prefix == preferences.getString('mode'),
    orElse: () => RunMode.sprint,
  );
  Future<void> setMode(RunMode mode) async {
    await preferences.setString('mode', mode.prefix);
  }

  Future<bool> claimSeed(String seed) async {
    // Seed checks reload preferences on native platforms. Finish history writes
    // first so that reload cannot replace their in-memory cache with old data.
    // Record at START, not at submission: abandoned runs count as attempts.
    return _serialize(() => attempts.claimSeed(preferences, seed));
  }

  /// Whether this device has started [seed] before, without claiming it.
  Future<bool> hasAttempted(String seed) async {
    return _serialize(() => attempts.hasAttempted(preferences, seed));
  }

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

  List<PracticeBoard> get attemptsHistory {
    final records = <PracticeBoard>[];
    for (final raw
        in preferences.getStringList('set-attempts-v1') ?? <String>[]) {
      try {
        records.add(
          PracticeBoard.fromJson(jsonDecode(raw) as Map<String, dynamic>),
        );
      } catch (_) {
        /* Ignore damaged records independently. */
      }
    }
    return records;
  }

  List<RunRecord> get runHistory {
    final saved = <RunRecord>[];
    for (final raw
        in preferences.getStringList('run-history-v1') ?? <String>[]) {
      try {
        saved.add(RunRecord.fromJson(jsonDecode(raw) as Map<String, dynamic>));
      } catch (_) {
        // Keep the rest of the history available if an entry is damaged.
      }
    }
    return restoreRunHistory(saved, attemptsHistory, savedScores);
  }

  Future<void> recordRun(RunRecord run) => _serialize(() async {
    final records = preferences.getStringList('run-history-v1') ?? <String>[];
    if (!await preferences.setStringList('run-history-v1', [
      ...records,
      jsonEncode(run.toJson()),
    ])) {
      throw StateError('Could not save run statistics.');
    }
  });

  double? get benchmarkMedian => medianMilliseconds(
    attemptsHistory
        .where((a) => a.benchmark && a.source != 'review')
        .toList()
        .reversed
        .take(100)
        .map((a) => a.milliseconds),
  );
  int get benchmarkCount =>
      attemptsHistory.where((a) => a.benchmark && a.source != 'review').length;

  // Serialize read/modify/write operations, including fast consecutive solves.
  Future<void> _historyWrites = Future.value();
  Future<T> _serialize<T>(Future<T> Function() action) {
    final write = _historyWrites.then((_) => action());
    _historyWrites = write.then<void>((_) {}, onError: (Object _) {});
    return write;
  }

  Future<void> recordPractice(PracticeBoard board) async {
    await _serialize(() async {
      if (board.source != 'legacy') {
        final records =
            preferences.getStringList('set-attempts-v1') ?? <String>[];
        if (!await preferences.setStringList('set-attempts-v1', [
          ...records,
          jsonEncode(board.toJson()),
        ])) {
          throw StateError('Could not save set statistics.');
        }
      }
      if (!board.countsForTraining) return;
      final boards = practiceHistory
        ..removeWhere((old) => old.key == board.key);
      boards.insert(0, board);
      if (!await preferences.setStringList(
        'practice-history-v1',
        boards.take(100).map((entry) => jsonEncode(entry.toJson())).toList(),
      )) {
        throw StateError('Could not save practice history.');
      }
    });
    onRecordsChanged?.call();
  }

  /// Append-only history positions are stable IDs for idempotent cloud uploads.
  int get historyLength =>
      (preferences.getStringList('set-attempts-v1') ?? []).length;
  int get syncedHistory => preferences.getInt('synced-attempts-v1') ?? 0;
  int get pendingAttempts => historyLength - syncedHistory;
  List<Map<String, dynamic>> attemptBatch() {
    final records = preferences.getStringList('set-attempts-v1') ?? <String>[];
    return [
      for (
        var i = syncedHistory;
        i < records.length && i < syncedHistory + 10;
        i++
      )
        {'id': '$i', 'board': jsonDecode(records[i])},
    ];
  }

  Future<void> acknowledgeAttempts(int count) => _serialize(() async {
    if (!await preferences.setInt('synced-attempts-v1', count)) {
      throw StateError('Could not save synchronization progress.');
    }
  });

  List<Map<String, dynamic>> get savedScores => [
    for (final key in preferences.getKeys().where(
      (k) => k.startsWith('saved-score:'),
    ))
      jsonDecode(preferences.getString(key)!) as Map<String, dynamic>,
  ];
  int get pendingScores =>
      savedScores.where((s) => s['status'] == 'pending').length;
  int get rejectedScores =>
      savedScores.where((s) => s['status'] == 'rejected').length;
  Map<String, dynamic>? savedScore(String seed) {
    final raw = preferences.getString('saved-score:$seed');
    return raw == null ? null : jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<void> queueScore({
    required String seed,
    required int milliseconds,
    required int mistakes,
    required List<List<int>> solutions,
  }) async {
    await _serialize(() async {
      // Never replace a first attempt, even while it is waiting for a nickname.
      if (savedScore(seed) != null) return;
      await _saveScore({
        'seed': seed,
        'player': player,
        'name': nickname,
        'milliseconds': milliseconds,
        'mistakes': mistakes,
        'solutions': solutions,
        'status': 'pending',
      });
    });
    onRecordsChanged?.call();
  }

  Future<void> _saveScore(Map<String, dynamic> score) async {
    if (!await preferences.setString(
      'saved-score:${score['seed']}',
      jsonEncode(score),
    )) {
      throw StateError('Could not save this score on your device.');
    }
  }

  Future<void> updateSavedScore(Map<String, dynamic> score) =>
      _serialize(() => _saveScore(score));
}

/// Sets found in a timed run, and when the last of them was found.
class TimedScore {
  const TimedScore(this.sets, this.milliseconds);
  final int sets;
  final int milliseconds;
  bool beats(TimedScore? other) =>
      other == null ||
      sets > other.sets ||
      (sets == other.sets && milliseconds < other.milliseconds);
}

class Score {
  Score.fromJson(Map<String, dynamic> json)
    : name = json['name'] as String,
      seed = json['seed'] as String,
      milliseconds = json['milliseconds'] as int,
      mistakes = json['mistakes'] as int,
      sets = json['sets'] as int? ?? 5;
  final String name;
  final String seed;
  final int milliseconds;
  final int mistakes;
  final int sets;
}

class ApiException implements Exception {
  const ApiException(this.status, this.message);
  final int status;
  final String message;
  @override
  String toString() => message;
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
      throw ApiException(
        response.statusCode,
        json['error'] as String? ?? 'Request failed',
      );
    }
    return json;
  }

  Future<List<Score>> scores({
    required bool unique,
    RunMode mode = RunMode.sprint,
    String? seed,
  }) async {
    final response = await request(
      '/scores',
      query: {'unique': '$unique', 'mode': mode.prefix, 'seed': ?seed},
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

/// Median includes every solved attempt, including repeated layouts.
double? medianMilliseconds(Iterable<int> values) {
  final sorted = values.toList()..sort();
  if (sorted.isEmpty) return null;
  final middle = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[middle].toDouble()
      : (sorted[middle - 1] + sorted[middle]) / 2;
}
