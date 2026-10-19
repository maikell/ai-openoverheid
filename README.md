# AI Open Overheid Toolkit

**English** · [Nederlands](README.nl.md)

Skills and MCP servers that let an AI assistant work directly with Dutch and Amsterdam open government data: national statistics (CBS), council meetings and documents, zoning plans, court rulings, official publications, neighbourhood statistics, Woo (Freedom of Information) decisions and the municipal subsidy register.

The toolkit is **AI-agnostic**. It is built on two open formats, so the same files work with several assistants:

- **Skills** use the `SKILL.md` format (Markdown with YAML front matter), supported by Google Antigravity (Gemini) and Claude.
- **Tools** are exposed through the [Model Context Protocol](https://modelcontextprotocol.io) (MCP), which any MCP-capable client can run.

All sources are public. No API keys or accounts are required.

## ✅ Supported environments

| Environment | Model | Skills | MCP servers | Install |
| :--- | :--- | :---: | :---: | :--- |
| Google Antigravity | Gemini | ✅ | ✅ | [Instructions](#google-antigravity-gemini) |
| Claude Desktop | Claude | ✅ | ✅ | [Instructions](#claude-desktop) |
| Claude Code | Claude | ✅ | ✅ | [Instructions](#claude-code) |
| Claude on the web | Claude | ✅ | ❌ | [Instructions](#claude-on-the-web) |
| Other agents | any | if `SKILL.md` is supported | if MCP is supported | [Instructions](#other-agents-and-models) |

Without the MCP servers the skills still work: they document the underlying APIs, so the assistant can call them directly.

---

## 🏛️ Included skills

The data is Dutch, so skill names and some instructions are in Dutch. Assistants handle questions in English or Dutch.

| Skill | What it does | Data source |
| :--- | :--- | :--- |
| `amsterdam-subsidies` | Search and aggregate the Amsterdam public subsidy register (amounts, applicants, departments). | Datapunt Amsterdam (CSV stream) + MCP server |
| `amsterdam-woo` | Search Woo/Wob (FOI) decisions and retrieve the released PDFs. | Memorix Mediabank (`open.amsterdam`) + MCP server |
| `omgevingsplan` | Geocode an address to coordinates/parcel and find zoning rules under the Environment and Planning Act (Omgevingswet). | PDOK Locatieserver, KOOP SRU |
| `rechtspraak` | Search and read Dutch court rulings by ECLI. | `data.rechtspraak.nl` |
| `officiele-bekendmakingen` | Municipal gazettes, Government Gazette, permits and regulations. | KOOP SRU 1.2 |
| `amsterdam-kerncijfers` | District and neighbourhood statistics (BBGA). | Amsterdam Research & Statistics (O&S) |
| `cbs` | Statistics for every Dutch municipality, district and neighbourhood (population, income, housing, facilities), to compare areas and draw neighbourhood maps without a map service. Explained in `references/cbs-statline.md`. | CBS StatLine OData v4 (`datasets.cbs.nl`) + MCP server |
| `raadsinformatie` | Council and district committee meetings, agendas, motions, letters and minutes, with direct PDF links. | NotuBiz API (`amsterdam.raadsinformatie.nl`) + MCP server |

### MCP tools

| Server | Tools |
| :--- | :--- |
| `amsterdam-woo` | `search_woo_decisions`, `get_woo_document` |
| `amsterdam-subsidies` | `search_subsidies`, `get_subsidies_summary` |
| `amsterdam-raadsinformatie` | `get_meetings`, `get_meeting_agenda` |
| `cbs` | `cbs_search_tables`, `cbs_get_table_info`, `cbs_find_codes`, `cbs_get_observations` |

## 📁 Repository layout

```
skills/<name>/SKILL.md            The skills (shared by all environments)
mcp/*.ps1                         Four MCP servers (stdio, PowerShell)
rules/AGENTS.md                   General agent guidelines (loaded automatically by Antigravity)
plugin.json                       Plugin manifest for Antigravity
mcp_config.example.json           MCP config template for Antigravity
.claude-plugin/plugin.json        Plugin manifest for Claude
.claude-plugin/marketplace.json   Makes this repo installable as a Claude plugin marketplace
.mcp.json                         MCP config for Claude (relative paths)
```

## Requirements

- **Skills:** nothing extra; they work on Windows, macOS and Linux.
- **MCP servers:** PowerShell. Windows ships with it (`powershell.exe`). On macOS/Linux install [PowerShell 7](https://learn.microsoft.com/powershell/scripting/install/installing-powershell) (`pwsh`), see [Adapting to your machine](#-adapting-to-your-machine).
- **`amsterdam_kerncijfers.mjs` script** (optional): Node.js 18 or later.

---

## 🚀 Installation

### Google Antigravity (Gemini)

1. **Clone the repository** into the Antigravity plugins folder:

   ```powershell
   cd $env:USERPROFILE\.gemini\config\plugins
   git clone https://github.com/maikell/ai-openoverheid.git open-overheid
   ```

   Make sure `plugin.json` sits directly in `...\plugins\open-overheid\`.

2. **Create the MCP config** from the template:

   ```powershell
   cd open-overheid
   Copy-Item mcp_config.example.json mcp_config.json
   ```

   The template uses `${env:USERPROFILE}`. If your Antigravity build does not expand environment variables in MCP paths, replace it in `mcp_config.json` with your full path, e.g. `C:\\Users\\<YOUR_USERNAME>\\.gemini\\config\\plugins\\open-overheid\\mcp\\amsterdam_woo_mcp.ps1`. `mcp_config.json` is in `.gitignore`, so your personal path never ends up in Git.

3. **Restart Antigravity** or reload plugins.

**Update:** run `git pull` in the `open-overheid` folder.

### Claude Desktop

1. Open **Customize** in the left sidebar and go to the **Plugins** tab.
2. Click **Add** → **Add marketplace** → **Add from a repository**.
3. Enter `maikell/ai-openoverheid`.
4. Install **open-overheid** from that marketplace and make sure it is enabled.

Skills and all MCP servers become available. Paths are relative (`${CLAUDE_PLUGIN_ROOT}`), so nothing needs editing.

### Claude Code

Inside a Claude Code session:

```text
/plugin marketplace add maikell/ai-openoverheid
/plugin install open-overheid@open-overheid
```

Or from a terminal (no slash):

```powershell
claude plugin marketplace add maikell/ai-openoverheid
claude plugin install open-overheid@open-overheid
```

Restart Claude Code afterwards. Update later with `claude plugin marketplace update open-overheid`.

Don't have Claude Code yet? Install it with `irm https://claude.ai/install.ps1 | iex` (Windows PowerShell) or `curl -fsSL https://claude.ai/install.sh | bash` (macOS/Linux), then open a new terminal. If `claude` is not recognised on Windows, run it as `& "$env:USERPROFILE\.local\bin\claude.exe"` or add that folder to your PATH. See the [setup docs](https://code.claude.com/docs/en/setup).

**Skills only, without the plugin:** copy the folders in `skills/` to `~/.claude/skills/` (Windows: `%USERPROFILE%\.claude\skills\`).

### Claude on the web

The web app installs skills as ZIP files, **one ZIP per skill**:

```powershell
cd ai-openoverheid\skills
Compress-Archive -Path omgevingsplan -DestinationPath ..\omgevingsplan.zip
# repeat for the other skills you want
```

Go to **Customize → Skills**, click **+** → **Create skill** → **Upload a skill**, upload the ZIP and toggle the skill on. Skills require **Code execution and file creation** (Settings → Capabilities). The folder name must match the `name` in `SKILL.md`.

MCP servers do not run in the web app; the skills fall back to calling the APIs directly. Don't combine this with the Desktop plugin on the same account, or the skills appear twice.

### Other agents and models

- **Skills:** any agent that loads `SKILL.md` folders can use `skills/` as is. For agents without skill support, use the `SKILL.md` files and `rules/AGENTS.md` as plain instructions or context.
- **MCP servers:** register the two scripts in your client's MCP configuration as stdio servers, for example:

  ```json
  {
    "mcpServers": {
      "amsterdam-woo": {
        "command": "powershell.exe",
        "args": ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "<path-to-repo>/mcp/amsterdam_woo_mcp.ps1"]
      },
      "amsterdam-subsidies": {
        "command": "powershell.exe",
        "args": ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "<path-to-repo>/mcp/subsidies_mcp.ps1"]
      },
      "amsterdam-raadsinformatie": {
        "command": "powershell.exe",
        "args": ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "<path-to-repo>/mcp/raadsinformatie_mcp.ps1"]
      },
      "cbs": {
        "command": "powershell.exe",
        "args": ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "<path-to-repo>/mcp/cbs_mcp.ps1"]
      }
    }
  }
  ```

---

## 🔧 Adapting to your machine

| Situation | What to change |
| :--- | :--- |
| **Different username or folder (Antigravity)** | Only your local `mcp_config.json`. Never put a personal path in `mcp_config.example.json`. |
| **macOS or Linux** | Replace `"powershell.exe"` with `"pwsh"` in `.mcp.json` (Claude) or `mcp_config.json` (Antigravity). In Antigravity use a path like `/Users/<name>/.gemini/config/plugins/open-overheid/mcp/subsidies_mcp.ps1`. |
| **Memorix key changed** | The Woo server uses the public key that open.amsterdam itself uses. If it changes, set the `MEMORIX_API_KEY` environment variable; the current key can be found in the network requests of `open.amsterdam/woo-zoeken`. |
| **Subsidy cache** | The server caches the CSV for up to 12 hours in an `antigravity_subsidies` folder in the system temp directory (Windows: `%TEMP%`). Delete that folder to refresh immediately. |
| **ExecutionPolicy** | The servers start with `-ExecutionPolicy Bypass` because the scripts are unsigned. This applies only to that process. Read the scripts before running them if you got them from someone else. |

Files are UTF-8 without BOM. Keep the `.ps1` files ASCII (no accented characters), or Windows PowerShell 5.1 will display them incorrectly.

---

## 💡 Example questions

- *"Which subsidies has the Gemeente Amsterdam granted in Stadsdeel Nieuw-West?"*
- *"Find Woo decisions by the Gemeente Amsterdam about waste collection and open the decision document."*
- *"What zoning rules and environmental plans apply around Amstel 1 in Amsterdam?"*
- *"Find recent rulings on environmental law in which the Gemeente Amsterdam is a party."*
- *"Give me the key figures for the neighbourhood around Amstel 1."*
- *"What is on the agenda of the next Stadsdeel Nieuw-West committee meeting?"*
- *"Compare the share of residents aged 65+ in Osdorp with Amsterdam as a whole (CBS)."*

## 🧪 Example data convention

Examples, tests and prompts use only the address **Amstel 1** (City Hall / Stopera) and the organisations **Gemeente Amsterdam** and **Stadsdeel Nieuw-West**. Do not use real people, companies or other addresses. Exception: technical value lists (such as the court codes in the `rechtspraak` skill, the NotuBiz organisation IDs in the `raadsinformatie` skill and the CBS area codes in the `cbs` skill).

Live results can of course contain other names and addresses; those come from the public sources, not from this repository.

## 🔒 Security

- **No keys of your own.** The only key in the code is the public key that open.amsterdam uses itself.
- **Input validation:** `get_woo_document` accepts only a valid UUID, `rows` is capped at 50 and the council tools accept only positive integer IDs, so manipulated input cannot reach other endpoints.
- **Retrieved documents are data, not instructions.** Woo documents and rulings contain third-party text; the assistant should not follow instructions found in them.
- **No scraping:** only official REST, SRU and XML web services, see `rules/AGENTS.md`.

## License

GPL-3.0, see [LICENSE](LICENSE).
