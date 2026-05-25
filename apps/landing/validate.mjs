import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

const root = new URL(".", import.meta.url).pathname;
const files = [
  "index.html",
  "download.html",
  "styles.css",
  "script.js",
  "robots.txt",
  "sitemap.xml",
  "site.webmanifest",
];

const read = (file) => readFileSync(join(root, file), "utf8");
const fail = (message) => {
  throw new Error(message);
};

for (const file of files) {
  if (!existsSync(join(root, file))) fail(`Missing ${file}`);
}

const index = read("index.html");
const styles = read("styles.css");
const robots = read("robots.txt");
const sitemap = read("sitemap.xml");
const manifest = JSON.parse(read("site.webmanifest"));

const requiredSnippets = [
  '<html lang="es">',
  "<h1 id=\"hero-title\">Better Calories</h1>",
  '<link rel="canonical" href="https://bettercalories.app/">',
  '<meta name="robots" content="index, follow, max-image-preview:large">',
  '<meta property="og:type" content="website">',
  '<meta name="twitter:card" content="summary_large_image">',
  "application/ld+json",
];

for (const snippet of requiredSnippets) {
  if (!index.includes(snippet)) fail(`Missing SEO snippet: ${snippet}`);
}

const title = index.match(/<title>(.*?)<\/title>/)?.[1] ?? "";
if (title.length < 35 || title.length > 65) {
  fail(`Title should stay search-result friendly, got ${title.length} chars`);
}

const description =
  index.match(/<meta\s+name="description"\s+content="([^"]+)"/)?.[1] ?? "";
if (description.length < 110 || description.length > 165) {
  fail(`Description should stay useful in SERPs, got ${description.length} chars`);
}

const jsonLd = index.match(
  /<script type="application\/ld\+json">\s*([\s\S]*?)\s*<\/script>/,
)?.[1];
if (!jsonLd) fail("Missing JSON-LD");
JSON.parse(jsonLd);

const imageTags = [...index.matchAll(/<img\b[^>]*>/g)].map(([tag]) => tag);
for (const tag of imageTags) {
  if (!/\salt=/.test(tag)) fail(`Image without alt attribute: ${tag}`);
}

const localAssets = [
  "assets/brand-icon.png",
  "assets/icon-192.png",
  "assets/icon-512.png",
  "assets/fresh-food-01.webp",
  "assets/fresh-food-02.webp",
  "assets/fresh-food-03.webp",
  "assets/meal-breakfast.webp",
  "assets/meal-lunch.webp",
  "favicon.ico",
];

for (const asset of localAssets) {
  if (!existsSync(join(root, asset))) fail(`Missing asset ${asset}`);
}

if (!robots.includes("Sitemap: https://bettercalories.app/sitemap.xml")) {
  fail("robots.txt does not point to sitemap");
}

if (!sitemap.includes("<loc>https://bettercalories.app/</loc>")) {
  fail("sitemap.xml does not include canonical homepage");
}

if (manifest.name !== "Better Calories" || manifest.lang !== "es") {
  fail("site.webmanifest identity mismatch");
}

const combined = [index, read("download.html"), styles].join("\n");
if (combined.includes("\u2014")) {
  fail("Landing copy must not use em dashes");
}

if (/#(?:000|fff)\b/i.test(styles)) {
  fail("Use tinted neutrals instead of pure black or pure white in CSS");
}

if (/font-size\s*:[^;]*vw/i.test(styles)) {
  fail("Font sizes must not scale directly with viewport width");
}

console.log("Landing SEO and asset validation passed.");
