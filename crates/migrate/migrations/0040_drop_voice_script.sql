-- The spoken cue is gone from the product: a session is paced by tones and
-- haptics, and nothing renders, ships, or reads a clip any more.
--
-- The column's constraint named two keys at once, so dropping the column alone
-- would leave a check referring to a column that is not there. Both are
-- rewritten together, and the haptic half is restated unchanged.
ALTER TABLE technique_phases
  DROP CONSTRAINT technique_phases_cadence_keys_are_named;

ALTER TABLE technique_phases
  DROP COLUMN voice_script;

ALTER TABLE technique_phases
  -- An empty key would be a second spelling of the null beside it.
  ADD CONSTRAINT technique_phases_cadence_keys_are_named
    CHECK (haptic_pattern IS NULL OR char_length(haptic_pattern) BETWEEN 1 AND 64);
