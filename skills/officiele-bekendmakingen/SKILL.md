---
name: officiele-bekendmakingen
description: >-
  Use this skill whenever the user asks to search, retrieve, filter, or analyze official Dutch government
  announcements, legal publications, municipal notices, state gazettes, permits, or regulations from
  officielebekendmakingen.nl or repository.overheid.nl (KOOP Open Data).
---

# Official Publications (Officiële Bekendmakingen) & KOOP Open Data

This skill explains how to search and retrieve official Dutch government publications (*Officiële Bekendmakingen*) from **KOOP** (Kennis- en exploitatiecentrum Officiële Overheidspublicaties).

Use it for the **publication** of a decision (when it appeared, in which gazette). For the consolidated text of a local regulation that applies today, use the `lokale-regelgeving` skill instead.

## Source and architecture

`https://www.officielebekendmakingen.nl/` provides public access to:

- **Gemeenteblad** (municipal gazette: ordinances, decisions, permits)
- **Provinciaal blad** (provincial gazette)
- **Waterschapsblad** (water board gazette)
- **Staatscourant** (Government Gazette)
- **Staatsblad** (Bulletin of Acts and Decrees)
- **Tractatenblad** (treaties)
- **Parliamentary papers** (Kamerstukken, Handelingen)

Instead of scraping HTML, use the public KOOP SRU 1.2 web service:
**`https://repository.overheid.nl/sru`**

---

## Searching with CQL (Contextual Query Language)

A query is built from CQL parameters and sent as a `GET` request.

### Main parameters

1. `operation=searchRetrieve`
2. `version=1.2`
3. `maximumRecords=10` (or the number you need)
4. `startRecord=1` (paging)
5. `query=...` (the CQL string)

### Example CQL queries

- **Full text in official publications:**
  ```text
  c.product-area=officielepublicaties AND cql.textAndIndexes="omgevingsvergunning"
  ```

- **Filter by authority and date:**
  ```text
  c.product-area=officielepublicaties AND cql.textAndIndexes="bestemmingsplan" AND dt.creator="Gemeente Amsterdam" AND dt.issued>=2026-01-01
  ```

- **Filter by publication type (e.g. Gemeenteblad):**
  ```text
  c.product-area=officielepublicaties AND dt.type="Gemeenteblad" AND dt.creator="Stadsdeel Nieuw-West"
  ```

- **Staatsblad since a date:**
  ```text
  c.product-area=officielepublicaties AND dt.type="Staatsblad" AND dt.issued>=2026-01-01
  ```

For local notices (permit applications and similar), the product area `lokalebekendmakingen` can be used instead of `officielepublicaties`.

---

## Fetching in PowerShell

```powershell
$query = 'c.product-area=officielepublicaties AND cql.textAndIndexes="vergunning" AND dt.creator="Gemeente Amsterdam"'
$encodedQuery = [System.Uri]::EscapeDataString($query)
$url = "https://repository.overheid.nl/sru?operation=searchRetrieve&version=1.2&maximumRecords=5&query=$encodedQuery"

[xml]$res = (New-Object System.Net.WebClient).DownloadString($url)
$total = $res.searchRetrieveResponse.numberOfRecords
Write-Host "Publications found: $total"

# Walk the records
$records = $res.searchRetrieveResponse.records.record
foreach ($rec in $records) {
    # Metadata is in $rec.recordData
    Write-Host "Record ID: $($rec.recordIdentifier)"
}
```

---

## Documentation and references

- See [sru_api_reference.md](references/sru_api_reference.md) for the full list of fields and indexes.

## Presenting results

- Give the title, publication type, issuing authority, publication date and the identifier (e.g. `gmb-2026-12345`) with a link.
- A publication date is not the date a rule takes effect; check the text or the `lokale-regelgeving` skill for the entry-into-force date.
