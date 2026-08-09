-- The routes into the catalogue: the occasion entries and the Start here
-- ordering.
--
-- Both are curated reference data over the nine techniques that already exist.
-- Nothing here adds a technique or a column to `techniques`: an occasion is a
-- named moment that resolves to one of them, and the progression is an order
-- over them.

-- How loudly a session runs. A native enum for the reason `technique_goal` is
-- one: the proto contract fixes the value set, so the database should reject a
-- third surface at write time rather than let it reach a client as an unmapped
-- variant.
CREATE TYPE delivery_surface AS ENUM ('FULL_SCREEN', 'DISCREET');

CREATE TABLE occasions (
  -- The slug is the primary key, as on `foundation_topics` and for the same
  -- reason: nothing references an occasion by foreign key, so a surrogate id
  -- would buy only the ability to rename a slug, which is the one thing a
  -- stable key must not do.
  slug text PRIMARY KEY,

  -- The moment in the person's words, and one sentence on what it does for
  -- them here. Provisional copy: TIM-28 owns the final wording.
  name text NOT NULL,
  summary text NOT NULL,

  -- The prescription. `technique_slug` references the key clients navigate by
  -- rather than `techniques.id`, so the read path answers without a join and
  -- the integrity constraint is on the same column the wire carries. What the
  -- foreign key buys at seed time is the insert: an occasion naming a slug the
  -- catalogue does not hold is refused rather than served as a route to
  -- nowhere. No ON DELETE clause, so a technique cannot later be deleted out
  -- from under a route either.
  technique_slug text NOT NULL REFERENCES techniques (slug),

  -- The goal the moment borrows. Denormalised from the technique deliberately:
  -- the framing is the occasion's own fact and must not move when a technique
  -- is re-grouped.
  goal technique_goal NOT NULL,

  surface delivery_surface NOT NULL,

  -- What the occasion asks for, as a target the client fits whole cycles into.
  duration_ms integer NOT NULL CHECK (duration_ms > 0),

  -- Curated presentation order, on the same terms as `techniques.sort_order`.
  sort_order integer NOT NULL
);

-- One progression, so its steps need no owner column. "Start here" is the
-- single curated ordering the decision on TIM-60 ratified, and a second one is
-- a migration away — cheaper than carrying a `progressions` table holding one
-- row until a second exists.
CREATE TABLE progression_steps (
  -- Position in the ordering, 0-based. The primary key, so two steps cannot
  -- claim one rung and the read path takes its order from an index it would
  -- use anyway.
  ordinal integer PRIMARY KEY,

  -- UNIQUE because a progression that revisits a technique is not a
  -- progression. Same foreign key and same absent ON DELETE as `occasions`.
  technique_slug text NOT NULL UNIQUE REFERENCES techniques (slug),

  -- Why this one at this point, empty where the technique's own summary is
  -- enough. Provisional copy, as above.
  note text NOT NULL
);
