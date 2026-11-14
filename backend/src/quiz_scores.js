// Copyright (C) 2026 Florian Loitsch.
import {isSet, validName, validPlayer} from './game.js';

export function quizResult(body) {
  if (!body || !validPlayer(body.player) || !validPlayer(body.id) || !validName(body.name) ||
      ![30, 60, 180].includes(body.seconds) || typeof body.difficult !== 'boolean' ||
      !Array.isArray(body.answers) || body.answers.length < 1 || body.answers.length > 3000) return null;
  let correct = 0;
  for (const entry of body.answers) {
    if (!Array.isArray(entry) || entry.length !== 4 || typeof entry[3] !== 'boolean') return null;
    const cards = entry.slice(0, 3);
    if (new Set(cards).size !== 3 || !cards.every(c => Number.isInteger(c) && c >= 0 && c < 81)) return null;
    const same = [1, 3, 9, 27].filter(place => new Set(cards.map(c => Math.floor(c / place) % 3)).size === 1).length;
    if (body.difficult && same > 1) return null;
    if (isSet(cards) === entry[3]) correct++;
  }
  return {correct, mistakes: body.answers.length - correct};
}

export async function saveQuizScore(db, body) {
  const result = quizResult(body);
  if (!result) return {error: 'Invalid recognition race or answers', status: 400};
  const answers = JSON.stringify(body.answers);
  await db.prepare(`INSERT INTO quiz_scores (player, run_id, name, seconds, difficult, correct, mistakes, answers)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT(player, run_id) DO NOTHING`)
    .bind(body.player, body.id, body.name.trim(), body.seconds, Number(body.difficult), result.correct, result.mistakes, answers).run();
  const previous = await db.prepare('SELECT seconds, difficult, answers FROM quiz_scores WHERE player = ? AND run_id = ?')
    .bind(body.player, body.id).first();
  if (!previous || previous.seconds !== body.seconds || previous.difficult !== Number(body.difficult) || previous.answers !== answers)
    return {error: 'This race was already submitted with different answers', status: 409};
  return {ok: true};
}

// Linked devices share an identity; ties favor fewer mistakes, then the earlier run.
export function quizScoreQuery(unique) {
  return `WITH ranked AS (
    SELECT quiz_scores.*, correct - mistakes AS score,
      ROW_NUMBER() OVER (PARTITION BY COALESCE(player_links.identity, quiz_scores.player)
        ORDER BY correct - mistakes DESC, mistakes, quiz_scores.id) AS player_rank
    FROM quiz_scores LEFT JOIN player_links ON player_links.player = quiz_scores.player
    WHERE seconds = ? AND difficult = ?
  ) SELECT name, score, correct, mistakes FROM ranked ${unique ? 'WHERE player_rank = 1' : ''}
    ORDER BY score DESC, mistakes, id LIMIT 100`;
}
