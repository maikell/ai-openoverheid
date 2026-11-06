# JSON-RPC 2.0 Stdio MCP Server for Amsterdam Raadsinformatie (NotuBiz)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$wc = New-Object System.Net.WebClient
$wc.Headers.Add("User-Agent", "open-overheid-mcp/1.5 (+https://github.com/maikell/ai-openoverheid)")
$wc.Headers.Add("Accept", "application/json")

function Send-Response($id, $result, $error) {
    $resp = [ordered]@{
        jsonrpc = "2.0"
        id = $id
    }
    if ($error) {
        $resp["error"] = $error
    } else {
        $resp["result"] = $result
    }
    $json = $resp | ConvertTo-Json -Depth 10 -Compress
    [Console]::WriteLine($json)
}

while ($true) {
    $line = [Console]::ReadLine()
    if ($null -eq $line) { break }
    if ([string]::IsNullOrWhiteSpace($line)) { continue }

    try {
        $req = $line | ConvertFrom-Json
        $id = $req.id
        $method = $req.method

        switch ($method) {
            "initialize" {
                Send-Response $id @{
                    protocolVersion = "2024-11-05"
                    capabilities = @{ tools = @{} }
                    serverInfo = @{ name = "amsterdam-raadsinformatie"; version = "1.0.0" }
                } $null
            }
            "notifications/initialized" {
                # No response needed
            }
            "tools/list" {
                $tools = @(
                    @{
                        name = "get_meetings"
                        description = "Haal recente en geplande raads- en commissievergaderingen op van Amsterdam."
                        inputSchema = @{
                            type = "object"
                            properties = @{
                                organisation_id = @{
                                    type = "integer"
                                    description = "281 = Gemeenteraad, 1768 = B&W, 547 = Centrum, 977 = Noord, 1413 = West, 1424 = Zuid, 1425 = Oost, 2328 = Nieuw-West, 2122 = Zuidoost."
                                    default = 281
                                }
                            }
                        }
                    },
                    @{
                        name = "get_meeting_agenda"
                        description = "Haal de volledige agenda, agendapunten en gekoppelde raadsdocumenten (moties, verslagen, brieven) op van een specifieke vergadering."
                        inputSchema = @{
                            type = "object"
                            properties = @{
                                event_id = @{
                                    type = "integer"
                                    description = "Het unieke identificatienummer van de vergadering (bijv. 1545281)."
                                }
                            }
                            required = @("event_id")
                        }
                    },
                    @{
                        name = "archive_meeting"
                        description = "Download and archive the agenda and all documents of one meeting into a local folder (one folder per meeting), verified by SHA-256. Unchanged files are skipped, changed files get a version suffix (v2, v3, ...), originals are never overwritten. Writes README.md and manifest.json in the folder. Give event_id, or organisation_id (optionally with category) for the next meeting. Use dry_run first for large meetings."
                        inputSchema = @{
                            type = "object"
                            properties = @{
                                event_id = @{ type = "integer"; description = "Meeting (event) ID, e.g. 1439170." }
                                organisation_id = @{ type = "integer"; description = "Used when event_id is empty: take the next meeting of this organisation (281 = Gemeenteraad, 2328 = Nieuw-West, see get_meetings)." }
                                category = @{ type = "string"; description = "Optional with organisation_id: part of the body or committee name, e.g. 'Stadsdeelcommissie'." }
                                root = @{ type = "string"; description = "Optional absolute base folder. The meeting goes in <root>/<organisation>/<yyyy-mm-dd> <body>. Default: env OPEN_OVERHEID_ARCHIVE_ROOT, else Documents/Raadsinformatie." }
                                target_dir = @{ type = "string"; description = "Optional absolute folder for this meeting; overrides root." }
                                dry_run = @{ type = "boolean"; description = "Only report what would be filed; write nothing."; default = $false }
                            }
                        }
                    }
                )
                Send-Response $id @{ tools = $tools } $null
            }
            "tools/call" {
                $toolName = $req.params.name
                $toolArgs = $req.params.arguments

                if ($toolName -eq "get_meetings") {
                    # Alleen een positief geheel getal toelaten, zodat de URL niet te manipuleren is
                    $orgId = 281
                    if ($null -ne $toolArgs.organisation_id) {
                        $tmp = 0
                        if (-not [int]::TryParse([string]$toolArgs.organisation_id, [ref]$tmp) -or $tmp -lt 1) {
                            Send-Response $id $null @{ code = -32602; message = "Ongeldig organisation_id: verwacht een positief geheel getal." }
                            continue
                        }
                        $orgId = $tmp
                    }
                    $url = "https://api.notubiz.nl/organisations/$orgId/events"
                    $data = $wc.DownloadString($url)
                    Send-Response $id @{
                        content = @(
                            @{ type = "text"; text = $data }
                        )
                    } $null
                }
                elseif ($toolName -eq "get_meeting_agenda") {
                    $eventId = 0
                    if (-not [int]::TryParse([string]$toolArgs.event_id, [ref]$eventId) -or $eventId -lt 1) {
                        Send-Response $id $null @{ code = -32602; message = "Ongeldig event_id: verwacht een positief geheel getal." }
                        continue
                    }
                    $url = "https://api.notubiz.nl/events/$eventId"
                    $data = $wc.DownloadString($url)
                    Send-Response $id @{
                        content = @(
                            @{ type = "text"; text = $data }
                        )
                    } $null
                }
                elseif ($toolName -eq "archive_meeting") {
                    $p = @{}
                    foreach ($k in @("event_id", "organisation_id")) {
                        if ($null -ne $toolArgs.$k -and [string]$toolArgs.$k -ne "") {
                            $tmp = 0
                            if (-not [int]::TryParse([string]$toolArgs.$k, [ref]$tmp) -or $tmp -lt 1) { throw "Invalid ${k}: expected a positive integer." }
                            if ($k -eq "event_id") { $p.EventId = $tmp } else { $p.OrganisationId = $tmp }
                        }
                    }
                    if (-not $p.EventId -and -not $p.OrganisationId) { throw "Give event_id or organisation_id." }
                    if ($toolArgs.category) {
                        $cat = [string]$toolArgs.category
                        if ($cat -notmatch '^[\p{L}\p{N} &.,()-]{1,80}$') { throw "Invalid category." }
                        $p.Category = $cat
                    }
                    foreach ($k in @("root", "target_dir")) {
                        $v = [string]$toolArgs.$k
                        if ($v) {
                            if (-not [IO.Path]::IsPathRooted($v) -or $v -match '(^|[\\/])\.\.([\\/]|$)') { throw "Invalid ${k}: give an absolute folder without '..'." }
                            if ($k -eq "root") { $p.Root = $v } else { $p.TargetDir = $v }
                        }
                    }
                    if (-not $p.Root -and $env:OPEN_OVERHEID_ARCHIVE_ROOT) { $p.Root = $env:OPEN_OVERHEID_ARCHIVE_ROOT }
                    if ($toolArgs.dry_run -eq $true) { $p.WhatIfOnly = $true }
                    $script = Join-Path $PSScriptRoot "../skills/amsterdam-notubiz/scripts/archive_meeting.ps1"
                    $out = (& $script @p *>&1 | ForEach-Object { "$_" }) -join "`n"
                    Send-Response $id @{
                        content = @(
                            @{ type = "text"; text = $out }
                        )
                    } $null
                }
                else {
                    Send-Response $id $null @{ code = -32601; message = "Tool not found: $toolName" }
                }
            }
            default {
                if ($null -ne $id) {
                    Send-Response $id $null @{ code = -32601; message = "Method not supported: $method" }
                }
            }
        }
    }
    catch {
        if ($null -ne $id) {
            Send-Response $id $null @{ code = -32603; message = $_.Exception.Message }
        }
    }
}
