import 'dart:js_interop';

@JS('trioOnUpdate')
external void _onUpdate(JSFunction listener);

@JS('trioReload')
external void _reload();

/// Calls [callback] once a newer version has taken over and a reload would
/// show it. Pages cached before this hook existed simply never call it.
void onUpdateReady(void Function() callback) {
  try {
    _onUpdate(callback.toJS);
  } catch (_) {
    // An old cached install.js does not define the hook.
  }
}

void reloadApp() => _reload();
