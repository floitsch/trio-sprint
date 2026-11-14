-- Recognition races have separate boards for each duration and difficulty.
CREATE TABLE quiz_scores (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  player TEXT NOT NULL,
  run_id TEXT NOT NULL,
  name TEXT NOT NULL,
  seconds INTEGER NOT NULL CHECK(seconds IN (30, 60, 180)),
  difficult INTEGER NOT NULL CHECK(difficult IN (0, 1)),
  correct INTEGER NOT NULL CHECK(correct >= 0),
  mistakes INTEGER NOT NULL CHECK(mistakes >= 0),
  answers TEXT NOT NULL,
  UNIQUE(player, run_id)
);
CREATE INDEX quiz_scores_mode ON quiz_scores(seconds, difficult);
