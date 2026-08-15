-- How the breath is shaped on its way through, where `passage` says where it
-- goes.
--
-- Cooling Breath is a mouth inhale and so is nothing else in the catalogue, but
-- "mouth" is not what makes it that exercise — the tongue curled into a tube is,
-- and the same column that carries the nostrils had no way to say so. Pursed-Lip
-- Breathing and Humming Breath are the same shape of gap: one is a mouth exhale
-- whose narrow gap is the whole mechanism, and the other is an ordinary nasal
-- exhale that the person hums through. All three read on screen as a passage or
-- as nothing at all, so the mechanic lived only in prose somebody read before
-- starting.
--
-- Only three values, and the `CHECK` below says which breath each one may shape.
-- Pace is not among them: it is arithmetic over durations a dial can move, so a
-- stored `FAST` would go on asserting itself after somebody slowed the exercise
-- down.

CREATE TYPE manner AS ENUM ('CURLED_TONGUE', 'PURSED_LIPS', 'HUM');

ALTER TABLE technique_phases
  -- Nullable, and null for all but three phases in the seeded catalogue. Unlike
  -- `passage`, which every moving breath must answer, a manner is the exception
  -- — so there is no `NONE` member to mean "shaped no particular way", which
  -- would be a second spelling of the null already here.
  ADD COLUMN manner manner;

-- No backfill. `passage` needed one because its constraint is two-directional,
-- so rows predating it would have violated it on the spot; this one only
-- constrains rows that carry a manner, which none yet do.
ALTER TABLE technique_phases
  ADD CONSTRAINT technique_phases_manner_fits_its_breath
    CHECK (
      manner IS NULL
      OR (manner = 'CURLED_TONGUE' AND kind = 'INHALE' AND passage = 'MOUTH')
      OR (manner = 'PURSED_LIPS' AND kind = 'EXHALE' AND passage = 'MOUTH')
      OR (manner = 'HUM' AND kind = 'EXHALE' AND passage = 'NOSE')
    );

-- Nothing on `user_technique_phases`. The composer offers no manner, so the
-- column would be null for every row that will ever exist there — and a manner
-- is curated copy about a shaped breath, on the same footing as `mechanism`,
-- which an authored exercise also never carries.
