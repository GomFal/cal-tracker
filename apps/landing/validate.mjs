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
const script = read("script.js");
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
  'id="como-funciona"',
  "Una comida. Dos formas de registrarla.",
  "data-flow-comparison",
  'aria-describedby="flow-comparison-description"',
  'data-flow-visual aria-hidden="true"',
  "Aplicaciones de la competencia",
  'flow-lane-label-better flow-animated">Better Calories',
  "better-agent-dot",
  'data-flow-timer="manual"',
  'data-flow-clicks="better"',
];

for (const snippet of requiredSnippets) {
  if (!index.includes(snippet)) fail(`Missing SEO snippet: ${snippet}`);
}

if (index.includes('class="better-mark"')) {
  fail("Ambiguous abstract Better Calories mark must not return");
}

if (index.includes("better-voice-mark")) {
  fail("The agent mark must not regress to a microphone-only symbol");
}

if (index.includes("better-agent-mark") || index.includes("agent-mark-spark")) {
  fail("The Better Calories marker must remain a plain green circle");
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

const flowVisualStart = index.indexOf("<!-- flow-visual-start -->");
const flowVisualEnd = index.indexOf("<!-- flow-visual-end -->");
if (flowVisualStart < 0 || flowVisualEnd <= flowVisualStart) {
  fail("Missing flow comparison visual boundaries");
}

for (const phone of ["manual", "better"]) {
  const screenStart = index.indexOf(`<!-- ${phone}-phone-screen-start -->`);
  const screenEnd = index.indexOf(`<!-- ${phone}-phone-screen-end -->`);
  if (screenStart < 0 || screenEnd <= screenStart) {
    fail(`Missing ${phone} phone screen boundaries`);
  }
  const screenMarkup = index.slice(screenStart, screenEnd);
  const screenText = screenMarkup
    .replace(/<!--[\s\S]*?-->/g, "")
    .replace(/<[^>]+>/g, "")
    .replace(/\s+/g, "");
  if (screenText.length > 0) {
    fail(`${phone} phone screen must not contain visible text`);
  }
}

const flowScriptSnippets = [
  "[data-flow-comparison]",
  "IntersectionObserver",
  "visibilitychange",
  "prefers-reduced-motion: reduce",
  "flowCycleMs = 16000",
  "finishMs: 15040",
  "clicks: [1280, 7360]",
  "data-flow-timer",
];
for (const snippet of flowScriptSnippets) {
  if (!script.includes(snippet)) {
    fail(`Missing flow playback behavior: ${snippet}`);
  }
}

if (!styles.includes("[data-flow-comparison] .flow-animated")) {
  fail("Missing reduced-motion-safe flow animation styles");
}

if (!styles.includes("@keyframes manual-loading")) {
  fail("Missing the traditional-search loading phase");
}

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

console.log("Landing SEO, accessibility, animation, and asset validation passed.");
