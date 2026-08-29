-- Typed reading content beside the complete plain-text fallbacks.
--
-- Nullable for upgrade compatibility: migrations run before the catalogue is
-- reseeded, and a server briefly reading an existing row must be able to fall
-- back to `mechanism`, `evidence`, `preparation`, or `answer`. Every curated
-- row receives its structured value when the seed transaction completes.
ALTER TABLE techniques
  ADD COLUMN mechanism_content jsonb,
  ADD COLUMN evidence_content jsonb,
  ADD COLUMN preparation_content jsonb;

ALTER TABLE foundation_topics
  ADD COLUMN answer_content jsonb;
