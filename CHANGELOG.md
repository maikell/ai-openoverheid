# Changelog

All notable changes to the AI Open Overheid Toolkit.

## 1.10.1 – 2026-11-17

### Changed
- **`mcp_config.example.json` no longer depends on the user name.** Each server now starts as `powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "& (Join-Path $HOME '.gemini/config/plugins/open-overheid/mcp/<server>.ps1')"`: PowerShell itself resolves `$HOME` when the server starts, so the same `mcp_config.json` works on every computer and every account.
  - *Why:* the toolkit runs on computers with different Windows user names. The old template used `${env:USERPROFILE}`, which not every Antigravity build expands, so in practice every computer needed its own hand-edited path.

### Added
- **`install.ps1`**: installs or updates the toolkit for Antigravity on any computer in one command (also runnable straight from GitHub). It clones into `<home>/.gemini/config/plugins/open-overheid` or runs `git pull --ff-only`, writes the user-name independent server entries into `mcp_config.json` (servers you added yourself are kept, an existing BOM is preserved), and runs the smoke test against that file. If the `-Command` form fails on a computer, it falls back to absolute `-File` paths and tests again. `-Offline`, `-SkipTest`, `-PluginsDir` and `-UpdateClaudeCode` are optional.
  - *Why:* with 1.10.0 adding a server, a plain `git pull` was no longer enough; new servers also had to be copied into `mcp_config.json` by hand, on every computer.
- **`docs/features.png`** (source `docs/features.html`): an infographic in Dutch of what the toolkit supports, grouped by theme, with new features marked; shown at the top of both READMEs.
  - *Why:* the architecture diagram shows servers and tools, not what a user can ask; with 13 skills that had become hard to see.
- **`tests/smoke_test.ps1 -Config <file>`** tests the servers exactly as a given MCP config starts them (command and arguments as written), instead of only via `.mcp.json`.
  - *Why:* the Antigravity config starts the servers differently from the Claude plugin; a passing Claude test said nothing about it.

## 1.10.0 – 2026-11-17

### Added
- **`raadsarchief` skill and MCP server** (`archive_index`, `archive_search`, `motions_sync`, `motions_search`), with the shared logic in `skills/raadsarchief/scripts/raadsarchief_lib.ps1` and a command line in `raadsarchief.ps1`.
  - `archive_index` builds an incremental full-text index in `<archive>/_index/` over the meeting folders written by `archive_meeting` (Markdown agendas, PDF, DOCX, HTML). It uses `pdftotext` when installed and otherwise a built-in PDF reader in PowerShell (Flate and ASCII85 streams, object streams, ToUnicode CMaps, form XObjects; no OCR). Calls stop after a time budget and report what is left.
  - `archive_search` has three modes: `documents` (snippet and page), `first` (first mention, oldest meeting first) and `timeline` (documents and meetings per year or month, with index coverage per period so a quiet year is not mistaken for absence).
  - `motions_sync` and `motions_search` cache and search the NotuBiz motions module: outcome, submitters, parties, linked meeting and vote text, with counts per outcome, party, submitter or year.
  - *Why:* archiving single meetings (1.9.0) produced the documents, but the questions that matter in local politics run across years: since when has a plan been discussed, how often, which motions were filed and what became of them. NotuBiz has no full-text search API and Open Raadsinformatie did not respond during development, so the search runs on the user's own archive. The motions module has structured outcomes but no keyword filter, so it is cached locally. Nieuw-West and Centrum do not use that module; the skill tells the assistant to search their archived documents and besluitenlijsten instead, and never to guess how a party voted.
- **MCP tool `archive_period`** (server `amsterdam-raadsinformatie`) and script `skills/amsterdam-notubiz/scripts/archive_period.ps1`: archive all past meetings of an organisation over a range of months, skipping meetings that are already archived, in batches (`max_meetings`) with a dry run.
  - *Why:* a searchable archive over years needs dozens of meetings; doing that one `archive_meeting` call at a time was impractical.
- **`get_meetings` takes `year` and `month`**, using the NotuBiz `?year=&month=` parameters.
  - *Why:* without them the API only returns recent and upcoming meetings, so older event IDs could not be found.
- **MCP tool `bag_plannen_op_adres`** (server `bag`): the bestemmingsplannen, paraplu-plannen, enkel- and dubbelbestemmingen, building plane and aanduidingen at an address or RD point, with links to the rules, from the PDOK Ruimtelijke plannen WMS (CC0, no key). The `omgevingsplan` and `bag` skills explain that this is the temporary part of the omgevingsplan and point to Regels op de kaart for the rest.
  - *Why:* the `omgevingsplan` skill could find publications but not answer "what is allowed here"; the only point lookup was the Omgevingsloket frontend, which the toolkit does not scrape.
- **`adresdossier` skill** with a Markdown template (`references/dossier-template.md`): one address in, one dossier out, in a fixed order (BAG, CBS neighbourhood figures, zoning, permits in the gemeenteblad, APV and area decisions, Woo, council documents and motions, crime figures through the optional `politie-misdrijven` plugin), summary first and one section per source with dates and links.
  - *Why:* residents, journalists and small parties usually need the whole picture of a place at once; doing it by hand meant eight searches with different codes. The skill limits itself to places, not people: no owners or residents, and no names of private persons.
- **`tests/smoke_test.ps1`**: starts every server from `.mcp.json` as a client would and checks `initialize`, `tools/list` (expected tools, complete definitions), error codes `-32601` and `-32602`, and real calls against the live sources (`-Offline` skips those). `raadsarchief` is tested on a temporary mini-archive. Exit code 1 on any failure, optional JSON report.
  - *Why:* with seven servers, a broken server after an update was only noticed when a tool silently failed in a conversation.

### Changed
- `amsterdam-raadsinformatie` server: invalid input now returns `-32602` (was `-32603`), consistent with the other servers.
- `.mcp.json` and `mcp_config.example.json` register the `raadsarchief` server; README (English and Dutch), `rules/AGENTS.md` (sections 11 and 12), the `amsterdam-notubiz`, `raadsinformatie`, `bag` and `omgevingsplan` skills and `docs/architecture-v2.png` (7 servers, 13 skills) are updated. User-Agent strings of the changed servers and scripts name version 1.10.

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
