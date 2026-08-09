-- An id a sign-in merge folded away must stay dead, and this table is how the
-- middleware knows one.
--
-- `identity::resolve` recreates any well-formed unseen id as a fresh anonymous
-- row, which is right for an id a device just minted and wrong for one whose
-- history has moved to an account. The device that loses that distinction is
-- the watch: sessions recorded away from the phone go out under the old id
-- when the watch launches before the phone has handed it the adopted one, and
-- a recreated row would accept them — acknowledged into the watch's ledger,
-- filed on an orphan no sign-in can ever find again. The merge's `FOR UPDATE`
-- only covers writes in flight during its transaction; this covers every
-- request after it commits.

CREATE TABLE merged_identities (
  -- The id the merge deleted from `users`. One live row per retired id:
  -- `identity::resolve` refuses a tombstoned id, so it cannot re-enter
  -- circulation while its tombstone lives, and the cascade below clears the
  -- row before the id could ever retire again.
  id uuid PRIMARY KEY,

  -- The account the history moved to. Never disclosed to a caller presenting
  -- the dead id — possession of a retired id is not a claim to the account it
  -- fed. ON DELETE CASCADE: erasing the account takes its tombstones with it,
  -- returning the old ids to the ordinary recreate-empty path — the same
  -- answer `DeleteAccount` already gives the id it erases directly.
  merged_into uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,

  -- Never read by the request path; an operator answering "when did this id
  -- retire" has an answer.
  merged_at timestamptz NOT NULL DEFAULT now()
);

-- Postgres does not index a foreign key for you, and `DeleteAccount` erases
-- the surviving account — without this the cascade scans every tombstone to
-- find the ones it is deleting.
CREATE INDEX merged_identities_merged_into_idx ON merged_identities (merged_into);
