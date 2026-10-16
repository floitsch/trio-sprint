// Copyright (C) 2026 Toit contributors.
import 'dart:js_interop';

@JS('trioOnOnline')
external void _onOnline(JSFunction? listener);
@JS('trioOfflineReady')
external bool _offlineReady();

void onOnline(void Function()? callback) {
  try {
    _onOnline(callback?.toJS);
  } catch (_) {
    /* Older cached install.js. */
  }
}

bool offlineReady() {
  try {
    return _offlineReady();
  } catch (_) {
    return false;
  }
}
