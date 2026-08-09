-- A credential's lifetime, bounded by disuse rather than by age.
--
-- 0018 minted rows with no expiry, and two ways a row outlives its use were
-- known at the time: sign-out is deliberately best-effort (a phone with no
-- signal signs out locally and leaves its row behind), and a device that is
-- wiped or reinstalled never signs out at all. The surviving row is a hash
-- nobody holds the preimage of — dead weight, not a hole — but a credential
-- table that only grows has no lifetime the privacy page could state.
--
-- The rule: a session unseen for 90 days is swept, by `start_session`, on the
-- next sign-in from anybody. Disuse rather than age because the other bound
-- breaks people: a fixed lifetime signs out whoever outlasts it, however often
-- they practise, and "the Apple sheet again because a timer ran out" is
-- exactly what 0018 existed to avoid. Ninety days of silence, by contrast, is
-- a device this credential no longer lives on.
--
-- `identity::resolve` refreshes this at most once per day per session — the
-- request path must not gain a write per request — so the value is coarse to
-- a day, which a 90-day bound does not notice.
--
-- This is the idle policy 0018's `created_at` anticipated, expiring against
-- `last_seen_at` instead: age is exactly the bound rejected above.
-- `created_at` stays for the operator question 0018 gives it, and nothing
-- reads it.
ALTER TABLE user_sessions
  ADD COLUMN last_seen_at timestamptz NOT NULL DEFAULT now();

-- No index: the sweep runs once per sign-in against a table that holds one
-- row per signed-in device, so a sequential scan is the cheap plan for years
-- yet. Revisit alongside the row count, not before it.
