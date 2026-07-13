import type { Metadata } from "next";
import Link from "next/link";

import { spaceGrotesk } from "../fonts";
import { TransferConfirmation } from "./transfer-confirmation";

export const metadata: Metadata = {
  title: "Confirm Device Transfer",
  robots: { index: false, follow: false },
};

export default async function LicenseTransferPage({
  searchParams,
}: {
  searchParams: Promise<{ token?: string }>;
}) {
  const { token } = await searchParams;
  return (
    <main className="transfer-page">
      <section className="transfer-panel" aria-labelledby="transfer-title">
        <Link className={`wordmark ${spaceGrotesk.className}`} href="/" aria-label="Flint home">FLINT<span aria-hidden="true">/</span></Link>
        <p className="eyebrow">LICENSE SECURITY</p>
        <h1 className={spaceGrotesk.className} id="transfer-title">Confirm device transfer.</h1>
        <p>
          This will deactivate Flint on the currently active Mac and allow the new Mac to finish activation.
        </p>
        <TransferConfirmation token={token ?? ""} />
      </section>
    </main>
  );
}
