-- A refund outlives the row it was granted against.
--
-- 0009 bound one App Store transaction to one identity, and the refund-replay
-- defence was built on top of that binding: a revocation clears the tier while
-- leaving `app_store_original_transaction_id` and `subscription_signed_at` in
-- place, so the pre-refund `jwsRepresentation` — which verifies forever, its
-- payload carrying no revocationDate — loses the ordering comparison and grants
-- nothing. Both halves of that defence are columns on `users`.
--
-- `DeleteAccount` deletes that row. Tap delete, let the client mint a fresh
-- UUID, resubmit the transaction that was refunded: no holder, no ordering
-- marker, and the refunded tier is restored until the period it was refunded
-- for expires. The invariant the replay defence exists to establish — a refund
-- is final — held only for accounts nobody ever deleted.
--
-- So the fact is recorded where erasure cannot reach it. This table is about a
-- transaction rather than about a person: it names something Apple did, carries
-- nothing anybody could be identified by, and is deliberately free of the
-- foreign key that would make it cascade.

CREATE TABLE revoked_transactions (
  -- Apple's `originalTransactionId`, the same key `users` binds and the same
  -- one a resubmission arrives carrying. The primary key is the whole index:
  -- `entitlement::service::claim` reads exactly one row by equality, on the
  -- purchase path, once per submission.
  original_transaction_id text PRIMARY KEY,

  -- Apple's `revocationDate`, and the reason this table stores anything beyond
  -- its key. `originalTransactionId` names a whole subscription lineage rather
  -- than one payment, so presence alone would blacklist every renewal after a
  -- refund; what the claim path compares is the submitted transaction's
  -- `signedDate` against this, which refuses the pre-refund token and admits a
  -- purchase made afterwards.
  --
  -- The first revocation to arrive wins — see `repository::record_revocation` —
  -- so a refund resubmitted years later does not re-date itself.
  revoked_at timestamptz NOT NULL
);
