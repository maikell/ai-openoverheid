# BAG via PDOK: API reference

Two open PDOK services, no authentication. Licence of the BAG data: Public Domain Mark 1.0.

## 1. PDOK Locatieserver (address lookup)

`GET https://api.pdok.nl/bzk/locatieserver/search/v3_1/free`

| Parameter | Use |
| :--- | :--- |
| `q` | Free text, or `*` together with filters |
| `fq` | Filter, repeatable: `type:adres`, `postcode:1011PN`, `huisnummer:1`, `huisletter:A`, `huisnummertoevoeging:1`, `adresseerbaarobject_id:<16 digits>` |
| `rows` | Number of results |
| `fl` | Fields to return |

Exact lookup (recommended):

```text
?q=*&fq=type:adres&fq=postcode:1011PN&fq=huisnummer:1
```

Free text (returns candidates by score; verify the result):

```text
?q=Amstel%201%2C%20Amsterdam&fq=type:adres&rows=5
```

On 19 October 2026 the free-text query `Amstel 1 Amsterdam` ranked *Amstel 312A-1, 1017AP* first and *Amstel 1, 1011PN* second.

Useful fields: `weergavenaam`, `adresseerbaarobject_id` (verblijfsobject, ligplaats or standplaats ID), `nummeraanduiding_id`, `postcode`, `huisnummer`, `huisletter`, `huisnummertoevoeging`, `buurtcode`, `buurtnaam`, `wijkcode`, `wijknaam`, `gemeentecode` (without `GM`), `centroide_ll` (WGS84), `centroide_rd` (RD New).

## 2. PDOK BAG OGC API Features

Base: `https://api.pdok.nl/kadaster/bag/ogc/v2/collections`

Collections: `adres`, `verblijfsobject`, `pand`, `ligplaats`, `standplaats`, `woonplaats`. Add `?f=json`. Filters by property, e.g. `identificatie=`, `postcode=`.

### Verblijfsobject

```text
/verblijfsobject/items?f=json&identificatie=0363010012143319
```

Properties include `identificatie`, `status`, `gebruiksdoel` (comma-separated), `oppervlakte` (m²), `hoofdadres_identificatie`, `openbare_ruimte_naam`, `huisnummer`, `huisletter`, `toevoeging`, `postcode`, `woonplaats_naam`, `documentdatum`, `rdf_seealso`, and `pand.href` (list of links to the pand items). Geometry: Point.

### Pand

```text
/pand/items?f=json&identificatie=0363100012186092
```

Properties include `identificatie`, `bouwjaar`, `status`, `gebruiksdoel`, `aantal_verblijfsobjecten`, `documentdatum`, `rdf_seealso`, and `verblijfsobject.href`. Geometry: Polygon.

Note: `pand.href` links to items by an internal UUID, not by the 16-digit `identificatie`. Only follow links that start with `https://api.pdok.nl/kadaster/bag/ogc/v2/collections/pand/items/`.

## 3. Example: Amstel 1, Amsterdam (Stopera)

| Field | Value |
| :--- | :--- |
| Verblijfsobject | `0363010012143319`, in gebruik, bijeenkomstfunctie + kantoorfunctie, 58,673 m² |
| Addresses | Amstel 1, 1011PN; Waterlooplein 6, 1011PG |
| Pand | `0363100012186092`, bouwjaar 1985, 41 verblijfsobjecten |
| Area | `BU0363AF09` (buurt), `WK0363AF` (wijk), `GM0363` (gemeente) |
