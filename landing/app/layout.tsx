import type { Metadata, Viewport } from "next";
import "./globals.css";
import { ibmPlexMono, inter, spaceGrotesk } from "../lib/fonts";
import { resolveBaseTheme } from "./lib/theme";
import { cn } from "@/lib/utils";
import { Analytics } from "@vercel/analytics/next"
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
  icons: {
    icon: [
      { url: "/favicon.ico", sizes: "16x16 32x32 48x48" },
      { url: "/icon.png", type: "image/png", sizes: "512x512" },
    ],
    apple: [{ url: "/apple-icon.png", type: "image/png", sizes: "180x180" }],
  },
  openGraph: {
    type: "website",
    url: "/",
    title: "Flint - Local Dictation for Mac",
    description: "Speak naturally. Flint puts the words where your cursor is.",
    siteName: "Flint",
    images: [
      {
        url: "/og_image.webp",
        width: 1450,
        height: 747,
        alt: "Flint — local dictation for Mac",
        type: "image/webp",
      },
    ],
  },
  twitter: {
    card: "summary_large_image",
    title: "Flint - Local Dictation for Mac",
    description: "Speak naturally. Flint puts the words where your cursor is.",
    images: [
      {
        url: "/og_image.webp",
        width: 1450,
        height: 747,
        alt: "Flint — local dictation for Mac",
      },
    ],
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
    <html lang="en" className={cn("font-sans", inter.variable)}>
      <body
        className={`${spaceGrotesk.variable} ${inter.variable} ${ibmPlexMono.variable} ${inter.className}`}
        data-base-theme={resolveBaseTheme()}
      >
    
        {children}
      </body>
    </html>
  );
}
