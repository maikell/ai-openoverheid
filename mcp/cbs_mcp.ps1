# JSON-RPC 2.0 Stdio MCP Server for CBS StatLine open data (datasets.cbs.nl, OData v4)
# Licence of the data: CC BY 4.0, source "CBS". No API key required.
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$baseUrl = "https://datasets.cbs.nl/odata/v1"
$userAgent = "open-overheid-mcp/1.6 (+https://github.com/maikell/ai-openoverheid)"

# Strict patterns: every value that ends up in a URL path or OData filter is validated
$tablePattern = '^[0-9A-Za-z]{4,12}$'
$namePattern  = '^[A-Za-z][A-Za-z0-9]{0,63}$'
$codePattern  = '^[A-Za-z0-9_]{1,32}$'

function New-Client {
    $wc = New-Object System.Net.WebClient
    $wc.Encoding = [System.Text.Encoding]::UTF8
    $wc.Headers.Add("User-Agent", $userAgent)
    $wc.Headers.Add("Accept", "application/json")
    return $wc
}

function Get-Json($url) {
    $wc = New-Client
    return ($wc.DownloadString($url) | ConvertFrom-Json)
}

function Send-Response($id, $result, $err) {
    $resp = [ordered]@{ jsonrpc = "2.0"; id = $id }
    if ($err) { $resp["error"] = $err } else { $resp["result"] = $result }
    [Console]::WriteLine(($resp | ConvertTo-Json -Depth 12 -Compress))
}

function Send-Text($id, $text) {
    Send-Response $id @{ content = @(@{ type = "text"; text = $text }) } $null
}

function Fail($message) { throw [System.ArgumentException]::new($message) }

function Get-Limit($value, $default, $max) {
    if ($null -eq $value) { return $default }
    $n = 0
    if (-not [int]::TryParse([string]$value, [ref]$n) -or $n -lt 1) { Fail "Ongeldige limiet: verwacht een positief geheel getal." }
    return [Math]::Min($n, $max)
}

function Test-Table($toolArgs) {
    $t = [string]$toolArgs.table_id
    if ($t -notmatch $tablePattern) { Fail "Ongeldig table_id (bijv. 86165NED)." }
    $c = if ($toolArgs.catalog) { [string]$toolArgs.catalog } else { "CBS" }
    if ($c -notmatch $namePattern) { Fail "Ongeldige catalog (standaard CBS)." }
    return "$baseUrl/$c/$t"
}

# Escape a free-text search term for use inside an OData string literal
function ConvertTo-ODataText($text) {
    $s = ([string]$text).Trim()
    if ($s.Length -lt 1 -or $s.Length -gt 100) { Fail "Zoekterm moet 1 tot 100 tekens zijn." }
    return $s.Replace("'", "''")
}

function Get-CodeList($value, $label) {
    $list = @()
    foreach ($v in @($value)) {
        if ($null -eq $v) { continue }
        $s = ([string]$v).Trim()
        if ($s -notmatch $codePattern) { Fail "Ongeldige code in ${label}: '$s'." }
        $list += $s
    }
    if ($list.Count -gt 50) { Fail "Maximaal 50 codes per ${label}." }
    return ,$list
}

function Join-OrFilter($field, $codes) {
    $parts = @()
    foreach ($c in $codes) { $parts += "$field eq '$c'" }
    return "(" + ($parts -join " or ") + ")"
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
                Send-Response $id @{
                    protocolVersion = "2024-11-05"
                    capabilities = @{ tools = @{} }
                    serverInfo = @{ name = "cbs"; version = "1.0.0" }
                } $null
            }
            "notifications/initialized" { }
            "tools/list" {
                $tools = @(
                    @{
                        name = "cbs_search_tables"
                        description = "Zoek CBS StatLine-tabellen op titel (bijv. 'wijken en buurten', 'bevolking', 'inkomen'). Geeft tabelnummer, titel en wijzigingsdatum, nieuwste eerst."
                        inputSchema = @{ type = "object"; properties = @{
                            query = @{ type = "string"; description = "Zoekterm in de tabeltitel." }
                            top = @{ type = "integer"; description = "Aantal resultaten (standaard 10, max 25)."; default = 10 }
                        }; required = @("query") }
                    },
                    @{
                        name = "cbs_get_table_info"
                        description = "Metadata van een CBS-tabel: titel, periode, licentie, samenvatting en de dimensies (zoals WijkenEnBuurten, RegioS, Perioden) die je kunt filteren."
                        inputSchema = @{ type = "object"; properties = @{
                            table_id = @{ type = "string"; description = "Tabelnummer, bijv. 86165NED (Kerncijfers wijken en buurten 2025)." }
                            catalog = @{ type = "string"; description = "Catalogus (standaard CBS)."; default = "CBS" }
                        }; required = @("table_id") }
                    },
                    @{
                        name = "cbs_find_codes"
                        description = "Zoek codes binnen een tabel: gebruik dimension 'Measure' voor onderwerpen/maatstaven (bijv. 'inwoners', 'inkomen') of een dimensienaam zoals 'WijkenEnBuurten' voor gebieden (bijv. 'Osdorp', 'Nieuw-West')."
                        inputSchema = @{ type = "object"; properties = @{
                            table_id = @{ type = "string"; description = "Tabelnummer, bijv. 86165NED." }
                            dimension = @{ type = "string"; description = "'Measure' of de naam van een dimensie uit cbs_get_table_info."; default = "Measure" }
                            query = @{ type = "string"; description = "Zoekterm in de titel van de code (optioneel)." }
                            top = @{ type = "integer"; description = "Aantal resultaten (standaard 25, max 100)."; default = 25 }
                            catalog = @{ type = "string"; default = "CBS" }
                        }; required = @("table_id") }
                    },
                    @{
                        name = "cbs_get_observations"
                        description = "Haal cijfers op uit een CBS-tabel, gefilterd op maatstaven (measures) en dimensiecodes, bijv. measures ['T001036'] en filters {WijkenEnBuurten: ['GM0363','WK0363FJ']}. Geeft per waarde de maatstaf met titel en eenheid."
                        inputSchema = @{ type = "object"; properties = @{
                            table_id = @{ type = "string"; description = "Tabelnummer, bijv. 86165NED." }
                            measures = @{ type = "array"; items = @{ type = "string" }; description = "Maatstafcodes (max 50), bijv. ['T001036']." }
                            filters = @{ type = "object"; description = "Per dimensie een lijst codes (max 50), bijv. {WijkenEnBuurten: ['GM0363']}." }
                            max_rows = @{ type = "integer"; description = "Maximaal aantal waarden (standaard 200, max 2000)."; default = 200 }
                            catalog = @{ type = "string"; default = "CBS" }
                        }; required = @("table_id") }
                    }
                )
                Send-Response $id @{ tools = $tools } $null
            }
            "tools/call" {
                $toolName = $req.params.name
                $toolArgs = $req.params.arguments
                if ($null -eq $toolArgs) { $toolArgs = New-Object PSObject }

                if ($toolName -eq "cbs_search_tables") {
                    $q = ConvertTo-ODataText $toolArgs.query
                    $top = Get-Limit $toolArgs.top 10 25
                    $filter = [uri]::EscapeDataString("contains(Title,'$q')")
                    $url = "$baseUrl/Datasets?`$filter=$filter&`$select=Identifier,Title,Catalog,Modified&`$orderby=Modified%20desc&`$top=$top"
                    $data = Get-Json $url
                    Send-Text $id (ConvertTo-Json -InputObject @($data.value) -Depth 4)
                }
                elseif ($toolName -eq "cbs_get_table_info") {
                    $tableUrl = Test-Table $toolArgs
                    $p = Get-Json "$tableUrl/Properties"
                    $d = Get-Json "$tableUrl/Dimensions"
                    $info = [ordered]@{
                        Identifier = $p.Identifier; Title = $p.Title; Summary = $p.Summary
                        TemporalCoverage = $p.TemporalCoverage; Modified = $p.Modified
                        DatasetType = $p.DatasetType; ObservationCount = $p.ObservationCount
                        License = $p.License; Source = $p.Source
                        Dimensions = @($d.value | ForEach-Object { [ordered]@{ Identifier = $_.Identifier; Title = $_.Title; Kind = $_.Kind } })
                    }
                    Send-Text $id ($info | ConvertTo-Json -Depth 5)
                }
                elseif ($toolName -eq "cbs_find_codes") {
                    $tableUrl = Test-Table $toolArgs
                    $dim = if ($toolArgs.dimension) { [string]$toolArgs.dimension } else { "Measure" }
                    if ($dim -notmatch $namePattern) { Fail "Ongeldige dimensie." }
                    $top = Get-Limit $toolArgs.top 25 100
                    $url = "$tableUrl/${dim}Codes?`$top=$top"
                    if ($toolArgs.query) {
                        $q = ConvertTo-ODataText $toolArgs.query
                        $url += "&`$filter=" + [uri]::EscapeDataString("contains(Title,'$q')")
                    }
                    $data = Get-Json $url
                    $rows = @($data.value | ForEach-Object {
                        $o = [ordered]@{ Identifier = $_.Identifier; Title = $_.Title }
                        if ($_.Unit) { $o["Unit"] = $_.Unit }
                        if ($_.DimensionGroupId) { $o["Group"] = $_.DimensionGroupId }
                        $o
                    })
                    Send-Text $id (ConvertTo-Json -InputObject $rows -Depth 4)
                }
                elseif ($toolName -eq "cbs_get_observations") {
                    $tableUrl = Test-Table $toolArgs
                    $maxRows = Get-Limit $toolArgs.max_rows 200 2000
                    $clauses = @()
                    $measures = Get-CodeList $toolArgs.measures "measures"
                    if ($measures.Count -gt 0) { $clauses += Join-OrFilter "Measure" $measures }
                    if ($toolArgs.filters) {
                        foreach ($prop in $toolArgs.filters.PSObject.Properties) {
                            if ($prop.Name -notmatch $namePattern) { Fail "Ongeldige dimensienaam '$($prop.Name)'." }
                            $codes = Get-CodeList $prop.Value $prop.Name
                            if ($codes.Count -gt 0) { $clauses += Join-OrFilter $prop.Name $codes }
                        }
                    }
                    if ($clauses.Count -eq 0) { Fail "Geef minstens measures of filters op; een hele tabel kan miljoenen waarden bevatten." }

                    $url = "$tableUrl/Observations?`$filter=" + [uri]::EscapeDataString($clauses -join " and ")
                    $rows = @()
                    $pages = 0
                    while ($url -and $rows.Count -lt $maxRows -and $pages -lt 10) {
                        $data = Get-Json $url
                        $rows += @($data.value)
                        $url = $data.'@odata.nextLink'
                        $pages++
                    }
                    $truncated = ($rows.Count -gt $maxRows) -or [bool]$url
                    if ($rows.Count -gt $maxRows) { $rows = $rows[0..($maxRows - 1)] }

                    # Look up titles and units for the measures that were returned
                    $titles = @{}
                    $ids = @($rows | ForEach-Object { $_.Measure } | Where-Object { $_ -match $codePattern } | Select-Object -Unique | Select-Object -First 50)
                    if ($ids.Count -gt 0) {
                        $mUrl = "$tableUrl/MeasureCodes?`$select=Identifier,Title,Unit&`$filter=" + [uri]::EscapeDataString((Join-OrFilter "Identifier" $ids))
                        foreach ($m in (Get-Json $mUrl).value) { $titles[$m.Identifier] = $m }
                    }

                    $out = @($rows | ForEach-Object {
                        $o = [ordered]@{}
                        foreach ($p in $_.PSObject.Properties) {
                            if ($p.Name -in @("Id", "ValueAttribute")) { continue }
                            if ($p.Name -eq "StringValue" -and $null -eq $p.Value) { continue }
                            if ($p.Name -eq "Value" -and $null -eq $p.Value -and $null -ne $_.StringValue) { continue }
                            $val = $p.Value
                            if ($val -is [string]) { $val = $val.Trim() }
                            $o[$p.Name] = $val
                        }
                        if ($_.ValueAttribute -and $_.ValueAttribute -ne "None") { $o["ValueAttribute"] = $_.ValueAttribute }
                        $t = $titles[$_.Measure]
                        if ($t) { $o["MeasureTitle"] = $t.Title; $o["Unit"] = $t.Unit }
                        $o
                    })
                    $result = [ordered]@{
                        table = $toolArgs.table_id; count = $out.Count; truncated = $truncated
                        source = "CBS StatLine, CC BY 4.0"; observations = @($out)
                    }
                    Send-Text $id ($result | ConvertTo-Json -Depth 6)
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
