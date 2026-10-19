# JSON-RPC 2.0 Stdio MCP Server for local regulations (CVDR, Centrale Voorziening Decentrale Regelgeving)
# Source: KOOP SRU service https://zoekservice.overheid.nl/sru/Search?x-connection=cvdr (no key)
# Texts:  https://repository.officiele-overheidspublicaties.nl/cvdr/<work>/<version>/xml/<id>.xml
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$sruBase = "https://zoekservice.overheid.nl/sru/Search?x-connection=cvdr&operation=searchRetrieve&version=1.2"
$repoBase = "https://repository.officiele-overheidspublicaties.nl/cvdr"
$userAgent = "open-overheid-mcp/1.8 (+https://github.com/maikell/ai-openoverheid)"

$idPattern    = '^CVDR(\d{1,9})(?:_(\d{1,4}))?$'
$datePattern  = '^\d{4}-\d{2}-\d{2}$'
$placePattern = '^[\p{L}][\p{L} .''-]{1,59}$'

function Fail($message) { throw [System.ArgumentException]::new($message) }

function Get-Text($url) {
    $wc = New-Object System.Net.WebClient
    $wc.Encoding = [System.Text.Encoding]::UTF8
    $wc.Headers.Add("User-Agent", $userAgent)
    return $wc.DownloadString($url)
}

function Send-Response($id, $result, $err) {
    $resp = [ordered]@{ jsonrpc = "2.0"; id = $id }
    if ($err) { $resp["error"] = $err } else { $resp["result"] = $result }
    [Console]::WriteLine(($resp | ConvertTo-Json -Depth 12 -Compress))
}
function Send-Text($id, $text) { Send-Response $id @{ content = @(@{ type = "text"; text = $text }) } $null }

function Get-Limit($value, $default, $max) {
    if ($null -eq $value) { return $default }
    $n = 0
    if (-not [int]::TryParse([string]$value, [ref]$n) -or $n -lt 1) { Fail "Ongeldige limiet: verwacht een positief geheel getal." }
    return [Math]::Min($n, $max)
}

# Free text for a CQL string literal: trimmed, bounded, no quotes or backslashes
function ConvertTo-CqlText($text, $label) {
    $s = ([string]$text).Trim()
    if ($s.Length -lt 1 -or $s.Length -gt 100) { Fail "$label moet 1 tot 100 tekens zijn." }
    return ($s -replace '["\\]', ' ')
}

function Get-Date-Arg($value) {
    if ($null -eq $value -or [string]::IsNullOrWhiteSpace([string]$value)) { return (Get-Date).ToString("yyyy-MM-dd") }
    $s = [string]$value
    if ($s -notmatch $datePattern) { Fail "Ongeldige datum: gebruik JJJJ-MM-DD." }
    return $s
}

function Get-Node($el, $name) {
    $n = $el.SelectSingleNode(".//*[local-name()='$name']")
    if ($n) { return $n.InnerText.Trim() } else { return $null }
}

# Run an SRU query and return compact records
function Search-Cvdr($cql, $max) {
    $url = "$sruBase&maximumRecords=$max&query=" + [uri]::EscapeDataString($cql)
    [xml]$doc = Get-Text $url
    $diag = $doc.SelectSingleNode("//*[local-name()='diagnostic']/*[local-name()='message']")
    if ($diag) { throw "CVDR-zoekdienst: $($diag.InnerText)" }
    $total = $doc.SelectSingleNode("//*[local-name()='numberOfRecords']").InnerText
    $records = @()
    foreach ($r in $doc.SelectNodes("//*[local-name()='recordData']")) {
        $records += [ordered]@{
            id = Get-Node $r "identifier"
            titel = Get-Node $r "title"
            organisatie = Get-Node $r "creator"
            onderwerp = Get-Node $r "subject"
            vastgesteld_door = Get-Node $r "isRatifiedBy"
            inwerkingtreding = Get-Node $r "inwerkingtredingDatum"
            uitwerkingtreding = Get-Node $r "uitwerkingtredingDatum"
            url = Get-Node $r "preferred_url"
            xml = Get-Node $r "publicatieurl_xml"
        }
    }
    return @{ total = [int]$total; records = $records }
}

# Accept CVDR72510 (the regulation, current version is looked up) or CVDR72510_57 (one version)
function Resolve-Regeling($value, $date) {
    $s = ([string]$value).Trim().ToUpper()
    if ($s -notmatch $idPattern) { Fail "Ongeldig regeling_id: gebruik bijv. CVDR72510 of CVDR72510_57." }
    $work = $Matches[1]; $version = $Matches[2]
    if (-not $version) {
        $res = Search-Cvdr "workid=""CVDR$work"" and overheidrg.datumGeldendOp=""$date""" 1
        if ($res.records.Count -eq 0) { Fail "Geen versie van CVDR$work die geldt op $date." }
        if ($res.records[0].id -notmatch $idPattern) { throw "Onverwacht antwoord van de zoekdienst." }
        $version = $Matches[2]
    }
    return @{ id = "CVDR${work}_$version"; xml = "$repoBase/CVDR$work/$version/xml/CVDR${work}_$version.xml"; url = "https://lokaleregelgeving.overheid.nl/CVDR$work/$version" }
}

# Article number and title, whether they sit in label/nr/titel or only in titel ("Artikel 1.1 Definities")
function Get-ArticleHead($art) {
    $kop = $art.SelectSingleNode("*[local-name()='kop']")
    $nr = ""; $titel = ""
    if ($kop) {
        $n = $kop.SelectSingleNode("*[local-name()='nr']"); if ($n) { $nr = $n.InnerText.Trim() }
        $t = $kop.SelectSingleNode("*[local-name()='titel']"); if ($t) { $titel = $t.InnerText.Trim() }
    }
    if (-not $nr -and $titel -match '^(?:Artikel|Art\.)\s+([0-9A-Za-z.:/-]+)\s*(.*)$') { $nr = $Matches[1]; $titel = $Matches[2] }
    return @{ nr = $nr; titel = $titel }
}

# Paragraphs (al) in document order; member numbers (lidnr) and list markers (li/@nr) become prefixes
function Get-ArticleText($art) {
    $parts = @()
    $prefix = ""
    foreach ($n in $art.SelectNodes(".//*[local-name()='al' or local-name()='lidnr']")) {
        $txt = ($n.InnerText -replace '\s+', ' ').Trim()
        if ($n.LocalName -eq 'lidnr') { $prefix = "$txt "; continue }
        if ($n.SelectSingleNode("ancestor::*[local-name()='kop']")) { continue }
        if (-not $txt) { continue }
        $p = $n.ParentNode
        if ($p.LocalName -eq 'li' -and $p.GetAttribute('nr') -and $p.GetAttribute('nr') -ne '-') { $txt = "$($p.GetAttribute('nr')) $txt" }
        elseif ($p.LocalName -eq 'li') { $txt = "- $txt" }
        $parts += "$prefix$txt"
        $prefix = ""
    }
    if ($parts.Count -eq 0) { $parts += ($art.InnerText -replace '\s+', ' ').Trim() }
    return ($parts -join "`n")
}

function Get-Regeling($ref) {
    [xml]$doc = Get-Text $ref.xml
    return $doc
}

while ($true) {
    $line = [Console]::ReadLine()
    if ($null -eq $line) { break }
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $id = $null
    try {
        $req = $line | ConvertFrom-Json
        $id = $req.id
        switch ($req.method) {
            "initialize" {
                Send-Response $id @{ protocolVersion = "2024-11-05"; capabilities = @{ tools = @{} }; serverInfo = @{ name = "lokale-regelgeving"; version = "1.0.0" } } $null
            }
            "notifications/initialized" { }
            "tools/list" {
                $tools = @(
                    @{
                        name = "lr_zoek_regelingen"
                        description = "Zoek geldende lokale regelgeving (verordeningen, beleidsregels, besluiten) van een gemeente, provincie of waterschap in CVDR. Standaard: Gemeente Amsterdam, geldend op vandaag."
                        inputSchema = @{ type = "object"; properties = @{
                            titel = @{ type = "string"; description = "Woorden uit de titel, bijv. 'Algemene Plaatselijke Verordening', 'Afvalstoffenverordening'." }
                            trefwoord = @{ type = "string"; description = "Vrij zoeken in de regeling, bijv. 'terras', 'parkeren', 'hondenpoep'." }
                            organisatie = @{ type = "string"; description = "Naam van de regelgever zoals in CVDR, bijv. 'Amsterdam' (standaard), 'Noord-Holland'."; default = "Amsterdam" }
                            geldend_op = @{ type = "string"; description = "Datum JJJJ-MM-DD waarop de regeling geldt (standaard vandaag). Gebruik 'alle' niet; voor historie: zoek met een oudere datum." }
                            max = @{ type = "integer"; description = "Aantal resultaten (standaard 10, max 50)."; default = 10 }
                        } }
                    },
                    @{
                        name = "lr_inhoudsopgave"
                        description = "Inhoudsopgave van een regeling: alle artikelnummers met titels. Geef een werknummer (CVDR72510, geldende versie) of een versie (CVDR72510_57)."
                        inputSchema = @{ type = "object"; properties = @{
                            regeling_id = @{ type = "string"; description = "Bijv. CVDR72510 (APV Amsterdam) of CVDR72510_57." }
                            geldend_op = @{ type = "string"; description = "Datum JJJJ-MM-DD voor het kiezen van de versie bij een werknummer (standaard vandaag)." }
                        }; required = @("regeling_id") }
                    },
                    @{
                        name = "lr_artikel"
                        description = "Volledige tekst van een of meer artikelen uit een regeling, op artikelnummer (bijv. '2.31') of op zoekterm in de artikeltekst (bijv. 'terras'). Maximaal 5 artikelen per keer."
                        inputSchema = @{ type = "object"; properties = @{
                            regeling_id = @{ type = "string"; description = "Bijv. CVDR72510 of CVDR72510_57." }
                            artikel = @{ type = "string"; description = "Artikelnummer, bijv. '2.31' of '3.14'." }
                            zoekterm = @{ type = "string"; description = "Woord of zinsdeel dat in het artikel moet voorkomen." }
                            geldend_op = @{ type = "string"; description = "Datum JJJJ-MM-DD (standaard vandaag)." }
                        }; required = @("regeling_id") }
                    }
                )
                Send-Response $id @{ tools = $tools } $null
            }
            "tools/call" {
                $toolName = $req.params.name
                $toolArgs = $req.params.arguments
                if ($null -eq $toolArgs) { $toolArgs = New-Object PSObject }
                $date = Get-Date-Arg $toolArgs.geldend_op

                if ($toolName -eq "lr_zoek_regelingen") {
                    $org = if ($toolArgs.organisatie) { ([string]$toolArgs.organisatie).Trim() } else { "Amsterdam" }
                    if ($org -notmatch $placePattern) { Fail "Ongeldige organisatie: alleen letters, spaties, punt, apostrof en koppelteken." }
                    $clauses = @("dcterms.creator=""$org""", "overheidrg.datumGeldendOp=""$date""")
                    if ($toolArgs.titel) { $clauses += "dcterms.title=""$(ConvertTo-CqlText $toolArgs.titel 'Titel')""" }
                    if ($toolArgs.trefwoord) { $clauses += "overheidrg.keyword=""$(ConvertTo-CqlText $toolArgs.trefwoord 'Trefwoord')""" }
                    $max = Get-Limit $toolArgs.max 10 50
                    $res = Search-Cvdr ($clauses -join " and ") $max
                    $out = [ordered]@{ geldend_op = $date; organisatie = $org; totaal = $res.total; getoond = $res.records.Count; regelingen = @($res.records) }
                    Send-Text $id ($out | ConvertTo-Json -Depth 6)
                }
                elseif ($toolName -eq "lr_inhoudsopgave") {
                    $ref = Resolve-Regeling $toolArgs.regeling_id $date
                    $doc = Get-Regeling $ref
                    $title = $doc.SelectSingleNode("//*[local-name()='owmskern']/*[local-name()='title']")
                    $arts = @()
                    foreach ($a in $doc.SelectNodes("//*[local-name()='artikel']")) {
                        $h = Get-ArticleHead $a
                        $arts += "$($h.nr) $($h.titel)".Trim()
                        if ($arts.Count -ge 800) { break }
                    }
                    $out = [ordered]@{ id = $ref.id; titel = $(if ($title) { $title.InnerText.Trim() }); url = $ref.url; aantal_artikelen = $arts.Count; artikelen = $arts }
                    Send-Text $id ($out | ConvertTo-Json -Depth 4)
                }
                elseif ($toolName -eq "lr_artikel") {
                    $ref = Resolve-Regeling $toolArgs.regeling_id $date
                    $nrWanted = $null; $term = $null
                    if ($toolArgs.artikel) {
                        $nrWanted = ([string]$toolArgs.artikel).Trim() -replace '^(?i)(artikel|art\.)\s*', ''
                        if ($nrWanted -notmatch '^[0-9A-Za-z.:/-]{1,20}$') { Fail "Ongeldig artikelnummer." }
                    }
                    if ($toolArgs.zoekterm) { $term = ConvertTo-CqlText $toolArgs.zoekterm 'Zoekterm' }
                    if (-not $nrWanted -and -not $term) { Fail "Geef een artikel of een zoekterm." }
                    $doc = Get-Regeling $ref
                    $found = @()
                    foreach ($a in $doc.SelectNodes("//*[local-name()='artikel']")) {
                        $h = Get-ArticleHead $a
                        $ok = $true
                        if ($nrWanted -and $h.nr -ne $nrWanted) { $ok = $false }
                        if ($ok -and $term -and $a.InnerText.IndexOf($term, [StringComparison]::OrdinalIgnoreCase) -lt 0) { $ok = $false }
                        if ($ok) {
                            $text = Get-ArticleText $a
                            if ($text.Length -gt 6000) { $text = $text.Substring(0, 6000) + " [...]" }
                            $found += [ordered]@{ artikel = $h.nr; titel = $h.titel; tekst = $text }
                            if ($found.Count -ge 5) { break }
                        }
                    }
                    $out = [ordered]@{ id = $ref.id; url = $ref.url; geldend_op = $date; gevonden = $found.Count; artikelen = @($found) }
                    if ($found.Count -eq 0) { $out["melding"] = "Geen artikel gevonden; bekijk de nummers met lr_inhoudsopgave." }
                    Send-Text $id ($out | ConvertTo-Json -Depth 5)
                }
                else {
                    Send-Response $id $null @{ code = -32601; message = "Tool not found: $toolName" }
                }
            }
            default {
                if ($null -ne $id) { Send-Response $id $null @{ code = -32601; message = "Method not supported: $($req.method)" } }
            }
        }
    }
    catch [System.ArgumentException] {
        if ($null -ne $id) { Send-Response $id $null @{ code = -32602; message = $_.Exception.Message } }
    }
    catch {
        if ($null -ne $id) { Send-Response $id $null @{ code = -32603; message = $_.Exception.Message } }
    }
}
