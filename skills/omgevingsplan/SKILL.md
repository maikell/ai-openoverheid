---
name: omgevingsplan
description: Zoeken en analyseren van omgevingsplannen, bestemmingsplannen, ruimtelijke regels, functies en percelen onder de Omgevingswet (DSO, PDOK, KOOP).
---

# Omgevingsplan & Ruimtelijke Ordening Skill

Gebruik deze vaardigheid wanneer de gebruiker vraagt om:
1. Het achterhalen van planologische regels of vergunningplichten op een specifiek adres/locatie.
2. Het zoeken naar vastgestelde of ontwerpomgevingsplannen en wijzigingsbesluiten van een gemeente.
3. Het analyseren van ruimtelijke activiteiten (zoals kappen, bouwen, monumenten, BOPA) binnen het omgevingsplan.

---

## 1. Locatie-identificatie via PDOK Locatieserver

Om planologische regels te koppelen aan een fysieke locatie heb je de exacte coördinaten of het kadastrale perceel nodig. Gebruik hiervoor de gratis en open PDOK Locatieserver.

### Endpoint
```
https://api.pdok.nl/bzk/locatieserver/search/v3_1/free?q={zoekterm}&rows=1
```

### PowerShell Voorbeeld
```powershell
$adres = [uri]::EscapeDataString("Amstel 1 Amsterdam")
$url = "https://api.pdok.nl/bzk/locatieserver/search/v3_1/free?q=$adres&rows=1"
$resp = Invoke-RestMethod -Uri $url -Method Get
$doc = $resp.response.docs[0]

Write-Output "Weergavenaam: $($doc.weergavenaam)"
Write-Output "RD Coördinaten: $($doc.centroide_rd)"
Write-Output "WGS84 Coördinaten: $($doc.centroide_ll)"
Write-Output "Kadastraal Perceel: $($doc.gekoppeld_perceel)"
```

---

## 2. Bekendmakingen en Wijzigingsbesluiten via KOOP SRU

Alle officiële publicaties van omgevingsplannen, voorbereidingsbesluiten en wijzigingen worden gepubliceerd via de KOOP Open Data SRU endpoint.

### Query Formaat (CQL)
```
c.product-area=officielepublicaties AND dt.type="ruimtelijk plan of omgevingsdocument" AND cql.textAndIndexes="{zoekterm}"
```

Optioneel filteren op bevoegd gezag (bijv. gemeente):
```
dt.creator="Gemeente Amsterdam"
```

### PowerShell Voorbeeld: Recente Omgevingsplan publicaties ophalen
```powershell
$query = 'c.product-area=officielepublicaties AND dt.type="ruimtelijk plan of omgevingsdocument" AND cql.textAndIndexes="Omgevingsplan" AND dt.creator="Gemeente Amsterdam"'
$encodedQuery = [uri]::EscapeDataString($query)
$url = "https://repository.overheid.nl/sru?operation=searchRetrieve&version=1.2&query=$encodedQuery&maximumRecords=5"

$resp = Invoke-RestMethod -Uri $url -Method Get
# De XML bevat Dublin Core records met titels, identifiers en links naar de officiële documenten
```

---

## 3. Juridische Structuur van het Omgevingsplan (Omgevingswet)

Bij het interpreteren van regels voor een gebruiker:
- **Tijdelijk deel van het omgevingsplan**:
  - Bestaat tot eind 2031 uit alle geldende bestemmingsplannen van vóór 1 januari 2024.
  - Bevat de **Bruidsschat**: een set rijksregels over o.a. bouwen, milieu en geluid die per 1 januari 2024 zijn overgedragen aan de gemeenten.
  - Bevat lokale verordeningen die overgaan naar het omgevingsplan (zoals de Algemene Plaatselijke Verordening m.b.t. kapverboden en bomen).
- **Nieuw deel van het omgevingsplan**:
  - Wijzigingsbesluiten die sinds 1 januari 2024 door de gemeenteraad zijn vastgesteld conform de STOP/TPOD standaard.
- **BOPA (Buitenplanse Omgevingsplanactiviteit)**:
  - Indien een activiteit (zoals bouwen of kappen) in strijd is met het omgevingsplan, kan een omgevingsvergunning voor een BOPA worden aangevraagd. Hierop is de reguliere procedure (8 weken) in beginsel van toepassing.
