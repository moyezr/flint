import type { Metadata } from "next";
import Link from "next/link";

import { spaceGrotesk } from "@/lib/fonts";

const appComponents = [
  { name: "Argmax OSS / WhisperKit", license: "MIT", href: "https://github.com/argmaxinc/argmax-oss-swift" },
  { name: "swift-transformers portions incorporated by Argmax OSS", license: "Apache License 2.0", href: "https://github.com/huggingface/swift-transformers" },
  { name: "Swift Argument Parser", license: "Apache License 2.0 with Runtime Library Exception", href: "https://github.com/apple/swift-argument-parser" },
];

const websiteComponents = [
  ["Base UI", "MIT"],
  ["Class Variance Authority", "Apache License 2.0"],
  ["clsx", "MIT"],
  ["GSAP", "GSAP Standard License"],
  ["Lucide", "ISC"],
  ["Next.js", "MIT"],
  ["Postgres.js", "Unlicense"],
  ["React and React DOM", "MIT"],
  ["Resend Node.js SDK", "MIT"],
  ["shadcn", "MIT"],
  ["tailwind-merge", "MIT"],
  ["tw-animate-css", "MIT"],
  ["Zod", "MIT"],
] as const;

export const metadata: Metadata = {
  title: "Third-Party Notices",
  description: "Open-source and third-party software acknowledgements for Flint.",
};

export default function ThirdPartyNoticesPage() {
  return (
    <main className="min-h-screen bg-paper px-6 py-16 text-ink">
      <article className="mx-auto max-w-[760px]">
        <Link className="font-mono text-[11px] font-semibold text-signal" href="/">← FLINT</Link>
        <p className="mt-16 mb-5 font-mono text-[11px] font-semibold text-signal">LEGAL / ATTRIBUTION</p>
        <h1 className={`${spaceGrotesk.className} text-[64px] leading-[0.95] font-semibold max-[520px]:text-[44px]`}>
          Third-party notices.
        </h1>
        <p className="mt-7 text-lg leading-[1.65] text-muted">Last updated: July 20, 2026.</p>

        <section className="mt-16 border-t border-line pt-9">
          <h2 className={`${spaceGrotesk.className} text-3xl font-semibold`}>Flint macOS application</h2>
          <p className="mt-4 leading-[1.7] text-muted">
            Flint includes the following third-party software. Copyright and license text files are also included in each newly packaged Flint.app under Contents/Resources.
          </p>
          <ul className="mt-5 grid gap-3 pl-5 leading-[1.7] text-muted">
            {appComponents.map((component) => (
              <li key={component.name}>
                <a className="border-b border-current text-ink" href={component.href}>{component.name}</a> — {component.license}
              </li>
            ))}
          </ul>
        </section>

        <section className="mt-14 border-t border-line pt-9">
          <h2 className={`${spaceGrotesk.className} text-3xl font-semibold`}>Website and service</h2>
          <p className="mt-4 leading-[1.7] text-muted">
            The Flint website and its server-side download and licensing service use these direct production dependencies:
          </p>
          <ul className="mt-5 grid gap-3 pl-5 leading-[1.7] text-muted">
            {websiteComponents.map(([name, license]) => <li key={name}>{name} — {license}</li>)}
          </ul>
        </section>

        <section className="mt-14 border-t border-line pt-9">
          <h2 className={`${spaceGrotesk.className} text-3xl font-semibold`}>Scope</h2>
          <p className="mt-4 leading-[1.7] text-muted">
            These acknowledgements do not imply endorsement by any third-party project or trademark owner. Third-party license terms apply only to their respective components and do not license Flint&apos;s original proprietary code, name, or assets.
          </p>
        </section>
      </article>
    </main>
  );
}
