-- Which words an occasion's session speaks.
--
-- On the route rather than on the technique, which is the whole reason
-- occasions exist: the same exercise is read plainly in the catalogue and
-- playfully by somebody who arrived through "with your child". A column on
-- `techniques` would be the second taxonomy 0021 was written to avoid.

-- A native enum on `delivery_surface`'s terms: the proto contract fixes the
-- value set, so a third register should be refused at write time rather than
-- reach a client as a variant nothing maps.
CREATE TYPE copy_register AS ENUM ('PLAIN', 'PLAYFUL');

-- Defaulted rather than backfilled-then-tightened. Every occasion seeded before
-- this column existed meant PLAIN by saying nothing, and a default keeps that
-- true for the next one somebody adds without thinking about registers at all.
ALTER TABLE occasions
  ADD COLUMN register copy_register NOT NULL DEFAULT 'PLAIN';
