import type { Metadata, Viewport } from "next";
import "./globals.css";
import { ibmPlexMono, inter, spaceGrotesk } from "./fonts";
import { resolveBaseTheme } from "./lib/theme";

const siteUrl = process.env.NEXT_PUBLIC_SITE_URL ?? "https://flint.moyezrabbani.dev";

export const metadata: Metadata = {
  metadataBase: new URL(siteUrl),
  title: {
    default: "Flint - Local Dictation for Mac",
    template: "%s | Flint",
  },
  description:
    "Flint is a local-first macOS dictation tool that turns your voice into text wherever you type.",
  applicationName: "Flint",
  keywords: ["Mac dictation", "offline transcription", "voice typing", "local AI", "Whisper"],
  alternates: {
    canonical: "/",
  },
  openGraph: {
    type: "website",
    url: "/",
    title: "Flint - Local Dictation for Mac",
    description: "Speak naturally. Flint puts the words where your cursor is.",
    siteName: "Flint",
  },
  twitter: {
    card: "summary_large_image",
    title: "Flint - Local Dictation for Mac",
    description: "Speak naturally. Flint puts the words where your cursor is.",
  },
  robots: {
    index: true,
    follow: true,
  },
};

export const viewport: Viewport = {
  themeColor: "#f5f3ef",
  colorScheme: "light",
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en">
      <body
        className={`${spaceGrotesk.variable} ${inter.variable} ${ibmPlexMono.variable} ${inter.className}`}
        data-base-theme={resolveBaseTheme()}
      >
        {children}
      </body>
    </html>
  );
}
