import type { Metadata } from "next";
import Link from "next/link";

import { spaceGrotesk } from "../../lib/fonts";
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
    <main className="grid min-h-screen place-items-center bg-mist p-6 max-[520px]:p-6">
      <section className="w-full max-w-[620px] border border-ink bg-paper p-9 max-[520px]:p-[26px]" aria-labelledby="transfer-title">
        <Link className={`${spaceGrotesk.className} mb-[72px] inline-flex text-[23px] leading-none font-bold`} href="/" aria-label="Flint home">FLINT<span className="text-signal" aria-hidden="true">/</span></Link>
        <p className="mb-[22px] font-mono text-[11px] font-semibold text-signal tabular-nums">LICENSE SECURITY</p>
        <h1 className={`${spaceGrotesk.className} mb-5 text-[56px] leading-[0.95] font-semibold max-[520px]:text-[44px]`} id="transfer-title">Confirm device transfer.</h1>
        <p className="mb-[34px] text-[17px] leading-[1.5] text-muted">
          This will deactivate Flint on the currently active Mac and allow the new Mac to finish activation.
        </p>
        <TransferConfirmation token={token ?? ""} />
      </section>
    </main>
  );
}
