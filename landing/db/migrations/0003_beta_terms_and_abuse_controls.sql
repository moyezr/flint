ALTER TABLE flint_beta_signups
  ADD COLUMN IF NOT EXISTS terms_version TEXT,
  ADD COLUMN IF NOT EXISTS terms_accepted_at TIMESTAMPTZ;

CREATE TABLE IF NOT EXISTS flint_api_rate_limits (
  key_hash TEXT NOT NULL,
  window_started_at TIMESTAMPTZ NOT NULL,
  request_count INTEGER NOT NULL CHECK (request_count > 0),
  expires_at TIMESTAMPTZ NOT NULL,
  PRIMARY KEY (key_hash, window_started_at)
);

CREATE INDEX IF NOT EXISTS flint_api_rate_limits_expiry_index
  ON flint_api_rate_limits (expires_at);
