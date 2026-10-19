# KOOP SRU API Reference (Officiële Bekendmakingen)

## Endpoint
- **URL**: `https://repository.overheid.nl/sru`
- **Protocol**: SRU 1.2 (Search/Retrieve via URL)
- **Methode**: `GET`
- **Authenticatie**: Geen authenticatie vereist (publieke open data)

## Standaard Query Parameters
| Parameter | Type | Omschrijving | Voorbeeld |
| :--- | :--- | :--- | :--- |
| `operation` | string | Vaste waarde voor bevragingen | `searchRetrieve` |
| `version` | string | SRU versie | `1.2` |
| `query` | string | De zoekopdracht in CQL (URL-encoded) | `c.product-area=officielepublicaties AND cql.textAndIndexes="kappen"` |
| `maximumRecords` | integer | Aantal records per pagina (default 10) | `10` |
| `startRecord` | integer | Paginering startindex (1-indexed) | `1` |
| `recordSchema` | string | Formaat van records (optioneel) | `gult` (default) of `oai_dc` |

## CQL Query Indexen
| Index | Omschrijving | Voorbeeldwaarde |
| :--- | :--- | :--- |
| `c.product-area` | Collectie / domein | `officielepublicaties` (voor officielebekendmakingen.nl) |
| `cql.textAndIndexes` | Vrij zoeken in de volledige tekst en metadata | `"omgevingsvergunning"` of `"bestemmingsplan"` |
| `dt.creator` | Uitgevende instantie | `"Gemeente Amsterdam"`, `"Stadsdeel Nieuw-West"` |
| `dt.type` | Type publicatie / blad | `"Gemeenteblad"`, `"Staatscourant"`, `"Staatsblad"`, `"Provinciaal blad"` |
| `dt.modified` | Datum van laatste wijziging | `>=2026-01-01` |
| `dt.issued` | Publicatiedatum | `>=2026-01-01` |
| `dt.identifier` | Officieel publicatienummer / ID | `"gmb-2026-12345"` |

## Responsestructuur
De SRU service retourneert XML met namespace `http://www.loc.gov/zing/srw/`:
- `numberOfRecords`: Totaal aantal gevonden publicaties.
- `records/record/recordData`: Bevat de documentmetadata (titel, datum, creator, identifier, type, en rechtstreekse downloadlinks naar PDF/XML).
