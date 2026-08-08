-- Once a row is bound to an Apple account, possession of its id stops being
-- enough to use it.
--
-- 0004 wrote down the trade this closes: "Nothing here is a credential —
-- possession of the id is the whole of the claim". That held while the id
-- reached nothing but an anonymous practice history on one device. It stopped
-- holding when 0007 hung a subscription off the same id and TIM-6 put it on the
-- Settings screen with a copy button, so the value a person is invited to paste
-- into a support email became the whole of the claim to a paid account.
--
-- An Apple identity token cannot be the credential on the request path: Apple
-- expires one in ten minutes and offers no silent refresh, so demanding one per
-- request means a system sign-in sheet every ten minutes of use. This table is
-- what a verified sign-in mints instead.
--
-- Anonymous identities are untouched. A row with no `apple_user_id` has nothing
-- to prove and gets no row here, which is why the table is separate rather than
-- two more columns on `users`.

CREATE TABLE user_sessions (
  -- SHA-256 of the credential, and never the credential itself. A leak of this
  -- table is then a leak of nothing usable: the client holds 256 random bits,
  -- so there is no dictionary to run against a hash and no key to sign with.
  -- The primary key is the whole index — `identity::resolve` reads one row by
  -- equality on this, on the path of every request from a signed-in caller.
  token_hash bytea PRIMARY KEY,

  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,

  -- Never read by the request path. It is here so an operator answering "when
  -- did this device sign in" has an answer, and so a future policy that expires
  -- an idle credential has something to expire against.
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Postgres does not index a foreign key for you, and `DeleteAccount` erases a
-- signed-in row — so without this the cascade scans every credential in the
-- system to find the one it is deleting.
CREATE INDEX user_sessions_user_id_idx ON user_sessions (user_id);
