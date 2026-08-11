-- Where a session came from: the occasion that prescribed it and the surface
-- that delivered it.
--
-- Both columns are nullable because both are provenance, not measurement — a
-- session is real without either. A null `occasion_slug` is a person who picked
-- the technique themselves; a null `surface` is a record from before the column
-- existed, which every reader treats as full-screen because that was the only
-- surface any client could deliver then.

ALTER TABLE sessions
  -- Text with no foreign key to `occasions`, on `technique_slug`'s exact
  -- reasoning one table up: occasions are reseeded reference data whose slugs
  -- may be renamed or retired, and a session someone actually breathed must
  -- never be invalidated by the catalogue moving underneath it.
  ADD COLUMN occasion_slug text CHECK (char_length(occasion_slug) BETWEEN 1 AND 64),

  -- Reuses the `delivery_surface` enum the occasions table introduced, so a
  -- session records the same vocabulary its prescription was written in.
  -- Carried at all because `completed` reads differently per surface: a
  -- discreet session's sparse cadence runs near half an hour, and grading it
  -- like a five-minute guided session would misread both.
  ADD COLUMN surface delivery_surface;
