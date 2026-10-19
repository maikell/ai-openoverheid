# Changelog

All notable changes to the AI Open Overheid Toolkit.

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
