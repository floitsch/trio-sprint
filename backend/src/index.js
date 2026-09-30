// Copyright (C) 2026 Toit contributors.
import { DurableObject } from 'cloudflare:workers';
import { SeededRun, seededBoards, validName, validPlayer, validSeed, validateScore } from './game.js';
import { registerDevice, deviceCount, pairingCode, linkDevices, scoreQuery, insertScoreQuery, existingScoreQuery } from './players.js';

const headers = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
  'Cache-Control': 'no-store',
};
const json = (body, status = 200) => Response.json(body, { status, headers });
async function readJson(request) {
  const reader = request.body?.getReader();
  if (!reader) throw new Error('Missing body');
  let size = 0;
  const chunks = [];
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.length;
    if (size > 8192) { await reader.cancel(); throw new Error('Request too large'); }
    chunks.push(value);
  }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
  return JSON.parse(new TextDecoder().decode(bytes));
}

export default {
  async fetch(request, env) {
    if (request.method === 'OPTIONS') return new Response(null, { headers });
    const url = new URL(request.url);
    try {
      if (url.pathname === '/players/pairing' && request.method === 'POST') {
        const body = await readJson(request);
        if (!validPlayer(body?.player)) return json({ error: 'Invalid player' }, 400);
        const code = await pairingCode(env.DB, body.player);
        return json({ code, devices: await deviceCount(env.DB, body.player) });
      }
      if (url.pathname === '/players/code' && request.method === 'POST') {
        const body = await readJson(request);
        if (!validPlayer(body?.player)) return json({ error: 'Invalid player' }, 400);
        await registerDevice(env.DB, body.player);
        return json({ code: body.player, devices: await deviceCount(env.DB, body.player) });
      }
      if (url.pathname === '/players/merge' && request.method === 'POST') {
        const result = await linkDevices(env.DB, await readJson(request));
        return json(result, result.status ?? 200);
      }
      if (url.pathname === '/scores' && request.method === 'GET') {
        const seed = url.searchParams.get('seed');
        if (seed && !validSeed(seed)) return json({ error: 'Invalid seed' }, 400);
        const unique = url.searchParams.get('unique') !== 'false';
        const statement = env.DB.prepare(scoreQuery(unique, !!seed));
        const { results } = await (seed ? statement.bind(seed) : statement).all();
        return json({ scores: results });
      }
      if (url.pathname === '/scores' && request.method === 'POST') {
        const body = await readJson(request);
        if (!validateScore(body)) return json({ error: 'Invalid score or solutions' }, 400);
        const result = await env.DB.prepare(insertScoreQuery)
          .bind(body.player, body.name.trim(), body.seed, body.milliseconds, body.mistakes,
            body.seed, body.player, body.player).run();
        if (!result.meta.changes) {
          const previous = await env.DB.prepare(existingScoreQuery)
            .bind(body.seed, body.player, body.player).first();
          // Retrying a timed-out submission is safe; a better replay cannot replace it.
          if (!previous || previous.milliseconds !== body.milliseconds || previous.mistakes !== body.mistakes)
            return json({ error: 'This player has already submitted this seed. Replays are practice.' }, 409);
        }
        return json({ ok: true });
      }
      if (url.pathname === '/rooms' && request.method === 'POST') {
        const bytes = crypto.getRandomValues(new Uint8Array(6));
        const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
        const code = Array.from(bytes, b => alphabet[b % alphabet.length]).join('');
        const room = env.ROOMS.get(env.ROOMS.idFromName(code));
        const response = await room.fetch(new Request('https://room/create', { method: 'POST' }));
        if (!response.ok) return json({ error: 'Please try creating a room again.' }, 409);
        return json({ room: code });
      }
      const match = url.pathname.match(/^\/rooms\/([A-Z0-9]{6})$/);
      if (match && request.method === 'GET') {
        return env.ROOMS.get(env.ROOMS.idFromName(match[1])).fetch(request);
      }
      return json({ error: 'Not found' }, 404);
    } catch (error) {
      if (error instanceof SyntaxError || ['Missing body', 'Request too large'].includes(error.message))
        return json({ error: 'Invalid request' }, 400);
      console.error(error);
      return json({ error: 'Service unavailable. Please retry.' }, 503);
    }
  },
};

export class RaceRoom extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
    this.ctx = ctx;
    ctx.blockConcurrencyWhile(async () => { this.game = await ctx.storage.get('game'); });
  }
  async save() { await this.ctx.storage.put('game', this.game); }
  connected(token) {
    return this.ctx.getWebSockets(token).some(socket => socket.readyState === WebSocket.OPEN);
  }
  async fetch(request) {
    if (new URL(request.url).pathname === '/create') {
      if (this.game) return json({ error: 'Room already exists' }, 409);
      const seed = 's2-' + crypto.getRandomValues(new Uint32Array(1))[0].toString(16).padStart(8, '0');
      this.game = { seed, players: [], startAt: null, winner: null, ended: false, expires: Date.now() + 3600000 };
      await this.save();
      await this.ctx.storage.setAlarm(this.game.expires);
      return json({ ok: true });
    }
    if (!this.game || Date.now() >= this.game.expires) return json({ error: 'Room expired or does not exist' }, 404);
    if (request.headers.get('Upgrade')?.toLowerCase() !== 'websocket') return json({ error: 'WebSocket required' }, 400);
    const url = new URL(request.url);
    const token = url.searchParams.get('player');
    const name = url.searchParams.get('name');
    if (!validPlayer(token) || !validName(name)) return json({ error: 'Invalid player' }, 400);
    let player = this.game.players.find(p => p.token === token);
    if (!player) {
      if (this.game.players.length >= 2 || this.game.startAt || this.game.ended) return json({ error: 'Room is full or finished' }, 409);
      player = { token, name: name.trim(), progress: 0, mistakes: 0, ready: false, solutions: [] };
      this.game.players.push(player);
      await this.save();
    }
    for (const socket of this.ctx.getWebSockets(token)) socket.close(4001, 'Joined on another connection');
    const pair = new WebSocketPair();
    this.ctx.acceptWebSocket(pair[1], [token]);
    pair[1].serializeAttachment({ token });
    this.broadcast();
    return new Response(null, { status: 101, webSocket: pair[0] });
  }
  runFor(player) {
    const run = new SeededRun(this.game.seed);
    // Rooms already in progress at deployment retain their original boards.
    if (this.game.seed.startsWith('s1-')) {
      run.progress = player.progress;
      run.board = seededBoards(this.game.seed)[player.progress] ?? [];
    } else {
      for (const solution of player.solutions) run.pick(solution);
    }
    return run;
  }
  state(token) {
    const game = this.game;
    const own = game.players.find(p => p.token === token);
    const started = game.startAt && Date.now() >= game.startAt;
    return { type: 'state', now: Date.now(), startAt: game.startAt, ended: game.ended,
      winner: game.winner, you: game.players.indexOf(own),
      seed: started || game.ended ? game.seed : null,
      board: started && !game.ended ? this.runFor(own).board : [],
      players: game.players.map(p => ({ name: p.name, progress: p.progress, mistakes: p.mistakes,
        ready: p.ready, connected: this.connected(p.token) })),
    };
  }
  broadcast() {
    for (const socket of this.ctx.getWebSockets()) {
      try { socket.send(JSON.stringify(this.state(socket.deserializeAttachment().token))); } catch (_) { /* closed */ }
    }
  }
  async webSocketMessage(socket, message) {
    if (typeof message !== 'string' || message.length > 2048) return;
    let data;
    try { data = JSON.parse(message); } catch (_) { return; }
    if (!data || typeof data !== 'object' || !this.game || this.game.ended) return;
    if (Date.now() >= this.game.expires) { await this.alarm(); return; }
    const token = socket.deserializeAttachment().token;
    const player = this.game.players.find(p => p.token === token);
    if (!player) return;
    if (data.type === 'ready' && !this.game.startAt) {
      player.ready = true;
      if (this.game.players.length === 2 && this.game.players.every(p => p.ready && this.connected(p.token))) {
        this.game.startAt = Date.now() + 3000;
        await this.ctx.storage.setAlarm(this.game.startAt);
      }
    } else if (data.type === 'pick' && this.game.startAt && Date.now() >= this.game.startAt) {
      if (data.round !== player.progress) { this.broadcast(); return; }
      const run = this.runFor(player);
      if (run.pick(data.cards)) {
        (player.solutions ??= []).push(data.cards);
        player.progress++;
        if (player.progress === 5) {
          this.game.ended = true;
          this.game.winner = this.game.players.indexOf(player);
        }
      } else {
        player.mistakes++;
        socket.send(JSON.stringify({ type: 'error', message: 'Not a set. Try again.' }));
      }
    } else if (data.type === 'leave') {
      if (this.game.startAt) {
        this.game.ended = true;
        this.game.winner = this.game.players.findIndex(p => p !== player);
      } else {
        this.game.players = this.game.players.filter(p => p !== player);
        socket.close(1000, 'Left room');
      }
    }
    await this.save();
    this.broadcast();
  }
  async webSocketClose(socket, code, reason) {
    // These codes describe a disconnect but cannot be sent in a close frame.
    socket.close([1005, 1006, 1015].includes(code) ? 1000 : code, reason);
    this.broadcast();
  }
  async webSocketError(socket) { socket.close(1011, 'Connection error'); }
  async alarm() {
    if (!this.game) return;
    if (Date.now() >= this.game.expires) {
      for (const socket of this.ctx.getWebSockets()) socket.close(4000, 'Room expired');
      await this.ctx.storage.deleteAll();
      this.game = undefined;
    } else {
      this.broadcast();
      await this.ctx.storage.setAlarm(this.game.expires);
    }
  }
}
