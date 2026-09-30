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
if ('serviceWorker' in navigator) {
  window.addEventListener('load', () => {
    // Updated workers wait until existing app windows close; never reload a run.
    navigator.serviceWorker.register('sw.js').catch(console.warn);
  });
}

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
