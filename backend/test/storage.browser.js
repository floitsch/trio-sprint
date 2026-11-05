// Copyright (C) 2026 Florian Loitsch.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createServer} from 'node:http';
import {after, before, test} from 'node:test';
import {chromium} from 'playwright-core';

let browser, server, origin;
const script = await readFile(new URL('../../web/storage.js', import.meta.url), 'utf8');
before(async () => {
  server = createServer((request, response) => {
    response.setHeader('Content-Type', 'text/html');
    response.end('<!doctype html><title>Storage regression tests</title>');
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  origin = `http://127.0.0.1:${server.address().port}`;
  browser = await chromium.launch({
    ...(process.env.CHROME_EXECUTABLE
      ? {executablePath: process.env.CHROME_EXECUTABLE} : {channel: 'chrome'}),
  });
});
after(async () => {
  await browser?.close();
  await new Promise(resolve => server?.close(resolve));
});

async function pageFor(t) {
  const context = await browser.newContext();
  t.after(() => context.close());
  const page = await context.newPage();
  await page.goto(origin);
  await page.addScriptTag({content: script});
  return page;
}

test('full localStorage migrates without losing identity, history, queue or seed claims', async t => {
  const page = await pageFor(t);
  const expected = await page.evaluate(() => {
    const values = {
      'flutter.player': 'original-player',
      'flutter.nickname': 'Prolific player',
      'flutter.best-s2': 12345,
      'flutter.synced-attempts-v1': 8000,
      'flutter.set-attempts-v1': Array.from({length: 9000}, (_, i) => JSON.stringify({
        cards: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11],
        outcome: 'solved', source: 's2', milliseconds: 1000, recordedAt: i,
      })),
      'flutter.run-history-v1': [JSON.stringify({id: 'run-1', sets: 5})],
      'flutter.practice-history-v1': [JSON.stringify({cards: [0, 1, 2]})],
      'flutter.saved-score:s2-12345678': JSON.stringify({status: 'pending', milliseconds: 12345}),
    };
    for (const [key, value] of Object.entries(values)) localStorage.setItem(key, JSON.stringify(value));
    localStorage.setItem('trio-attempt:s2-12345678', 'started');
    // Exhaust the actual browser quota, including its final bytes.
    for (let size = 1024 * 1024; size >= 1; size = Math.floor(size / 2)) {
      try {
        while (true) localStorage.setItem(`padding-${localStorage.length}`, 'x'.repeat(size));
      } catch (error) {
        if (error.name !== 'QuotaExceededError') throw error;
      }
    }
    let oldClaimFailed = false;
    try { localStorage.setItem('trio-attempt:s2-abcdef01', 'started'); }
    catch (error) { oldClaimFailed = error.name === 'QuotaExceededError'; }
    return {values, oldClaimFailed};
  });
  assert.equal(expected.oldClaimFailed, true);
  assert.deepEqual(await page.evaluate(async () => JSON.parse(await trioPreferencesRead())), expected.values);
  assert.equal(await page.evaluate(() => localStorage.getItem('flutter.player')), null);
  assert.equal(await page.evaluate(() => localStorage.getItem('padding-9') !== null), true);
  assert.equal(await page.evaluate(() => trioClaimSeed('s2-12345678')), false);
  assert.equal(await page.evaluate(() => trioClaimSeed('s2-abcdef01')), true);
  await page.evaluate(() => trioPreferencesWrite('flutter.nickname', JSON.stringify('Still playing')));
  await page.reload();
  await page.addScriptTag({content: script});
  const reloaded = await page.evaluate(async () => JSON.parse(await trioPreferencesRead()));
  assert.deepEqual(reloaded, {...expected.values, 'flutter.nickname': 'Still playing'});
  assert.equal(await page.evaluate(() => trioClaimSeed('s2-abcdef01')), false);
});

test('simultaneous tabs can claim a seed only once, without Web Locks', async t => {
  const page = await pageFor(t);
  const second = await page.context().newPage();
  await second.goto(origin);
  await second.addScriptTag({content: script});
  for (const tab of [page, second]) {
    await tab.evaluate(() => Object.defineProperty(navigator, 'locks', {value: undefined}));
  }
  const claims = await Promise.all([page, second].map(tab => tab.evaluate(() => trioClaimSeed('s2-11111111'))));
  assert.deepEqual(claims.sort(), [false, true]);
  assert.equal(await second.evaluate(() => trioSeedAttempted('s2-11111111')), true);
});

test('failed migration retains every original record and can be retried', async t => {
  const page = await pageFor(t);
  const result = await page.evaluate(async () => {
    localStorage.setItem('flutter.player', JSON.stringify('keep-me'));
    localStorage.setItem('trio-attempt:s2-22222222', 'started');
    const original = IDBObjectStore.prototype.put;
    IDBObjectStore.prototype.put = function (...args) {
      const request = original.apply(this, args);
      this.transaction.abort();
      return request;
    };
    let failed = false;
    try { await trioPreferencesRead(); } catch (_) { failed = true; }
    IDBObjectStore.prototype.put = original;
    return {
      failed,
      player: localStorage.getItem('flutter.player'),
      seed: localStorage.getItem('trio-attempt:s2-22222222'),
      retried: JSON.parse(await trioPreferencesRead()),
      claimed: await trioClaimSeed('s2-22222222'),
    };
  });
  assert.deepEqual(result, {
    failed: true, player: '"keep-me"', seed: 'started',
    retried: {'flutter.player': 'keep-me'}, claimed: false,
  });
});

test('interrupted cleanup cannot overwrite newer committed data on reload', async t => {
  const page = await pageFor(t);
  await page.evaluate(async () => {
    localStorage.setItem('flutter.player', JSON.stringify('original'));
    localStorage.setItem('flutter.nickname', JSON.stringify('old-name'));
    Storage.prototype.removeItem = () => { throw new Error('Cleanup interrupted'); };
    await trioPreferencesRead();
    await trioPreferencesWrite('flutter.nickname', JSON.stringify('new-name'));
  });
  await page.reload();
  await page.addScriptTag({content: script});
  assert.deepEqual(await page.evaluate(async () => JSON.parse(await trioPreferencesRead())), {
    'flutter.player': 'original', 'flutter.nickname': 'new-name',
  });
  assert.equal(await page.evaluate(() => localStorage.length), 0);
});

test('a failed claim rejects and does not consume eligibility', async t => {
  const page = await pageFor(t);
  const result = await page.evaluate(async () => {
    await trioPreferencesRead();
    const original = IDBObjectStore.prototype.put;
    IDBObjectStore.prototype.put = function (...args) {
      const request = original.apply(this, args);
      this.transaction.abort();
      return request;
    };
    let failed = false;
    try { await trioClaimSeed('s2-33333333'); } catch (_) { failed = true; }
    IDBObjectStore.prototype.put = original;
    return {failed, attempted: await trioSeedAttempted('s2-33333333'), retry: await trioClaimSeed('s2-33333333')};
  });
  assert.deepEqual(result, {failed: true, attempted: false, retry: true});
});

test('preference remove and clear retain seed eligibility records', async t => {
  const page = await pageFor(t);
  await page.evaluate(async () => {
    await trioPreferencesWrite('flutter.player', JSON.stringify('player'));
    await trioPreferencesWrite('flutter.nickname', JSON.stringify('name'));
    await trioClaimSeed('s2-44444444');
    await trioPreferencesRemove('flutter.nickname');
  });
  assert.deepEqual(await page.evaluate(async () => JSON.parse(await trioPreferencesRead())), {'flutter.player': 'player'});
  await page.evaluate(() => trioPreferencesClear());
  assert.deepEqual(await page.evaluate(async () => JSON.parse(await trioPreferencesRead())), {});
  assert.equal(await page.evaluate(() => trioClaimSeed('s2-44444444')), false);
});
