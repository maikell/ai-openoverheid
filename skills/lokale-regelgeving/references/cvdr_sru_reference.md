# CVDR SRU API Reference (lokale regelgeving)

CVDR (Centrale Voorziening Decentrale Regelgeving) holds the consolidated regulations of Dutch municipalities, provinces, water boards and other decentralised bodies. KOOP publishes it through an SRU search service and a file repository. No authentication is required; a fair-use policy applies.

## 1. Search service

- **Base URL:** `https://zoekservice.overheid.nl/sru/Search`
- **Required parameters:** `x-connection=cvdr`, `operation=searchRetrieve`, `version=1.2`, `query=<CQL>`
- **Optional:** `maximumRecords` (default 10, max 1000), `startRecord` (1-based paging)
- **Index overview:** `?x-connection=cvdr&operation=explain&version=1.2`

### Useful indexes (verified with `explain`)

| Index | Meaning | Example |
| :--- | :--- | :--- |
| `dcterms.creator` | Regulating body | `dcterms.creator="Amsterdam"` |
| `dcterms.title` | Words in the title | `dcterms.title="Algemene Plaatselijke Verordening"` |
| `overheidrg.keyword` | Free text in the regulation | `overheidrg.keyword="terras"` |
| `overheidrg.datumGeldendOp` | In force on a date | `overheidrg.datumGeldendOp="2026-10-19"` |
| `overheidrg.inwerkingtredingDatum` | Entry into force | `overheidrg.inwerkingtredingDatum>="2026-01-01"` |
| `overheidrg.uitwerkingtredingDatum` | End of validity | |
| `workid` | All versions of one regulation | `workid="CVDR72510"` |
| `dcterms.identifier` | One version | `dcterms.identifier="CVDR72510_57"` |
| `dcterms.modified`, `dcterms.issued` | Dates | |
| `organisatieType`, `gemeente`, `provincie`, `waterschap` | Type of body | |

Not supported here: `cql.textAndIndexes` (returns "Unsupported index"). Use `overheidrg.keyword` instead.

### Example queries

```text
dcterms.creator="Amsterdam" and dcterms.title="Algemene Plaatselijke Verordening" and overheidrg.datumGeldendOp="2026-10-19"
dcterms.creator="Amsterdam" and overheidrg.keyword="terras" and overheidrg.datumGeldendOp="2026-10-19"
workid="CVDR72510" and overheidrg.datumGeldendOp="2026-10-19"
```

On 19 October 2026 the first query returns 3 regulations (APV 2008 plus two decisions that refer to it); without the date filter there are 73 versions. The second returns 46 regulations.

### Response (per record)

`recordData/gzd/originalData/overheidrg:meta` holds:

- `owmskern`: `dcterms:identifier` (e.g. `CVDR72510_57`), `dcterms:title`, `dcterms:creator`, `dcterms:modified`
- `owmsmantel`: `dcterms:source` (legal basis, e.g. articles of the Gemeentewet), `overheid:isRatifiedBy` (e.g. gemeenteraad), `dcterms:subject`, `dcterms:issued`, `dcterms:isFormatOf` (the Gemeenteblad publication)
- `cvdripm`: `inwerkingtredingDatum`, `uitwerkingtredingDatum` (empty = still in force), `betreft` (changed articles)

`recordData/gzd/enrichedData` holds the links:

- `publicatieurl_xml`: the full text as XML
- `preferred_url`: the page on lokaleregelgeving.overheid.nl for this version
- `preferred_work_url`: the page for the regulation (always the latest version)

## 2. Identifiers

- `CVDR72510` is the **work** (the regulation over time).
- `CVDR72510_57` is **version 57** of that work.
- XML: `https://repository.officiele-overheidspublicaties.nl/cvdr/CVDR72510/57/xml/CVDR72510_57.xml`
- Web: `https://lokaleregelgeving.overheid.nl/CVDR72510/57`

## 3. Full-text XML

Root element `cvdr`, with `meta` (as above) and `body/regeling/regeling-tekst`. Structure: `hoofdstuk` > `paragraaf` > `artikel`. An `artikel` contains:

- `kop` with either `label` + `nr` + `titel` (`Artikel` / ` 1.1A ` / `Toepasselijkheid Omgevingswet`), or only `titel` containing the number (`Artikel 1.1 Definities`). Trim whitespace around `nr`.
- `al` paragraphs, `lid` members with `lidnr`, and `lijst`/`li` lists where `li/@nr` holds the marker (`a.`, `b.`, or `-`).

The Amsterdam APV is about 490 KB with 387 articles: extract the articles you need instead of passing the whole document to a model.
