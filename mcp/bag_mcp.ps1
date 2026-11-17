# JSON-RPC 2.0 Stdio MCP Server for the BAG (Basisregistratie Adressen en Gebouwen)
# Sources (no key): PDOK Locatieserver for address lookup and area codes,
#                   PDOK BAG OGC API Features for verblijfsobject and pand details.
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$locBase = "https://api.pdok.nl/bzk/locatieserver/search/v3_1/free"
$bagBase = "https://api.pdok.nl/kadaster/bag/ogc/v2/collections"
$userAgent = "open-overheid-mcp/1.10 (+https://github.com/maikell/ai-openoverheid)"
$locFields = "weergavenaam,adresseerbaarobject_id,nummeraanduiding_id,straatnaam,huisnummer,huisletter,huisnummertoevoeging,postcode,woonplaatsnaam,gemeentecode,gemeentenaam,wijkcode,wijknaam,buurtcode,buurtnaam,centroide_ll,centroide_rd,score"

$rpBase = "https://service.pdok.nl/kadaster/ruimtelijke-plannen/wms/v1_0"
$rpLayers = "bestemmingsplangebied,enkelbestemming,dubbelbestemming,bouwvlak,bouwaanduiding,functieaanduiding,gebiedsaanduiding,maatvoering"

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

# Spatial plans (Wro: bestemmingsplannen, the temporary part of the omgevingsplan) at one RD point
function Get-PlansAt([double]$x, [double]$y) {
    $inv = [Globalization.CultureInfo]::InvariantCulture
    $bbox = "{0},{1},{2},{3}" -f ($x - 1).ToString($inv), ($y - 1).ToString($inv), ($x + 1).ToString($inv), ($y + 1).ToString($inv)
    $url = "$rpBase`?service=WMS&version=1.3.0&request=GetFeatureInfo&layers=$rpLayers&query_layers=$rpLayers&crs=EPSG:28992&bbox=$bbox&width=3&height=3&i=1&j=1&info_format=application/json&feature_count=100"
    return (Get-Json $url)
}

function Format-Plans($json) {
    $plans = @(); $enkel = @(); $dubbel = @(); $aand = @()
    foreach ($f in @($json.features)) {
        if ($null -eq $f) { continue }
        $p = $f.properties
        if ([string]$p.historisch -eq "1") { continue }
        $layer = ([string]$f.id).Split(".")[0]
        $link = (([string]$p.verwijzingnaartekst) -split ",")[0]
        if ($layer -eq "bestemmingsplangebied") {
            $plans += [pscustomobject][ordered]@{ naam = $p.naam; type = $p.typeplan; planstatus = $p.planstatus; dossierstatus = $p.dossierstatus
                datum = $p.datum; id = $p.identificatie; regels = $link; besluit = $p.verwijzingnaarvaststellingsbesluit
                viewer = "https://ruimtelijkeplannen.nl/viewer/view?planidn=$($p.identificatie)" }
        } elseif ($layer -eq "enkelbestemming") {
            $enkel += [pscustomobject][ordered]@{ bestemming = $p.naam; hoofdgroep = $p.bestemmingshoofdgroep; plan = $p.plangebied; datum = $p.datum; regels = $link }
        } elseif ($layer -eq "dubbelbestemming") {
            $dubbel += [pscustomobject][ordered]@{ bestemming = $p.naam; plan = $p.plangebied; datum = $p.datum; regels = $link }
        } else {
            $aand += [pscustomobject][ordered]@{ soort = $layer; naam = $p.naam; plan = $p.plangebied; regels = $link }
        }
    }
    return [ordered]@{
        plannen = @($plans | Sort-Object datum -Descending)
        enkelbestemmingen = @($enkel | Sort-Object datum -Descending)
        dubbelbestemmingen = @($dubbel)
        aanduidingen = @($aand | Where-Object { $_.naam -or $_.soort -eq "bouwvlak" })
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
                        name = "bag_plannen_op_adres"
                        description = "Ruimtelijke plannen (Wro) op een adres of RD-punt: bestemmingsplannen en paraplu-plannen, enkel- en dubbelbestemmingen, bouwvlak en aanduidingen, met links naar de regels. Dit is het tijdelijke deel van het omgevingsplan (bron PDOK Ruimtelijke plannen, CC0, 2x per jaar bijgewerkt). Wijzigingen onder de Omgevingswet (nieuw deel, sinds 2024) staan hier niet in: verwijs daarvoor naar Regels op de kaart."
                        inputSchema = @{ type = "object"; properties = @{
                            postcode = @{ type = "string" }
                            huisnummer = @{ type = "integer" }
                            huisletter = @{ type = "string" }
                            toevoeging = @{ type = "string" }
                            rd_x = @{ type = "number"; description = "RD-coordinaat x (EPSG:28992), in plaats van een adres." }
                            rd_y = @{ type = "number"; description = "RD-coordinaat y (EPSG:28992)." }
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
                elseif ($toolName -eq "bag_plannen_op_adres") {
                    $adres = $null
                    $inv = [Globalization.CultureInfo]::InvariantCulture
                    $x = 0.0; $y = 0.0
                    if ($null -ne $a.rd_x -and $null -ne $a.rd_y) {
                        if (-not [double]::TryParse([string]$a.rd_x, [Globalization.NumberStyles]::Float, $inv, [ref]$x) -or -not [double]::TryParse([string]$a.rd_y, [Globalization.NumberStyles]::Float, $inv, [ref]$y) -or $x -lt 0 -or $x -gt 300000 -or $y -lt 289000 -or $y -gt 629000) { Fail "Ongeldige RD-coordinaten." }
                    } elseif ($a.postcode) {
                        $docs = Search-Address (Get-AddressFilter $a) "*" 1
                        if ($docs.Count -eq 0) { Fail "Adres niet gevonden in de BAG." }
                        $adres = $docs[0].weergavenaam
                        if ([string]$docs[0].centroide_rd -notmatch 'POINT\(([0-9.]+) ([0-9.]+)\)') { Fail "Geen coordinaten voor dit adres." }
                        $x = [double]::Parse($Matches[1], $inv); $y = [double]::Parse($Matches[2], $inv)
                    } else { Fail "Geef postcode + huisnummer of rd_x + rd_y." }
                    $out = [ordered]@{ adres = $adres; rd = "$($x.ToString($inv)), $($y.ToString($inv))" }
                    $res = Format-Plans (Get-PlansAt $x $y)
                    foreach ($k in $res.Keys) { $out[$k] = $res[$k] }
                    $out.let_op = "Tijdelijk deel van het omgevingsplan (Wro-plannen op ruimtelijkeplannen.nl). Paraplu-plannen gelden naast het hoofdplan. Omgevingswet-wijzigingen sinds 2024 en de bruidsschat: zie Regels op de kaart (omgevingswet.overheid.nl). Informatie, geen juridisch advies."
                    $out.bron = "PDOK Ruimtelijke plannen (Kadaster), CC0"
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
