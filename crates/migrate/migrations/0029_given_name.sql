-- The name onboarding now asks for, so the app can greet somebody by it.
--
-- Deliberately not `display_name`, which sits two columns away and answers a
-- different question: that one is a public handle the boards print, which is
-- why it carries a unique index, a screening pass, and a collision suffix. This
-- one never leaves the person it belongs to, so it has none of that — no index,
-- no uniqueness, and what was sent is what comes back.
--
-- NULL is "they did not say", and most rows will hold it: the question is
-- optional and one tap away from being skipped. Bounded on the same argument as
-- every other user-writable text column here — a greeting is drawn on one line.

ALTER TABLE users
  ADD COLUMN given_name text CHECK (char_length(given_name) BETWEEN 1 AND 24);
