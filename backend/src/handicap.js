// Copyright (C) 2026 Toit contributors.
export function validHandicap(value) {
  return Number.isInteger(value) && value >= 0 && value <= 30000 && value % 100 === 0;
}

export function visibleBoard(board, player, now) {
  if (now >= (player.revealAt ?? 0)) return board;
  return board.map((card, index) => (player.hidden ?? []).includes(index) ? null : card);
}

export function delayBoard(player, before, after, now) {
  player.hidden = after.flatMap((card, index) => before[index] === card ? [] : [index]);
  player.revealAt = now + (player.handicapMs ?? 0);
}
