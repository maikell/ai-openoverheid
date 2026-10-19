# Memorix Mediabank API Referentie (Open Amsterdam)

## Basisconfiguratie
- **API URL**: `https://webservices.memorix.nl/mediabank/`
- **Tenant**: `ams` (Amsterdam)
- **API Sleutel**: `fdf0129e-e0d2-11ec-aa22-775b74759445`

## Endpoints

### 1. Zoeken (`GET /mediabank/media`)
| Parameter | Type | Omschrijving |
|---|---|---|
| `apiKey` | string | Verplichte publieke sleutel. |
| `q` | string | Vrije tekstzoekopdracht (bijv. `subsidie`, `handhaving`). |
| `fq[]` | string | Facetfilter. Voor uitsluitend Woo-besluiten: `search_s_categorie:"Wob-en Woo-besluiten"`. |
| `sort` | string | Sortering, bijv. `order_i_created_time desc` of `order_i_datum_dossier desc`. |
| `page` | integer | Paginanummer (1-indexed). |
| `rows` | integer | Aantal resultaten per pagina (bijv. 10 of 30). |

### 2. Detail & Download (`GET /mediabank/media/{uuid}`)
Retourneert volledige metadata over het document en gekoppelde bestanden:
- `asset`: Array met bestandsmetadata.
- `asset[].download`: Directe download-URL voor de PDF.
- `metadata`: Lijst met key-value paren (dossiernaam, categorie, datum_dossier, documentnaam).
- `handle`: Canonical URL op `https://open.amsterdam/woo-zoeken/detail/{uuid}`.
