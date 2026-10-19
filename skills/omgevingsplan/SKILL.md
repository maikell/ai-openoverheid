---
name: omgevingsplan
description: >-
  Use this skill to search and analyse zoning and environmental plans under the Dutch Environment and Planning
  Act (Omgevingswet): omgevingsplannen, former bestemmingsplannen, spatial rules, permitted functions and
  parcels for a specific address or area, using PDOK and KOOP open data. Use it for questions like "what is
  allowed at this address" or "which plan changes has the municipality adopted".
---

# Zoning Plan (Omgevingsplan) & Spatial Planning

Use this skill when the user asks to:

1. Find the planning rules or permit requirements that apply at a specific address or location.
2. Find adopted or draft omgevingsplannen and amendment decisions of a municipality.
3. Analyse spatial activities (such as tree felling, building, monuments, BOPA) under the omgevingsplan.

For what is registered at an address (use, floor area, construction year), use the `bag` skill. For local ordinances such as the APV, use `lokale-regelgeving`.

---

## 1. Locating an address with the PDOK Locatieserver

To link planning rules to a physical location you need exact coordinates or the cadastral parcel. Use the free, open PDOK Locatieserver.

### Endpoint

```
https://api.pdok.nl/bzk/locatieserver/search/v3_1/free?q={search term}&rows=1
```

Free text can return a different address first (in a test, "Amstel 1 Amsterdam" returned *Amstel 312A-1*). Prefer filters: `?q=*&fq=type:adres&fq=postcode:1011PN&fq=huisnummer:1`, and always check the returned address.

### PowerShell example

```powershell
$url = "https://api.pdok.nl/bzk/locatieserver/search/v3_1/free?q=*&fq=type:adres&fq=postcode:1011PN&fq=huisnummer:1&rows=1"
$resp = Invoke-RestMethod -Uri $url -Method Get
$doc = $resp.response.docs[0]

Write-Output "Address: $($doc.weergavenaam)"
Write-Output "RD coordinates: $($doc.centroide_rd)"
Write-Output "WGS84 coordinates: $($doc.centroide_ll)"
Write-Output "Neighbourhood code: $($doc.buurtcode)"
```

---

## 2. Publications and amendments via KOOP SRU

All official publications of omgevingsplannen, preparatory decisions and amendments are published through the KOOP Open Data SRU endpoint.

### Query format (CQL)

```
c.product-area=officielepublicaties AND dt.type="ruimtelijk plan of omgevingsdocument" AND cql.textAndIndexes="{search term}"
```

Optional filter on the competent authority (e.g. a municipality):

```
dt.creator="Gemeente Amsterdam"
```

### PowerShell example: recent omgevingsplan publications

```powershell
$query = 'c.product-area=officielepublicaties AND dt.type="ruimtelijk plan of omgevingsdocument" AND cql.textAndIndexes="Omgevingsplan" AND dt.creator="Gemeente Amsterdam"'
$encodedQuery = [uri]::EscapeDataString($query)
$url = "https://repository.overheid.nl/sru?operation=searchRetrieve&version=1.2&query=$encodedQuery&maximumRecords=5"

$resp = Invoke-RestMethod -Uri $url -Method Get
# The XML holds Dublin Core records with titles, identifiers and links to the official documents
```

---

## 3. Legal structure of the omgevingsplan (Omgevingswet)

When interpreting rules for a user:

- **Temporary part of the omgevingsplan** (*tijdelijk deel*):
  - Until the end of 2031 it consists of all zoning plans (bestemmingsplannen) adopted before 1 January 2024.
  - It includes the **Bruidsschat**: a set of national rules on building, environment and noise that were transferred to municipalities on 1 January 2024.
  - It includes local ordinances that move into the omgevingsplan (such as APV rules on tree felling).
- **New part of the omgevingsplan** (*nieuw deel*):
  - Amendment decisions adopted by the municipal council since 1 January 2024 under the STOP/TPOD standard.
- **BOPA (Buitenplanse Omgevingsplanactiviteit)**:
  - If an activity (such as building or felling) conflicts with the omgevingsplan, a permit for a BOPA can be requested. The regular procedure (8 weeks) applies in principle.

## Presenting results

- Name the plan or publication, its status (draft or adopted), the authority and the date, with a link.
- Explain which part of the omgevingsplan a rule comes from when that matters.
- This is information, not legal advice; for a specific case the municipality's own assessment applies.
