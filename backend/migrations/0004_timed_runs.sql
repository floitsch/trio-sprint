-- Timed runs rank by the number of sets found. Every existing score is a
-- five-set sprint, so existing rows keep their place unchanged.
ALTER TABLE scores ADD COLUMN sets INTEGER NOT NULL DEFAULT 5 CHECK(sets > 0);
