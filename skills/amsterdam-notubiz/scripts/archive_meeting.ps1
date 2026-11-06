<#
.SYNOPSIS
  Archive the agenda and all documents of one NotuBiz meeting (Amsterdam city council,
  council committees, district committees) into a local folder, verified by SHA-256.

.DESCRIPTION
  Uses only the public NotuBiz API (https://api.notubiz.nl), no scraping and no key.
  - Agenda: written as Markdown from the API data ("Agenda <body> dd-mm-yyyy.md").
  - Documents: downloaded under their NotuBiz title with the right extension.
  - A document or agenda that is already filed with the same SHA-256 is skipped.
    If the same name exists with different content, the new file gets " (v2)", " (v3)", ...
    The original is never overwritten.
  - README.md and manifest.json in the folder record every file, its hash and a change log.
  Works with Windows PowerShell 5.1 and PowerShell 7 (pwsh) on Windows, macOS and Linux.

.EXAMPLE
  # Next meeting of Stadsdeelcommissie Nieuw-West (organisation 2328)
  ./archive_meeting.ps1 -OrganisationId 2328 -Root "$HOME/Documents/Raadsinformatie"

.EXAMPLE
  # A specific meeting by event ID, into an explicit folder
  ./archive_meeting.ps1 -EventId 1439170 -TargetDir "D:\Archief\Nieuw-West\2026-11-10"

.EXAMPLE
  # Only show what would happen
  ./archive_meeting.ps1 -EventId 1439170 -Root ./archief -WhatIfOnly
#>
[CmdletBinding()]
param(
  [int]$EventId,
  [int]$OrganisationId,
  [string]$Category,
  [string]$Root = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Raadsinformatie'),
  [string]$TargetDir,
  [switch]$WhatIfOnly,
  [string]$EventXmlPath   # offline testing: read the event XML from a file instead of the API
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$UserAgent = 'open-overheid/1.9 (+https://github.com/maikell/ai-openoverheid)'
$Utf8 = New-Object System.Text.UTF8Encoding($false)

$OrgNames = @{
  281 = 'Gemeenteraad Amsterdam'; 1768 = 'College van B&W'; 547 = 'Stadsdeel Centrum'
  977 = 'Stadsdeel Noord'; 1413 = 'Stadsdeel West'; 1424 = 'Stadsdeel Zuid'
  1425 = 'Stadsdeel Oost'; 2328 = 'Stadsdeel Nieuw-West'; 2122 = 'Stadsdeel Zuidoost'
}

function Get-Bytes([string]$Url, [string]$Accept = '*/*') {
  $wc = New-Object System.Net.WebClient
  $wc.Headers.Add('User-Agent', $UserAgent)
  $wc.Headers.Add('Accept', $Accept)
  try { return , $wc.DownloadData($Url) } finally { $wc.Dispose() }
}

function Get-Sha256([byte[]]$Bytes) {
  $sha = [Security.Cryptography.SHA256]::Create()
  try { return (($sha.ComputeHash($Bytes) | ForEach-Object { $_.ToString('x2') }) -join '') } finally { $sha.Dispose() }
}

function Get-FileSha256([string]$Path) { (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLower() }

function Get-Text($node) {
  if ($null -eq $node) { return '' }
  return (($node.InnerText -replace '\s+', ' ').Trim())
}

function ConvertTo-SafeName([string]$Name) {
  $n = $Name -replace '[\\/:*?"<>|\x00-\x1f]', ' '
  $n = ($n -replace '\s+', ' ').Trim().TrimEnd('.')
  if ($n.Length -gt 150) { $n = $n.Substring(0, 150).Trim() }
  if (-not $n) { $n = 'document' }
  return $n
}

# ---------- 1. Find the meeting ----------
if (-not $EventId -and -not $EventXmlPath) {
  if (-not $OrganisationId) { throw 'Give -EventId, or -OrganisationId (optionally with -Category) for the next meeting.' }
  $json = $Utf8.GetString((Get-Bytes "https://api.notubiz.nl/organisations/$OrganisationId/events" 'application/json')) | ConvertFrom-Json
  $today = (Get-Date).ToString('yyyy-MM-dd')
  $events = @($json.events.event) | Where-Object { $_.'@attributes'.date -ge $today }
  if ($Category) { $events = $events | Where-Object { $_.category.title -like "*$Category*" -or $_.title -like "*$Category*" } }
  $next = $events | Sort-Object { $_.'@attributes'.date }, { $_.'@attributes'.time } | Select-Object -First 1
  if (-not $next) { throw "No upcoming meeting found for organisation $OrganisationId$(if ($Category) { " and category '$Category'" })." }
  $EventId = [int]$next.'@attributes'.id
}

if ($EventXmlPath) { $xmlText = [IO.File]::ReadAllText((Resolve-Path $EventXmlPath), $Utf8) }
else { $xmlText = $Utf8.GetString((Get-Bytes "https://api.notubiz.nl/events/$EventId" 'application/xml')) }
[xml]$doc = $xmlText
$ev = $doc.SelectSingleNode('//event')
if (-not $ev) { throw "No event in the API response for event $EventId." }

$EventId  = [int]$ev.GetAttribute('id')
$date     = $ev.GetAttribute('date')            # yyyy-MM-dd
$time     = $ev.GetAttribute('time')
$orgId    = [int](Get-Text $ev.SelectSingleNode('organisation'))
$catTitle = Get-Text $ev.SelectSingleNode('category/title')
$title    = Get-Text $ev.SelectSingleNode('title')
$pageUrl  = Get-Text $ev.SelectSingleNode('url')
$body     = if ($catTitle) { $catTitle } else { $title }
$orgName  = if ($OrgNames.ContainsKey($orgId)) { $OrgNames[$orgId] } else { "Organisation $orgId" }
$dmy      = ([datetime]::ParseExact($date, 'yyyy-MM-dd', $null)).ToString('dd-MM-yyyy')

if (-not $TargetDir) { $TargetDir = Join-Path (Join-Path $Root (ConvertTo-SafeName $orgName)) ("$date " + (ConvertTo-SafeName $body)) }

# ---------- 2. Agenda and document list ----------
$items = @()
$docs  = @()
$order = 0
foreach ($ai in $ev.SelectNodes('agenda//agendaitem')) {
  $order++
  $num = Get-Text $ai.SelectSingleNode('numbering')
  $aiTitle = Get-Text $ai.SelectSingleNode('title')
  $itemDocs = @()
  foreach ($d in $ai.SelectNodes('documents/document')) {
    $ext = (Get-Text $d.SelectSingleNode('filetype')).ToLower()
    if (-not $ext) { $ext = 'pdf' }
    $o = [pscustomobject]@{
      Id = $d.GetAttribute('id'); Version = $d.GetAttribute('version')
      Title = Get-Text $d.SelectSingleNode('title'); Ext = $ext
      Url = Get-Text $d.SelectSingleNode('url'); Item = $num
      Name = $null; Bytes = $null; Size = 0; Sha = $null; Status = $null; FinalName = $null
    }
    $docs += $o; $itemDocs += $o
  }
  $items += [pscustomobject]@{ Order = $order; Number = $num; Title = $aiTitle; Docs = $itemDocs }
}

# Unique file names (same title twice -> add [id] to the later one)
$used = @{}
foreach ($o in $docs) {
  $base = ConvertTo-SafeName ($o.Title -replace "\.$([regex]::Escape($o.Ext))$", '')
  $name = "$base.$($o.Ext)"
  if ($used.ContainsKey($name.ToLower())) { $name = "$base [$($o.Id)].$($o.Ext)" }
  $used[$name.ToLower()] = $true
  $o.Name = $name
}

$agendaName = ConvertTo-SafeName "Agenda $body $dmy"
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("# Agenda $body $dmy")
[void]$sb.AppendLine('')
[void]$sb.AppendLine("- Organisation: $orgName ($orgId)")
[void]$sb.AppendLine("- Date and time: $dmy $time")
[void]$sb.AppendLine("- Meeting page: $pageUrl")
[void]$sb.AppendLine('')
foreach ($it in $items) {
  $label = if ($it.Number) { "$($it.Number). " } else { '' }
  [void]$sb.AppendLine("- $label$($it.Title)")
  foreach ($o in $it.Docs) { [void]$sb.AppendLine("  - $($o.Title) (document $($o.Id), version $($o.Version))") }
}
$agendaBytes = $Utf8.GetBytes(($sb.ToString() -replace "`r`n", "`n"))
$agenda = [pscustomobject]@{ Id = 'agenda'; Title = "Agenda $body $dmy"; Name = "$agendaName.md"; Bytes = $agendaBytes
  Size = $agendaBytes.Length; Sha = (Get-Sha256 $agendaBytes); Status = $null; FinalName = $null; Url = $pageUrl; Version = '' }

# ---------- 3. Download documents and hash ----------
$failed = @()
foreach ($o in $docs) {
  try {
    $b = Get-Bytes $o.Url
    $o.Bytes = $b; $o.Size = $b.Length; $o.Sha = Get-Sha256 $b
  } catch { $o.Status = 'failed'; $failed += $o; Write-Warning "Download failed: $($o.Title) ($($o.Url)): $($_.Exception.Message)" }
}

# ---------- 4. Compare with what is filed and decide names ----------
$existing = @{}
if (Test-Path -LiteralPath $TargetDir) {
  Get-ChildItem -LiteralPath $TargetDir -File | Where-Object { $_.Name -notin @('README.md', 'manifest.json') } |
    ForEach-Object { $existing[$_.Name.ToLower()] = $_.FullName }
}

function Resolve-Target($o) {
  $stem = [IO.Path]::GetFileNameWithoutExtension($o.Name); $ext = [IO.Path]::GetExtension($o.Name)
  $pattern = '^' + [regex]::Escape($stem.ToLower()) + '( \(v(\d+)\))?' + [regex]::Escape($ext.ToLower()) + '$'
  $versions = @($existing.Keys | Where-Object { $_ -match $pattern })
  if ($versions.Count -eq 0) { $o.Status = 'new'; $o.FinalName = $o.Name; return }
  foreach ($k in $versions) { if ((Get-FileSha256 $existing[$k]) -eq $o.Sha) { $o.Status = 'unchanged'; $o.FinalName = [IO.Path]::GetFileName($existing[$k]); return } }
  $max = 1
  foreach ($k in $versions) { if ($k -match $pattern -and $Matches[2]) { $max = [Math]::Max($max, [int]$Matches[2]) } }
  $o.Status = 'new version'; $o.FinalName = "$stem (v$($max + 1))$ext"
}

$all = @($agenda) + @($docs | Where-Object { $_.Status -ne 'failed' })
foreach ($o in $all) { Resolve-Target $o }

# ---------- 5. Write ----------
$now = (Get-Date).ToString('yyyy-MM-dd HH:mm')
$toWrite = @($all | Where-Object { $_.Status -in @('new', 'new version') })

if ($WhatIfOnly) {
  Write-Output "Meeting : $orgName - $body $dmy $time (event $EventId)"
  Write-Output "Target  : $TargetDir"
  $all + $failed | ForEach-Object { Write-Output ("{0,-12} {1}" -f $_.Status, $(if ($_.FinalName) { $_.FinalName } else { $_.Name })) }
  return
}

New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null
foreach ($o in $toWrite) {
  $path = Join-Path $TargetDir $o.FinalName
  if (Test-Path -LiteralPath $path) { throw "Refusing to overwrite $path" }
  [IO.File]::WriteAllBytes($path, $o.Bytes)
  if ((Get-FileSha256 $path) -ne $o.Sha) { Remove-Item -LiteralPath $path; throw "Hash mismatch after writing $($o.FinalName)" }
}

# ---------- 6. manifest.json and README.md ----------
$manifestPath = Join-Path $TargetDir 'manifest.json'
$manifest = if (Test-Path -LiteralPath $manifestPath) { [IO.File]::ReadAllText($manifestPath, $Utf8) | ConvertFrom-Json } else { $null }
$files = @{}
if ($manifest) { foreach ($f in @($manifest.files)) { $files[$f.file] = $f } }
foreach ($o in $toWrite) {
  $files[$o.FinalName] = [pscustomobject]@{ file = $o.FinalName; title = $o.Title; notubiz_id = $o.Id; notubiz_version = $o.Version
    url = $o.Url; size = $o.Size; sha256 = $o.Sha; filed = $now }
}
$changes = @()
foreach ($o in $toWrite) { $changes += "$($o.Status): $($o.FinalName)" }
foreach ($o in $failed) { $changes += "download failed: $($o.Name)" }
if ($changes.Count -eq 0) { $changes = @('no changes found') }
$log = @(); if ($manifest) { $log = @($manifest.log) }
$log += [pscustomobject]@{ checked = $now; changes = $changes }

$newManifest = [ordered]@{
  organisation = $orgName; organisation_id = $orgId; body = $body; event_id = $EventId
  date = $date; time = $time; meeting_page = $pageUrl; last_checked = $now
  files = @($files.Values | Sort-Object file); log = $log
}
[IO.File]::WriteAllText($manifestPath, ($newManifest | ConvertTo-Json -Depth 6), $Utf8)

$r = New-Object System.Text.StringBuilder
[void]$r.AppendLine("# $body $dmy")
[void]$r.AppendLine('')
[void]$r.AppendLine("- Organisation: $orgName")
[void]$r.AppendLine("- Date and time: $dmy $time")
[void]$r.AppendLine("- Meeting page: $pageUrl")
[void]$r.AppendLine("- Last checked: $now")
[void]$r.AppendLine('- Source: NotuBiz API (https://api.notubiz.nl). Files are compared by SHA-256; a changed file gets a version suffix (v2, v3, ...).')
[void]$r.AppendLine('')
[void]$r.AppendLine('## Files')
[void]$r.AppendLine('')
[void]$r.AppendLine('| File | Size (bytes) | SHA-256 | Filed |')
[void]$r.AppendLine('|---|---:|---|---|')
foreach ($f in ($files.Values | Sort-Object file)) { [void]$r.AppendLine("| $($f.file) | $($f.size) | ``$($f.sha256)`` | $($f.filed) |") }
[void]$r.AppendLine('')
[void]$r.AppendLine('## Log')
[void]$r.AppendLine('')
foreach ($l in $log) { [void]$r.AppendLine("- $($l.checked): $((@($l.changes)) -join '; ')") }
[IO.File]::WriteAllText((Join-Path $TargetDir 'README.md'), ($r.ToString() -replace "`r`n", "`n"), $Utf8)

# ---------- 7. Summary ----------
Write-Output "Meeting : $orgName - $body $dmy $time (event $EventId)"
Write-Output "Folder  : $TargetDir"
foreach ($s in @('new', 'new version', 'unchanged')) {
  $n = @($all | Where-Object { $_.Status -eq $s })
  Write-Output ("{0,-12}: {1}" -f $s, $n.Count)
  if ($s -ne 'unchanged') { $n | ForEach-Object { Write-Output "  - $($_.FinalName)" } }
}
if ($failed) { Write-Output "failed      : $($failed.Count)"; $failed | ForEach-Object { Write-Output "  - $($_.Name) ($($_.Url))" } }
