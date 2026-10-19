---
name: rechtspraak
description: >-
  Use this skill whenever the user asks to search, retrieve, filter, or analyze court judgments, case law,
  rulings, or jurisprudence from the Dutch judiciary (Rechtspraak.nl, data.rechtspraak.nl, ECLI).
---

# Dutch Case Law (Rechtspraak Open Data & ECLI)

This skill explains how to search and retrieve official Dutch court rulings (*rechterlijke uitspraken*) published by the **Raad voor de Rechtspraak** (Council for the Judiciary).

## Architecture and endpoints

All published rulings are available through the public RESTful API at `https://data.rechtspraak.nl`.

The process has two steps:

1. **Query the index:** search for ECLI identifiers by court, date and area of law.
2. **Fetch the ruling:** retrieve the full XML of a ruling by its ECLI.

---

## 1. Searching the index (`/uitspraken/zoeken`)

Searches are `GET` requests.

### Main courts (`instantie` parameter)

- `HR`: Hoge Raad der Nederlanden (Supreme Court)
- `RVS`: Afdeling bestuursrechtspraak van de Raad van State (Council of State, administrative jurisdiction)
- `CRVB`: Centrale Raad van Beroep (Central Appeals Tribunal)
- `CBB`: College van Beroep voor het bedrijfsleven (Trade and Industry Appeals Tribunal)
- `GHAMS`: Gerechtshof Amsterdam (Court of Appeal Amsterdam)
- `GHDHA`: Gerechtshof Den Haag
- `RBAMS`: Rechtbank Amsterdam (District Court Amsterdam)
- `RBDHA`: Rechtbank Den Haag
- `RBMNE`: Rechtbank Midden-Nederland
- `RBROT`: Rechtbank Rotterdam

For municipal decisions (permits, enforcement, Woo), appeals usually go to the district court (e.g. `RBAMS`) and then to the Council of State (`RVS`).

### PowerShell example (search by date and court)

```powershell
$url = "https://data.rechtspraak.nl/uitspraken/zoeken?instantie=HR&date=2026-01-01..2026-10-17&return=DOC&max=5"
$wc = New-Object System.Net.WebClient
$wc.Encoding = [System.Text.Encoding]::UTF8
[xml]$feed = $wc.DownloadString($url)

foreach ($entry in $feed.feed.entry) {
    Write-Host "ECLI: $($entry.id)"
    Write-Host "Title: $($entry.title.InnerText)"
    Write-Host "Link: $($entry.link.href)"
}
```

---

## 2. Fetching the full text (`/uitspraken/content`)

To read the content, considerations and decision of a ruling:
`GET https://data.rechtspraak.nl/uitspraken/content?id={ECLI}`

### PowerShell example

```powershell
$ecli = "ECLI:NL:HR:2023:1"
$url = "https://data.rechtspraak.nl/uitspraken/content?id=$ecli"
$wc = New-Object System.Net.WebClient
$wc.Encoding = [System.Text.Encoding]::UTF8
[xml]$doc = $wc.DownloadString($url)

# Paragraphs of the ruling
$paragraphs = $doc.SelectNodes("//para")
foreach ($p in $paragraphs) {
    Write-Host $p.InnerText
}
```

The API allows at most 10 requests per second. See [rechtspraak_api_reference.md](references/rechtspraak_api_reference.md) for all parameters and value lists.

## Presenting results

- Give the ECLI, court, date, area of law and a short summary of the decision, with a link to `uitspraken.rechtspraak.nl`.
- Published rulings are pseudonymised; do not try to identify parties.
- Rulings explain the law for one case. Do not present them as advice for the user's own situation.
