import assert from "node:assert/strict";
import test from "node:test";

import nextConfig from "../next.config.ts";

const demoAssetOrigin = "https://ee7apxf8lxdpfnbh.public.blob.vercel-storage.com";
const youtubeEmbedOrigin = "https://www.youtube.com";

test("CSP permits the hosted Flint demo video", async () => {
  assert(nextConfig.headers);

  const rules = await nextConfig.headers();
  const contentSecurityPolicy = rules
    .flatMap((rule) => rule.headers)
    .find((header) => header.key === "Content-Security-Policy")?.value;

  assert(contentSecurityPolicy);
  assert.match(contentSecurityPolicy, new RegExp(`frame-src 'self' ${demoAssetOrigin} ${youtubeEmbedOrigin}`));
  assert.match(contentSecurityPolicy, new RegExp(`media-src 'self' ${demoAssetOrigin}`));
});
