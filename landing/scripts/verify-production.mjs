import assert from "node:assert/strict";

const baseURL = new URL(process.env.FLINT_PRODUCTION_URL || "https://flint.moyezrabbani.dev");

const requiredPages = [
  "/",
  "/beta",
  "/privacy",
  "/support",
  "/terms",
  "/third-party-notices",
  "/robots.txt",
  "/sitemap.xml",
];

for (const path of requiredPages) {
  const response = await fetch(new URL(path, baseURL), { redirect: "error" });
  assert.equal(response.status, 200, `${path} returned ${response.status}.`);
  assert(response.headers.get("content-security-policy"), `${path} is missing Content-Security-Policy.`);
  assert.equal(response.headers.get("x-content-type-options"), "nosniff", `${path} is missing nosniff.`);
}

const releaseResponse = await fetch(new URL("/api/releases/latest", baseURL));
assert.equal(releaseResponse.status, 200, `Release endpoint returned ${releaseResponse.status}.`);
assert.match(releaseResponse.headers.get("content-type") || "", /application\/json/);
const release = await releaseResponse.json();
assert.equal(release.minimumSystemVersion, "14.0");
assert.deepEqual(release.supportedArchitectures, ["arm64"]);
assert.match(release.sha256, /^[a-f0-9]{64}$/);
assert(new URL(release.downloadURL).protocol === "https:", "Release download page must use HTTPS.");

console.log(`Production surface verified at ${baseURL.origin}.`);
