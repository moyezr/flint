export function betaDownloadFormIsReady(input: {
  firstName: string;
  email: string;
  acceptedTerms: boolean;
  verificationID: string | null;
  verificationCode: string;
  pendingDownloadURL: string | null;
}): boolean {
  if (input.pendingDownloadURL) {
    return true;
  }
  if (input.verificationID) {
    return /^\d{6}$/u.test(input.verificationCode);
  }
  return input.firstName.trim().length > 0
    && /^[^\s@]+@[^\s@]+\.[^\s@]+$/u.test(input.email.trim())
    && input.acceptedTerms;
}
