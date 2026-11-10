// Copyright (C) 2026 Florian Loitsch.
export function validHandicap(value) {
  return Number.isInteger(value) && value >= 0 && value <= 30000 && value % 100 === 0;
}

export function visibleBoard(board, player, now) {
  if (now >= (player.revealAt ?? 0)) return board;
  return board.map((card, index) => (player.hidden ?? []).includes(index) ? null : card);
}

export function delayBoard(player, before, after, now) {
  // An opponent may claim again while this player still has hidden cards.
  const pending = now < (player.revealAt ?? 0) ? player.hidden ?? [] : [];
  player.hidden = after.flatMap((card, index) =>
    before[index] !== card || pending.includes(index) ? [index] : []);
  player.revealAt = now + (player.handicapMs ?? 0);
}
