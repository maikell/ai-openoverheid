---
name: rechtspraak
description: >-
  Use this skill whenever the user asks to search, retrieve, filter, or analyze court judgments, case law,
  rulings, or jurisprudence from the Dutch judiciary (Rechtspraak.nl, data.rechtspraak.nl, ECLI).
---

# Rechtspraak Open Data & Jurisprudentie Retrieval

This skill teaches how to search and retrieve official Dutch court judgments (*rechterlijke uitspraken*) from the **Raad voor de Rechtspraak**.

## Architectuur & Endpoints

Alle uitspraken worden gepubliceerd via de openbare RESTful API op `https://data.rechtspraak.nl`.

Het proces bestaat uit twee stappen:
1. **Index bevragen**: Zoeken naar ECLI-identificatiecodes op basis van instantie, datum en rechtsgebied.
2. **Uitspraaktekst ophalen**: De volledige XML-uitspraak ophalen via het ECLI-nummer.

---

## 1. Zoeken in de Index (`/uitspraken/zoeken`)

Zoekopdrachten worden uitgevoerd via een `GET` request.

### Belangrijkste gerechten (`instantie` parameter):
- `HR`: Hoge Raad der Nederlanden
- `RVS`: Afdeling bestuursrechtspraak van de Raad van State
- `CRVB`: Centrale Raad van Beroep
- `CBB`: College van Beroep voor het bedrijfsleven
- `GHAMS`: Gerechtshof Amsterdam
- `GHDHA`: Gerechtshof Den Haag
- `RBAMS`: Rechtbank Amsterdam
- `RBDHA`: Rechtbank Den Haag
- `RBMNE`: Rechtbank Midden-Nederland
- `RBROT`: Rechtbank Rotterdam

### PowerShell voorbeeld (Zoeken op datum & instantie):
```powershell
$url = "https://data.rechtspraak.nl/uitspraken/zoeken?instantie=HR&date=2026-01-01..2026-10-17&return=DOC&max=5"
$wc = New-Object System.Net.WebClient
$wc.Encoding = [System.Text.Encoding]::UTF8
[xml]$feed = $wc.DownloadString($url)

foreach ($entry in $feed.feed.entry) {
    Write-Host "ECLI: $($entry.id)"
    Write-Host "Titel: $($entry.title.InnerText)"
    Write-Host "Link: $($entry.link.href)"
}
```

---

## 2. Volledige uitspraaktekst ophalen (`/uitspraken/content`)

Om de inhoud, rechtsoverwegingen en de beslissing van een uitspraak te lezen:
`GET https://data.rechtspraak.nl/uitspraken/content?id={ECLI}`

### PowerShell voorbeeld:
```powershell
$ecli = "ECLI:NL:HR:2023:1"
$url = "https://data.rechtspraak.nl/uitspraken/content?id=$ecli"
$wc = New-Object System.Net.WebClient
$wc.Encoding = [System.Text.Encoding]::UTF8
[xml]$doc = $wc.DownloadString($url)

# Inhoudelijke paragrafen
$paragraphs = $doc.SelectNodes("//para")
foreach ($p in $paragraphs) {
    Write-Host $p.InnerText
}
```
