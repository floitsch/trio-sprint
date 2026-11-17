// Copyright (C) 2026 Florian Loitsch.
import test from 'node:test';
import assert from 'node:assert/strict';
import { validHandicap } from '../src/handicap.js';

test('answer delays allow zero and tenth-second increments up to thirty seconds', () => {
  for (const value of [0, 100, 1200, 30000]) assert.ok(validHandicap(value));
  for (const value of [-100, 10, 100.1, 30100, null, '100', NaN]) assert.ok(!validHandicap(value));
});
