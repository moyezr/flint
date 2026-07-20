const maximumEmailLocalPartLength = 64;
const maximumEmailLength = 320;

export function disposableBetaTestEmail(email, entropy) {
  const trimmedEmail = email.trim();
  const separator = trimmedEmail.lastIndexOf("@");
  if (separator <= 0 || separator === trimmedEmail.length - 1) {
    throw new Error("FLINT_BETA_TEST_EMAIL must be a valid email address.");
  }

  const local = trimmedEmail.slice(0, separator).split("+")[0];
  const domain = trimmedEmail.slice(separator + 1);
  const compactEntropy = entropy.replaceAll(/[^a-zA-Z0-9]/g, "").slice(0, 12).toLocaleLowerCase("en-US");
  if (!compactEntropy) {
    throw new Error("The beta verifier could not create a unique email suffix.");
  }

  const disposableLocal = `${local}+flint-${compactEntropy}`;
  const disposableEmail = `${disposableLocal}@${domain}`;
  if (disposableLocal.length > maximumEmailLocalPartLength || disposableEmail.length > maximumEmailLength) {
    throw new Error(
      "FLINT_BETA_TEST_EMAIL is too long to add a disposable test suffix. Use a shorter plus-addressable inbox.",
    );
  }
  return disposableEmail;
}
