import 'dart:js_interop';

@JS('trioInstall')
external JSPromise<JSBoolean> _install();

Future<bool> promptInstall() async {
  try {
    return (await _install().toDart).toDart;
  } catch (_) {
    return false;
  }
}
