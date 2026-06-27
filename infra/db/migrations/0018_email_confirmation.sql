ALTER TABLE users
  ADD COLUMN IF NOT EXISTS email_verified_at timestamptz;

UPDATE users
SET email_verified_at = created_at
WHERE email_verified_at IS NULL;

CREATE TABLE IF NOT EXISTS pending_registrations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email text NOT NULL,
  display_name text NOT NULL,
  password_hash text NOT NULL,
  token_hash text NOT NULL,
  expires_at timestamptz NOT NULL,
  consumed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS pending_registrations_active_email_unique
  ON pending_registrations (lower(email))
  WHERE consumed_at IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS pending_registrations_active_token_unique
  ON pending_registrations (token_hash)
  WHERE consumed_at IS NULL;
