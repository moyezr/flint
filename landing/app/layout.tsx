import type { Metadata, Viewport } from "next";
import { IBM_Plex_Mono, Inter, Space_Grotesk } from "next/font/google";
import "./globals.css";

const siteUrl = process.env.NEXT_PUBLIC_SITE_URL ?? "https://flint.moyezrabbani.dev";

const spaceGrotesk = Space_Grotesk({
  variable: "--font-space-grotesk",
  subsets: ["latin"],
  display: "swap",
});

const inter = Inter({
  variable: "--font-inter",
  subsets: ["latin"],
  display: "swap",
});

const ibmPlexMono = IBM_Plex_Mono({
  variable: "--font-ibm-plex-mono",
  subsets: ["latin"],
  weight: ["400", "500", "600"],
  display: "swap",
});

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
      <body className={`${spaceGrotesk.variable} ${inter.variable} ${ibmPlexMono.variable}`}>{children}</body>
    </html>
  );
}
