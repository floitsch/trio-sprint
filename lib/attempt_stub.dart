import 'package:shared_preferences/shared_preferences.dart';

Future<bool> claimSeed(SharedPreferences preferences, String seed) async {
  await preferences.reload();
  final key = 'attempt:$seed';
  if (preferences.containsKey(key)) return false;
  return preferences.setBool(key, true);
}

Future<bool> hasAttempted(SharedPreferences preferences, String seed) async {
  await preferences.reload();
  return preferences.containsKey('attempt:$seed');
}
