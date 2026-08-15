-- A refund belongs to one App Store transaction, not to every renewal in its
-- subscription lineage.
--
-- `originalTransactionId` remains the ownership key: every renewal of one
-- subscription carries it, so it is what lets Restore Purchases find the row
-- already holding that subscription. It cannot identify the payment Apple
-- refunded, though. A refund for an older period may arrive after the next
-- period renewed, and filing it against the lineage either revokes that newer
-- payment or requires a date heuristic that later refunds can escape.
--
-- New revocations therefore use Apple's per-payment `transactionId`. The old
-- table is retained under an explicit legacy name because its rows predate this
-- column and cannot be mapped back to the individual transaction safely. The
-- claim path consults those cutoffs for historical refunds while every new
-- refund is exact.

ALTER TABLE users
  ADD COLUMN app_store_transaction_id text;

ALTER TABLE users
  ADD CONSTRAINT users_app_store_transaction_has_lineage
  CHECK (
    app_store_transaction_id IS NULL
    OR app_store_original_transaction_id IS NOT NULL
  );

ALTER TABLE revoked_transactions
  RENAME TO legacy_revoked_transaction_lineages;

ALTER TABLE legacy_revoked_transaction_lineages
  RENAME CONSTRAINT revoked_transactions_pkey
  TO legacy_revoked_transaction_lineages_pkey;

CREATE TABLE revoked_transactions (
  transaction_id text PRIMARY KEY,
  original_transaction_id text NOT NULL,
  revoked_at timestamptz NOT NULL
);
