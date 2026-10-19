# JSON-RPC 2.0 Stdio MCP Server for Amsterdam Woo-besluiten (Open Amsterdam / Memorix Mediabank)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
# Publieke sleutel die open.amsterdam zelf gebruikt; overschrijfbaar via MEMORIX_API_KEY
$apiKey = if ($env:MEMORIX_API_KEY) { $env:MEMORIX_API_KEY } else { "fdf0129e-e0d2-11ec-aa22-775b74759445" }
$uuidPattern = '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
$wc = New-Object System.Net.WebClient
$wc.Headers.Add("User-Agent", "open-overheid-mcp/1.4 (+https://github.com/maikell/ai-openoverheid)")
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
                    serverInfo = @{ name = "amsterdam-woo"; version = "1.0.0" }
                } $null
            }
            "notifications/initialized" {
                # No response needed
            }
            "tools/list" {
                $tools = @(
                    @{
                        name = "search_woo_decisions"
                        description = "Doorzoek openbaar gemaakte Wob- en Woo-besluiten en dossiers van Gemeente Amsterdam (open.amsterdam)."
                        inputSchema = @{
                            type = "object"
                            properties = @{
                                query = @{
                                    type = "string"
                                    description = "Zoekterm, trefwoord of dossieronderwerp (optioneel, laat leeg voor meest recente besluiten)."
                                }
                                page = @{
                                    type = "integer"
                                    description = "Paginanummer (standaard 1)."
                                    default = 1
                                }
                                rows = @{
                                    type = "integer"
                                    description = "Aantal op te halen documenten (standaard 10, max 50)."
                                    default = 10
                                }
                            }
                        }
                    },
                    @{
                        name = "get_woo_document"
                        description = "Haal volledige details, dossiercontext en de directe PDF download-URL op van een specifiek Woo-document via het document-ID (UUID)."
                        inputSchema = @{
                            type = "object"
                            properties = @{
                                document_id = @{
                                    type = "string"
                                    description = "Het unieke UUID van het document (bijv. 145deecc-e5ad-45d2-87d1-267eaa3f7efd)."
                                }
                            }
                            required = @("document_id")
                        }
                    }
                )
                Send-Response $id @{ tools = $tools } $null
            }
            "tools/call" {
                $toolName = $req.params.name
                $toolArgs = $req.params.arguments

                if ($toolName -eq "search_woo_decisions") {
                    # Alleen gehele getallen binnen veilige grenzen toelaten
                    $page = 1
                    if ($toolArgs.page) { $page = [Math]::Max(1, [Math]::Min(1000, [int]$toolArgs.page)) }
                    $rows = 10
                    if ($toolArgs.rows) { $rows = [Math]::Max(1, [Math]::Min(50, [int]$toolArgs.rows)) }
                    $qParam = ""
                    if ($toolArgs.query -and -not [string]::IsNullOrWhiteSpace($toolArgs.query)) {
                        $qParam = "&q=" + [uri]::EscapeDataString([string]$toolArgs.query)
                    }

                    $url = "https://webservices.memorix.nl/mediabank/media?apiKey=$apiKey&page=$page&rows=$rows&fq[]=search_s_categorie:%22Wob-en%20Woo-besluiten%22&sort=order_i_created_time%20desc$qParam"
                    $data = $wc.DownloadString($url)
                    Send-Response $id @{
                        content = @(
                            @{ type = "text"; text = $data }
                        )
                    } $null
                }
                elseif ($toolName -eq "get_woo_document") {
                    $docId = [string]$toolArgs.document_id
                    # Voorkomt dat een gemanipuleerd ID andere Memorix-endpoints aanroept
                    if ($docId -notmatch $uuidPattern) {
                        Send-Response $id $null @{ code = -32602; message = "Ongeldig document_id: verwacht een UUID." }
                        continue
                    }
                    $url = "https://webservices.memorix.nl/mediabank/media/$docId`?apiKey=$apiKey"
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
