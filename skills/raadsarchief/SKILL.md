---
name: raadsarchief
description: >-
  Use this skill to search and analyse the user's own local archive of Amsterdam council and district committee
  documents across years, and to follow motions and amendments with their outcome and votes. Use it for questions
  like "when did the Meervaart first come up in the stadsdeelcommissie", "how often was afval on the agenda per
  year", "which motions about afval were submitted since 2024 and what happened to them", "how many motions of
  party X were adopted", or "find every document that mentions this street".
---

# Raadsarchief: search across years, follow motions and votes

Two local data sets, both on the user's own computer, both built from public NotuBiz data:

1. **Document index.** The archive folders made by the `amsterdam-notubiz` skill (one folder per meeting, with `manifest.json`) are read into a full-text index: Markdown agendas, PDFs, DOCX and HTML. Questions over many years then take seconds and need no internet.
2. **Motion cache.** All motions and amendments that NotuBiz registers for an organisation, with submitters, parties, outcome (*uitslag*) and, where recorded, the vote text.

Everything is stored under the archive folder, in `_index/`. Default archive folder: environment variable `OPEN_OVERHEID_ARCHIVE_ROOT`, else `Documents/Raadsinformatie`. All tools take an optional absolute `root`.

## MCP tools (server `raadsarchief`)

| Tool | Use |
|---|---|
| `archive_index` | Build or refresh the index. Incremental (only new or changed files). Stops after `max_seconds` (default 45) and says what is left: call again until `complete` is true. |
| `archive_search` | Search. `mode`: `documents` (hits with snippet and page), `first` (first mention, oldest meeting first), `timeline` (documents and meetings per year or month). Filters: `organisation` (name part or NotuBiz id), `body`, `date_from`, `date_to` (yyyy, yyyy-mm or yyyy-mm-dd), `doc_type`. |
| `motions_sync` | Download or refresh the motion cache for one organisation. First run for the Gemeenteraad (about 10,000 items since 2013) takes several calls; later runs only fetch new items and re-read the most recent 500, because outcomes are often filled in later. |
| `motions_search` | Search the motion cache: `query`, `fractie`, `indiener`, `uitslag`, `type`, dates; `summary_by` = `uitslag`, `fractie`, `indiener` or `jaar` gives counts of submitted, adopted, rejected and withdrawn. |

Query syntax (both search tools): all words must occur, matched as part of a word and case-insensitive (`afval` also finds `afvalinzameling`); `"exact phrase"`; `-word` excludes.

## Workflow

### Search the archive across years

1. **Is there an archive?** If `archive_search` says there is no index, check whether meetings were archived. If not, offer to archive the period first with `archive_period` (server `amsterdam-raadsinformatie`, see the `amsterdam-notubiz` skill), e.g. all Stadsdeelcommissie meetings of Nieuw-West from 2022. That downloads every document and can take a while; do it in batches (`max_meetings`).
2. **Index:** run `archive_index` until `complete` is true. Report the period covered and how many files had no text layer.
3. **Search** with the mode that fits the question:
   - "When did X first come up?" → `mode: first`. Report the date, body, document and snippet, and the next few meetings.
   - "How often / since when / trend?" → `mode: timeline`. Always read `coverage` next to `timeline`: a year with few documents in the index says nothing about how often a topic was discussed.
   - "Which documents about X?" → `mode: documents`, with `doc_type` (e.g. `motie`, `verslag`, `besluitenlijst`) and dates.
4. **Present** in Dutch for a Dutch question: a short answer first, then a table (date, body, document, page, snippet), with the meeting link (`meeting_page`) where available. Say plainly that the answer only covers what is in the local archive, and for which period.

### Follow motions and votes

1. **Which organisation?** NotuBiz registers motions for the Gemeenteraad (`281`) and the stadsdelen Oost (`1425`), Zuidoost (`2122`), West (`1413`), Zuid (`1424`) and Noord (`977`, few items). **Nieuw-West (`2328`) and Centrum (`547`) do not**: for those, search the archived meeting documents with `archive_search` and `doc_type: motie` (or `amendement`), and read the outcome in the besluitenlijst of the same meeting (`doc_type: besluitenlijst`).
2. **Sync** with `motions_sync` until `complete` is true. Tell the user the cache date (`synced`) in the answer.
3. **Search and count** with `motions_search`. Examples:
   - motions about afval since 2024: `query: "afval", date_from: "2024"`
   - what happened to them: `summary_by: "uitslag"`
   - adoption rate per party: `summary_by: "fractie"` (a motion with several parties counts for each party)
   - one party or member: `fractie: "<party name>"` or `indiener: "<member name>"`.
4. **Votes.** The field `stemming` holds the vote text as NotuBiz registered it (e.g. "met de stemmen tegen van <party A> en <party B> is aangenomen", or "met algemene stemmen aangenomen"). It is often empty for older items and for stadsdelen. Do not guess how a party voted: if `stemming` is empty, say so and point to the besluitenlijst or stemmingsuitslagen of the meeting (search them with `archive_search`).

## Command line (Claude Code, Antigravity, by hand)

```powershell
# Index and search (Windows: powershell -NoProfile -ExecutionPolicy Bypass -File ...)
./scripts/raadsarchief.ps1 index  -Root "$HOME/Documents/Raadsinformatie"
./scripts/raadsarchief.ps1 search -Query "Meervaart" -Mode first -Organisation "Nieuw-West"
./scripts/raadsarchief.ps1 search -Query "afval" -Mode timeline -DateFrom 2022
./scripts/raadsarchief.ps1 motions-sync   -OrganisationId 281
./scripts/raadsarchief.ps1 motions-search -Query "afval" -DateFrom 2024-01-01 -SummaryBy fractie
```

Output is JSON. Without a time budget the CLI indexes or syncs everything in one run.

## Points of attention

- **PDF text.** If `pdftotext` (Poppler, Xpdf, or the one in Git for Windows) is on PATH it is used; otherwise a built-in reader in PowerShell. Neither does OCR: scanned PDFs without a text layer are only found by their title. `archive_index` reports how many there are.
- **Doc types** are derived from document titles (`motie`, `amendement`, `agenda`, `besluitenlijst`, `verslag`, `vragen`, `voorstel`, `brief`, `advies`, `bijlage`, `overig`). They are a filter aid, not an official classification.
- **Outcome labels** are normalised from the NotuBiz field *Uitslag* to `aangenomen`, `verworpen`, `ingetrokken`, `aangehouden`, `vervallen`, `afgedaan`, `anders` or `onbekend`; the original text is in `uitslag_tekst`.
- **Privacy.** Council documents name council members and sometimes residents (e.g. insprekers). Use names of elected members and officials as they appear; do not build profiles of residents.
- The data stays local. Nothing is uploaded; the only network calls are to `api.notubiz.nl`.

## Why this skill was added (version 1.10.0)

Archiving meetings (1.9.0) gave a pile of PDFs per meeting, but questions that matter for local politics run across years: since when has a plan been discussed, how often, which motions were filed and what became of them. NotuBiz has no full-text search API, and Open Raadsinformatie could not be reached reliably, so the search runs on the user's own archive. Motions have a structured NotuBiz module with outcomes, but no keyword filter, so they are cached locally and searched there.
