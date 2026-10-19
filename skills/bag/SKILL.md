---
name: bag
description: >-
  Use this skill whenever the user asks about a Dutch address or building from the BAG (Basisregistratie Adressen
  en Gebouwen): whether an address exists, its official spelling and postcode, the use (gebruiksdoel) and floor area
  of a dwelling or unit, the construction year (bouwjaar) and status of a building, how many units a building has,
  or which neighbourhood and district an address is in. Also use it for questions like "when was this building
  built", "is this a home or an office", "how many dwellings are in this building", "which neighbourhood is this
  address in".
---

# BAG: Addresses and Buildings

Use this skill for official data on addresses and buildings in the Netherlands from the **Basisregistratie Adressen en Gebouwen (BAG)**, the national register maintained by municipalities and published by the Kadaster.

- **Sources:** PDOK Locatieserver (address lookup, neighbourhood and district codes) and the PDOK BAG OGC API (verblijfsobjecten and panden).
- **No key required.** Licence: Public Domain Mark 1.0. API details: [references/bag_pdok_reference.md](references/bag_pdok_reference.md).

## Concepts

| BAG term | Meaning |
| :--- | :--- |
| **Nummeraanduiding** | The address itself (street, house number, letter, addition, postcode). |
| **Verblijfsobject** | The unit behind the address (a dwelling, office, shop), with use and floor area. |
| **Pand** | The building, with construction year and status. A building can contain many units; a unit can span several buildings. |
| **Ligplaats / standplaats** | A houseboat mooring or caravan pitch with an address but no verblijfsobject. |

A verblijfsobject can have several addresses (a main address and secondary addresses). Example: the Stopera is both Amstel 1 and Waterlooplein 6.

## Workflow

1. **Pin down the address** with `bag_zoek_adres`, preferably by **postcode + house number** (exact). Free text ("Amstel 1 Amsterdam") returns candidates by relevance and can put a different address first (for example *Amstel 312A-1*). Always check street, house number and postcode.
2. **Get the details** with `bag_adresinfo`: use, floor area and status of the unit, construction year and number of units of the building, all addresses of the object, and the neighbourhood, district and municipality codes.
3. **Building only** with `bag_pand` if you have a building ID.

Several addresses on one house number (e.g. `1-H`, `1-1`)? `bag_adresinfo` then returns the candidates; ask for or choose the right letter or addition.

## Linking with other skills

- **Neighbourhood statistics:** the `buurtcode` and `wijkcode` from `bag_adresinfo` (e.g. `BU0363AF09`) can be used directly in the `cbs` skill (`WijkenEnBuurten` filter).
- **Rules at the location:** use the coordinates with the `omgevingsplan` skill.
- **Local rules:** the `lokale-regelgeving` skill, for example for the APV.

## Points of attention

- **Floor area** is the usable floor area of the unit in m², not of the whole building.
- **Use** (gebruiksdoel) is what is registered in the BAG; actual use can differ.
- **Construction year** is the original construction year of the building, even after major renovations.
- **Privacy:** the BAG contains no owners or residents. Do not link BAG data to people.

## Without the MCP server

```text
https://api.pdok.nl/bzk/locatieserver/search/v3_1/free?q=*&fq=type:adres&fq=postcode:1011PN&fq=huisnummer:1
https://api.pdok.nl/kadaster/bag/ogc/v2/collections/verblijfsobject/items?f=json&identificatie=0363010012143319
https://api.pdok.nl/kadaster/bag/ogc/v2/collections/pand/items?f=json&identificatie=0363100012186092
```

## Why this skill was added (version 1.8.0)

- **Address questions came up in every other skill without an authoritative source.** Zoning, local rules, statistics and council documents all start from an address, but the toolkit could only geocode it. The BAG adds what is actually registered there: use, floor area, construction year and the number of units in a building.
- **Free-text geocoding is not reliable enough on its own.** A test with "Amstel 1 Amsterdam" ranked *Amstel 312A-1* above the correct address. The skill and server therefore prefer an exact postcode + house number lookup and return candidates instead of guessing.
- **One object can have several addresses.** The Stopera is both Amstel 1 and Waterlooplein 6. Returning all addresses of an object avoids treating them as different buildings.
- **It links the other skills.** The BAG lookup returns the CBS neighbourhood and district codes, so an address leads directly to `cbs` statistics and maps.
- **No key and no personal data.** Both PDOK services are open (Public Domain Mark 1.0) and the BAG holds no owner or resident information, which fits the toolkit's principles.
