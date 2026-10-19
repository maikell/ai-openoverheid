---
name: amsterdam-kerncijfers
description: >-
  Use this skill whenever the user asks to retrieve data, indicators, statistics, or metrics from
  Gemeente Amsterdam's Onderzoek en Statistiek, specifically the interactive Dashboard Kerncijfers
  (onderzoek.amsterdam.nl/interactief/dashboard-kerncijfers) or Basisbestand Gebieden Amsterdam (BBGA).
---

# Amsterdam Dashboard Kerncijfers & BBGA Data Retrieval

This skill explains how to extract statistical data, indicators, and metadata directly from the official **Gemeente Amsterdam Onderzoek & Statistiek** API.

## API Architecture

The interactive dashboard at `https://onderzoek.amsterdam.nl/interactief/dashboard-kerncijfers` is a client-side frontend powered by the static REST API at:
`https://onderzoek.amsterdam.nl/statistieken/api`

### 1. Metadata Endpoints

* **All Indicators Metadata** (~1100+ variables):
  `GET https://onderzoek.amsterdam.nl/statistieken/api/data/meta/indicators.json`
  Provides indicator code (`name`), Dutch title (`label`), English title (`enLabel`), `themes`, `unit`, `decimals`, `definition`, and `source`.

* **All Areas Metadata** (800+ areas):
  `GET https://onderzoek.amsterdam.nl/statistieken/api/data/meta/areas.json`
  Provides mapping of area codes (e.g. `GA01`, `0363`, `A`, `DX01`) to names (`naam`), types (`type` / `label` e.g. `ggw-gebied`, `stadsdeel`, `wijk`, `buurt`, `gemeente`), and parent districts (`stadsdeelNaam`, `stadsdeelCode`).

* **Statistical Overview**:
  `GET https://onderzoek.amsterdam.nl/statistieken/api/data/meta/stats.json`
  Summary of year spans and data counts per indicator.

### 2. Indicator Time-Series Endpoint

* **Full Data per Indicator**:
  `GET https://onderzoek.amsterdam.nl/statistieken/api/data/indicatoren/{INDICATOR_CODE}.json`
  Example:
  `GET https://onderzoek.amsterdam.nl/statistieken/api/data/indicatoren/BEVTOTAAL.json`

  Each record in the returned array contains:
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

## Resolving Dashboard URLs

When given a dashboard URL such as:
`https://onderzoek.amsterdam.nl/interactief/dashboard-kerncijfers?tab=indicator&thema=bevolking&indicator=BEVTOTAAL&indeling=ggwgebieden&jaar=2026&gebied=GA01&taal=nl`

Parse the query parameters:
* `indicator`: Indicator code (e.g. `BEVTOTAAL`)
* `jaar`: Target year (e.g. `2026`)
* `gebied`: Area code (e.g. `GA01`)
* `indeling`: Geographic breakdown level (`gemeente`, `stadsdelen`, `ggwgebieden`, `wijken`, `buurten`, `winkelgebieden`)
* `thema`: Subject category (e.g. `bevolking`, `wonen`, `duurzaamheid-en-milieu`)

Then:
1. Fetch `https://onderzoek.amsterdam.nl/statistieken/api/data/indicatoren/{indicator}.json`
2. Filter the records where `areaCode === gebied` and `year === parseInt(jaar)`
3. (Optional) Fetch `areas.json` and `indicators.json` to get label, definition, unit, and source.

---

## Direct Fetch Example (PowerShell / Node.js)

```powershell
# In PowerShell:
$data = Invoke-RestMethod -Uri "https://onderzoek.amsterdam.nl/statistieken/api/data/indicatoren/BEVTOTAAL.json"
$item = $data | Where-Object { $_.areaCode -eq "GA01" -and $_.year -eq 2026 }
$item
```
