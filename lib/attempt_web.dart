import 'dart:js_interop';

import 'package:shared_preferences/shared_preferences.dart';

@JS('trioClaimSeed')
external JSPromise<JSBoolean> _claimSeed(JSString seed);

@JS('trioSeedAttempted')
external JSPromise<JSBoolean> _seedAttempted(JSString seed);

Future<bool> claimSeed(SharedPreferences preferences, String seed) async =>
    (await _claimSeed(seed.toJS).toDart).toDart;

Future<bool> hasAttempted(SharedPreferences preferences, String seed) async =>
    (await _seedAttempted(seed.toJS).toDart).toDart;
