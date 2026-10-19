#!/usr/bin/env node
/**
 * Fetch CBS district (wijk) and neighbourhood (buurt) boundaries from PDOK,
 * simplify them, and write a compact JSON file that can be embedded in a map page.
 *
 * Why: map pages (artifacts, static HTML) usually cannot fetch data from other
 * websites at view time. The boundaries and figures must be fetched beforehand,
 * made small enough to embed, and shipped with the page. PDOK's "CBS Wijken en
 * Buurten" service also carries the CBS key figures on every feature, so one
 * request gives both the shape and the numbers.
 *
 * Source: https://api.pdok.nl/cbs/wijken-en-buurten-2025/ogc/v1 (OGC API Features)
 * Data licence: CC BY 4.0, source "CBS". No API key required.
 *
 * Usage:
 *   node pdok_area_geometries.mjs --gemeente GM0363 --prefix BU0363F --out nieuw-west.json
 *   node pdok_area_geometries.mjs --gemeente GM0363 --level wijken --tolerance 0.0002
 *
 * Options:
 *   --gemeente   CBS municipality code (required), e.g. GM0363 (Amsterdam)
 *   --level      buurten (default) or wijken
 *   --prefix     keep only features whose code starts with this, e.g. BU0363F (Nieuw-West)
 *   --year       boundary year of the PDOK service (default 2025)
 *   --tolerance  simplification tolerance in degrees (default 0.00012, about 10-15 m)
 *   --fields     comma-separated CBS fields to keep (default: see DEFAULT_FIELDS)
 *   --out        output file (default: stdout)
 *
 * Output format (compact, about 20 KB for the 73 buurten of Nieuw-West):
 *   { source, year, level, origin: [x0, y0], unit: 1e-5,
 *     fields: [...], areas: [[code, name, ...field values, geometry], ...] }
 *   geometry: polygons separated by "/", rings by "|", points by " ".
 *   Each ring starts with an absolute point and continues with deltas, as "dx,dy"
 *   integers in units of 1e-5 degree relative to `origin`. CBS placeholder values
 *   for missing or confidential data (-99997 and similar) are written as null.
 *
 * Decode a ring (JavaScript):
 *   let x = 0, y = 0;
 *   ring.split(" ").map(p => { const [dx, dy] = p.split(",").map(Number);
 *     x += dx; y += dy; return [(x + origin[0]) * unit, (y + origin[1]) * unit]; });
 */

const DEFAULT_FIELDS = [
  "aantal_inwoners",
  "percentage_personen_0_tot_15_jaar",
  "percentage_personen_65_jaar_en_ouder",
  "percentage_eenpersoonshuishoudens",
  "aantal_huishoudens",
];

function parseArgs(argv) {
  const a = {};
  for (let i = 0; i < argv.length; i++) {
    if (argv[i].startsWith("--")) a[argv[i].slice(2)] = argv[i + 1] && !argv[i + 1].startsWith("--") ? argv[++i] : true;
  }
  return a;
}

const args = parseArgs(process.argv.slice(2));
const gemeente = String(args.gemeente || "");
const level = args.level === "wijken" ? "wijken" : "buurten";
const year = String(args.year || "2025");
const prefix = String(args.prefix || "");
const tolerance = Number(args.tolerance || 0.00012);
const fields = args.fields ? String(args.fields).split(",") : DEFAULT_FIELDS;

if (!/^GM\d{4}$/.test(gemeente)) { console.error("Use --gemeente with a CBS code like GM0363."); process.exit(1); }
if (!/^\d{4}$/.test(year)) { console.error("Use --year with four digits, e.g. 2025."); process.exit(1); }
if (prefix && !/^[A-Z0-9]{2,12}$/.test(prefix)) { console.error("Use --prefix with letters and digits only, e.g. BU0363F."); process.exit(1); }
if (!(tolerance >= 0 && tolerance < 0.01)) { console.error("Use --tolerance between 0 and 0.01 degrees."); process.exit(1); }

const BASE = `https://api.pdok.nl/cbs/wijken-en-buurten-${year}/ogc/v1/collections/${level}/items`;
const codeField = level === "wijken" ? "wijkcode" : "buurtcode";
const nameField = level === "wijken" ? "wijknaam" : "buurtnaam";

async function fetchAll() {
  let url = `${BASE}?f=json&limit=1000&gemeentecode=${gemeente}`;
  const out = [];
  for (let page = 0; url && page < 20; page++) {
    const res = await fetch(url, { headers: { Accept: "application/geo+json", "User-Agent": "open-overheid/1.7" } });
    if (!res.ok) throw new Error(`PDOK answered ${res.status} for ${url}`);
    const j = await res.json();
    out.push(...j.features);
    const next = (j.links || []).find(l => l.rel === "next");
    url = next ? next.href : null;
  }
  return out;
}

// Douglas-Peucker line simplification
function simplify(pts, eps) {
  if (pts.length <= 3) return pts;
  let dmax = 0, idx = 0;
  const [a, b] = [pts[0], pts[pts.length - 1]];
  const dx = b[0] - a[0], dy = b[1] - a[1], len = Math.hypot(dx, dy) || 1e-12;
  for (let i = 1; i < pts.length - 1; i++) {
    const d = Math.abs(dy * pts[i][0] - dx * pts[i][1] + b[0] * a[1] - b[1] * a[0]) / len;
    if (d > dmax) { dmax = d; idx = i; }
  }
  if (dmax <= eps) return [a, b];
  const left = simplify(pts.slice(0, idx + 1), eps), right = simplify(pts.slice(idx), eps);
  return left.slice(0, -1).concat(right);
}

function encode(geometry, eps, origin) {
  const polys = geometry.type === "Polygon" ? [geometry.coordinates] : geometry.coordinates;
  return polys.map(poly => poly.map(ring => {
    let s = simplify(ring, eps);
    if (s.length < 4) s = ring;
    let px = 0, py = 0;
    return s.map(([lon, lat]) => {
      const x = Math.round(lon * 1e5) - origin[0], y = Math.round(lat * 1e5) - origin[1];
      const o = `${x - px},${y - py}`; px = x; py = y; return o;
    }).join(" ");
  }).join("|")).join("/");
}

const clean = v => (typeof v === "number" && v <= -99990) || v === "-99997" || v == null ? null : v;

const features = (await fetchAll()).filter(f => !prefix || String(f.properties[codeField]).startsWith(prefix));
if (!features.length) { console.error("No areas found. Check --gemeente, --level and --prefix."); process.exit(1); }

// Origin: rounded minimum of all coordinates, so deltas stay small and positive at the start
let minX = Infinity, minY = Infinity;
for (const f of features) {
  const polys = f.geometry.type === "Polygon" ? [f.geometry.coordinates] : f.geometry.coordinates;
  for (const poly of polys) for (const ring of poly) for (const [x, y] of ring) { minX = Math.min(minX, x); minY = Math.min(minY, y); }
}
const origin = [Math.floor(minX * 100) * 1000, Math.floor(minY * 100) * 1000];

const result = {
  source: `CBS, Kerncijfers wijken en buurten ${year}, via PDOK (CC BY 4.0)`,
  year: Number(year), level, origin, unit: 1e-5,
  fields: ["code", "name", ...fields, "geometry"],
  areas: features.map(f => [
    f.properties[codeField], f.properties[nameField],
    ...fields.map(k => clean(f.properties[k])),
    encode(f.geometry, tolerance, origin),
  ]),
};

const json = JSON.stringify(result);
if (args.out) {
  const { writeFileSync } = await import("node:fs");
  writeFileSync(String(args.out), json);
  console.error(`Wrote ${features.length} ${level} (${json.length} bytes) to ${args.out}`);
} else {
  process.stdout.write(json + "\n");
}
