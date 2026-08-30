-- Somewhere to author a phase's cadence instead of deriving all of it.
--
-- The gap that closes a phase is sized from the phase's own length, so nothing
-- can say the physiological sigh takes longer to turn into its sip than that
-- tempo rule allows. The tap and the spoken line are derived the same way.

-- Null in every seeded row and null means "derive it", so the catalogue plays
-- exactly as it did until a cadence is authored.
ALTER TABLE technique_phases
  ADD COLUMN turn_gap_ms integer,
  ADD COLUMN haptic_pattern text,
  ADD COLUMN voice_script text;

ALTER TABLE technique_phases
  -- Zero is a real answer, not an absent one: a continuous rhythm turns without
  -- a gap on purpose. 600 ms is the cadence design's ceiling.
  ADD CONSTRAINT technique_phases_turn_gap_within_its_bound
    CHECK (turn_gap_ms IS NULL OR turn_gap_ms BETWEEN 0 AND 600),

  -- An empty key would be a second spelling of the null beside it.
  ADD CONSTRAINT technique_phases_cadence_keys_are_named
    CHECK (
      (haptic_pattern IS NULL OR char_length(haptic_pattern) BETWEEN 1 AND 64)
      AND (voice_script IS NULL OR char_length(voice_script) BETWEEN 1 AND 64)
    );

-- Nothing on `user_technique_phases`, on `0035_phase_manner.sql`'s reasoning:
-- the composer offers no cadence, so the columns would be null for every row
-- that will ever exist there. A cadence is curated design work per exercise.
