-- A Sign in with Apple identity token is accepted only when its nonce matches
-- a short-lived ceremony this server issued to the same caller for the same
-- purpose. The raw nonce is returned once and never stored; only its SHA-256
-- reaches this table.

CREATE TYPE apple_authorization_purpose AS ENUM ('SIGN_IN', 'DELETE_ACCOUNT');

CREATE TABLE apple_authorization_challenges (
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  purpose apple_authorization_purpose NOT NULL,
  nonce_hash bytea NOT NULL UNIQUE CHECK (octet_length(nonce_hash) = 32),
  expires_at timestamptz NOT NULL,

  -- A newer ceremony for the same action replaces the older one. This bounds
  -- storage to two rows per identity and makes a second sheet invalidate the
  -- nonce from the first rather than leaving both live.
  PRIMARY KEY (user_id, purpose)
);

