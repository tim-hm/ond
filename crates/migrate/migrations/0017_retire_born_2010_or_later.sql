-- The youngest birth-year band goes, so that nothing önd offers can record
-- somebody as under 13 — the age web/privacy.html says the app does not
-- knowingly collect data from. 'BORN_2010_OR_LATER' was open downwards: it
-- admitted a newborn in any year, so it was the one band that could fall out of
-- agreement with the published policy without anyone touching it. Why removal
-- rather than a rename, and when a replacement may be added, is on
-- `BirthYearBand` in proto/ond/v1/profile_service.proto.
--
-- Four statements because Postgres has no `DROP VALUE`: the type is rebuilt
-- without the label and the column carried across. A row still holding the
-- retired label becomes NULL — "rather not say", which is what the app already
-- shows for an unanswered band. No production row exists to convert; the CASE
-- is for the dev and test databases that have already run 0005.

ALTER TYPE birth_year_band RENAME TO birth_year_band_retired;

CREATE TYPE birth_year_band AS ENUM (
  'BORN_BEFORE_1960',
  'BORN_1960S',
  'BORN_1970S',
  'BORN_1980S',
  'BORN_1990S',
  'BORN_2000S'
);

ALTER TABLE users
  ALTER COLUMN birth_year_band TYPE birth_year_band
  USING CASE
    WHEN birth_year_band::text = 'BORN_2010_OR_LATER' THEN NULL
    ELSE birth_year_band::text::birth_year_band
  END;

DROP TYPE birth_year_band_retired;
