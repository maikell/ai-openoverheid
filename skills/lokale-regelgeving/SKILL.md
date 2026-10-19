---
name: lokale-regelgeving
description: >-
  Use this skill whenever the user asks what a Dutch municipality, province or water board has ruled in its own
  regulations: the text of a local ordinance (verordening), the APV (Algemene Plaatselijke Verordening), policy
  rules (beleidsregels), fees, waste, parking, terraces, events, dogs, noise, subsidy schemes, or which version
  applied on a given date. Source: CVDR / lokaleregelgeving.overheid.nl. Also use it for questions like "what does
  the APV say about ...", "which ordinance applies to ...", "is this allowed under municipal rules".
---

# Local Regulations (CVDR)

Use this skill for the **text in force** of rules that a municipality, province or water board adopts itself: ordinances (such as the APV), policy rules and other generally binding decisions.

- **Source:** CVDR (Centrale Voorziening Decentrale Regelgeving) by KOOP, also shown on `lokaleregelgeving.overheid.nl`.
- **No key required.** API details: [references/cvdr_sru_reference.md](references/cvdr_sru_reference.md).

## Which skill to use

| Question | Use |
| :--- | :--- |
| What does the APV, the waste ordinance or the parking ordinance say now? | **this skill** |
| Which decision changed the rule, and when was it published (Gemeenteblad)? | `officiele-bekendmakingen` |
| What is allowed at a location under the omgevingsplan? | `omgevingsplan` (spatial rules are not in CVDR but in the omgevingsplan) |
| How has a court interpreted a rule? | `rechtspraak` |

## Workflow

1. **Find the regulation** with `lr_zoek_regelingen`:
   - by title (`titel: "Algemene Plaatselijke Verordening"`), or
   - by keyword in the regulation (`trefwoord: "terras"`).
   By default the tool searches Gemeente Amsterdam and only returns regulations in force **today**.
2. **Table of contents** with `lr_inhoudsopgave` to find the right article number.
3. **Article text** with `lr_artikel`, by number (`artikel: "2.31"`) or by search term.
4. **Answer** with the title, the CVDR number, the article, the entry-into-force date and the link to `lokaleregelgeving.overheid.nl`.

Use a **work number** (`CVDR72510`) to get the version in force; the tool looks up the version itself. Use a **version number** (`CVDR72510_57`) to refer to a fixed version. For the situation on an earlier date, pass `geldend_op`.

## Examples (Gemeente Amsterdam)

| Regulation | Work number |
| :--- | :--- |
| Algemene Plaatselijke Verordening 2008 (APV) | `CVDR72510` |

Always look up other regulations with `lr_zoek_regelingen`; numbers of policy rules and temporary regulations change often.

## Points of attention

- **In force on a date.** CVDR keeps every version (more than 70 for the Amsterdam APV). Without a date filter you also get expired versions; the tools therefore filter on today by default.
- **Districts.** Older regulations of Amsterdam districts (such as "dagelijks bestuur van stadsdeel Centrum") are listed under organisation `Amsterdam`. Check whether they still apply.
- **Changes in the pipeline.** A decision can be published but take effect later. When in doubt, also check `officiele-bekendmakingen`.
- **Omgevingswet.** Since 2024, rules on the physical environment (for example tree felling or terraces) are partly moving to the omgevingsplan. The APV sometimes refers to it.
- **No legal advice.** Give the text and the source; do not draw conclusions about an individual case.

## Without the MCP server

All tools are plain HTTP GET requests. Example:

```text
https://zoekservice.overheid.nl/sru/Search?x-connection=cvdr&operation=searchRetrieve&version=1.2&maximumRecords=10&query=dcterms.creator="Amsterdam" and dcterms.title="Algemene Plaatselijke Verordening" and overheidrg.datumGeldendOp="2026-10-19"
```

The full text is in the XML at `https://repository.officiele-overheidspublicaties.nl/cvdr/CVDR72510/57/xml/CVDR72510_57.xml`.

## Why this skill was added (version 1.8.0)

- **The toolkit could find decisions but not the rules themselves.** `officiele-bekendmakingen` returns the Gemeenteblad publication that *changes* a regulation, not the consolidated text that applies today. Questions such as "what does the APV say about terraces?" need the consolidated text, which only CVDR provides.
- **Versions matter.** CVDR keeps every version (more than 70 for the Amsterdam APV). Without a date filter, assistants pick outdated versions. The tools filter on the date the user asks about, by default today.
- **Full-text search works differently here.** The CVDR service does not support `cql.textAndIndexes` (used by the other KOOP service); it uses `overheidrg.keyword`. Documenting this prevents failed searches.
- **Article numbers are stored inconsistently.** Some articles carry the number in separate `label`/`nr` fields, others only inside the title ("Artikel 1.1 Definities"). The MCP server handles both, so lookups by article number are reliable.
