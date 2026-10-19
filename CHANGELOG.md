# Changelog

All notable changes to the AI Open Overheid Toolkit.

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
