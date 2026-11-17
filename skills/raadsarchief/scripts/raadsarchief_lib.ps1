<#
.SYNOPSIS
  Library for the raadsarchief skill: a local search index over archived council documents
  and a local cache of motions and amendments with their outcome (NotuBiz).

.DESCRIPTION
  Dot-source this file. Functions:
    Update-ArchiveIndex   build or refresh <root>/_index (text of every PDF, Markdown, DOCX, HTML)
    Search-Archive        search the index: documents, first mention, timeline
    Sync-Motions          download motions and amendments of one organisation into <root>/_index/moties
    Search-Motions        search the motion cache, with counts per outcome, party, submitter or year
  The archive is what archive_meeting.ps1 / archive_period.ps1 write: one folder per meeting with
  manifest.json. Other folders are indexed too; their date comes from a folder name starting with
  yyyy-mm-dd. Works with Windows PowerShell 5.1 and PowerShell 7.
#>

. (Join-Path $PSScriptRoot 'pdf_text.ps1')

$script:RaUserAgent = 'open-overheid/1.10 (+https://github.com/maikell/ai-openoverheid)'
$script:RaUtf8 = New-Object System.Text.UTF8Encoding($false)
$script:RaExtensions = @('.pdf', '.md', '.txt', '.docx', '.html', '.htm')
$script:RaOrgNames = @{
    281 = 'Gemeenteraad Amsterdam'; 1768 = 'College van B&W'; 547 = 'Stadsdeel Centrum'
    977 = 'Stadsdeel Noord'; 1413 = 'Stadsdeel West'; 1424 = 'Stadsdeel Zuid'
    1425 = 'Stadsdeel Oost'; 2328 = 'Stadsdeel Nieuw-West'; 2122 = 'Stadsdeel Zuidoost'
}

function Resolve-ArchiveRoot([string]$Root) {
    if (-not $Root) { $Root = $env:OPEN_OVERHEID_ARCHIVE_ROOT }
    if (-not $Root) { $Root = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Raadsinformatie' }
    return $Root
}

function Read-JsonFile([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    return ([IO.File]::ReadAllText($Path, $script:RaUtf8) | ConvertFrom-Json)
}

function Write-JsonFile([string]$Path, $Object, [int]$Depth = 6) {
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $tmp = "$Path.tmp"
    [IO.File]::WriteAllText($tmp, (ConvertTo-Json -InputObject $Object -Depth $Depth -Compress), $script:RaUtf8)
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function Get-DocType([string]$Title) {
    $t = $Title.ToLower()
    if ($t -match 'amendement') { return 'amendement' }
    if ($t -match 'motie') { return 'motie' }
    if ($t -match '^agenda\b') { return 'agenda' }
    if ($t -match 'besluitenlijst') { return 'besluitenlijst' }
    if ($t -match 'verslag|notulen') { return 'verslag' }
    if ($t -match 'schriftelijke vragen|technische vragen|beantwoording') { return 'vragen' }
    if ($t -match 'voordracht|raadsvoorstel|voorstel|besluit') { return 'voorstel' }
    if ($t -match 'brief|memo|informatie') { return 'brief' }
    if ($t -match 'advies') { return 'advies' }
    if ($t -match 'bijlage') { return 'bijlage' }
    return 'overig'
}

# ------------------------------------------------------------------ index

function Update-ArchiveIndex {
    param([string]$Root, [int]$MaxSeconds = 0, [switch]$BuiltInOnly)
    $Root = Resolve-ArchiveRoot $Root
    if (-not (Test-Path -LiteralPath $Root)) { throw "Archive folder not found: $Root. Archive meetings first (archive_meeting or archive_period)." }
    $Root = (Resolve-Path -LiteralPath $Root).ProviderPath
    $indexDir = Join-Path $Root '_index'
    $textDir = Join-Path $indexDir 'text'
    if (-not (Test-Path -LiteralPath $textDir)) { New-Item -ItemType Directory -Force -Path $textDir | Out-Null }
    $indexPath = Join-Path $indexDir 'index.json'
    $sw = [Diagnostics.Stopwatch]::StartNew()

    $previous = @{}
    $old = Read-JsonFile $indexPath
    if ($old) { foreach ($d in @($old.docs)) { $previous[$d.path] = $d } }

    $manifests = @{}
    $docs = New-Object System.Collections.ArrayList
    $stats = [ordered]@{ files = 0; reused = 0; extracted = 0; no_text = 0; failed = 0; pending = 0 }
    $failures = New-Object System.Collections.ArrayList
    $rootPrefix = $Root.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar

    $files = Get-ChildItem -LiteralPath $Root -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $script:RaExtensions -contains $_.Extension.ToLower() -and $_.Name -notin @('README.md', 'manifest.json') -and $_.FullName -notmatch '[\\/]_index[\\/]' }

    foreach ($f in $files) {
        $stats.files++
        $rel = $f.FullName.Substring($rootPrefix.Length) -replace '\\', '/'
        $dir = $f.DirectoryName
        if (-not $manifests.ContainsKey($dir)) { $manifests[$dir] = Read-JsonFile (Join-Path $dir 'manifest.json') }
        $man = $manifests[$dir]
        $mtime = $f.LastWriteTimeUtc.ToString('o')
        $prev = $previous[$rel]

        if ($prev -and $prev.size -eq $f.Length -and $prev.mtime -eq $mtime -and $prev.extractor -and (Test-Path -LiteralPath (Join-Path $textDir "$($prev.sha256).txt"))) {
            [void]$docs.Add($prev); $stats.reused++; continue
        }

        # Meeting metadata: manifest first, else folder names
        $folder = Split-Path -Leaf $dir
        $parent = Split-Path -Leaf (Split-Path -Parent $dir)
        $date = ''; $body = $folder; $org = $parent; $orgId = $null; $eventId = $null; $page = ''
        if ($folder -match '^(\d{4}-\d{2}-\d{2})\s*(.*)$') { $date = $Matches[1]; if ($Matches[2]) { $body = $Matches[2] } }
        $title = [IO.Path]::GetFileNameWithoutExtension($f.Name)
        $sha = $null
        if ($man) {
            if ($man.date) { $date = [string]$man.date }
            if ($man.body) { $body = [string]$man.body }
            if ($man.organisation) { $org = [string]$man.organisation }
            $orgId = $man.organisation_id; $eventId = $man.event_id; $page = [string]$man.meeting_page
            $mf = @($man.files) | Where-Object { $_.file -eq $f.Name } | Select-Object -First 1
            if ($mf) { if ($mf.title) { $title = [string]$mf.title }; if ($mf.size -eq $f.Length -and $mf.sha256) { $sha = [string]$mf.sha256 } }
        }
        if (-not $sha) { $sha = (Get-FileHash -Algorithm SHA256 -LiteralPath $f.FullName).Hash.ToLower() }

        $entry = [ordered]@{
            path = $rel; sha256 = $sha; size = $f.Length; mtime = $mtime; ext = $f.Extension.ToLower().TrimStart('.')
            date = $date; organisation = $org; organisation_id = $orgId; body = $body; event_id = $eventId; meeting_page = $page
            title = $title; doc_type = (Get-DocType $title); pages = 0; chars = 0; extractor = $null
        }
        $textPath = Join-Path $textDir "$sha.txt"
        if (Test-Path -LiteralPath $textPath) {
            $t = [IO.File]::ReadAllText($textPath, $script:RaUtf8)
            $entry.chars = $t.Length; $entry.pages = ($t.Split("`f")).Count
            $entry.extractor = if ($prev -and $prev.sha256 -eq $sha -and $prev.extractor) { $prev.extractor } else { 'cached' }
            [void]$docs.Add([pscustomobject]$entry); $stats.reused++; continue
        }
        if ($MaxSeconds -gt 0 -and $sw.Elapsed.TotalSeconds -ge $MaxSeconds) {
            $stats.pending++; continue   # not in the index yet; next run picks it up
        }
        try {
            $r = Get-DocumentText -Path $f.FullName -BuiltInOnly:$BuiltInOnly
            if ($null -eq $r) { continue }
            $text = [string]$r.Text
            [IO.File]::WriteAllText($textPath, $text, $script:RaUtf8)
            $entry.pages = $r.Pages; $entry.chars = $text.Length; $entry.extractor = $r.Extractor
            if (-not $text.Trim()) { $stats.no_text++ }
            $stats.extracted++
        } catch {
            $stats.failed++
            $entry.extractor = 'failed: ' + $_.Exception.Message
            [void]$failures.Add($rel)
        }
        [void]$docs.Add([pscustomobject]$entry)
    }

    $index = [ordered]@{ version = 1; built = (Get-Date).ToString('yyyy-MM-dd HH:mm'); docs = @($docs) }
    Write-JsonFile $indexPath $index 4
    $meetings = @($docs | Where-Object { $_.date } | ForEach-Object { "$($_.organisation)|$($_.date)|$($_.body)" } | Sort-Object -Unique).Count
    $dates = @($docs | Where-Object { $_.date } | ForEach-Object { $_.date } | Sort-Object)
    return [ordered]@{
        root = $Root; index = $indexPath; documents = $docs.Count; meetings = $meetings
        period = $(if ($dates.Count) { "$($dates[0]) .. $($dates[$dates.Count - 1])" } else { '' })
        stats = $stats; failed_files = @($failures | Select-Object -First 20)
        pdf_extractor = $(if (-not $BuiltInOnly -and (Get-Command pdftotext -ErrorAction SilentlyContinue)) { 'pdftotext' } else { 'built-in' })
        complete = ($stats.pending -eq 0)
        note = $(if ($stats.pending -gt 0) { "Time budget reached: $($stats.pending) files not indexed yet. Run again to continue." } elseif ($stats.no_text -gt 0) { "$($stats.no_text) files have no text layer (scans); they are found by title only." } else { '' })
    }
}

# ------------------------------------------------------------------ search

function ConvertTo-QueryParts([string]$Query) {
    $must = New-Object System.Collections.ArrayList
    $not = New-Object System.Collections.ArrayList
    foreach ($m in [regex]::Matches($Query, '(-?)"([^"]+)"|(-?)(\S+)')) {
        $neg = ($m.Groups[1].Value -eq '-' -or $m.Groups[3].Value -eq '-')
        $term = if ($m.Groups[2].Success) { $m.Groups[2].Value } else { $m.Groups[4].Value }
        $term = $term.Trim()
        if ($term.Length -lt 2) { continue }
        $rx = New-Object regex (([regex]::Escape($term) -replace '\\ ', '\s+'), ([Text.RegularExpressions.RegexOptions]'IgnoreCase, CultureInvariant'))
        if ($neg) { [void]$not.Add($rx) } else { [void]$must.Add(@{ Term = $term; Rx = $rx }) }
    }
    if ($must.Count -eq 0) { throw [ArgumentException]::new('Give at least one search term of 2 or more characters.') }
    return @{ Must = $must; Not = $not }
}

function Get-Snippet([string]$Text, [int]$Index, [int]$Length) {
    $start = [Math]::Max(0, $Index - 140)
    $end = [Math]::Min($Text.Length, $Index + $Length + 140)
    $s = $Text.Substring($start, $end - $start) -replace '[\f\r\n\t ]+', ' '
    if ($start -gt 0) { $s = '...' + $s }
    if ($end -lt $Text.Length) { $s = $s + '...' }
    return $s.Trim()
}

function Test-DocFilter($d, $Organisation, $Body, $DateFrom, $DateTo, $DocType) {
    if ($Organisation) {
        $o = [string]$Organisation
        if ($o -match '^\d+$') { if ([string]$d.organisation_id -ne $o) { return $false } }
        elseif ([string]$d.organisation -notlike "*$o*") { return $false }
    }
    if ($Body -and [string]$d.body -notlike "*$Body*") { return $false }
    if ($DateFrom -and (-not $d.date -or [string]$d.date -lt $DateFrom)) { return $false }
    if ($DateTo -and (-not $d.date -or [string]$d.date -gt $DateTo)) { return $false }
    if ($DocType -and [string]$d.doc_type -ne $DocType) { return $false }
    return $true
}

function Search-Archive {
    param(
        [string]$Root, [Parameter(Mandatory)][string]$Query,
        [ValidateSet('documents', 'first', 'timeline')][string]$Mode = 'documents',
        [string]$Organisation, [string]$Body, [string]$DateFrom, [string]$DateTo, [string]$DocType,
        [ValidateSet('year', 'month')][string]$GroupBy = 'year',
        [ValidateSet('newest', 'oldest')][string]$Sort = 'newest',
        [int]$Limit = 20
    )
    $Root = Resolve-ArchiveRoot $Root
    $indexPath = Join-Path (Join-Path $Root '_index') 'index.json'
    $index = Read-JsonFile $indexPath
    if (-not $index) { throw "No index in $Root. Run archive_index first." }
    $q = ConvertTo-QueryParts $Query
    $textDir = Join-Path (Join-Path $Root '_index') 'text'

    $hits = New-Object System.Collections.ArrayList
    $searched = 0
    foreach ($d in @($index.docs)) {
        if (-not (Test-DocFilter $d $Organisation $Body $DateFrom $DateTo $DocType)) { continue }
        $searched++
        $tp = Join-Path $textDir "$($d.sha256).txt"
        $text = if (Test-Path -LiteralPath $tp) { [IO.File]::ReadAllText($tp, $script:RaUtf8) } else { '' }
        $hay = [string]$d.title + "`n" + $text
        $ok = $true; $count = 0; $first = $null
        foreach ($t in $q.Must) {
            $ms = $t.Rx.Matches($hay)
            if ($ms.Count -eq 0) { $ok = $false; break }
            $count += $ms.Count
            if ($null -eq $first -or $ms[0].Index -lt $first.Index) { $first = $ms[0] }
        }
        if (-not $ok) { continue }
        foreach ($rx in $q.Not) { if ($rx.IsMatch($hay)) { $ok = $false; break } }
        if (-not $ok) { continue }
        $titleLen = ([string]$d.title).Length + 1
        $page = $null
        if ($first.Index -ge $titleLen) { $page = ($text.Substring(0, $first.Index - $titleLen).Split("`f")).Count }
        [void]$hits.Add([pscustomobject][ordered]@{
            date = $d.date; organisation = $d.organisation; body = $d.body; title = $d.title; doc_type = $d.doc_type
            hits = $count; page = $page; snippet = (Get-Snippet $hay $first.Index $first.Length)
            path = $d.path; meeting_page = $d.meeting_page; event_id = $d.event_id
        })
    }

    $meetingKey = { "$($_.organisation)|$($_.date)|$($_.body)" }
    $result = [ordered]@{
        query = $Query; mode = $Mode; root = $Root; index_built = $index.built
        documents_searched = $searched; documents_matched = $hits.Count
        meetings_matched = @($hits | ForEach-Object $meetingKey | Sort-Object -Unique).Count
    }
    switch ($Mode) {
        'documents' {
            $sorted = if ($Sort -eq 'oldest') { $hits | Sort-Object date, title } else { $hits | Sort-Object @{ Expression = 'date'; Descending = $true }, @{ Expression = 'hits'; Descending = $true } }
            $result.results = @($sorted | Select-Object -First $Limit)
        }
        'first' {
            $dated = @($hits | Where-Object { $_.date } | Sort-Object date, @{ Expression = 'hits'; Descending = $true })
            $result.first_mention = $(if ($dated.Count) { $dated[0] } else { $null })
            $seen = @{}; $firstPerMeeting = New-Object System.Collections.ArrayList
            foreach ($h in $dated) { $k = "$($h.organisation)|$($h.date)|$($h.body)"; if (-not $seen.ContainsKey($k)) { $seen[$k] = $true; [void]$firstPerMeeting.Add($h) } }
            $result.first_meetings = @($firstPerMeeting | Select-Object -First $Limit)
            $result.undated_matches = @($hits | Where-Object { -not $_.date }).Count
        }
        'timeline' {
            $len = if ($GroupBy -eq 'month') { 7 } else { 4 }
            $groups = $hits | Where-Object { $_.date } | Group-Object { ([string]$_.date).Substring(0, $len) } | Sort-Object Name
            $result.timeline = @($groups | ForEach-Object {
                $g = $_.Group
                [pscustomobject][ordered]@{
                    period = $_.Name; documents = $g.Count
                    meetings = @($g | ForEach-Object $meetingKey | Sort-Object -Unique).Count
                    mentions = [int](($g | Measure-Object hits -Sum).Sum)
                    by_type = (($g | Group-Object doc_type | Sort-Object Count -Descending | ForEach-Object { "$($_.Name) $($_.Count)" }) -join ', ')
                }
            })
            # Coverage: how many documents per period are in the index at all, so a zero is not mistaken for absence
            $all = @($index.docs | Where-Object { $_.date -and (Test-DocFilter $_ $Organisation $Body $DateFrom $DateTo $DocType) })
            $result.coverage = @($all | Group-Object { ([string]$_.date).Substring(0, $len) } | Sort-Object Name | ForEach-Object { [pscustomobject]@{ period = $_.Name; documents_in_index = $_.Count } })
        }
    }
    return $result
}

# ------------------------------------------------------------------ motions

function Get-NotubizJson([string]$Url) {
    $wc = New-Object System.Net.WebClient
    $wc.Encoding = [Text.Encoding]::UTF8
    $wc.Headers.Add('User-Agent', $script:RaUserAgent)
    $wc.Headers.Add('Accept', 'application/json')
    try { return ($wc.DownloadString($Url) | ConvertFrom-Json) } finally { $wc.Dispose() }
}

function ConvertFrom-HtmlText([string]$Html) {
    if (-not $Html) { return '' }
    $t = [Net.WebUtility]::HtmlDecode(($Html -replace '<[^>]+>', ' '))
    return ($t -replace '\s+', ' ').Trim()
}

function ConvertFrom-MotionItem($item, [int]$OrgId) {
    $f = @{}
    foreach ($a in @($item.attributes.attribute)) {
        if ($null -eq $a) { continue }
        $v = $null
        if ($null -ne $a.values) { $v = @($a.values.value | ForEach-Object { [string]$_ }) }
        elseif ($a.value -is [psobject] -and $a.value.url) { $v = [pscustomobject]@{ title = [string]$a.value.title; url = [string]$a.value.url } }
        else { $v = $a.value }
        $f[[string]$a.label] = $v
    }
    function first([string[]]$keys) { foreach ($k in $keys) { if ($f.ContainsKey($k) -and $null -ne $f[$k] -and [string]$f[$k] -ne '') { return $f[$k] } }; return $null }
    function list([string[]]$keys) { foreach ($k in $keys) { if ($f.ContainsKey($k) -and $null -ne $f[$k]) { return @($f[$k] | ForEach-Object { [string]$_ }) } }; return @() }
    $doc = first @('Hoofddocument', 'Document')
    $date = [string](first @('Datum indiening', 'Datum vergadering', 'Datum', 'Aanmaakdatum'))
    $known = @('Titel', 'Type', 'Datum indiening', 'Datum vergadering', 'Datum', 'Aanmaakdatum', 'Uitslag', 'Status', 'Toelichting', 'Indiener(s)', 'Indiener', 'Fractie', 'Medeondertekenaars',
        'Ondersteuners fractie', 'Gekoppeld evenement', 'Ingediend in', 'Hoofddocument', 'Document', 'Datum afdoening', 'Stand van zaken', 'Portefeuillehouder', 'RIS-nummer', 'Beleidsveld')
    $extra = [ordered]@{}
    foreach ($k in $f.Keys) { if ($known -notcontains $k -and $null -ne $f[$k] -and -not ($f[$k] -is [psobject] -and $f[$k].url)) { $extra[$k] = [string]($f[$k] -join '; ') } }
    $vergadering = first @('Gekoppeld evenement', 'Ingediend in')
    return [pscustomobject][ordered]@{
        id = [int]$item.'@attributes'.id; organisation_id = $OrgId
        type = [string](first @('Type')); titel = [string](first @('Titel'))
        datum = $(if ($date.Length -ge 10) { $date.Substring(0, 10) } else { $date })
        uitslag = [string](first @('Uitslag')); status = [string](first @('Status'))
        toelichting = (ConvertFrom-HtmlText ([string](first @('Toelichting'))))
        indieners = @(list @('Indiener(s)', 'Indiener')); fracties = @(list @('Fractie'))
        medeondertekenaars = @(list @('Medeondertekenaars')); ondersteuners = @(list @('Ondersteuners fractie'))
        vergadering = [string](@($vergadering) -join '; ')
        document = $(if ($doc) { [string]$doc.url } else { '' }); document_titel = $(if ($doc) { [string]$doc.title } else { '' })
        afdoening = [string](first @('Datum afdoening')); stand_van_zaken = (ConvertFrom-HtmlText ([string](first @('Stand van zaken'))))
        portefeuillehouder = [string](@(first @('Portefeuillehouder')) -join '; '); ris = [string](first @('RIS-nummer'))
        beleidsveld = [string](first @('Beleidsveld')); last_modified = [string]$item.'@attributes'.last_modified
        extra = $extra
    }
}

function Sync-Motions {
    param([int]$OrganisationId = 281, [string]$Root, [switch]$Full, [int]$MaxSeconds = 0, [int]$PageSize = 250, [string]$ItemsJsonPath)
    $Root = Resolve-ArchiveRoot $Root
    $dir = Join-Path (Join-Path $Root '_index') 'moties'
    $cachePath = Join-Path $dir "$OrganisationId.json"
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $cache = Read-JsonFile $cachePath
    $byId = @{}
    $order = New-Object System.Collections.ArrayList
    if ($cache -and -not $Full) { foreach ($m in @($cache.items)) { $byId[[int]$m.id] = $m; [void]$order.Add([int]$m.id) } }
    $base = "https://api.notubiz.nl/organisations/$OrganisationId/modules/6/items?format=json"

    if ($ItemsJsonPath) {   # offline testing: one API page from a file
        $pages = @(Get-Content -Raw -LiteralPath $ItemsJsonPath | ConvertFrom-Json)
        $total = [int]$pages[0].pagination.'@attributes'.total_results
        $start = 0
    } else {
        $probe = Get-NotubizJson "$base&limit=1"
        if ($null -eq $probe.pagination) { throw "Organisation $OrganisationId has no motions module with items in NotuBiz. For Stadsdeel Nieuw-West and Centrum, search the archived meeting documents instead (archive_search with doc_type motie)." }
        $total = [int]$probe.pagination.'@attributes'.total_results
        if ($cache -and -not $Full -and $null -ne $cache.next_start) { $start = [int]$cache.next_start }
        elseif ($cache -and -not $Full) { $start = [Math]::Max(0, $order.Count - 500) }   # re-read the tail: outcomes are often filled in later
        else { $start = 0 }
    }

    $fetched = 0; $added = 0; $updated = 0; $next = $null
    while ($start -lt $total) {
        if ($MaxSeconds -gt 0 -and $sw.Elapsed.TotalSeconds -ge $MaxSeconds) { $next = $start; break }
        if ($ItemsJsonPath) { $page = $pages[0] } else { $page = Get-NotubizJson "$base&limit=$PageSize&start=$start" }
        $items = @($page.item)
        if ($items.Count -eq 0) { break }
        foreach ($it in $items) {
            if ($null -eq $it) { continue }
            $m = ConvertFrom-MotionItem $it $OrganisationId
            if ($byId.ContainsKey($m.id)) { $updated++ } else { $added++; [void]$order.Add($m.id) }
            $byId[$m.id] = $m
            $fetched++
        }
        $start += $items.Count
        if ($ItemsJsonPath) { break }
    }
    $orgName = if ($script:RaOrgNames.ContainsKey($OrganisationId)) { $script:RaOrgNames[$OrganisationId] } else { "Organisation $OrganisationId" }
    $obj = [ordered]@{
        organisation_id = $OrganisationId; organisation = $orgName; source = $base
        synced = (Get-Date).ToString('yyyy-MM-dd HH:mm'); total_in_notubiz = $total; next_start = $next
        items = @($order | ForEach-Object { $byId[$_] })
    }
    Write-JsonFile $cachePath $obj 5
    $dates = @($obj.items | Where-Object { $_.datum } | ForEach-Object { $_.datum } | Sort-Object)
    return [ordered]@{
        organisation = "$orgName ($OrganisationId)"; cache = $cachePath; in_cache = $obj.items.Count; total_in_notubiz = $total
        fetched = $fetched; added = $added; refreshed = $updated
        period = $(if ($dates.Count) { "$($dates[0]) .. $($dates[$dates.Count - 1])" } else { '' })
        complete = ($null -eq $next)
        note = $(if ($null -ne $next) { "Time budget reached at item $next of $total. Run motions_sync again to continue." } else { '' })
    }
}

function Get-OutcomeKey([string]$Uitslag, [string]$Status) {
    $u = ("$Uitslag $Status").ToLower()
    if ($u -match 'aangenomen') { return 'aangenomen' }
    if ($u -match 'verworpen') { return 'verworpen' }
    if ($u -match 'ingetrokken') { return 'ingetrokken' }
    if ($u -match 'aangehouden') { return 'aangehouden' }
    if ($u -match 'vervallen') { return 'vervallen' }
    if ($u -match 'afgedaan') { return 'afgedaan' }
    if ($u.Trim()) { return 'anders' }
    return 'onbekend'
}

function Search-Motions {
    param(
        [int]$OrganisationId = 281, [string]$Root, [string]$Query, [string]$Fractie, [string]$Indiener,
        [string]$Uitslag, [string]$Type, [string]$DateFrom, [string]$DateTo,
        [ValidateSet('none', 'uitslag', 'fractie', 'indiener', 'jaar')][string]$SummaryBy = 'uitslag',
        [ValidateSet('newest', 'oldest')][string]$Sort = 'newest', [int]$Limit = 25
    )
    $Root = Resolve-ArchiveRoot $Root
    $cachePath = Join-Path (Join-Path (Join-Path $Root '_index') 'moties') "$OrganisationId.json"
    $cache = Read-JsonFile $cachePath
    if (-not $cache) { throw "No motion cache for organisation $OrganisationId. Run motions_sync first." }
    $q = if ($Query) { ConvertTo-QueryParts $Query } else { $null }
    $hits = New-Object System.Collections.ArrayList
    foreach ($m in @($cache.items)) {
        if ($DateFrom -and (-not $m.datum -or $m.datum -lt $DateFrom)) { continue }
        if ($DateTo -and (-not $m.datum -or $m.datum -gt $DateTo)) { continue }
        if ($Type -and [string]$m.type -notlike "*$Type*" -and [string]$m.titel -notlike "*$Type*") { continue }
        $outcome = Get-OutcomeKey $m.uitslag $m.status
        if ($Uitslag -and $outcome -ne $Uitslag.ToLower() -and [string]$m.uitslag -notlike "*$Uitslag*") { continue }
        if ($Fractie -and -not (@($m.fracties) | Where-Object { $_ -like "*$Fractie*" })) { continue }
        if ($Indiener -and -not (@($m.indieners) + @($m.medeondertekenaars) | Where-Object { $_ -like "*$Indiener*" }) -and [string]$m.titel -notlike "*$Indiener*") { continue }
        if ($q) {
            $hay = @($m.titel, $m.toelichting, $m.document_titel, $m.vergadering, $m.beleidsveld, $m.stand_van_zaken, (@($m.indieners) -join ' '), (@($m.fracties) -join ' ')) -join "`n"
            $ok = $true
            foreach ($t in $q.Must) { if (-not $t.Rx.IsMatch($hay)) { $ok = $false; break } }
            if ($ok) { foreach ($rx in $q.Not) { if ($rx.IsMatch($hay)) { $ok = $false; break } } }
            if (-not $ok) { continue }
        }
        [void]$hits.Add([pscustomobject][ordered]@{
            datum = $m.datum; type = $m.type; titel = $m.titel; uitslag = $outcome; uitslag_tekst = $m.uitslag
            stemming = $m.toelichting; indieners = (@($m.indieners) -join ', '); fracties = (@($m.fracties) -join ', ')
            vergadering = $m.vergadering; afdoening = $m.afdoening; stand_van_zaken = $m.stand_van_zaken
            document = $m.document; notubiz_id = $m.id
        })
    }
    $summary = $null
    if ($SummaryBy -ne 'none') {
        $rows = @{}
        foreach ($h in $hits) {
            $keys = switch ($SummaryBy) {
                'uitslag' { @($h.uitslag) }
                'jaar' { @($(if ($h.datum) { ([string]$h.datum).Substring(0, 4) } else { 'onbekend' })) }
                'fractie' { $(if ($h.fracties) { @($h.fracties -split ', ') } else { @('onbekend') }) }
                'indiener' { $(if ($h.indieners) { @($h.indieners -split ', ') } else { @('onbekend') }) }
            }
            foreach ($k in $keys) {
                if (-not $rows.ContainsKey($k)) { $rows[$k] = [ordered]@{ key = $k; total = 0; aangenomen = 0; verworpen = 0; ingetrokken = 0; overig = 0 } }
                $r = $rows[$k]; $r.total++
                if ($h.uitslag -in @('aangenomen', 'verworpen', 'ingetrokken')) { $r[$h.uitslag]++ } else { $r.overig++ }
            }
        }
        $sortKey = if ($SummaryBy -eq 'jaar') { @{ Expression = { $_.key } } } else { @{ Expression = { $_.total }; Descending = $true } }
        $summary = @($rows.Values | ForEach-Object { [pscustomobject]$_ } | Sort-Object $sortKey | Select-Object -First 60)
    }
    $sorted = if ($Sort -eq 'oldest') { $hits | Sort-Object datum, notubiz_id } else { $hits | Sort-Object @{ Expression = 'datum'; Descending = $true }, @{ Expression = 'notubiz_id'; Descending = $true } }
    return [ordered]@{
        organisation = $cache.organisation; synced = $cache.synced; in_cache = @($cache.items).Count
        matched = $hits.Count; summary_by = $SummaryBy; summary = $summary
        results = @($sorted | Select-Object -First $Limit)
        note = 'Outcome (uitslag) as registered in NotuBiz. Vote details per party are only in "stemming" when NotuBiz recorded them; otherwise check the besluitenlijst or stemmingsuitslagen of the meeting.'
    }
}
