---
name: raadsinformatie
description: Zoeken en ophalen van raadsvergaderingen, agendapunten, raadsstukken, moties, verslagen en video-opnamen van Gemeente Amsterdam (amsterdam.raadsinformatie.nl / NotuBiz API).
---

# Raadsinformatie Amsterdam Skill (NotuBiz API)

Gebruik deze vaardigheid wanneer de gebruiker vraagt om:
1. Het inzien van gemeenteraadsvergaderingen of stadsdeelcommissies in Amsterdam (`amsterdam.raadsinformatie.nl`).
2. Agendapunten, besluitenlijsten en commissievergaderingen (bijv. Ruimtelijke Ordening, Financiën, Wonen).
3. Het direct ophalen van raadsdocumenten, moties, amendementen, brieven en raadsverslagen.
4. Livestreams en video-opnamen (`videotulen`) van debatten.

---

## 1. Organisatie-ID's Amsterdam

NotuBiz categoriseert de vergaderingen per orgaan binnen Amsterdam:

| Orgaan | Organisatie ID | Omschrijving |
|---|---|---|
| **Gemeenteraad Amsterdam** | `281` | Plenaire raad & algemene commissies |
| **College van B&W** | `1768` | Collegevergaderingen & B&W besluiten |
| **Stadsdeel Centrum** | `547` | Stadsdeelcommissie Centrum |
| **Stadsdeel Noord** | `977` | Stadsdeelcommissie Noord |
| **Stadsdeel West** | `1413` | Stadsdeelcommissie West |
| **Stadsdeel Zuid** | `1424` | Stadsdeelcommissie Zuid |
| **Stadsdeel Oost** | `1425` | Stadsdeelcommissie Oost |
| **Stadsdeel Nieuw-West** | `2328` | Stadsdeelcommissie Nieuw-West |
| **Stadsdeel Zuidoost** | `2122` | Stadsdeelcommissie Zuidoost |

---

## 2. Belangrijkste Endpoints

Alle data kan zonder authenticatietoken worden opgevraagd door de header `Accept: application/json` mee te sturen.

### A. Recente of komende vergaderingen ophalen
```http
GET https://api.notubiz.nl/organisations/{organisation_id}/events
Accept: application/json
```

**PowerShell voorbeeld**:
```powershell
$wc = New-Object System.Net.WebClient
$wc.Headers.Add("User-Agent", "open-overheid/1.5")
$wc.Headers.Add("Accept", "application/json")
$json = $wc.DownloadString("https://api.notubiz.nl/organisations/281/events") | ConvertFrom-Json

foreach ($ev in $json.events.event[0..4]) {
    Write-Output "[$($ev.'@attributes'.id)] $($ev.'@attributes'.date) | $($ev.title) - $($ev.category.title)"
    Write-Output "URL: $($ev.url)"
}
```

### B. Agenda en documenten van een vergadering ophalen
```http
GET https://api.notubiz.nl/events/{event_id}
Accept: application/json
```

**PowerShell voorbeeld**:
```powershell
$wc = New-Object System.Net.WebClient
$wc.Headers.Add("User-Agent", "open-overheid/1.5")
$wc.Headers.Add("Accept", "application/json")
$json = $wc.DownloadString("https://api.notubiz.nl/events/1545281") | ConvertFrom-Json

$meeting = $json.event[0]
Write-Output "Vergadering: $($meeting.title) op $($meeting.'@attributes'.date)"

foreach ($item in $meeting.agenda.agendaitem) {
    Write-Output "Agendapunt: $($item.order). $($item.title)"
    if ($item.documents.document) {
        foreach ($doc in $item.documents.document) {
            Write-Output "  - Document: $($doc.title) ($($doc.url))"
        }
    }
}
```

### C. Direct een raadsdocument / PDF downloaden
De document-URL uit de agenda heeft het formaat `https://api.notubiz.nl/document/{document_id}/1`. Deze kan direct gedownload of geanalyseerd worden.
