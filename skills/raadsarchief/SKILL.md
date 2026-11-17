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
| `motions_sync` | Download or refresh the motion cache for one organisation. Each call stops after `max_seconds` (default 20, because MCP clients usually stop waiting after 60 s) and fetches 4 pages of 250 in parallel. First run for the Gemeenteraad (about 10,000 items since 2013) takes about 6 calls; later runs only fetch new items and re-read the most recent 500, because outcomes are often filled in later. |
| `motions_search` | Search the motion cache: `query`, `fractie` (submitting party), `indiener`, `uitslag`, `type`, dates, `stemde_tegen` / `stemde_voor` (how parties voted). `summary_by` = `uitslag`, `fractie`, `indiener`, `jaar`, `tegenstemmers` or `voorstemmers` gives counts of adopted, rejected and withdrawn. Only motions and amendments, unless `alle_typen: true`. |

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
4. **Votes.** Every motion has `stemming` (the vote text as registered) and, read from that text by pattern, `unaniem`, `tegen` and `voor` (lists of parties). Examples:
   - who voted against motions about afval: `query: "afval", summary_by: "tegenstemmers"`
   - adopted motions a party voted against: `stemde_tegen: "<party>", uitslag: "aangenomen"`
   - how often a party's own motions passed: `fractie: "<party>", summary_by: "uitslag"`.
   Read the result honestly:
   - The Gemeenteraad usually records only one side: for adopted motions who voted **against**, for rejected motions who voted **for**. `summary_by: "tegenstemmers"` therefore shows rejected motions as "(alleen voorstemmers vastgelegd)"; use `voorstemmers` for those.
   - "(geen stemming vastgelegd)" means NotuBiz has no vote text (often withdrawn motions, older items and some stadsdelen). Do not guess; point to the besluitenlijst or stemmingsuitslagen of the meeting (`archive_search`).
   - Party names are used as written ("Partij voor de Dieren" and "PvdD" are different keys); mention it when it matters.
   - The parsing is best effort; quote `stemming` when a single vote is the point of the answer.

5. **What is registered where** (checked November 2026):

   | Organisation | Motions + amendments | Outcome known | Vote detail |
   |---|---:|---|---|
   | Gemeenteraad (281) | about 10,200 since 2013 | almost all | most since about 2015 |
   | Oost (1425) | about 770 since 2010 | almost all | about 1 in 10 |
   | West (1413) | about 460, 2010 to March 2024 | almost all, mostly adopted | most |
   | Zuid (1424) | about 210 since 2014 | 4 in 5 | none |
   | Zuidoost (2122) | about 510 since 2006 | few (older items hold only a number) | almost none |
   | Noord (977) | 11 | few | none |

6. **Differences between organisations.** Each stadsdeel configured the module itself. The tools read the variants (`Initiatiefnemer`, `Betrokken partijen`, `Fractie(s)`, `Partij(en)`, `Datum motie`, `Datum vergadering`, vote text in *Uitslag* in West, outcome only in *Toelichting* in parts of Zuidoost). West mostly registered adopted motions; say so when comparing stadsdelen. Zuid and Oost also keep advice (*advies*, *ongevraagd advies*) and proposals in the module: they are left out unless `alle_typen: true`.

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
