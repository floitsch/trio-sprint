// Copyright (C) 2026 Florian Loitsch.
export function validHandicap(value) {
  return Number.isInteger(value) && value >= 0 && value <= 30000 && value % 100 === 0;
}
