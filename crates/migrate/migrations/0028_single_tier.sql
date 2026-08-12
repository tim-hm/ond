-- One paid tier instead of two.
--
-- Plus and Coach sold a ladder nobody buying could see. The line that replaced
-- them is what a use costs to serve, so the enum needs one label and every row
-- that held COACH holds the survivor: those people bought the most expensive
-- thing on offer and must not come out of this with less.
--
-- Postgres cannot drop a label from an enum in use, so the type is rebuilt
-- beside the old one and the column is carried across.

ALTER TYPE subscription_tier RENAME TO subscription_tier_two_products;

CREATE TYPE subscription_tier AS ENUM ('PLUS');

ALTER TABLE users
  ALTER COLUMN subscription_tier TYPE subscription_tier
  USING (CASE WHEN subscription_tier IS NULL THEN NULL ELSE 'PLUS' END)::subscription_tier;

DROP TYPE subscription_tier_two_products;
