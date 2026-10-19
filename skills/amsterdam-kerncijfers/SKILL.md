---
name: amsterdam-kerncijfers
description: >-
  Use this skill whenever the user asks to retrieve data, indicators, statistics, or metrics from
  Gemeente Amsterdam's Onderzoek en Statistiek, specifically the interactive Dashboard Kerncijfers
  (onderzoek.amsterdam.nl/interactief/dashboard-kerncijfers) or Basisbestand Gebieden Amsterdam (BBGA).
---

# Amsterdam Key Figures (Dashboard Kerncijfers & BBGA)

This skill explains how to retrieve statistical data, indicators and metadata directly from the official API of **Gemeente Amsterdam, Onderzoek & Statistiek (O&S)**.

For national figures, other municipalities or comparisons between them, use the `cbs` skill instead. Definitions and reference dates can differ between BBGA and CBS, so always name the source of each figure.

## API architecture

The interactive dashboard at `https://onderzoek.amsterdam.nl/interactief/dashboard-kerncijfers` is a client-side frontend on top of a static REST API:
`https://onderzoek.amsterdam.nl/statistieken/api`

### 1. Metadata endpoints

- **All indicators** (about 1,100):
  `GET https://onderzoek.amsterdam.nl/statistieken/api/data/meta/indicators.json`
  Returns the indicator code (`name`), Dutch title (`label`), English title (`enLabel`), `themes`, `unit`, `decimals`, `definition` and `source`.

- **All areas** (800+):
  `GET https://onderzoek.amsterdam.nl/statistieken/api/data/meta/areas.json`
  Maps area codes (e.g. `GA01`, `0363`, `A`, `DX01`) to names (`naam`), types (`type` / `label`: `ggw-gebied`, `stadsdeel`, `wijk`, `buurt`, `gemeente`) and parent districts (`stadsdeelNaam`, `stadsdeelCode`).

- **Statistics overview**:
  `GET https://onderzoek.amsterdam.nl/statistieken/api/data/meta/stats.json`
  Year spans and data counts per indicator.

### 2. Time series per indicator

`GET https://onderzoek.amsterdam.nl/statistieken/api/data/indicatoren/{INDICATOR_CODE}.json`

Example: `GET https://onderzoek.amsterdam.nl/statistieken/api/data/indicatoren/BEVTOTAAL.json`

Each record in the returned array looks like:

```json
{
  "indicatorId": 2267,
  "indicatorName": "BEVTOTAAL",
  "areaCode": "GA01",
  "areaName": "Centrum-West",
  "areaDate": "2022-03-24",
  "areaType": "ggw-gebied",
  "year": 2026,
  "value": 43905
}
```

---

## Resolving dashboard URLs

Given a dashboard URL such as:
`https://onderzoek.amsterdam.nl/interactief/dashboard-kerncijfers?tab=indicator&thema=bevolking&indicator=BEVTOTAAL&indeling=ggwgebieden&jaar=2026&gebied=GA01&taal=nl`

Read the query parameters:

- `indicator`: indicator code (e.g. `BEVTOTAAL`)
- `jaar`: year (e.g. `2026`)
- `gebied`: area code (e.g. `GA01`)
- `indeling`: geographic level (`gemeente`, `stadsdelen`, `ggwgebieden`, `wijken`, `buurten`, `winkelgebieden`)
- `thema`: theme (e.g. `bevolking`, `wonen`, `duurzaamheid-en-milieu`)

Then:

1. Fetch `https://onderzoek.amsterdam.nl/statistieken/api/data/indicatoren/{indicator}.json`.
2. Keep the records where `areaCode === gebied` and `year === parseInt(jaar)`.
3. Optionally fetch `areas.json` and `indicators.json` for the label, definition, unit and source.

A ready-made client is in `scripts/amsterdam_kerncijfers.mjs` (Node.js 18+); see its `--help`.

---

## Direct fetch example (PowerShell)

```powershell
$data = Invoke-RestMethod -Uri "https://onderzoek.amsterdam.nl/statistieken/api/data/indicatoren/BEVTOTAAL.json"
$item = $data | Where-Object { $_.areaCode -eq "GA01" -and $_.year -eq 2026 }
$item
```

## Presenting results

- Name the indicator label, the area name and code, the year and the unit.
- State the source: "Gemeente Amsterdam, Onderzoek & Statistiek (BBGA)".
- Use the `definition` field when a figure could be misread (for example a percentage of households versus of residents).
