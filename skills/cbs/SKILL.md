---
name: cbs
description: >-
  Use this skill whenever the user asks for statistics from CBS (Centraal Bureau voor de Statistiek / Statistics
  Netherlands) or StatLine: population, age, households, income, housing, benefits, health, crime, energy,
  facilities, per municipality, district (wijk) or neighbourhood (buurt), or to compare Dutch areas and
  municipalities with each other (e.g. Amsterdam Nieuw-West versus other cities). Gebruik ook bij vragen over
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
