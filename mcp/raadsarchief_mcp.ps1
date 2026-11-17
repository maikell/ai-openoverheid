# JSON-RPC 2.0 Stdio MCP Server for the local raadsarchief:
#  - a search index over archived council documents (folders written by archive_meeting / archive_period)
#  - a local cache of motions and amendments with their outcome (NotuBiz module "Moties")
# Logic lives in skills/raadsarchief/scripts/raadsarchief_lib.ps1, so the CLI and this server behave the same.
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
. (Join-Path $PSScriptRoot "../skills/raadsarchief/scripts/raadsarchief_lib.ps1")

function Fail($message) { throw [System.ArgumentException]::new($message) }

function Send-Response($id, $result, $err) {
    $resp = [ordered]@{ jsonrpc = "2.0"; id = $id }
    if ($err) { $resp["error"] = $err } else { $resp["result"] = $result }
    [Console]::WriteLine(($resp | ConvertTo-Json -Depth 12 -Compress))
}
function Send-Text($id, $text) { Send-Response $id @{ content = @(@{ type = "text"; text = $text }) } $null }

# ---- input validation
function Get-Root($a) {
    $v = [string]$a.root
    if (-not $v) { return $null }
    if (-not [IO.Path]::IsPathRooted($v) -or $v -match '(^|[\\/])\.\.([\\/]|$)') { Fail "Invalid root: give an absolute folder without '..'." }
    return $v
}
function Get-Date10($a, $name) {
    $v = [string]$a.$name
    if (-not $v) { return $null }
    if ($v -notmatch '^\d{4}(-\d{2}(-\d{2})?)?$') { Fail "Invalid ${name}: use yyyy, yyyy-mm or yyyy-mm-dd." }
    if ($name -eq 'date_to') {
        if ($v.Length -eq 4) { return "$v-12-31" }
        if ($v.Length -eq 7) { return "$v-31" }
    }
    return $v
}
function Get-Name($a, $name) {
    $v = [string]$a.$name
    if (-not $v) { return $null }
    if ($v -notmatch "^[\p{L}\p{N} .,'()&/+-]{1,80}$") { Fail "Invalid ${name}." }
    return $v.Trim()
}
function Get-Choice($a, $name, $allowed, $default) {
    $v = [string]$a.$name
    if (-not $v) { return $default }
    if ($allowed -notcontains $v) { Fail "Invalid ${name}: use one of $($allowed -join ', ')." }
    return $v
}
function Get-Int($a, $name, $default, $min, $max) {
    if ($null -eq $a.$name -or [string]$a.$name -eq '') { return $default }
    $n = 0
    if (-not [int]::TryParse([string]$a.$name, [ref]$n) -or $n -lt $min -or $n -gt $max) { Fail "Invalid ${name}: whole number from $min to $max." }
    return $n
}
function Get-Query($a, [bool]$required) {
    $v = [string]$a.query
    if (-not $v) { if ($required) { Fail "Give a query." }; return $null }
    if ($v.Length -gt 200 -or $v -match '[\x00-\x1f]') { Fail "Invalid query: at most 200 characters, no control characters." }
    return $v
}

$docTypes = @('motie', 'amendement', 'agenda', 'besluitenlijst', 'verslag', 'vragen', 'voorstel', 'brief', 'advies', 'bijlage', 'overig')

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
                Send-Response $id @{ protocolVersion = "2024-11-05"; capabilities = @{ tools = @{} }; serverInfo = @{ name = "raadsarchief"; version = "1.0.0" } } $null
            }
            "notifications/initialized" { }
            "tools/list" {
                $rootDesc = "Optional absolute archive folder. Default: env OPEN_OVERHEID_ARCHIVE_ROOT, else Documents/Raadsinformatie."
                $tools = @(
                    @{
                        name = "archive_index"
                        description = "Build or refresh the local search index over the archived council documents (PDF, Markdown agendas, DOCX, HTML) in the archive folder. Incremental: only new or changed files are read. Uses pdftotext when installed, else a built-in PDF reader (no OCR: scans are found by title only). Stops after max_seconds and reports what is left; call again to continue."
                        inputSchema = @{ type = "object"; properties = @{
                            root = @{ type = "string"; description = $rootDesc }
                            max_seconds = @{ type = "integer"; description = "Time budget for text extraction in this call (10-600, default 45)."; default = 45 }
                        } }
                    },
                    @{
                        name = "archive_search"
                        description = "Search the local raadsarchief index across years. mode 'documents' = matching documents with snippet and page; 'first' = first mention (oldest meeting first, e.g. 'when did X first come up in the stadsdeelcommissie'); 'timeline' = number of documents and meetings per year or month, with index coverage per period. Query: words must all occur (substring, case-insensitive), ""exact phrase"", -word excludes."
                        inputSchema = @{ type = "object"; properties = @{
                            query = @{ type = "string"; description = "E.g. 'Meervaart', '""Nieuwe Meervaart"" Sloterplas', 'afval -zwerfvuil'." }
                            mode = @{ type = "string"; enum = @("documents", "first", "timeline"); default = "documents" }
                            organisation = @{ type = "string"; description = "Organisation name part or NotuBiz id, e.g. 'Nieuw-West' or 2328." }
                            body = @{ type = "string"; description = "Body or committee name part, e.g. 'Stadsdeelcommissie'." }
                            date_from = @{ type = "string"; description = "yyyy, yyyy-mm or yyyy-mm-dd." }
                            date_to = @{ type = "string"; description = "yyyy, yyyy-mm or yyyy-mm-dd." }
                            doc_type = @{ type = "string"; enum = $docTypes; description = "Document type, derived from the title." }
                            group_by = @{ type = "string"; enum = @("year", "month"); description = "For mode timeline."; default = "year" }
                            sort = @{ type = "string"; enum = @("newest", "oldest"); description = "For mode documents."; default = "newest" }
                            limit = @{ type = "integer"; description = "1-200, default 20."; default = 20 }
                            root = @{ type = "string"; description = $rootDesc }
                        }; required = @("query") }
                    },
                    @{
                        name = "motions_sync"
                        description = "Download motions and amendments with their outcome (aangenomen, verworpen, ingetrokken), submitters, parties and vote text from NotuBiz into a local cache. Available for the Gemeenteraad (281, about 10,000 since 2013) and stadsdelen Oost (1425), Zuidoost (2122), West (1413), Zuid (1424), Noord (977). Nieuw-West (2328) and Centrum (547) do not register motions in NotuBiz: use archive_search with doc_type motie. Incremental; call again when it reports a time budget stop."
                        inputSchema = @{ type = "object"; properties = @{
                            organisation_id = @{ type = "integer"; description = "Default 281 (Gemeenteraad)."; default = 281 }
                            full = @{ type = "boolean"; description = "Download everything again instead of only new items and the most recent 500."; default = $false }
                            max_seconds = @{ type = "integer"; description = "Time budget for this call (10-600, default 45)."; default = 45 }
                            root = @{ type = "string"; description = $rootDesc }
                        } }
                    },
                    @{
                        name = "motions_search"
                        description = "Search the local motion cache (run motions_sync first) and count outcomes. Filter on words in title and vote text, party (fractie), submitter (indiener), outcome, type and date; summary_by gives counts per outcome, party, submitter or year (submitted, adopted, rejected, withdrawn)."
                        inputSchema = @{ type = "object"; properties = @{
                            organisation_id = @{ type = "integer"; default = 281 }
                            query = @{ type = "string"; description = "Words in title, vote text, meeting; ""phrase"" and -exclude work." }
                            fractie = @{ type = "string"; description = "Part of the party (fractie) name." }
                            indiener = @{ type = "string"; description = "Submitter name part." }
                            uitslag = @{ type = "string"; enum = @("aangenomen", "verworpen", "ingetrokken", "aangehouden", "vervallen", "afgedaan", "anders", "onbekend") }
                            type = @{ type = "string"; description = "'Motie' or 'Amendement'." }
                            date_from = @{ type = "string"; description = "yyyy, yyyy-mm or yyyy-mm-dd." }
                            date_to = @{ type = "string"; description = "yyyy, yyyy-mm or yyyy-mm-dd." }
                            summary_by = @{ type = "string"; enum = @("none", "uitslag", "fractie", "indiener", "jaar"); default = "uitslag" }
                            sort = @{ type = "string"; enum = @("newest", "oldest"); default = "newest" }
                            limit = @{ type = "integer"; description = "0-200, default 25."; default = 25 }
                            root = @{ type = "string"; description = $rootDesc }
                        } }
                    }
                )
                Send-Response $id @{ tools = $tools } $null
            }
            "tools/call" {
                $toolName = $req.params.name
                $a = $req.params.arguments
                if ($null -eq $a) { $a = New-Object PSObject }
                $root = Get-Root $a

                if ($toolName -eq "archive_index") {
                    $secs = Get-Int $a 'max_seconds' 45 10 600
                    $res = Update-ArchiveIndex -Root $root -MaxSeconds $secs 3>$null 4>$null 6>$null
                    Send-Text $id ($res | ConvertTo-Json -Depth 5)
                }
                elseif ($toolName -eq "archive_search") {
                    $p = @{ Root = $root; Query = (Get-Query $a $true)
                        Mode = (Get-Choice $a 'mode' @('documents', 'first', 'timeline') 'documents')
                        GroupBy = (Get-Choice $a 'group_by' @('year', 'month') 'year')
                        Sort = (Get-Choice $a 'sort' @('newest', 'oldest') 'newest')
                        Limit = (Get-Int $a 'limit' 20 1 200) }
                    $org = [string]$a.organisation
                    if ($org) { if ($org -notmatch "^[\p{L}\p{N} .,'()&/+-]{1,80}$") { Fail "Invalid organisation." }; $p.Organisation = $org.Trim() }
                    $v = Get-Name $a 'body'; if ($v) { $p.Body = $v }
                    $v = Get-Date10 $a 'date_from'; if ($v) { $p.DateFrom = $v }
                    $v = Get-Date10 $a 'date_to'; if ($v) { $p.DateTo = $v }
                    $v = Get-Choice $a 'doc_type' $docTypes $null; if ($v) { $p.DocType = $v }
                    $res = Search-Archive @p 3>$null
                    Send-Text $id ($res | ConvertTo-Json -Depth 6)
                }
                elseif ($toolName -eq "motions_sync") {
                    $org = Get-Int $a 'organisation_id' 281 1 99999999
                    $secs = Get-Int $a 'max_seconds' 45 10 600
                    $res = Sync-Motions -OrganisationId $org -Root $root -Full:($a.full -eq $true) -MaxSeconds $secs 3>$null
                    Send-Text $id ($res | ConvertTo-Json -Depth 5)
                }
                elseif ($toolName -eq "motions_search") {
                    $p = @{ Root = $root; OrganisationId = (Get-Int $a 'organisation_id' 281 1 99999999)
                        SummaryBy = (Get-Choice $a 'summary_by' @('none', 'uitslag', 'fractie', 'indiener', 'jaar') 'uitslag')
                        Sort = (Get-Choice $a 'sort' @('newest', 'oldest') 'newest')
                        Limit = (Get-Int $a 'limit' 25 0 200) }
                    $q = Get-Query $a $false; if ($q) { $p.Query = $q }
                    foreach ($k in @('fractie', 'indiener', 'type')) { $v = Get-Name $a $k; if ($v) { $p[(Get-Culture).TextInfo.ToTitleCase($k)] = $v } }
                    $v = Get-Choice $a 'uitslag' @('aangenomen', 'verworpen', 'ingetrokken', 'aangehouden', 'vervallen', 'afgedaan', 'anders', 'onbekend') $null; if ($v) { $p.Uitslag = $v }
                    $v = Get-Date10 $a 'date_from'; if ($v) { $p.DateFrom = $v }
                    $v = Get-Date10 $a 'date_to'; if ($v) { $p.DateTo = $v }
                    $res = Search-Motions @p 3>$null
                    Send-Text $id ($res | ConvertTo-Json -Depth 6)
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
