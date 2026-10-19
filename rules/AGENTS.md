# Open Overheid: Richtlijnen voor Juridische, Ruimtelijke, Financiële en Statistische Data

Wanneer de gebruiker vragen stelt over Nederlandse open overheidsdata, jurisprudentie, bekendmakingen, het omgevingsplan, Woo-besluiten of subsidies, volg dan deze richtlijnen:

---

## 1. Omgevingsplan & Ruimtelijke Ordening (Omgevingswet)
- Scrape niet direct de dynamische frontend van het Omgevingsloket (`omgevingswet.overheid.nl/regels-op-de-kaart`).
- **Locatie & Geocodering (PDOK Locatieserver)**:
  - Gebruik de gratis PDOK Locatieserver om adressen om te zetten naar coördinaten (RD & WGS84) en perceelidentificatie:
    `GET https://api.pdok.nl/bzk/locatieserver/search/v3_1/free?q={adres}&rows=1`
- **Bekendmakingen Omgevingsplan & Plannen (KOOP SRU)**:
  - Wijzigingsbesluiten, ontwerp-omgevingsplannen en vastgestelde plannen worden gepubliceerd via KOOP:
    `https://repository.overheid.nl/sru?operation=searchRetrieve&version=1.2&query=c.product-area=officielepublicaties%20AND%20dt.type="ruimtelijk%20plan%20of%20omgevingsdocument"%20AND%20cql.textAndIndexes="{zoekterm}"`
- **Juridische duiding (Omgevingswet)**:
  - Maak onderscheid tussen het *tijdelijk deel van het omgevingsplan* (de vroegere bestemmingsplannen en de bruidsschat) en het *nieuwe deel van het omgevingsplan*.
  - Houd rekening met BOPA (Buitenplanse Omgevingsplanactiviteit) bij afwijkingen van het omgevingsplan.

---

## 2. Rechtspraak Open Data (Jurisprudentie & ECLI)
- Scrape `uitspraken.rechtspraak.nl` HTML niet direct.
- Gebruik de officiële RESTful webservice van Rechtspraak (`https://data.rechtspraak.nl`):
  1. **Zoeken**: `GET https://data.rechtspraak.nl/uitspraken/zoeken?max={N}&from={offset}&return=DOC&modified={datum}&instantie={code}&rechtsgebied={gebied}`
  2. **Inhoud ophalen per ECLI**: `GET https://data.rechtspraak.nl/uitspraken/content?id={ECLI}` (geeft gestructureerde XML terug).
- Rate limit: Maximaal 10 requests per seconde.

---

## 3. Officiële Bekendmakingen & KOOP Open Data
- Gebruik voor publicaties, vergunningen en regelgeving de officiële KOOP SRU 1.2 webservice:
  `https://repository.overheid.nl/sru`
- Pas Context Query Language (CQL) toe:
  - Filter productgebied: `c.product-area=officielepublicaties` (of `lokalebekendmakingen`)
  - Vrije tekst: `cql.textAndIndexes="{zoekterm}"`
  - Bevoegd gezag: `dt.creator="{instantie}"`
  - Datum: `dt.modified>={YYYY-MM-DD}`

---

## 4. Amsterdam Onderzoek & Statistiek (Kerncijfers & BBGA)
- Voor indicatoren en statistieken van `https://onderzoek.amsterdam.nl/interactief/dashboard-kerncijfers`:
  - Statische API: `https://onderzoek.amsterdam.nl/statistieken/api`
  - Metadata indicatoren: `.../statistieken/api/data/meta/indicators.json`
  - Metadata gebieden: `.../statistieken/api/data/meta/areas.json`
  - Tijdreeksen per indicator: `.../statistieken/api/data/indicatoren/{indicator}.json`
  - Filter records op `areaCode` (bijv. `GA01`) en `year`.

---

## 5. Open Amsterdam (Woo-besluiten & Memorix API)
- Scrape `open.amsterdam/woo-zoeken/` HTML niet direct.
- Gebruik de achterliggende open REST API van de Memorix Mediabank of de `amsterdam-woo` MCP-server (`search_woo_decisions`, `get_woo_document`):
  - **Base URL**: `https://webservices.memorix.nl/mediabank/`
  - **API Sleutel**: `fdf0129e-e0d2-11ec-aa22-775b74759445`
  - **Filter voor uitsluitend Woo-besluiten**: `fq[]=search_s_categorie:"Wob-en Woo-besluiten"`
  - **Sorteervolgorde (standaard nieuwste eerst)**: `sort=order_i_created_time desc`
  - **Zoekterm**: parameter `q={zoekterm}`
- **PDF- en brondocumenten**:
  - Elk resultaat bevat een `id` (UUID) waarmee via `GET /mediabank/media/{id}` de directe downloadlink naar de PDF (`asset.download`) en IIIF-preview kan worden opgehaald.

---

## 6. Raadsinformatie (NotuBiz)
- Scrape `amsterdam.raadsinformatie.nl` of `nieuw-west.notubiz.nl` niet direct.
- Gebruik de `amsterdam-raadsinformatie` MCP-server (`get_meetings`, `get_meeting_agenda`) of de NotuBiz REST API met header `Accept: application/json`:
  - **Vergaderingen per orgaan**: `GET https://api.notubiz.nl/organisations/{id}/events`
  - **Agenda en documenten**: `GET https://api.notubiz.nl/events/{event_id}`
  - **Document (PDF)**: `GET https://api.notubiz.nl/document/{document_id}/{versie}`
- Organisatie-ID's: `281` Gemeenteraad Amsterdam, `2328` Stadsdeel Nieuw-West (zie de skill `raadsinformatie` voor de overige stadsdelen).

---

## 7. Openbaar Subsidieregister Amsterdam (PowerBI / Datapunt)
- Vraag de gebruiker niet om handmatig een CSV te downloaden uit het PowerBI dashboard.
- Gebruik de `amsterdam-subsidies` MCP-server (`search_subsidies`, `get_subsidies_summary`) of de live open data stream:
  `https://api.data.amsterdam.nl/v1/subsidies/openbaar_subsidieregister?_format=csv`
- Bevat alle verleende subsidies, dossiers, aanvragers, bedragen en clusters.
