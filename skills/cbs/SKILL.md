---
name: cbs
description: >-
  Use this skill whenever the user asks for statistics from CBS (Centraal Bureau voor de Statistiek / Statistics
  Netherlands) or StatLine: population, age, households, income, housing, benefits, health, crime, energy,
  facilities, per municipality, district (wijk) or neighbourhood (buurt), or to compare Dutch areas and
  municipalities with each other (e.g. Amsterdam Nieuw-West versus other cities), or to show such figures on a
  map of districts and neighbourhoods. Gebruik ook bij vragen over
  CBS-cijfers, kerncijfers wijken en buurten en landelijke vergelijkingen.
---

# CBS StatLine (open data)

Gebruik deze skill voor officiële statistieken van het CBS, voor heel Nederland, tot op buurtniveau.

- **Bron:** CBS StatLine via de open data-API `https://datasets.cbs.nl/odata/v1` (OData v4).
- **Geen sleutel nodig.** Licentie **CC BY 4.0**: vermeld altijd "Bron: CBS" bij cijfers.
- Uitgebreide uitleg van de API, codes en valkuilen: [references/cbs-statline.md](references/cbs-statline.md).

## Wanneer welke bron

| Vraag | Gebruik |
| :--- | :--- |
| Amsterdamse cijfers met eigen gemeentelijke indicatoren (BBGA, gebiedsgerichte gebieden) | skill `amsterdam-kerncijfers` |
| Landelijke cijfers, andere gemeenten, vergelijken tussen gemeenten, of CBS als bron | **deze skill** |
| Beide | Haal beide op en noem bij elk getal de bron; definities en peildata kunnen verschillen. |

## Werkwijze (4 stappen)

1. **Tabel kiezen.** Voor buurtvragen is de standaardtabel **`86165NED` — Kerncijfers wijken en buurten 2025**. Voor andere onderwerpen: zoek met `cbs_search_tables` (bijv. "inkomen", "bevolking", "criminaliteit") en kies de nieuwste relevante tabel.
2. **Dimensies bekijken.** `cbs_get_table_info` toont de dimensies, bijv. `WijkenEnBuurten`, of `RegioS` en `Perioden` in andere tabellen.
3. **Codes opzoeken.**
   - Onderwerpen: `cbs_find_codes` met `dimension: "Measure"` en een zoekterm (bijv. "inwoners" → `T001036`).
   - Gebieden: `cbs_find_codes` met `dimension: "WijkenEnBuurten"` en een plaatsnaam (bijv. "Osdorp").
4. **Cijfers ophalen.** `cbs_get_observations` met `measures` en `filters`, bijv.:

   ```json
   { "table_id": "86165NED",
     "measures": ["T001036"],
     "filters": { "WijkenEnBuurten": ["GM0363", "WK0363FJ"] } }
   ```

Filter altijd op maatstaf en/of gebied: een complete tabel bevat al snel meer dan een miljoen waarden.

## Gebiedscodes (voorbeelden)

| Code | Gebied |
| :--- | :--- |
| `NL00` | Nederland |
| `GM0363` | Gemeente Amsterdam |
| `WK0363..` | Wijk in Amsterdam (bijv. `WK0363FJ` Osdorp-Midden) |
| `BU0363....` | Buurt in Amsterdam (bijv. `BU0363FK03` Osdorpplein e.o.) |

Voor Amsterdam volgen de letters na `0363` de gemeentelijke gebiedsindeling; de `F` hoort bij Stadsdeel Nieuw-West. Controleer een code altijd met `cbs_find_codes` voordat je hem gebruikt; wijk- en buurtindelingen veranderen per jaar.

## Koppelen met andere skills

- **Adres → buurt:** de PDOK Locatieserver (skill `omgevingsplan`) geeft bij een adres ook `buurtcode` en `wijkcode`. Die zijn direct bruikbaar als `WijkenEnBuurten`-code.
- **Vergelijking:** zet Amsterdamse BBGA-cijfers naast CBS-cijfers voor dezelfde wijk, met de bron per getal.

## Zonder MCP-server

Alle tools zijn gewone HTTP GET-verzoeken; zie de referentie voor de URL's. Voorbeeld:

```text
https://datasets.cbs.nl/odata/v1/CBS/86165NED/Observations?$filter=Measure eq 'T001036' and WijkenEnBuurten eq 'GM0363'
```

## Presentatie

- Noem tabelnummer, tabeltitel en peiljaar bij elk antwoord.
- Geef `StringValue` (tekst) of `Value` (getal) met de eenheid uit de maatstaf.
- Een `ValueAttribute` anders dan `None` betekent bijvoorbeeld geheim of onbekend: zeg dat, vul niets zelf in.
- Afgeronde of voorlopige cijfers: vermeld de status uit `cbs_get_table_info`.

## Maps of CBS figures

Use this when the user asks to show CBS figures on a map, for example "colour the neighbourhoods of Nieuw-West by the share of residents aged 65 and over".

### Why this was added (version 1.7.0)

- **No extra map service is needed.** A first test showed that an assistant can build a complete interactive choropleth map from open data alone. A hosted map connector (such as Felt) would require an account, which conflicts with this toolkit's principle of open sources without keys.
- **Map pages usually cannot fetch data themselves.** Published pages (Claude artifacts, many static hosts) block requests to other websites at view time, and map tiles from external servers are blocked too. The boundaries and figures must be fetched beforehand, reduced in size and embedded in the page. Without this guidance, assistants tend to write pages that try to load live data and silently show nothing.
- **PDOK already combines shape and numbers.** The PDOK service "CBS Wijken en Buurten" returns every district and neighbourhood boundary together with the CBS key figures (population, age groups, households). One request gives everything a map needs, with the same area codes (`WK0363..`, `BU0363....`) as the `cbs` MCP tools.
- **Raw boundaries are too large.** The full geometries for the 73 neighbourhoods of Nieuw-West are about 90 KB; simplified and delta-encoded they are about 20 KB, small enough to embed while still looking right at city-district scale.

### How to do it

1. **Get boundaries and figures** with `scripts/pdok_area_geometries.mjs` (Node.js 18+):

   ```bash
   node scripts/pdok_area_geometries.mjs --gemeente GM0363 --prefix BU0363F --out nieuw-west.json
   ```

   `--prefix BU0363F` keeps the neighbourhoods of Stadsdeel Nieuw-West; use `--level wijken` for districts. If the assistant's own environment cannot reach `api.pdok.nl`, run the same logic in a browser the user controls (the service allows cross-origin requests) or ask the user to run the script.
2. **Add more CBS figures if needed** with `cbs_get_observations` (table `86165NED`), matching on the area code.
3. **Embed the JSON in the page** and draw it as inline SVG with a simple equirectangular projection (scale longitude by `cos(latitude)`). No map library or tile server is needed.
4. **Verify the embedded data.** Compare a checksum or a few known values with the source before publishing; copying long encoded strings by hand is error-prone.

### Presentation rules for maps

- Grey out areas with very few residents (for example fewer than 200); CBS percentages there are unstable or suppressed.
- Treat CBS placeholder values such as `-99997` as "no data", never as numbers.
- Use a sequential colour scale with 4 to 6 classes, show the legend, and name a reference value (for example the whole municipality).
- State the source on the page: "CBS, Kerncijfers wijken en buurten 2025, via PDOK, CC BY 4.0", the reference date, and that boundaries are simplified.
