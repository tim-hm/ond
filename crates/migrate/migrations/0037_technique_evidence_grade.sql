-- How much the research supports what an exercise is offered for, as one word.
--
-- `evidence` already carries the honest paragraph, but a paragraph only reaches
-- somebody who opened the detail screen. The grade is the same judgement in a
-- form a row can carry, so what the trials found is visible where an exercise is
-- chosen rather than only after it has been.
--
-- Stored rather than derived. A grade read out of the prose at render time is a
-- claim the client invented, and it would quietly change the first time a
-- sentence was rewritten; this one is seeded next to the paragraph it summarises,
-- so the two move together or the seed test fails.
--
-- A native enum on `copy_register`'s terms: the proto contract fixes the value
-- set, so a third grade is refused at write time rather than reaching a client
-- as a variant nothing maps. Why there are two grades and no 'STRONG' is
-- argued in docs/product/breathing-science.md §2.1.
CREATE TYPE evidence_grade AS ENUM ('MODERATE', 'LIMITED');

-- Nullable rather than defaulted, which is where this parts company with
-- `register`. An occasion that says nothing about its register means PLAIN,
-- which is a real answer; an exercise that says nothing about its evidence has
-- not been graded, and a default would have the database assert a literature
-- nobody checked. Every seeded row carries a grade today, so the null is what a
-- future entry gets to say honestly rather than a state this catalogue is in.
--
-- Exercises people write themselves never reach this table at all — they live
-- in `user_techniques`, and the unspecified they go out as is stamped by that
-- feature's converter.
ALTER TABLE techniques ADD COLUMN evidence_grade evidence_grade;
