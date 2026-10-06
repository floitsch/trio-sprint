// Copyright (C) 2026 Toit contributors.
let installPrompt;
window.addEventListener('beforeinstallprompt', event => {
  event.preventDefault();
  installPrompt = event;
});
window.addEventListener('appinstalled', () => { installPrompt = null; });
window.trioInstall = async () => {
  if (!installPrompt) return false;
  const prompt = installPrompt;
  installPrompt = null;
  await prompt.prompt();
  await prompt.userChoice;
  return true;
};
// A new version takes over in the background (see tool/build_web.py) but never
// reloads the page by itself. The app offers a reload on its start screen.
let updateReady = false;
let updateListener;
if ('serviceWorker' in navigator) {
  // The first install also takes control of the page; that is not an update.
  let controlled = !!navigator.serviceWorker.controller;
  navigator.serviceWorker.addEventListener('controllerchange', () => {
    if (controlled) {
      updateReady = true;
      updateListener?.();
    }
    controlled = true;
  });
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('sw.js').then(registration => {
      // Installed apps can stay open for days; check again when they return.
      let lastCheck = Date.now();
      document.addEventListener('visibilitychange', () => {
        if (document.visibilityState !== 'visible' || Date.now() - lastCheck < 600000) return;
        lastCheck = Date.now();
        registration.update().catch(() => {});
      });
    }).catch(console.warn);
  });
}
window.trioOnUpdate = listener => {
  updateListener = listener;
  if (updateReady) listener();
};
window.trioReload = () => location.reload();

// Web Locks serializes claims across tabs. If storage/locking is unavailable,
// fail closed: solo play still works, but the run is not leaderboard eligible.
window.trioClaimSeed = async seed => {
  if (!navigator.locks) return false;
  return navigator.locks.request('trio-seed-attempt', () => {
    const key = 'trio-attempt:' + seed;
    if (localStorage.getItem(key) !== null) return false;
    localStorage.setItem(key, 'started');
    return true;
  });
};
window.trioSeedAttempted = seed =>
  localStorage.getItem('trio-attempt:' + seed) !== null;
