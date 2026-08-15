-- Let a protocol own the parts of a session that belong to the protocol rather
-- than to the catalogue exercise it uses.

-- Empty means the exercise keeps its curated rhythm. A populated array carries
-- one duration per phase of the exercise's single cyclic stage; the seed
-- validates that shape before it reaches a client.
ALTER TABLE occasions
  ADD COLUMN phase_durations_ms integer[] NOT NULL DEFAULT '{}'
    CHECK (0 < ALL (phase_durations_ms)),
  ADD COLUMN safety_note text NOT NULL DEFAULT '';

-- Breathing Together was the implementation detail behind this protocol, not
-- a standalone exercise. Preserve the protocol's 3:5 rhythm and child-specific
-- caution on the route, then retire the duplicate catalogue entry.
UPDATE occasions
SET technique_slug = 'extended-exhale',
    phase_durations_ms = ARRAY[3000, 5000],
    safety_note = 'This is for breathing alongside a child, not for teaching one to hold their breath. There are no holds here and none should be added — breath-holding and fast breathing are not for children. Stop if they feel dizzy, or if they have stopped enjoying it.'
WHERE slug = 'with-your-child';

DELETE FROM techniques
WHERE slug = 'breathing-together';
