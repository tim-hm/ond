CREATE TABLE resting_rates (
  user_id uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  client_measurement_id uuid NOT NULL,
  breaths_per_minute integer NOT NULL CHECK (breaths_per_minute >= 4 AND breaths_per_minute <= 60),
  measured_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, client_measurement_id)
);

CREATE INDEX resting_rates_user_rate_idx ON resting_rates (user_id, breaths_per_minute);

ALTER TYPE leaderboard_board ADD VALUE 'RESTING_RATE';
