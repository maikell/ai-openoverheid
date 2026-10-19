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
