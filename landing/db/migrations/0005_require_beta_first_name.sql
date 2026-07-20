DELETE FROM flint_beta_email_verifications
WHERE first_name IS NULL
   OR BTRIM(first_name) = ''
   OR CHAR_LENGTH(first_name) > 80;

ALTER TABLE flint_beta_email_verifications
  ALTER COLUMN first_name SET NOT NULL,
  ADD CONSTRAINT flint_beta_email_verifications_first_name_check
    CHECK (BTRIM(first_name) <> '' AND CHAR_LENGTH(first_name) <= 80);

-- Enforce the requirement for new verified signups without invalidating beta
-- rows collected before first-name collection became mandatory.
ALTER TABLE flint_beta_signups
  ADD CONSTRAINT flint_beta_verified_signup_first_name_check
    CHECK (
      email_verified_at IS NULL
      OR (first_name IS NOT NULL AND BTRIM(first_name) <> '' AND CHAR_LENGTH(first_name) <= 80)
    ) NOT VALID;
