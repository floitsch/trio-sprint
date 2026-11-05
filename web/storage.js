// Copyright (C) 2026 Florian Loitsch.
(() => {
  let opening;
  const owned = key => key.startsWith('flutter.') || key.startsWith('trio-attempt:');

  // Resolve only after commit, never on an individual request's success.
  function transaction(db, mode, action) {
    return new Promise((resolve, reject) => {
      const tx = db.transaction('records', mode);
      let result;
      tx.oncomplete = () => resolve(result);
      tx.onabort = () => reject(tx.error || new Error('Storage transaction aborted'));
      tx.onerror = () => {}; // The abort event supplies the transaction error.
      try {
        action(tx.objectStore('records'), value => { result = value; });
      } catch (error) {
        tx.abort();
        reject(error);
      }
    });
  }

  async function open() {
    const db = await new Promise((resolve, reject) => {
      const request = indexedDB.open('trio-sprint', 1);
      request.onupgradeneeded = () => request.result.createObjectStore('records');
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
    db.onversionchange = () => { db.close(); opening = undefined; };
    try {
      // Reading/removing localStorage still works when its write quota is full.
      // Preserve the exact JSON strings and array order: upload IDs are offsets.
      const legacy = [];
      for (let i = 0; i < localStorage.length; i++) {
        const key = localStorage.key(i);
        if (owned(key)) legacy.push([key, localStorage.getItem(key)]);
      }
      if (legacy.length) {
        await transaction(db, 'readwrite', store => {
          for (const [key, value] of legacy) {
            const request = store.get(key);
            request.onsuccess = () => {
              // A retry after a crash must not replace newer IndexedDB data.
              if (request.result === undefined) store.put(value, key);
            };
          }
        });
        for (const [key, value] of legacy) {
          // Cleanup is best effort. A crash here leaves safe, retryable copies.
          try {
            if (localStorage.getItem(key) === value) localStorage.removeItem(key);
          } catch (_) { /* Keep the committed database usable. */ }
        }
      }
      return db;
    } catch (error) {
      db.close();
      throw error;
    }
  }

  function database() {
    return opening ??= open().catch(error => {
      opening = undefined;
      throw error;
    });
  }

  window.trioPreferencesRead = async () => transaction(await database(), 'readonly', (store, done) => {
    const records = {};
    const request = store.openCursor();
    request.onsuccess = () => {
      const cursor = request.result;
      if (!cursor) { done(JSON.stringify(records)); return; }
      if (cursor.key.startsWith('flutter.')) records[cursor.key] = JSON.parse(cursor.value);
      cursor.continue();
    };
  });

  window.trioPreferencesWrite = async (key, value) => transaction(await database(), 'readwrite', (store, done) => {
    store.put(value, key);
    done(true);
  });

  window.trioPreferencesRemove = async key => transaction(await database(), 'readwrite', (store, done) => {
    store.delete(key);
    done(true);
  });

  window.trioPreferencesClear = async () => transaction(await database(), 'readwrite', (store, done) => {
    const request = store.openCursor();
    request.onsuccess = () => {
      const cursor = request.result;
      if (!cursor) { done(true); return; }
      if (cursor.key.startsWith('flutter.')) cursor.delete();
      cursor.continue();
    };
  });

  // A read/write transaction serializes claims across tabs without Web Locks.
  window.trioClaimSeed = async seed => transaction(await database(), 'readwrite', (store, done) => {
    const key = 'trio-attempt:' + seed;
    const request = store.get(key);
    request.onsuccess = () => {
      if (request.result !== undefined) { done(false); return; }
      store.put('started', key);
      done(true);
    };
  });

  window.trioSeedAttempted = async seed => transaction(await database(), 'readonly', (store, done) => {
    const request = store.get('trio-attempt:' + seed);
    request.onsuccess = () => done(request.result !== undefined);
  });
})();
