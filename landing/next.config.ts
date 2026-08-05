import type { NextConfig } from "next";

// React/Turbopack uses eval and a WebSocket for development diagnostics and
// hot reload. Keep both out of the production policy.
const isDevelopment = process.env.NODE_ENV === "development";
const demoAssetOrigin = "https://ee7apxf8lxdpfnbh.public.blob.vercel-storage.com";
const youtubeEmbedOrigin = "https://www.youtube.com";

const contentSecurityPolicy = [
  "default-src 'self'",
  "base-uri 'self'",
  `connect-src 'self'${isDevelopment ? " ws:" : ""}`,
  "font-src 'self'",
  "form-action 'self'",
  `frame-src 'self' ${demoAssetOrigin} ${youtubeEmbedOrigin}`,
  "frame-ancestors 'none'",
  "img-src 'self' data: blob:",
  `media-src 'self' ${demoAssetOrigin}`,
  "object-src 'none'",
  `script-src 'self' 'unsafe-inline'${isDevelopment ? " 'unsafe-eval'" : ""}`,
  "style-src 'self' 'unsafe-inline'",
  ...(isDevelopment ? [] : ["upgrade-insecure-requests"]),
].join("; ");

const securityHeaders = [
  { key: "Content-Security-Policy", value: contentSecurityPolicy },
  { key: "Cross-Origin-Opener-Policy", value: "same-origin" },
  { key: "Permissions-Policy", value: "camera=(), geolocation=(), microphone=()" },
  { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
  { key: "X-Content-Type-Options", value: "nosniff" },
  { key: "X-Frame-Options", value: "DENY" },
];

const nextConfig: NextConfig = {
  poweredByHeader: false,
  async headers() {
    return [
      {
        source: "/:path*",
        headers: securityHeaders,
      },
    ];
  },
};

export default nextConfig;
