CREATE TABLE IF NOT EXISTS flint_licenses (
  id UUID PRIMARY KEY,
  license_key_hash TEXT NOT NULL UNIQUE,
  customer_email TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'revoked', 'expired')),
  product_id TEXT NOT NULL DEFAULT 'flint-macos',
  max_active_devices SMALLINT NOT NULL DEFAULT 1 CHECK (max_active_devices = 1),
  purchased_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS flint_activations (
  id UUID PRIMARY KEY,
  license_id UUID NOT NULL REFERENCES flint_licenses(id) ON DELETE CASCADE,
  device_public_key_hash TEXT NOT NULL,
  device_name TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'revoked')),
  activated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_verified_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  revoked_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS flint_one_active_device_per_license
  ON flint_activations (license_id)
  WHERE status = 'active';

CREATE INDEX IF NOT EXISTS flint_activations_license_id_index
  ON flint_activations (license_id);

CREATE TABLE IF NOT EXISTS flint_license_challenges (
  id UUID PRIMARY KEY,
  device_public_key_hash TEXT NOT NULL,
  nonce_hash TEXT NOT NULL,
  purpose TEXT NOT NULL CHECK (purpose IN ('activate', 'validate', 'deactivate')),
  expires_at TIMESTAMPTZ NOT NULL,
  used_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS flint_license_challenges_expiry_index
  ON flint_license_challenges (expires_at);

CREATE TABLE IF NOT EXISTS flint_activation_transfers (
  id UUID PRIMARY KEY,
  license_id UUID NOT NULL REFERENCES flint_licenses(id) ON DELETE CASCADE,
  previous_activation_id UUID NOT NULL REFERENCES flint_activations(id),
  new_device_public_key_hash TEXT NOT NULL,
  new_device_name TEXT NOT NULL,
  token_hash TEXT NOT NULL UNIQUE,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'confirmed', 'expired', 'cancelled')),
  expires_at TIMESTAMPTZ NOT NULL,
  confirmed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS flint_activation_transfers_license_id_index
  ON flint_activation_transfers (license_id, status);

CREATE TABLE IF NOT EXISTS flint_license_audit_events (
  id UUID PRIMARY KEY,
  license_id UUID REFERENCES flint_licenses(id) ON DELETE SET NULL,
  activation_id UUID REFERENCES flint_activations(id) ON DELETE SET NULL,
  event_type TEXT NOT NULL,
  event_data JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS flint_license_audit_events_license_id_index
  ON flint_license_audit_events (license_id, created_at DESC);
