# Rechtspraak Open Data API Reference

## Base URL
`https://data.rechtspraak.nl`

## Endpoints

### 1. Zoeken in uitspraken (Index)
`GET https://data.rechtspraak.nl/uitspraken/zoeken`

Geeft een Atom-feed (XML) terug met gevonden ECLI's en basiskoppelingen.

#### Belangrijkste parameters:
| Parameter | Type | Omschrijving | Voorbeeld |
| :--- | :--- | :--- | :--- |
| `max` | integer | Aantal gewenste resultaten (default 10, max 1000) | `10` |
| `from` | integer | Paginering offset (0-indexed) | `0` |
| `return` | string | `DOC` (alleen documenten) of `META` (alleen metadata) | `DOC` |
| `date` | string / range | Uitspraakdatum (formaat `YYYY-MM-DD` of `YYYY-MM-DD..YYYY-MM-DD`) | `2026-01-01..2026-10-17` |
| `modified` | string / range | Datum van toevoeging/wijziging in register | `2026-09-01` |
| `instantie` | string | Gerecht / instantie code (zie waardelijsten) | `HR` (Hoge Raad), `RBAMS` (Rechtbank Amsterdam), `RBDHA` (Den Haag), `RVS` (Raad van State) |
| `rechtsgebied` | string | Rechtsgebied | `Bestuursrecht`, `Civiel recht`, `Strafrecht`, `Belastingrecht` |
| `type` | string | `Uitspraak` of `Conclusie` | `Uitspraak` |

### 2. Volledige uitspraak ophalen (Content)
`GET https://data.rechtspraak.nl/uitspraken/content?id={ECLI}`

Geeft de volledige XML terug in het `open-rechtspraak` schema.
- **Root**: `<open-rechtspraak>`
- **Metadata**: `<rdf:RDF>` met Dublin Core (`dcterms:title`, `dcterms:creator`, `dcterms:date`, `dcterms:abstract`, wetsverwijzingen)
- **Tekst**: `<uitspraak>` of `<conclusie>` met genummerde rechtsoverwegingen (`<section>`, `<para>`).

### 3. Waardelijsten
- Instanties: `GET https://data.rechtspraak.nl/waardelijsten/instanties`
- Rechtsgebieden: `GET https://data.rechtspraak.nl/waardelijsten/rechtsgebieden`
