---
name: officiele-bekendmakingen
description: >-
  Use this skill whenever the user asks to search, retrieve, filter, or analyze official Dutch government
  announcements, legal publications, municipal notices, state gazettes, permits, or regulations from
  officielebekendmakingen.nl or repository.overheid.nl (KOOP Open Data).
---

# Officiële Bekendmakingen & KOOP Open Data

This skill teaches how to search and retrieve official Dutch government publications (*Officiële Bekendmakingen*) from **KOOP** (Kennis- en exploitatiecentrum Officiële Overheidspublicaties).

## Bron & Architectuur

The website `https://www.officielebekendmakingen.nl/` provides public access to:
- **Gemeentebladen** (Gemeentelijke verordeningen, besluiten, vergunningen)
- **Provinciale bladen**
- **Waterschapsbladen**
- **Staatscourant**
- **Staatsblad**
- **Tractatenblad**
- **Parlementaire documenten** (Kamerstukken, Handelingen)

Instead of scraping HTML, KOOP provides the public SRU 1.2 webservice:
**`https://repository.overheid.nl/sru`**

---

## Zoeken via CQL (Context Query Language)

Een zoekvraag wordt opgebouwd met CQL parameters en verzonden via `GET`:

### Belangrijkste parameters:
1. `operation=searchRetrieve`
2. `version=1.2`
3. `maximumRecords=10` (of gewenst aantal)
4. `startRecord=1` (voor paginering)
5. `query=...` (CQL string)

### Voorbeelden van CQL zoekopdrachten:

- **Zoeken op tekst in officiële publicaties:**
  ```text
  c.product-area=officielepublicaties AND cql.textAndIndexes="omgevingsvergunning"
  ```

- **Filteren op gemeente/instantie en jaartal:**
  ```text
  c.product-area=officielepublicaties AND cql.textAndIndexes="bestemmingsplan" AND dt.creator="Gemeente Amsterdam" AND dt.issued>=2026-01-01
  ```

- **Filteren op publicatietype (bijv. Gemeenteblad):**
  ```text
  c.product-area=officielepublicaties AND dt.type="Gemeenteblad" AND dt.creator="Stadsdeel Nieuw-West"
  ```

- **Filteren op Staatsblad:**
  ```text
  c.product-area=officielepublicaties AND dt.type="Staatsblad" AND dt.issued>=2026-01-01
  ```

---

## Ophalen in PowerShell / Scripts

Voorbeeld van een PowerShell aanroep om records op te vragen:

```powershell
$query = 'c.product-area=officielepublicaties AND cql.textAndIndexes="vergunning" AND dt.creator="Gemeente Amsterdam"'
$encodedQuery = [System.Uri]::EscapeDataString($query)
$url = "https://repository.overheid.nl/sru?operation=searchRetrieve&version=1.2&maximumRecords=5&query=$encodedQuery"

[xml]$res = (New-Object System.Net.WebClient).DownloadString($url)
$total = $res.searchRetrieveResponse.numberOfRecords
Write-Host "Aantal gevonden publicaties: $total"

# Doorzoek de records
$records = $res.searchRetrieveResponse.records.record
foreach ($rec in $records) {
    # Metadata staat in $rec.recordData
    Write-Host "Record ID: $($rec.recordIdentifier)"
}
```

---

## Documentatie & Referenties
- Zie [sru_api_reference.md](references/sru_api_reference.md) voor de volledige velden- en indexenlijst.
