# Technische Referentie: Omgevingsplan & Ruimtelijke Open Data

## 1. PDOK Locatieserver (v3_1)

PDOK Locatieserver is de openbare geocodeerservice van het Kadaster voor Nederland.

### Belangrijke velden in response
- `weergavenaam`: Volledig leesbaar adres.
- `centroide_rd`: `POINT(X Y)` in Rijksdriehoeksmeting (EPSG:28992).
- `centroide_ll`: `POINT(lon lat)` in WGS84 (EPSG:4326).
- `gekoppeld_perceel`: Kadastrale aanduiding (bijv. `ASD00-E-1234`).
- `geometrie_rd`: GeoJSON geometrie van het object/perceel.

---

## 2. KOOP SRU API voor Ruimtelijke Documenten

Endpoint: `https://repository.overheid.nl/sru`

### Belangrijke CQL indexen
| Index | Omschrijving | Voorbeeld |
|---|---|---|
| `c.product-area` | Productgebied | `officielepublicaties` |
| `dt.type` | Documenttype | `"ruimtelijk plan of omgevingsdocument"` |
| `dt.creator` | Uitgevende instantie | `"Gemeente Amsterdam"`, `"Stadsdeel Nieuw-West"` |
| `dt.identifier` | Uniek plan-ID | `"NL.IMRO.0363..."` |
| `cql.textAndIndexes` | Vrije tekstzoekopdracht | `"omgevingsplan"`, `"bestemmingsplan"` |
| `dt.modified` / `dt.issued` | Datumfilter | `dt.modified>=2025-01-01` |

---

## 3. DSO-LV (Digitaal Stelsel Omgevingswet)

Het DSO-LV stelt via het Ontwikkelaarsportaal REST API's beschikbaar (o.a. OZON Presenteren API v8). Voor geautomatiseerde integraties zonder API-token kunnen de open standaarden via PDOK en KOOP direct worden aangesproken.
