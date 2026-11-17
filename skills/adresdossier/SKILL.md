---
name: adresdossier
description: >-
  Use this skill when the user gives one Dutch address (or asks "what do we know about this address / building /
  street") and wants a combined dossier: BAG data (use, floor area, construction year), CBS neighbourhood figures
  compared with the district and the municipality, the zoning plan rules at the location, relevant APV and other
  local rules, Woo decisions and council documents about the street, permits published for the address, and
  registered crime in the neighbourhood. Trigger phrases: "adresdossier", "alles over dit adres", "wat weten we
  over Amstel 1", "dossier voor deze locatie", "buurtprofiel bij dit adres".
---

# Adresdossier: everything public about one address

One address in, one dossier out. This skill only **orchestrates** the other skills and MCP servers of the open-overheid toolkit; each section names the tool to use. Work through the steps in order, because step 1 gives the codes and coordinates all later steps need.

**Scope.** The dossier is about a *place*: the building, the plot, the neighbourhood and what the government decided about them. It is never about the people who live or work there. Do not look up owners, residents or tenants, do not combine sources to find out who lives somewhere, and leave names of private persons out of the summary (council members, officials and companies with a permit may be named). If a request is aimed at a person's home rather than a place, say this skill is not meant for that.

## Step 1. Address and building (BAG) – required

1. `bag_zoek_adres` with postcode + house number (preferred) or free text. Check the returned address; with several candidates (`1-H`, `1-1`), ask which one.
2. `bag_adresinfo`: use (*gebruiksdoel*), floor area, status, construction year, number of units in the building, all addresses of the object, `buurtcode`, `wijkcode`, `gemeentecode` and the RD coordinates.

Keep these for the next steps: **street name, house number, postcode, buurtcode (BU…), wijkcode (WK…), gemeentecode (GM…), buurt and wijk names, RD x/y.** For Amsterdam also note the stadsdeel (derive it from the wijk; Osdorp and Geuzenveld are Nieuw-West, for example) and its NotuBiz organisation id (see the `raadsinformatie` skill).

## Step 2. Neighbourhood figures (CBS) – required

Use the `cbs` skill:

1. `cbs_search_tables` with `kerncijfers wijken en buurten`; take the newest table (e.g. `86165NED`). Check with `cbs_get_table_info` which period it covers.
2. `cbs_find_codes` (dimension `Measure`) for: inhabitants, age groups (0-15, 65+), households and single-person households, population density, average WOZ value, share of rented and social rented homes, average income per inhabitant, share of low-income households, people on social assistance (bijstand).
3. `cbs_get_observations` with filter `WijkenEnBuurten: [buurtcode, wijkcode, gemeentecode]` so every figure has two comparisons.

Report the period of each figure; CBS income and benefits figures lag one or two years behind the population figures. For Amsterdam the `amsterdam-kerncijfers` skill (BBGA) adds city figures per neighbourhood (e.g. safety index, satisfaction with the neighbourhood): optional.

## Step 3. Zoning plan at the location – required

1. `bag_plannen_op_adres` (server `bag`) with the same postcode and house number: the bestemmingsplannen and paraplu-plannen that apply, the enkelbestemming (e.g. *Gemengd - 2*, *Wonen*), dubbelbestemmingen (e.g. *Waarde - Cultuurhistorie*, archaeology), building plane and aanduidingen (maximum height, functions), with links to the rules.
2. This is the **temporary part** of the omgevingsplan (old Wro plans, updated twice a year). Changes adopted under the Omgevingswet since 2024 and the *bruidsschat* are not in it. Always add the link to *Regels op de kaart*: `https://omgevingswet.overheid.nl/regels-op-de-kaart` and tell the user to check the address there for the current, legally binding picture.
3. Optional, with the `omgevingsplan` skill: recent omgevingsplan amendments by the municipality that mention the street.

## Step 4. Permits and notices for the address – recommended

With the `officiele-bekendmakingen` skill, search the municipal gazette (*gemeenteblad*) for the street and house number (e.g. `"Amstel 1"` with creator `Amsterdam`) over the last few years: omgevingsvergunningen, exploitatievergunningen, terrace permits, traffic decisions. List date, type of decision and link; these notices are the most concrete source of "what is going on at this address".

## Step 5. Local rules (APV and other ordinances) – recommended

With the `lokale-regelgeving` skill:

1. `lr_zoek_regelingen` with `titel: "Algemene Plaatselijke Verordening"` (Amsterdam: CVDR72510) and pick the articles that matter for the **use found in step 1** (`lr_artikel` with a `zoekterm`): e.g. for horeca `terras`, `sluitingstijd`, `exploitatievergunning`; for housing `overlast`, `bouwwerkzaamheden`; for a shop `venten`, `reclame`.
2. `lr_zoek_regelingen` with `trefwoord` = street name, buurt name and wijk name: area designations (alcohol ban, camera surveillance, parking zones, event areas) are often separate decisions that name the area.
3. If the use calls for it: `Afvalstoffenverordening`, `Parkeerverordening`, `Huisvestingsverordening` (holiday rental, splitting), `Erfgoedverordening` (monuments).

State for each rule that it applies city-wide unless the decision names the area.

## Step 6. Woo decisions – recommended (Amsterdam)

`search_woo_decisions` (server `amsterdam-woo`) with the street name, and with the building or project name if it has one (e.g. *Stopera*). Report title, date and link. Many results are about the street in general; say so instead of claiming they concern this address.

## Step 7. Council and district documents – recommended

1. **Local archive** (`raadsarchief` skill): `archive_search` with the street name (and the building or project name), `mode: documents`, plus `mode: first` for "since when". If no archive or index exists, say so and offer to build one for the stadsdeel (`archive_period` + `archive_index`), but do not start a long download without asking.
2. **Motions** (Gemeenteraad and stadsdelen with a motions module): `motions_search` with the street or project name.
3. **Upcoming meetings:** `get_meetings` for the stadsdeel and the Gemeenteraad; mention agenda items that name the street or project.

## Step 8. Registered crime in the neighbourhood – optional

Requires the separate **politie-misdrijven** plugin (police open data, table 47022NED). If its tools (`misdrijven_cijfers`, `misdrijven_gebieden`) are available: figures for the buurtcode for the last 12 months and the same period a year earlier, compared with the wijk and the municipality, with the main types (burglary, bicycle theft, violence, vandalism). Per 1,000 inhabitants only with the inhabitant count from step 2. If the plugin is not installed, say so and link to `https://data.politie.nl`. Small neighbourhoods give small numbers: do not draw conclusions from a handful of incidents.

## Output

Use the template in [references/dossier-template.md](references/dossier-template.md): first a summary of at most eight lines (what the building is, what the plan allows, the most notable figures and decisions), then one section per step with a table and the source and date of each source, and finally a list of gaps (sources that could not be reached, a missing archive, a missing plugin).

- Write in the user's language (Dutch for a Dutch question); keep official terms in Dutch.
- Give every number its period and source, and every decision its date and link.
- Separate **facts from the registers** (BAG, CBS, plans, decisions) from **your interpretation**; mark interpretation as such.
- When the user wants to keep or share the dossier, deliver it as a document (in Claude: a doc artifact; elsewhere a Markdown file), with the summary at the top and the sections collapsible where the format allows.
- Not legal advice: for permits and enforcement the municipality's own assessment applies.

## Why this skill was added (version 1.10.0)

The toolkit could already answer single questions about an address, but residents, journalists and small parties usually need the whole picture at once: what the building is, what may be built or done there, how the neighbourhood is doing, and what the municipality has decided or published about it. Doing that by hand meant eight separate searches with different codes. This skill fixes the order (BAG first, because it yields the codes and coordinates) and adds the missing link to zoning rules at a point (`bag_plannen_op_adres`).
