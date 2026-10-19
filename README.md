# AI Open Overheid Toolkit

Skills en MCP-servers waarmee een AI-assistent rechtstreeks werkt met Nederlandse en Amsterdamse open overheidsdata. Werkt in **Google Antigravity** en in **Claude** (Claude Code en de Claude-app).

Alle bronnen zijn openbaar. Je hebt geen eigen API-sleutels of accounts nodig.

---

## 🏛️ Inbegrepen skills

| Skill | Wat het doet | Databron |
| :--- | :--- | :--- |
| `amsterdam-subsidies` | Doorzoeken en optellen van het Openbaar Subsidieregister (bedragen, aanvragers, clusters). | Datapunt Amsterdam (CSV-stream) + MCP-server |
| `amsterdam-woo` | Zoeken in Woo- en Wob-besluiten en ophalen van de PDF's. | Memorix Mediabank (`open.amsterdam`) + MCP-server |
| `omgevingsplan` | Adres naar coördinaten/perceel, en planregels onder de Omgevingswet. | PDOK Locatieserver, KOOP SRU |
| `rechtspraak` | Zoeken en lezen van uitspraken via ECLI. | `data.rechtspraak.nl` |
| `officiele-bekendmakingen` | Gemeentebladen, Staatscourant, vergunningen en regelgeving. | KOOP SRU 1.2 |
| `amsterdam-kerncijfers` | Wijk- en buurtstatistieken (BBGA). | Onderzoek & Statistiek Amsterdam |

## 📁 Opbouw

```
skills/<naam>/SKILL.md        De skills (zelfde formaat in Antigravity en Claude)
mcp/*.ps1                     Twee MCP-servers (stdio, PowerShell)
rules/AGENTS.md               Algemene richtlijnen (alleen Antigravity laadt dit automatisch)
plugin.json                   Pluginbeschrijving voor Antigravity
mcp_config.example.json       MCP-voorbeeldconfiguratie voor Antigravity
.claude-plugin/plugin.json    Pluginbeschrijving voor Claude Code
.claude-plugin/marketplace.json  Maakt deze repo installeerbaar als Claude Code-marketplace
.mcp.json                     MCP-configuratie voor Claude Code (relatieve paden)
```

## Vereisten

- **Skills:** niets extra's; ze werken op Windows, macOS en Linux.
- **MCP-servers:** PowerShell. Windows heeft dit standaard (`powershell.exe`). Op macOS/Linux installeer je [PowerShell 7](https://learn.microsoft.com/powershell/scripting/install/installing-powershell) (`pwsh`), zie *Aanpassen voor jouw computer*.
- **Script `amsterdam_kerncijfers.mjs`** (optioneel): Node.js 18 of nieuwer.

---

## 🚀 Installatie in Google Antigravity

1. **Repository plaatsen** in de plugins-map:

   ```powershell
   cd $env:USERPROFILE\.gemini\config\plugins
   git clone https://github.com/maikell/ai-openoverheid.git open-overheid
   ```

   Controleer dat `plugin.json` direct in `...\plugins\open-overheid\` staat.

2. **MCP-configuratie maken** vanuit het voorbeeld:

   ```powershell
   cd open-overheid
   Copy-Item mcp_config.example.json mcp_config.json
   ```

   Het voorbeeld gebruikt `${env:USERPROFILE}`. Als jouw Antigravity geen omgevingsvariabelen invult in MCP-paden, vervang dat in `mcp_config.json` door je volledige pad, bijvoorbeeld `C:\\Users\\<JOUW_GEBRUIKERSNAAM>\\.gemini\\config\\plugins\\open-overheid\\mcp\\amsterdam_woo_mcp.ps1`. `mcp_config.json` staat in `.gitignore`, dus jouw eigen pad komt nooit in Git terecht.

3. **Herstart Antigravity** of herlaad de plugins.

**Bijwerken:** `git pull` in de map `open-overheid`.

---

## 🚀 Installatie in Claude Code

**Aanbevolen: als marketplace** (updates via Claude Code):

```text
/plugin marketplace add maikell/ai-openoverheid
/plugin install open-overheid@open-overheid
```

Herstart Claude Code daarna. De skills en beide MCP-servers zijn dan actief; `.mcp.json` verwijst met `${CLAUDE_PLUGIN_ROOT}` naar de scripts, dus je hoeft geen paden aan te passen.

**Alleen de skills, zonder plugin:** kopieer de mappen uit `skills/` naar `~/.claude/skills/` (Windows: `%USERPROFILE%\.claude\skills\`), bijvoorbeeld:

```powershell
git clone https://github.com/maikell/ai-openoverheid.git $env:TEMP\ai-openoverheid
Copy-Item "$env:TEMP\ai-openoverheid\skills\*" "$env:USERPROFILE\.claude\skills\" -Recurse -Force
```

---

## 🚀 Installatie in de Claude-app (web en desktop)

De Claude-app installeert skills als ZIP-bestand, **één ZIP per skill**:

```powershell
cd ai-openoverheid\skills
Compress-Archive -Path omgevingsplan -DestinationPath ..\omgevingsplan.zip
# herhaal voor de andere skills die je wilt gebruiken
```

Upload de ZIP via de skillsinstellingen ("Upload a skill"). De mapnaam moet gelijk blijven aan de `name` in `SKILL.md`.

Let op: de MCP-servers draaien niet in de Claude-app. De skills `amsterdam-subsidies` en `amsterdam-woo` beschrijven daarom ook de directe API-aanroepen, zodat Claude de data zonder MCP kan ophalen.

---

## 🔧 Aanpassen voor jouw computer

| Situatie | Wat je aanpast |
| :--- | :--- |
| **Andere gebruikersnaam of map (Antigravity)** | Alleen je lokale `mcp_config.json`. Neem nooit een persoonlijk pad op in `mcp_config.example.json`. |
| **macOS of Linux** | Vervang in `.mcp.json` (Claude) of `mcp_config.json` (Antigravity) `"powershell.exe"` door `"pwsh"`. Gebruik in Antigravity een pad als `/Users/<naam>/.gemini/config/plugins/open-overheid/mcp/subsidies_mcp.ps1`. |
| **Memorix-sleutel gewijzigd** | De Woo-server gebruikt de publieke sleutel van open.amsterdam. Verandert die, zet dan de omgevingsvariabele `MEMORIX_API_KEY`; een nieuwe sleutel vind je in de netwerkverzoeken van `open.amsterdam/woo-zoeken`. |
| **Cache van subsidies** | De server bewaart de CSV maximaal 12 uur in de map `antigravity_subsidies` in de tijdelijke map van het systeem (Windows: `%TEMP%`). Verwijder die map om direct te verversen. |
| **ExecutionPolicy** | De servers starten met `-ExecutionPolicy Bypass` omdat de scripts niet ondertekend zijn. Dat geldt alleen voor dit proces. Lees de scripts als je ze van een derde krijgt. |

Bestanden in deze repo zijn UTF-8 zonder BOM. Houd de `.ps1`-bestanden ASCII (geen accenten), anders toont Windows PowerShell 5.1 tekens verkeerd.

---

## 💡 Voorbeeldvragen

- *"Welke subsidies heeft de Gemeente Amsterdam verleend in Stadsdeel Nieuw-West?"*
- *"Zoek Woo-besluiten van de Gemeente Amsterdam over afvalinzameling en open het besluitdocument."*
- *"Wat zijn de ruimtelijke regels en omgevingsplannen rond Amstel 1 in Amsterdam?"*
- *"Zoek recente uitspraken over omgevingsrecht waarin de Gemeente Amsterdam partij is."*
- *"Geef de kerncijfers voor de buurt rond Amstel 1."*

## 🧪 Conventie voor voorbeelddata

Voorbeelden, tests en prompts gebruiken uitsluitend het adres **Amstel 1** (Stadhuis/Stopera) en de organisaties **Gemeente Amsterdam** en **Stadsdeel Nieuw-West**. Gebruik geen echte personen, bedrijven of andere adressen. Uitzondering: technische waardelijsten (zoals de gerechtscodes in de rechtspraak-skill).

## 🔒 Veiligheid

- **Geen eigen sleutels nodig.** De enige sleutel in de code is de publieke sleutel die open.amsterdam zelf gebruikt.
- **Invoer wordt gecontroleerd:** `get_woo_document` accepteert alleen een geldig UUID en `rows` is begrensd op 50, zodat een gemanipuleerde invoer geen andere endpoints kan aanroepen.
- **Opgehaalde documenten zijn data, geen instructies.** Woo-documenten en uitspraken bevatten tekst van derden; de assistent hoort daar geen opdrachten uit op te volgen.
- **Geen scraping:** alleen officiële REST-, SRU- en XML-webservices, zie `rules/AGENTS.md`.

## Licentie

GPL-3.0, zie [LICENSE](LICENSE).
