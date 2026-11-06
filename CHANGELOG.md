# Changelog

All notable changes to the AI Open Overheid Toolkit.

## 1.9.1 – 2026-11-06

### Fixed
- **`amsterdam-kerncijfers` script: indicator and area codes are no longer case-sensitive.** `--indicator bevtotaal --gebied f` now returns the same as `BEVTOTAAL` / `F`. The exact code is resolved from `indicators.json` before the data is fetched.
  - *Why:* the API's file names are case-sensitive, so a lowercase code gave a bare `404 Not Found` while the metadata lookup in the same script already ignored case.
- **Clear error for an unknown indicator**, pointing to `--search`, instead of `API error 404`.
- **Deprecated indicators are marked.** `--search` lists them last with `[VERVALLEN <date>]`, and a lookup prints the reason (`deprecatedReason`), which usually names the replacement. `SKILL.md` tells the assistant to prefer current indicators.
  - *Why:* 143 of the 1,081 indicators are deprecated and were shown without any warning, so old figures could be presented as current.

### Changed
- `amsterdam-kerncijfers` script: the User-Agent names the toolkit (`ai-openoverheid/1.9.1`) instead of `Antigravity-Agent/1.0`, and the `Stadsdeel:` line is only shown for areas that belong to a district, with its code.

## 1.9.0 – 2026-11-06

### Added
- **`amsterdam-notubiz` skill** with `skills/amsterdam-notubiz/scripts/archive_meeting.ps1`: downloads the agenda and all documents of one NotuBiz meeting (city council, committees, college van B&W, district committees) into a local folder per meeting. Every file is checked by SHA-256; unchanged files are skipped, changed files are filed as `Name (v2)`, `(v3)`, … and the original is never overwritten. Each folder gets a `README.md` (files, sizes, hashes, change log) and a `manifest.json`.
- **MCP tool `archive_meeting`** in the `amsterdam-raadsinformatie` server, which runs the same script. Arguments: `event_id` or `organisation_id` (+ optional `category`), optional absolute `root` or `target_dir`, and `dry_run`. The default folder can be set with the environment variable `OPEN_OVERHEID_ARCHIVE_ROOT`. IDs must be positive integers, paths absolute without `..`.
- **`docs/architecture-v2.png` updated** for 1.9.0 (11 skills, `archive_meeting`, NotuBiz for Amsterdam and Stadsdeel Nieuw-West), with its HTML source `docs/architecture-v2.html` so it can be regenerated.
  - *Why (tool):* in Claude Desktop the assistant has no terminal on the user's computer, but the MCP servers do run there. The tool makes archiving work the same way in Claude Desktop, Claude Code and Antigravity.
  - *Why:* the `raadsinformatie` skill finds meetings and links, but following a committee over time needs the documents themselves, filed consistently and with proof of what changed between runs. The agenda is written as Markdown from the API instead of the website's PDF export, because every PDF export gets new timestamps and therefore a new hash even when nothing changed.

## 1.8.0 – 2026-10-20

### Added
- **`lokale-regelgeving` skill and MCP server** (`lr_zoek_regelingen`, `lr_inhoudsopgave`, `lr_artikel`) for the consolidated local regulations in CVDR, such as the Amsterdam APV, filtered on the date they apply. Reference: `skills/lokale-regelgeving/references/cvdr_sru_reference.md`.
  - *Why:* the toolkit could find the Gemeenteblad decisions that change a regulation, but not the text that applies today, which only CVDR provides. CVDR keeps every version (more than 70 for the Amsterdam APV), so the tools filter on today by default. The service uses `overheidrg.keyword` instead of `cql.textAndIndexes` and stores article numbers in two ways; both are handled so searches and article lookups do not fail silently.
- **`bag` skill and MCP server** (`bag_zoek_adres`, `bag_adresinfo`, `bag_pand`) for addresses and buildings from the BAG via PDOK: official address, use, floor area, construction year, units per building, all addresses of an object, and the CBS neighbourhood and district codes. Reference: `skills/bag/references/bag_pdok_reference.md`.
  - *Why:* almost every question in this toolkit starts from an address, but there was no authoritative source for what is registered there. The returned CBS area codes link an address directly to statistics and maps. Free-text geocoding ranked the wrong address first in a test ("Amstel 1 Amsterdam" returned Amstel 312A-1), so the tools prefer exact postcode + house number and return candidates instead of guessing. One object can have several addresses (the Stopera is Amstel 1 and Waterlooplein 6); all are returned.
- **`docs/architecture-v2.png`**: overview diagram of the skills and MCP servers, shown in both READMEs.
  - *Why:* the previous diagram showed only five components and Antigravity as the only host.

### Changed
- **All `SKILL.md` files are written in English.** Dutch official names (Woo, APV, Gemeenteblad, Raad van State) and Dutch API field names are kept as they are.
  - *Why:* the toolkit is public and AI-agnostic. English instructions are read most reliably by every assistant (Gemini and Claude) and by contributors outside the Netherlands, and match the English README. The skill files previously mixed Dutch and English.

## 1.7.0

### Added
- `cbs` skill: section **Maps of CBS figures** and the script `skills/cbs/scripts/pdok_area_geometries.mjs`, which fetches district and neighbourhood boundaries with CBS key figures from PDOK, simplifies them and writes a compact JSON file for embedding in a map page.
- `references/cbs-statline.md`: section 10 on the PDOK source, the encoding format and size guidance.

### Why
- A test map of the 73 neighbourhoods of Amsterdam Nieuw-West showed that a full interactive choropleth map can be built from open data alone, so a hosted map connector such as Felt is not needed and would add an account requirement.
- Published map pages usually cannot fetch data from other websites while being viewed. Without explicit guidance, assistants write pages that try to load live data and show an empty map. The skill now explains how to prepare and embed the data instead.
- PDOK's CBS Wijken en Buurten service delivers boundaries and key figures together with the same area codes as the `cbs` tools, which keeps maps and tables consistent.

## 1.6.0
- Added the `cbs` skill and MCP server for CBS StatLine statistics (OData v4, no key, CC BY 4.0).

## 1.5.0
- Added the `raadsinformatie` skill and MCP server for council and district committee meetings (NotuBiz), with integer validation of IDs.

## 1.4.0
- Input validation in the Woo server, English and Dutch READMEs, Claude plugin and marketplace manifests, and installation instructions for Antigravity and Claude.
