-- Where the air goes, as data rather than as a client-side table keyed on a
-- technique slug.
--
-- Alternate-nostril breathing is 4:6:4:6 without this column — the nostrils are
-- the exercise, and until now the only thing that knew them was a Swift table
-- shape-checked against the seed it was written from. Storing them here is what
-- lets somebody compose the same exercise for themselves, and what lets the
-- figures draw an authored one on alternating sides.

CREATE TYPE passage AS ENUM ('NOSE', 'MOUTH', 'LEFT_NOSTRIL', 'RIGHT_NOSTRIL');

ALTER TABLE technique_phases
  -- Nullable, and null exactly for a hold: air that is not moving goes nowhere,
  -- so there is no answer rather than a default one. The `CHECK` below is what
  -- makes that an invariant instead of a convention.
  ADD COLUMN passage passage;

ALTER TABLE user_technique_phases
  ADD COLUMN passage passage;

-- Nose for every breath already stored. Correct for the whole seeded catalogue
-- as it stands, and the seed rewrites its own phases wholesale on the next run
-- anyway — what this backfill is really for is the authored rows, which nothing
-- reseeds.
UPDATE technique_phases SET passage = 'NOSE' WHERE kind IN ('INHALE', 'EXHALE');
UPDATE user_technique_phases SET passage = 'NOSE' WHERE kind IN ('INHALE', 'EXHALE');

ALTER TABLE technique_phases
  ADD CONSTRAINT technique_phases_passage_iff_breathing
    CHECK ((kind IN ('INHALE', 'EXHALE')) = (passage IS NOT NULL));

ALTER TABLE user_technique_phases
  ADD CONSTRAINT user_technique_phases_passage_iff_breathing
    CHECK ((kind IN ('INHALE', 'EXHALE')) = (passage IS NOT NULL));

