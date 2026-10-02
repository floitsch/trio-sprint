{{flutter_js}}
{{flutter_build_config}}

// No serviceWorkerSettings: install.js registers the app's own offline worker
// (sw.js). Flutter's flutter_service_worker.js unregisters whatever worker
// controls the page and reloads it, which fought sw.js in a reload loop.
_flutter.loader.load();
