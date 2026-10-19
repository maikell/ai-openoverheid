# CBS StatLine: uitleg van de open data-API

Deze referentie hoort bij de skill `cbs`. Hij beschrijft de nieuwe CBS open data-API (OData v4) en hoe je er gericht cijfers uit haalt.

- **Basis-URL:** `https://datasets.cbs.nl/odata/v1`
- **Authenticatie:** geen.
- **Licentie:** CC BY 4.0. Bronvermelding: "CBS".
- **Documentatie:** [Snelstartgids OData v4](https://www.cbs.nl/nl-nl/onze-diensten/open-data/statline-als-open-data/snelstartgids-odata-v4), [release notes en Swagger](https://datasets.cbs.nl/odata/v1/releasenotes.html).

De oudere API (`opendata.cbs.nl/ODataApi`, OData v3) bestaat nog, maar gebruik voor nieuw werk deze v4-API.

---

## 1. Het datamodel in het kort

Een StatLine-tabel is opgebouwd uit **cellen** (`Observations`). Elke cel heeft:

| Veld | Betekenis |
| :--- | :--- |
| `Measure` | De maatstaf of het onderwerp, bijv. `T001036` = Aantal inwoners |
| een of meer dimensies | Bijv. `WijkenEnBuurten`, `RegioS`, `Perioden`, `Geslacht` |
| `Value` | Getalwaarde (of `null`) |
| `StringValue` | Tekstwaarde, bijv. een gemeentenaam (kan rechts opgevuld zijn met spaties) |
| `ValueAttribute` | `None`, of een aanduiding zoals geheim/onbekend |

Lege cellen worden niet teruggegeven.

## 2. Endpoints

| Doel | URL |
| :--- | :--- |
| Alle tabellen | `/Datasets` |
| Tabellen zoeken | `/Datasets?$filter=contains(Title,'wijken en buurten')&$select=Identifier,Title,Modified&$orderby=Modified desc` |
| Metadata van een tabel | `/CBS/{tabel}/Properties` |
| Dimensies van een tabel | `/CBS/{tabel}/Dimensions` |
| Maatstaven (onderwerpen) | `/CBS/{tabel}/MeasureCodes` |
| Codes van een dimensie | `/CBS/{tabel}/{Dimensie}Codes`, bijv. `/CBS/86165NED/WijkenEnBuurtenCodes` |
| Groepen van een dimensie | `/CBS/{tabel}/{Dimensie}Groups` |
| Cijfers | `/CBS/{tabel}/Observations` |
| Hele tabel als CSV | `https://datasets.cbs.nl/csv/CBS/nl/{tabel}` |

`CBS` is de catalogus. Bijna alle tabellen staan in deze catalogus.

## 3. Filteren (OData)

Combineer filters met `and`, alternatieven met `or`:

```text
/CBS/86165NED/Observations?$filter=Measure eq 'T001036' and (WijkenEnBuurten eq 'GM0363' or WijkenEnBuurten eq 'WK0363FJ')
/CBS/86165NED/MeasureCodes?$filter=contains(Title,'inkomen')
/CBS/86165NED/WijkenEnBuurtenCodes?$filter=contains(Title,'Osdorp')
```

- Tekst staat tussen enkele aanhalingstekens; een `'` in een zoekterm schrijf je als `''`.
- `contains()` is hoofdlettergevoelig.
- URL-encode de filter als je hem zelf in een URL zet.

## 4. Paginering en limieten

- Eén antwoord bevat **maximaal 100.000 cellen**.
- Is er meer, dan staat de volgende pagina in `@odata.nextLink`. Volg die link tot hij ontbreekt.
- Filter daarom altijd op maatstaf en/of gebied; `86165NED` alleen al heeft ruim 1,5 miljoen cellen.

## 5. Veelgebruikte tabel: Kerncijfers wijken en buurten

| Tabel | Titel |
| :--- | :--- |
| `86165NED` | Kerncijfers wijken en buurten 2025 |

Zoek oudere of nieuwere jaargangen met `contains(Title,'Kerncijfers wijken en buurten')`. Elke jaargang is een aparte tabel met de gebiedsindeling van dat jaar.

Dimensie: `WijkenEnBuurten`. Voorbeelden van maatstaven in deze tabel:

| Code | Maatstaf | Eenheid |
| :--- | :--- | :--- |
| `T001036` | Aantal inwoners | aantal |
| `3000` / `4000` | Mannen / Vrouwen | aantal |
| `10680` | 0 tot 15 jaar | aantal |
| `53050` | 15 tot 25 jaar | aantal |
| `53310` | 25 tot 45 jaar | aantal |
| `53715` | 45 tot 65 jaar | aantal |
| `80200` | 65 jaar of ouder | aantal |
| `GM000C` | Gemeentenaam | naam |
| `R00003` | Soort regio | omschrijving |

Zoek andere maatstaven (inkomen, woningen, uitkeringen, voorzieningen) op met `MeasureCodes` en een zoekterm. Codes kunnen per jaargang verschillen.

## 6. Gebiedscodes

| Voorvoegsel | Niveau | Voorbeeld |
| :--- | :--- | :--- |
| `NL00` | Nederland | `NL00` |
| `GM` + 4 cijfers | Gemeente | `GM0363` Amsterdam |
| `WK` + gemeentecode + 2 tekens | Wijk | `WK0363FJ` Osdorp-Midden |
| `BU` + gemeentecode + 4 tekens | Buurt | `BU0363FK03` Osdorpplein e.o. |

In andere tabellen heet de regiodimensie vaak `RegioS`, met dezelfde soort codes (`GM0363`, ook `PV..` voor provincies). Controleer de naam met `/Dimensions`.

**Van adres naar code:** de PDOK Locatieserver geeft bij een adres onder andere `buurtcode`, `wijkcode` en `gemeentecode`:

```text
https://api.pdok.nl/bzk/locatieserver/search/v3_1/free?q=Amstel%201%20Amsterdam&rows=1&fl=weergavenaam,buurtcode,buurtnaam,wijkcode,gemeentecode
```

## 7. Perioden

Tabellen met een `Perioden`-dimensie gebruiken codes als `2025JJ00` (jaar), `2025KW01` (kwartaal) en `2025MM01` (maand). Zoek ze op via `/CBS/{tabel}/PeriodenCodes`.

## 8. Voorbeeld in PowerShell

```powershell
$base = "https://datasets.cbs.nl/odata/v1/CBS/86165NED"
$filter = [uri]::EscapeDataString("Measure eq 'T001036' and WijkenEnBuurten eq 'GM0363'")
$wc = New-Object System.Net.WebClient
$wc.Encoding = [System.Text.Encoding]::UTF8
$wc.Headers.Add("Accept", "application/json")
($wc.DownloadString("$base/Observations?`$filter=$filter") | ConvertFrom-Json).value
```

## 9. Valkuilen

- **Jaargang en indeling:** wijk- en buurtcodes veranderen tussen jaren. Vergelijk over jaren heen alleen als de code in beide tabellen bestaat.
- **Peildatum:** bevolking is meestal per 1 januari; inkomen loopt vaak een of twee jaar achter. Lees de definitie in `MeasureCodes` (veld `Description`).
- **Geheimhouding:** kleine aantallen worden afgeschermd (`ValueAttribute`). Vul die nooit zelf in.
- **Verschil met BBGA:** de Amsterdamse BBGA (skill `amsterdam-kerncijfers`) kan andere definities, peildata en gebiedsgrenzen hebben. Noem altijd de bron per getal.

## 10. Mapping CBS figures (added in 1.7.0)

**Why:** published map pages usually cannot request data from other websites while they are being viewed, so boundaries and figures have to be prepared in advance. This section documents the source and format used by `scripts/pdok_area_geometries.mjs`, so that any assistant (Gemini or Claude) can reproduce it.

**Source:** PDOK OGC API Features, `https://api.pdok.nl/cbs/wijken-en-buurten-2025/ogc/v1`, collections `gemeenten`, `wijken` and `buurten`. Filter with `?gemeentecode=GM0363`, page with the `next` link, coordinates in WGS84 (longitude, latitude). Each feature carries CBS key figures such as `aantal_inwoners`, `percentage_personen_65_jaar_en_ouder`, `percentage_personen_0_tot_15_jaar`, `percentage_eenpersoonshuishoudens` and `aantal_huishoudens`. Percentages are rounded to whole numbers. `-99997` means missing or confidential.

```text
https://api.pdok.nl/cbs/wijken-en-buurten-2025/ogc/v1/collections/buurten/items?f=json&limit=1000&gemeentecode=GM0363
```

**Format:** the script simplifies each ring (Douglas-Peucker, default tolerance 0.00012 degrees, about 10 to 15 m) and writes points as integer deltas in units of 1e-5 degree. The decoding snippet is in the script header.

**Size guide:** Stadsdeel Nieuw-West (73 neighbourhoods) is about 20 KB encoded; all of Amsterdam's neighbourhoods are roughly six times that. Raise `--tolerance` for larger areas.
