import type { Metadata } from "next";
import {
  Fraunces,
  Geist,
  Geist_Mono,
  Noto_Serif_Devanagari,
} from "next/font/google";
import "./globals.css";

const fraunces = Fraunces({
  variable: "--font-fraunces",
  subsets: ["latin"],
  axes: ["opsz"],
  weight: "variable",
  display: "swap",
});

const geist = Geist({
  variable: "--font-geist",
  subsets: ["latin"],
  weight: ["400", "500"],
  display: "swap",
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
  weight: ["400", "500"],
  display: "swap",
});

const devanagari = Noto_Serif_Devanagari({
  variable: "--font-devanagari",
  subsets: ["devanagari", "latin"],
  weight: ["400", "500"],
  display: "swap",
});

const description =
  "Vani is local voice dictation for macOS. Hold a key, speak, and your exact words appear in whatever app you're typing in — transcribed on your machine, never sent off it.";

export const metadata: Metadata = {
  // Update when the custom domain (vani.rahulbhardwaj.dev) is wired up.
  metadataBase: new URL("https://the-vani-app.vercel.app"),
  title: "Vani — local dictation for macOS that never rewrites you",
  description,
  openGraph: {
    title: "Vani (वाणी) — it never rewrites you",
    description,
    type: "website",
  },
  twitter: {
    card: "summary_large_image",
    title: "Vani (वाणी) — it never rewrites you",
    description,
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html
      lang="en"
      className={`${fraunces.variable} ${geist.variable} ${geistMono.variable} ${devanagari.variable}`}
      suppressHydrationWarning
    >
      <head>
        {/* Re-apply a persisted dark choice before first paint so dark
            visitors never see a paper flash. Light needs no attribute. */}
        <script
          dangerouslySetInnerHTML={{
            __html: `try{if(localStorage.getItem("vani-theme")==="dark")document.documentElement.dataset.theme="dark"}catch(e){}`,
          }}
        />
      </head>
      <body>{children}</body>
    </html>
  );
}
