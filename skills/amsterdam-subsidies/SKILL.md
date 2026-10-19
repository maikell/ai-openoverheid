---
name: amsterdam-subsidies
description: >-
  Use this skill to search and aggregate the Openbaar Subsidieregister (public subsidy register) of
  Gemeente Amsterdam: who received a subsidy, how much, under which scheme, from which department or
  district, in which year. Live data from Datapunt Amsterdam, the same source as the PowerBI dashboard.
---

# Amsterdam Public Subsidy Register

Use this skill when the user asks to:

1. View or analyse municipal subsidies granted by Gemeente Amsterdam.
2. Filter by **subject or scheme**, **date or subsidy year**, or **cluster** (district or directorate).
3. Retrieve granted amounts, applicants and decision dates.

---

## 1. Live data source (no manual downloads)

Instead of exporting CSV files from the PowerBI portal, use the official open data stream of Datapunt Amsterdam:

```http
GET https://api.data.amsterdam.nl/v1/subsidies/openbaar_subsidieregister?_format=csv
```

The stream is updated daily and contains the same dataset that feeds the PowerBI dashboard.

Main columns: `dossiernummer`, `aanvrager` (applicant), `projectnaam`, `regelingnaam` (scheme), `organisatieonderdeel` (cluster, e.g. a district), `beleidsterrein` (policy area), `bedragAangevraagd` (requested), `bedragVerleend` (granted), `subsidiejaar`, `publicatiedatumVerleningsbesluit`.

---

## 2. MCP tools

The `amsterdam-subsidies` MCP server offers two tools:

1. **`search_subsidies`**
   - Filters records by search term (`query`, matched against applicant, project and scheme), cluster (`cluster`) and subsidy year (`jaar`).
   - Returns applicant, project, scheme, cluster, requested and granted amounts, and decision dates.

2. **`get_subsidies_summary`**
   - Groups and sums granted amounts per cluster (`organisatieonderdeel`) or per policy area (`beleidsterrein`).

The server caches the CSV for up to 12 hours.

## 3. Presenting results

- Distinguish **requested** from **granted** amounts; an empty granted amount usually means no decision has been published yet.
- Name the subsidy year and the cluster for every total.
- Applicants can be private individuals ("Particulier"). Do not try to identify them; report amounts and schemes only.
- Source: "Gemeente Amsterdam, Openbaar Subsidieregister (Datapunt Amsterdam)".
