---
name: amsterdam-woo
description: Zoeken en ophalen van openbaar gemaakte Wob- en Woo-besluiten, brondocumenten en dossiers van Gemeente Amsterdam (open.amsterdam / Memorix Mediabank API).
---

# Amsterdam Woo-besluiten Skill

Gebruik deze vaardigheid wanneer de gebruiker vraagt om:
1. Het doorzoeken van **Wob- en Woo-besluiten** van Gemeente Amsterdam (`open.amsterdam`).
2. Het ophalen van openbaar gemaakte documenten, inventarislijsten en besluitbrieven over specifieke onderwerpen (bijv. subsidies, handhaving, vergunningen, beleid, bomen).
3. Het direct verkrijgen van werkende downloadlinks naar de vrijgegeven PDF's.

---

## 1. API Architectuur & Endpoints

Het portaal `open.amsterdam/woo-zoeken/` is een client-side frontend bovenop de **Memorix Mediabank API**:
- **Base URL**: `https://webservices.memorix.nl/mediabank/`
- **Publieke API-Key**: `fdf0129e-e0d2-11ec-aa22-775b74759445`

### A. Woo-besluiten Doorzoeken
Om uitsluitend Woo-besluiten te doorzoeken (gesorteerd op datum, nieuwste eerst):
```http
GET https://webservices.memorix.nl/mediabank/media?apiKey=fdf0129e-e0d2-11ec-aa22-775b74759445&page={pagina}&rows={aantal}&fq[]=search_s_categorie:%22Wob-en%20Woo-besluiten%22&sort=order_i_created_time%20desc&q={zoekterm}
Accept: application/json
```

**PowerShell Voorbeeld:**
```powershell
$apiKey = "fdf0129e-e0d2-11ec-aa22-775b74759445"
$query = "boomkap"
$url = "https://webservices.memorix.nl/mediabank/media?apiKey=$apiKey&page=1&rows=5&fq[]=search_s_categorie:%22Wob-en%20Woo-besluiten%22&sort=order_i_created_time%20desc&q=" + [uri]::EscapeDataString($query)

$wc = New-Object System.Net.WebClient
$wc.Headers.Add("User-Agent", "open-overheid/1.4")
$wc.Headers.Add("Accept", "application/json")
$res = $wc.DownloadString($url) | ConvertFrom-Json

Write-Output "Totaal gevonden Woo-besluiten: $($res.metadata.pagination.total)"
foreach ($item in $res.media) {
    $meta = @{}
    foreach ($m in $item.metadata) { $meta[$m.field] = $m.value }
    Write-Output "[$($meta.datum_dossier)] $($meta.documentnaam)"
    Write-Output "Dossier: $($meta.dossiernaam)"
    Write-Output "Handle: $($item.handle)"
}
```

---

## 2. Documentdetails en Directe PDF Downloaden

Voor een specifiek document-ID kan de volledige metadata en de download-URL worden opgevraagd:
```http
GET https://webservices.memorix.nl/mediabank/media/{id}?apiKey=fdf0129e-e0d2-11ec-aa22-775b74759445
Accept: application/json
```

In het JSON-antwoord:
- `asset[0].download`: Directe link naar de PDF (bijv. op `stadsarchiefamsterdam.memorix.io`).
- `metadata`: Gestructureerde velden met o.a. `dossiernaam`, `documentnaam`, `datum_dossier`, `document_categorie`.
- `handle`: Publieke webpagina op `open.amsterdam`.
