# Gemeente Amsterdam Onderzoek en Statistiek - API Reference

## Base URL
`https://onderzoek.amsterdam.nl/statistieken/api`

## Core Data Schema

### 1. `GET /data/meta/indicators.json`
Returns an array of indicator metadata objects (~1100+ items):
```json
[
  {
    "id": 2267,
    "name": "BEVTOTAAL",
    "type": "number",
    "unit": "aantal",
    "decimals": 0,
    "indicator": "BEVTOTAAL",
    "source": "BRP, O&S",
    "deprecated": false,
    "deprecatedReason": null,
    "deprecatedDate": null,
    "themes": [ "Bevolking" ],
    "label": "Bevolking totaal",
    "labelShort": "Bevolking totaal",
    "definition": "Personen die op 1 januari zijn opgenomen in het bevolkingsregister van de gemeente Amsterdam...",
    "frequency": "1 keer per jaar",
    "enThemes": [ "Population" ],
    "enLabel": "Population",
    "enLabelShort": "Population",
    "referenceDate": "1 januari",
    "sort": 1020
  }
]
```

### 2. `GET /data/meta/areas.json`
Returns an object mapping area code to area description (800+ areas):
```json
{
  "GA01": {
    "type": "ggw-gebied",
    "label": "GGW-gebied",
    "naam": "Centrum-West",
    "code": "GA01",
    "stadsdeelNaam": "Centrum",
    "stadsdeelCode": "A",
    "gemeenteNaam": "Amsterdam"
  },
  "0363": {
    "type": "gemeente",
    "label": "Gemeente",
    "naam": "Amsterdam",
    "code": "0363"
  }
}
```

### 3. `GET /data/indicatoren/{INDICATOR}.json`
Returns all data points for that indicator:
```json
[
  {
    "indicatorId": 2267,
    "indicatorName": "BEVTOTAAL",
    "areaCode": "GA01",
    "areaName": "Centrum-West",
    "areaDate": "2022-03-24",
    "areaType": "ggw-gebied",
    "year": 2026,
    "value": 43905
  }
]
```

## Geographic Levels (`indeling`)
- `gemeente`: Amsterdam city-wide (code `0363`)
- `stadsdelen`: City districts (e.g. `A` for Centrum, `B` for Westpoort, `E` for West, `F` for Nieuw-West, `K` for Zuid, `M` for Oost, `N` for Noord, `T` for Zuidoost)
- `ggwgebieden`: Area-based working areas (Gebiedsgericht Werken, e.g. `GA01` Centrum-West, `GA02` Centrum-Oost, etc.)
- `wijken`: Neighborhoods (sub-districts)
- `buurten`: Smallest statistical zones
- `winkelgebieden`: Shopping areas
