# JSON-RPC 2.0 Stdio MCP Server for Amsterdam Openbaar Subsidieregister
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$wc = New-Object System.Net.WebClient
$wc.Headers.Add("User-Agent", "open-overheid-mcp/1.4 (+https://github.com/maikell/ai-openoverheid)")
$wc.Headers.Add("Accept", "application/hal+json, application/json")

$cacheDir = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "antigravity_subsidies")
if (-not (Test-Path $cacheDir)) { New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null }
$cacheFile = [System.IO.Path]::Combine($cacheDir, "subsidies_cache.csv")
$csvUrl = "https://api.data.amsterdam.nl/v1/subsidies/openbaar_subsidieregister?_format=csv"

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

function Get-SubsidiesData($maxAgeHours = 12) {
    $download = $true
    if (Test-Path $cacheFile) {
        $age = (Get-Date) - (Get-Item $cacheFile).LastWriteTime
        if ($age.TotalHours -lt $maxAgeHours) {
            $download = $false
        }
    }
    if ($download) {
        $wcDownload = New-Object System.Net.WebClient
        $wcDownload.DownloadFile($csvUrl, $cacheFile)
    }
    return Import-Csv -Path $cacheFile -Encoding UTF8
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
                    serverInfo = @{ name = "amsterdam-subsidies"; version = "1.0.0" }
                } $null
            }
            "notifications/initialized" {
                # No response needed
            }
            "tools/list" {
                $tools = @(
                    @{
                        name = "search_subsidies"
                        description = "Doorzoek het officiele Openbaar Subsidieregister van Gemeente Amsterdam (live gesynchroniseerd met het PowerBI dashboard)."
                        inputSchema = @{
                            type = "object"
                            properties = @{
                                query = @{
                                    type = "string"
                                    description = "Zoekterm voor projectnaam, regelingnaam of aanvrager (bijv. 'buurt', 'jeugd', 'kunst')."
                                }
                                cluster = @{
                                    type = "string"
                                    description = "Filter op cluster of organisatieonderdeel (bijv. 'Stadsdeel Nieuw-West', 'Gemeente Amsterdam')."
                                }
                                jaar = @{
                                    type = "integer"
                                    description = "Filter op subsidiejaar (bijv. 2025, 2026, 2027)."
                                }
                                limit = @{
                                    type = "integer"
                                    description = "Maximaal aantal records om terug te geven (standaard 10)."
                                    default = 10
                                }
                            }
                        }
                    },
                    @{
                        name = "get_subsidies_summary"
                        description = "Krijg actuele samenvattende statistieken en totalen over verleende subsidies per cluster of beleidsterrein."
                        inputSchema = @{
                            type = "object"
                            properties = @{
                                jaar = @{
                                    type = "integer"
                                    description = "Subsidiejaar (optioneel, bijv. 2026)."
                                }
                                group_by = @{
                                    type = "string"
                                    description = "Groeperen op 'organisatieonderdeel' (cluster) of 'beleidsterrein'."
                                    default = "organisatieonderdeel"
                                }
                            }
                        }
                    }
                )
                Send-Response $id @{ tools = $tools } $null
            }
            "tools/call" {
                $toolName = $req.params.name
                $toolArgs = $req.params.arguments
                $data = Get-SubsidiesData

                if ($toolName -eq "search_subsidies") {
                    $results = $data
                    if ($toolArgs.jaar) {
                        $j = [string]$toolArgs.jaar
                        $results = $results | Where-Object { $_.subsidiejaar -eq $j }
                    }
                    if ($toolArgs.cluster) {
                        $cl = $toolArgs.cluster
                        $results = $results | Where-Object { $_.organisatieonderdeel -like "*$cl*" -or $_.beleidsterrein -like "*$cl*" }
                    }
                    if ($toolArgs.query) {
                        $q = $toolArgs.query
                        $results = $results | Where-Object {
                            $_.aanvrager -like "*$q*" -or $_.projectnaam -like "*$q*" -or $_.regelingnaam -like "*$q*"
                        }
                    }

                    $limit = if ($toolArgs.limit) { [int]$toolArgs.limit } else { 10 }
                    $totalMatches = @($results).Count
                    $top = $results | Select-Object -First $limit | ForEach-Object {
                        [PSCustomObject]@{
                            Dossiernummer = $_.dossiernummer
                            Aanvrager = $_.aanvrager
                            Project = $_.projectnaam
                            Regeling = $_.regelingnaam
                            Cluster = $_.organisatieonderdeel
                            Beleidsterrein = $_.beleidsterrein
                            BedragAangevraagd = $_.bedragAangevraagd
                            BedragVerleend = $_.bedragVerleend
                            Subsidiejaar = $_.subsidiejaar
                            Publicatiedatum = $_.publicatiedatumVerleningsbesluit
                        }
                    }

                    $summaryText = "Totaal gevonden: $totalMatches subsidies (toont eerste $limit):`n" + ($top | ConvertTo-Json -Depth 3)
                    Send-Response $id @{
                        content = @(
                            @{ type = "text"; text = $summaryText }
                        )
                    } $null
                }
                elseif ($toolName -eq "get_subsidies_summary") {
                    $results = $data
                    if ($toolArgs.jaar) {
                        $j = [string]$toolArgs.jaar
                        $results = $results | Where-Object { $_.subsidiejaar -eq $j }
                    }
                    $groupField = if ($toolArgs.group_by -eq "beleidsterrein") { "beleidsterrein" } else { "organisatieonderdeel" }
                    
                    $groups = $results | Group-Object $groupField | Select-Object Name, Count, @{
                        Name = "TotaalBedragVerleend"
                        Expression = {
                            ($_.Group | Measure-Object -Property bedragVerleend -Sum).Sum
                        }
                    } | Sort-Object Count -Descending

                    $summaryText = ($groups | ConvertTo-Json -Depth 3)
                    Send-Response $id @{
                        content = @(
                            @{ type = "text"; text = $summaryText }
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
