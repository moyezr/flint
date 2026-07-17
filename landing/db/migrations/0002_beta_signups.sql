CREATE TABLE IF NOT EXISTS flint_beta_signups (
  id UUID PRIMARY KEY,
  email TEXT NOT NULL,
  normalized_email TEXT NOT NULL UNIQUE,
  source TEXT NOT NULL DEFAULT 'landing',
  beta_access_consented_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  marketing_consented_at TIMESTAMPTZ,
  download_count INTEGER NOT NULL DEFAULT 0 CHECK (download_count >= 0),
  last_downloaded_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS flint_beta_signups_created_at_index
  ON flint_beta_signups (created_at DESC);

CREATE TABLE IF NOT EXISTS flint_beta_download_tokens (
  token_hash TEXT PRIMARY KEY,
  signup_id UUID NOT NULL REFERENCES flint_beta_signups(id) ON DELETE CASCADE,
  expires_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS flint_beta_download_tokens_expiry_index
  ON flint_beta_download_tokens (expires_at);
