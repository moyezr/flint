ALTER TABLE flint_beta_signups
  ADD COLUMN IF NOT EXISTS first_name TEXT,
  ADD COLUMN IF NOT EXISTS last_name TEXT,
  ADD COLUMN IF NOT EXISTS email_verified_at TIMESTAMPTZ;

CREATE TABLE IF NOT EXISTS flint_beta_email_verifications (
  id UUID PRIMARY KEY,
  email TEXT NOT NULL,
  normalized_email TEXT NOT NULL,
  first_name TEXT,
  last_name TEXT,
  source TEXT NOT NULL,
  marketing_consent BOOLEAN NOT NULL DEFAULT FALSE,
  terms_version TEXT NOT NULL,
  terms_accepted_at TIMESTAMPTZ NOT NULL,
  code_hash TEXT NOT NULL,
  attempt_count INTEGER NOT NULL DEFAULT 0 CHECK (attempt_count >= 0 AND attempt_count <= 5),
  expires_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS flint_beta_email_verifications_email_index
  ON flint_beta_email_verifications (normalized_email);

CREATE INDEX IF NOT EXISTS flint_beta_email_verifications_expiry_index
  ON flint_beta_email_verifications (expires_at);
