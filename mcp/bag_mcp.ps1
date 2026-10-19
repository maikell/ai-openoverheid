# JSON-RPC 2.0 Stdio MCP Server for the BAG (Basisregistratie Adressen en Gebouwen)
# Sources (no key): PDOK Locatieserver for address lookup and area codes,
#                   PDOK BAG OGC API Features for verblijfsobject and pand details.
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$locBase = "https://api.pdok.nl/bzk/locatieserver/search/v3_1/free"
$bagBase = "https://api.pdok.nl/kadaster/bag/ogc/v2/collections"
$userAgent = "open-overheid-mcp/1.8 (+https://github.com/maikell/ai-openoverheid)"
$locFields = "weergavenaam,adresseerbaarobject_id,nummeraanduiding_id,straatnaam,huisnummer,huisletter,huisnummertoevoeging,postcode,woonplaatsnaam,gemeentecode,gemeentenaam,wijkcode,wijknaam,buurtcode,buurtnaam,centroide_ll,centroide_rd,score"

$postcodePattern = '^\d{4}\s?[A-Za-z]{2}$'
$bagIdPattern    = '^\d{16}$'
$pandHrefPattern = '^https://api\.pdok\.nl/kadaster/bag/ogc/v2/collections/pand/items/[0-9a-fA-F-]{36}$'

function Fail($message) { throw [System.ArgumentException]::new($message) }

function Get-Json($url) {
    $wc = New-Object System.Net.WebClient
    $wc.Encoding = [System.Text.Encoding]::UTF8
    $wc.Headers.Add("User-Agent", $userAgent)
    $wc.Headers.Add("Accept", "application/json")
    return ($wc.DownloadString($url) | ConvertFrom-Json)
}

function Send-Response($id, $result, $err) {
    $resp = [ordered]@{ jsonrpc = "2.0"; id = $id }
    if ($err) { $resp["error"] = $err } else { $resp["result"] = $result }
    [Console]::WriteLine(($resp | ConvertTo-Json -Depth 12 -Compress))
}
function Send-Text($id, $text) { Send-Response $id @{ content = @(@{ type = "text"; text = $text }) } $null }

# Validated address parts; returns Locatieserver filter queries
function Get-AddressFilter($a) {
    $pc = ([string]$a.postcode).Trim().ToUpper() -replace '\s', ''
    if ($pc -notmatch '^\d{4}[A-Z]{2}$') { Fail "Ongeldige postcode: gebruik bijv. 1011PN." }
    $nr = 0
    if (-not [int]::TryParse([string]$a.huisnummer, [ref]$nr) -or $nr -lt 1 -or $nr -gt 99999) { Fail "Ongeldig huisnummer." }
    $fq = @("type:adres", "postcode:$pc", "huisnummer:$nr")
    if ($a.huisletter) {
        $l = ([string]$a.huisletter).Trim().ToUpper()
        if ($l -notmatch '^[A-Z]$') { Fail "Ongeldige huisletter: een letter, bijv. A." }
        $fq += "huisletter:$l"
    }
    if ($a.toevoeging) {
        $t = ([string]$a.toevoeging).Trim()
        if ($t -notmatch '^[A-Za-z0-9]{1,4}$') { Fail "Ongeldige toevoeging: 1 tot 4 letters of cijfers." }
        $fq += "huisnummertoevoeging:$t"
    }
    return $fq
}

function Search-Address($fq, $q, $rows) {
    $url = "$locBase`?rows=$rows&fl=$locFields&q=" + [uri]::EscapeDataString($q)
    foreach ($f in $fq) { $url += "&fq=" + [uri]::EscapeDataString($f) }
    return @((Get-Json $url).response.docs)
}

function Get-Vbo($vboId) {
    $j = Get-Json "$bagBase/verblijfsobject/items?f=json&identificatie=$vboId"
    if (-not $j.features -or $j.features.Count -eq 0) { return $null }
    return $j.features[0]
}

function Format-Pand($p) {
    return [ordered]@{
        pand_id = $p.identificatie; bouwjaar = $p.bouwjaar; status = $p.status
        gebruiksdoelen = $p.gebruiksdoel; aantal_verblijfsobjecten = $p.aantal_verblijfsobjecten
        documentdatum = $p.documentdatum; bron = $p.rdf_seealso
    }
}

function Get-PandenFromVbo($vbo) {
    $out = @()
    foreach ($href in @($vbo.properties.'pand.href')) {
        if (-not $href) { continue }
        # Only follow links that point to PDOK pand items
        if ([string]$href -notmatch $pandHrefPattern) { continue }
        $p = Get-Json "$href`?f=json"
        $out += Format-Pand $p.properties
        if ($out.Count -ge 5) { break }
    }
    return $out
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
                Send-Response $id @{ protocolVersion = "2024-11-05"; capabilities = @{ tools = @{} }; serverInfo = @{ name = "bag"; version = "1.0.0" } } $null
            }
            "notifications/initialized" { }
            "tools/list" {
                $tools = @(
                    @{
                        name = "bag_zoek_adres"
                        description = "Zoek een adres in de BAG. Liefst met postcode + huisnummer (exact); anders vrije tekst (geeft kandidaten die je moet controleren). Geeft BAG-ID's en buurt-, wijk- en gemeentecodes."
                        inputSchema = @{ type = "object"; properties = @{
                            postcode = @{ type = "string"; description = "Bijv. 1011PN." }
                            huisnummer = @{ type = "integer"; description = "Bijv. 1." }
                            huisletter = @{ type = "string"; description = "Optioneel, bijv. A." }
                            toevoeging = @{ type = "string"; description = "Optioneel, bijv. 1 of H." }
                            adres = @{ type = "string"; description = "Vrije tekst als je geen postcode hebt, bijv. 'Amstel 1 Amsterdam'." }
                        } }
                    },
                    @{
                        name = "bag_adresinfo"
                        description = "Gegevens van een adres uit de BAG: gebruiksdoel, oppervlakte en status van het verblijfsobject, en bouwjaar, status en aantal verblijfsobjecten van het pand. Geef postcode + huisnummer of een verblijfsobject_id (16 cijfers)."
                        inputSchema = @{ type = "object"; properties = @{
                            postcode = @{ type = "string" }
                            huisnummer = @{ type = "integer" }
                            huisletter = @{ type = "string" }
                            toevoeging = @{ type = "string" }
                            verblijfsobject_id = @{ type = "string"; description = "16 cijfers, bijv. 0363010012143319." }
                        } }
                    },
                    @{
                        name = "bag_pand"
                        description = "Gegevens van een pand op pand-ID (16 cijfers): bouwjaar, status, gebruiksdoelen en aantal verblijfsobjecten."
                        inputSchema = @{ type = "object"; properties = @{
                            pand_id = @{ type = "string"; description = "16 cijfers, bijv. 0363100012186092." }
                        }; required = @("pand_id") }
                    }
                )
                Send-Response $id @{ tools = $tools } $null
            }
            "tools/call" {
                $toolName = $req.params.name
                $a = $req.params.arguments
                if ($null -eq $a) { $a = New-Object PSObject }

                if ($toolName -eq "bag_zoek_adres") {
                    if ($a.postcode) {
                        $docs = Search-Address (Get-AddressFilter $a) "*" 10
                        $out = [ordered]@{ zoekwijze = "exact (postcode + huisnummer)"; gevonden = $docs.Count; adressen = $docs }
                    } elseif ($a.adres) {
                        $q = ([string]$a.adres).Trim()
                        if ($q.Length -lt 3 -or $q.Length -gt 100) { Fail "Adres moet 3 tot 100 tekens zijn." }
                        $docs = Search-Address @("type:adres") $q 5
                        $out = [ordered]@{ zoekwijze = "vrije tekst"; let_op = "Kandidaten op relevantie; controleer straat, huisnummer en postcode voordat je verder gaat."; gevonden = $docs.Count; adressen = $docs }
                    } else { Fail "Geef postcode + huisnummer of een adres." }
                    Send-Text $id ($out | ConvertTo-Json -Depth 5)
                }
                elseif ($toolName -eq "bag_adresinfo") {
                    $loc = $null
                    if ($a.verblijfsobject_id) {
                        $vboId = ([string]$a.verblijfsobject_id).Trim()
                        if ($vboId -notmatch $bagIdPattern) { Fail "Ongeldig verblijfsobject_id: 16 cijfers." }
                        $docs = Search-Address @("type:adres", "adresseerbaarobject_id:$vboId") "*" 10
                        if ($docs.Count -gt 0) { $loc = $docs[0] }
                    } elseif ($a.postcode) {
                        $docs = Search-Address (Get-AddressFilter $a) "*" 2
                        if ($docs.Count -eq 0) { Fail "Adres niet gevonden in de BAG." }
                        if ($docs.Count -gt 1) {
                            $docs = Search-Address (Get-AddressFilter $a) "*" 25
                            $out = [ordered]@{ melding = "Meerdere adressen op dit huisnummer; geef huisletter en/of toevoeging."; kandidaten = @($docs | ForEach-Object { [ordered]@{ adres = $_.weergavenaam; huisletter = $_.huisletter; toevoeging = $_.huisnummertoevoeging } }) }
                            Send-Text $id ($out | ConvertTo-Json -Depth 4); continue
                        }
                        $loc = $docs[0]
                        $vboId = [string]$loc.adresseerbaarobject_id
                        if ($vboId -match $bagIdPattern) { $docs = Search-Address @("type:adres", "adresseerbaarobject_id:$vboId") "*" 10 }
                    } else { Fail "Geef postcode + huisnummer of een verblijfsobject_id." }

                    if ($vboId -notmatch $bagIdPattern) {
                        $out = [ordered]@{ adres = $loc.weergavenaam; melding = "Dit adres hoort bij een ligplaats of standplaats, niet bij een verblijfsobject." ; adresseerbaarobject_id = $vboId }
                        Send-Text $id ($out | ConvertTo-Json -Depth 4); continue
                    }
                    $vbo = Get-Vbo $vboId
                    if (-not $vbo) {
                        $out = [ordered]@{ adres = $(if ($loc) { $loc.weergavenaam }); adresseerbaarobject_id = $vboId; melding = "Geen verblijfsobject gevonden; mogelijk een ligplaats of standplaats." }
                        Send-Text $id ($out | ConvertTo-Json -Depth 4); continue
                    }
                    $v = $vbo.properties
                    $out = [ordered]@{
                        adres = $(if ($loc) { $loc.weergavenaam } else { "$($v.openbare_ruimte_naam) $($v.huisnummer)$($v.huisletter) $($v.toevoeging), $($v.postcode) $($v.woonplaats_naam)".Replace(" ,", ",") })
                        verblijfsobject = [ordered]@{
                            id = $v.identificatie; status = $v.status; gebruiksdoelen = $v.gebruiksdoel
                            oppervlakte_m2 = $v.oppervlakte; hoofdadres_id = $v.hoofdadres_identificatie
                            documentdatum = $v.documentdatum; bron = $v.rdf_seealso
                        }
                        alle_adressen = @($docs | ForEach-Object { $_.weergavenaam } | Select-Object -Unique)
                        panden = @(Get-PandenFromVbo $vbo)
                        gebied = $(if ($loc) { [ordered]@{ buurtcode = $loc.buurtcode; buurtnaam = $loc.buurtnaam; wijkcode = $loc.wijkcode; wijknaam = $loc.wijknaam; gemeentecode = "GM$($loc.gemeentecode)"; gemeentenaam = $loc.gemeentenaam } })
                        coordinaten = $(if ($loc) { [ordered]@{ wgs84 = $loc.centroide_ll; rd = $loc.centroide_rd } })
                        bron = "BAG via PDOK (Kadaster), Public Domain Mark 1.0"
                    }
                    Send-Text $id ($out | ConvertTo-Json -Depth 6)
                }
                elseif ($toolName -eq "bag_pand") {
                    $pandId = ([string]$a.pand_id).Trim()
                    if ($pandId -notmatch $bagIdPattern) { Fail "Ongeldig pand_id: 16 cijfers." }
                    $j = Get-Json "$bagBase/pand/items?f=json&identificatie=$pandId"
                    if (-not $j.features -or $j.features.Count -eq 0) { Fail "Pand niet gevonden." }
                    Send-Text $id ((Format-Pand $j.features[0].properties) | ConvertTo-Json -Depth 4)
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
