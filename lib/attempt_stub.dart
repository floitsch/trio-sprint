import 'package:shared_preferences/shared_preferences.dart';

Future<bool> claimSeed(SharedPreferences preferences, String seed) async {
  await preferences.reload();
  final key = 'attempt:$seed';
  if (preferences.containsKey(key)) return false;
  if (!await preferences.setBool(key, true)) {
    throw StateError('Could not save seed attempt.');
  }
  return true;
}

Future<bool> hasAttempted(SharedPreferences preferences, String seed) async {
  await preferences.reload();
  return preferences.containsKey('attempt:$seed');
}
