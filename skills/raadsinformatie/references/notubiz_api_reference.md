# NotuBiz API Referentie (amsterdam.raadsinformatie.nl)

Het raadsinformatiesysteem van Amsterdam (`amsterdam.raadsinformatie.nl`) draait op het platform van NotuBiz.

## Endpoints

### 1. Organisaties
`GET https://api.notubiz.nl/organisations`
Retourneert een overzicht van alle NotuBiz-organisaties met hun unieke ID.

### 2. Vergaderingenlijst
`GET https://api.notubiz.nl/organisations/{organisation_id}/events`
- Headers: `Accept: application/json`
- Geeft de chronologische lijst van vergaderingen terug.
- Bevat datum, tijd, categorie (bijv. Raad, Commissie Financiën, Presidium) en event-ID.

### 3. Vergaderdetails & Agenda
`GET https://api.notubiz.nl/events/{event_id}`
- Headers: `Accept: application/json`
- Retourneert de volledige agendaboom inclusief sub-agendapunten, sprekers, besluiten en gekoppelde raadsdocumenten (`documents`).
- Bevat tevens video metadata (`media.video`) met streaming URLs (`h264`, `playlist.m3u8`).

### 4. Raadsdocumenten
`GET https://api.notubiz.nl/document/{document_id}/{version}`
- Directe link naar de PDF of bijlage van het agendapunt.
