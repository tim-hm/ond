-- What a self-authored exercise is for, in the author's own words.
--
-- The catalogue has said this about every curated technique since 0001
-- (`techniques.summary`); somebody who builds their own got a name and nothing
-- else. A name separates two exercises in a list. It does not answer "why did I
-- build this" three weeks later, which is when a self-authored exercise stops
-- being used.

ALTER TABLE user_techniques
  -- The second free-text column in the feature, bounded for the reason the
  -- first is. `name`'s 60 is the difference between a name and a payload; this
  -- 500 is the difference between a sentence and a book, and is the bound
  -- `users.intent_note` already carries for a person's free-form prose. The
  -- widest curated summary is 328 characters, so anything below that would let
  -- the catalogue say something an author cannot.
  --
  -- Default empty rather than nullable: the summary is optional, and "" is what
  -- `Technique.summary` already carries for every exercise that has none, so a
  -- null here would be a second way to spell the same absence.
  ADD COLUMN summary text NOT NULL DEFAULT ''
    CHECK (char_length(summary) <= 500);
