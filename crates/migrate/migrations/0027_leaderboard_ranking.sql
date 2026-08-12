-- Indexes for two cascades and a date-ordered read, and the ranking the boards
-- used to recompute on every request.

-- `0013_leaderboard_snapshot.sql` says "No index beyond the primary key", and
-- reasons only about the read path. The delete path is what forces this one:
-- `user_id` is the third primary-key column, so `ON DELETE CASCADE` — an
-- account deletion, and every first Sign in with Apple from an anonymous
-- device, both holding `FOR UPDATE` on the `users` row — reaches it only by
-- skipping over every `(board, utc_offset_minutes)` prefix in the index. On
-- 50k people over twenty day boundaries that measured 47 index descents; here
-- it is one.
CREATE INDEX leaderboard_snapshot_user_idx ON leaderboard_snapshot (user_id);

-- Where a person stands on this board, globally and inside their own birth-year
-- band, as of the fold that wrote the row. Nullable because the fold's four
-- board statements insert the value and `leaderboard::repository::rank` fills
-- these in the same transaction; `band_rank` stays null for somebody who has
-- never given a band, whose band nobody can ask about.
--
-- `band` records which population `band_rank` counted, because a person can
-- answer or change the decade question between two folds: the read compares it
-- to the band being asked about and answers "not ranked here yet" rather than
-- quoting a rank from a board the caller has left.
ALTER TABLE leaderboard_snapshot
  ADD COLUMN global_rank integer CHECK (global_rank >= 1),
  ADD COLUMN band_rank integer CHECK (band_rank >= 1),
  ADD COLUMN band birth_year_band;

-- Who each board shows and in what order, decided once per key rather than
-- ranked per caller. Two sorts over every participant and a join to `users` for
-- each of them used to run on every `GetLeaderboard`; both now run on the
-- refresh that the 60-second snapshot already bounds.
--
-- `0013` argued against materialising the ranking because a per-band copy of
-- every row is eight times the storage and eight times the refresh. This holds
-- the twenty entries per scope that get shown, so the copies are bounded by the
-- board's limit rather than by the install base.
--
-- Membership and order only. Names, values and ranks stay where they already
-- live and are joined on read, which is at most twenty keyed lookups: copying
-- them here would give one row two staleness rules, and the one that matters is
-- that somebody clearing their display name must leave the board at once rather
-- than at the next fold.
CREATE TABLE leaderboard_listing (
  board leaderboard_board NOT NULL,
  utc_offset_minutes integer NOT NULL,

  -- The scope this listing answers: a band, or null for everyone.
  band birth_year_band,

  -- Position in the list, 1-based, which is the order to read the rows back in.
  -- Distinct from the rank on the snapshot, which counts the people ahead
  -- including the ones with no name to show, and which ties.
  position integer NOT NULL CHECK (position >= 1),

  user_id uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE
);

-- `NULLS NOT DISTINCT` so the global scope is one key rather than a key per
-- row: a primary key cannot hold the nullable `band` this needs.
CREATE UNIQUE INDEX leaderboard_listing_key_idx
  ON leaderboard_listing (board, utc_offset_minutes, band, position) NULLS NOT DISTINCT;

-- The cascade again, on the same terms as `leaderboard_snapshot_user_idx`: a
-- deleted account leaves every board it was listed on, and the delete path
-- cannot reach this table through the key index.
CREATE INDEX leaderboard_listing_user_idx ON leaderboard_listing (user_id);

-- Both tables are caches with a stated staleness bound, and the rows already
-- here predate the ranks. Dropping them is the whole of their migration: the
-- next read finds no refresh stamp and folds the board again.
DELETE FROM leaderboard_snapshot;
DELETE FROM leaderboard_refresh;

-- `resting_rate::repository::resting_rate_aggregate` takes the latest reading,
-- and `0022`'s `(user_id, breaths_per_minute)` orders by the wrong column for
-- it, so the whole of one person's history was sorted per call — on the request
-- path the assistant fans out hardest.
CREATE INDEX resting_rates_user_measured_idx
  ON resting_rates (user_id, measured_at DESC, client_measurement_id DESC);

-- `0021` indexed `progression_steps.technique_slug` by making it UNIQUE and
-- left the sibling foreign key on `occasions` bare. The catalogue is curated and
-- holds tens of rows, so this buys nothing measurable today; it is here so the
-- asymmetry is not read as a decision somebody has to re-derive.
CREATE INDEX occasions_technique_idx ON occasions (technique_slug);
