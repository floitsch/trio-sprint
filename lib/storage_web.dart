import 'dart:convert';
import 'dart:js_interop';

import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

@JS('trioPreferencesRead')
external JSPromise<JSString> _read();

@JS('trioPreferencesWrite')
external JSPromise<JSBoolean> _write(JSString key, JSString value);

@JS('trioPreferencesRemove')
external JSPromise<JSBoolean> _remove(JSString key);

@JS('trioPreferencesClear')
external JSPromise<JSBoolean> _clear();

void configureStorage() {
  SharedPreferencesStorePlatform.instance = _BrowserStorage();
}

/// Keep the existing preferences API and cache, with durable browser storage.
class _BrowserStorage extends SharedPreferencesStorePlatform {
  @override
  Future<Map<String, Object>> getAll() async =>
      (jsonDecode((await _read().toDart).toDart) as Map).cast<String, Object>();

  @override
  Future<bool> setValue(String valueType, String key, Object value) async =>
      (await _write(key.toJS, jsonEncode(value).toJS).toDart).toDart;

  @override
  Future<bool> remove(String key) async =>
      (await _remove(key.toJS).toDart).toDart;

  @override
  Future<bool> clear() async => (await _clear().toDart).toDart;
}
