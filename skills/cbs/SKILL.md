---
name: cbs
description: >-
  Use this skill whenever the user asks for statistics from CBS (Centraal Bureau voor de Statistiek / Statistics
  Netherlands) or StatLine: population, age, households, income, housing, benefits, health, crime, energy,
  facilities, per municipality, district (wijk) or neighbourhood (buurt), or to compare Dutch areas and
  municipalities with each other (e.g. Amsterdam Nieuw-West versus other cities), or to show such figures on a
  map of districts and neighbourhoods. Also use it for questions about CBS-cijfers, kerncijfers wijken en
  buurten and national comparisons.
---

# CBS StatLine (open data)

Use this skill for official CBS statistics for the whole of the Netherlands, down to neighbourhood level.

- **Source:** CBS StatLine through the open data API `https://datasets.cbs.nl/odata/v1` (OData v4).
- **No key required.** Licence **CC BY 4.0**: always credit "Source: CBS" with figures.
- Full explanation of the API, codes and pitfalls: [references/cbs-statline.md](references/cbs-statline.md).

## Which source to use

| Question | Use |
| :--- | :--- |
| Amsterdam figures with the city's own indicators (BBGA, Amsterdam area divisions) | skill `amsterdam-kerncijfers` |
| National figures, other municipalities, comparisons between municipalities, or CBS as the source | **this skill** |
| Both | Fetch both and name the source of each figure; definitions and reference dates can differ. |

## Workflow (4 steps)

1. **Choose a table.** For neighbourhood questions the default table is **`86165NED`, Kerncijfers wijken en buurten 2025**. For other subjects, search with `cbs_search_tables` (e.g. "inkomen", "bevolking", "criminaliteit"; table titles are in Dutch) and pick the most recent relevant table.
2. **Inspect the dimensions.** `cbs_get_table_info` lists the dimensions, e.g. `WijkenEnBuurten`, or `RegioS` and `Perioden` in other tables.
3. **Look up codes.**
   - Subjects: `cbs_find_codes` with `dimension: "Measure"` and a search term (e.g. "inwoners" gives `T001036`, number of residents).
   - Areas: `cbs_find_codes` with `dimension: "WijkenEnBuurten"` and a place name (e.g. "Osdorp").
4. **Fetch the figures.** `cbs_get_observations` with `measures` and `filters`, e.g.:

   ```json
   { "table_id": "86165NED",
     "measures": ["T001036"],
     "filters": { "WijkenEnBuurten": ["GM0363", "WK0363FJ"] } }
   ```

Always filter on measure and/or area: a complete table easily holds more than a million values.

## Area codes (examples)

| Code | Area |
| :--- | :--- |
| `NL00` | The Netherlands |
| `GM0363` | Municipality of Amsterdam |
| `WK0363..` | District in Amsterdam (e.g. `WK0363FJ` Osdorp-Midden) |
| `BU0363....` | Neighbourhood in Amsterdam (e.g. `BU0363FK03` Osdorpplein e.o.) |

For Amsterdam, the letters after `0363` follow the city's own area division; `F` belongs to Stadsdeel Nieuw-West. Always check a code with `cbs_find_codes` before using it; district and neighbourhood boundaries change from year to year.

## Linking with other skills

- **Address to neighbourhood:** the `bag` skill (and the PDOK Locatieserver in `omgevingsplan`) returns `buurtcode` and `wijkcode` for an address. These can be used directly as `WijkenEnBuurten` codes.
- **Comparison:** put Amsterdam BBGA figures next to CBS figures for the same district, naming the source of each.

## Without the MCP server

All tools are plain HTTP GET requests; see the reference for the URLs. Example:

```text
https://datasets.cbs.nl/odata/v1/CBS/86165NED/Observations?$filter=Measure eq 'T001036' and WijkenEnBuurten eq 'GM0363'
```

## Presentation

- Give the table number, table title and reference year with every answer.
- Report `StringValue` (text) or `Value` (number) with the unit from the measure.
- A `ValueAttribute` other than `None` means, for example, confidential or unknown: say so and never fill in a value yourself.
- For rounded or provisional figures, mention the status from `cbs_get_table_info`.

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
