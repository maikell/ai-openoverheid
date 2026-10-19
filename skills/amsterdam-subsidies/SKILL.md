---
name: amsterdam-subsidies
description: Doorzoeken en aggregeren van het Openbaar Subsidieregister van Gemeente Amsterdam (live koppeling met het PowerBI dashboard).
---

# Amsterdam Openbaar Subsidieregister Skill

Gebruik deze vaardigheid wanneer de gebruiker vraagt om:
1. Het inzien of analyseren van gemeentelijke subsidies van Gemeente Amsterdam.
2. Filteren op **onderwerp/regeling**, **datum/subsidiejaar** of **cluster** (stadsdeel of directie).
3. Het opvragen van verleende bedragen, aanvragers en besluitdata.

---

## 1. Live Databron (Geen handmatige downloads!)

In plaats van handmatig CSV's te downloaden uit het PowerBI portaal, tapt deze dienst direct in op de officiële open data stream van Datapunt Amsterdam:
```http
GET https://api.data.amsterdam.nl/v1/subsidies/openbaar_subsidieregister?_format=csv
```
Deze stream wordt dagelijks bijgewerkt en bevat exact dezelfde dataset die het PowerBI dashboard voedt.

---

## 2. Beschikbare MCP Tools

De bijbehorende MCP-server `amsterdam-subsidies` biedt twee tools:

1. **`search_subsidies`**:
   - Zoekt records op basis van zoektermen (`query`), organisatieonderdeel (`cluster`), en subsidiejaar (`jaar`).
   - Geeft aanvrager, projectnaam, regeling, cluster, bedragen en besluitdata terug.

2. **`get_subsidies_summary`**:
   - Groepeert en sommeert verleende bedragen per cluster (`organisatieonderdeel`) of beleidsterrein.
