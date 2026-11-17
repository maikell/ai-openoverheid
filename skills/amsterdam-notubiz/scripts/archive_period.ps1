<#
.SYNOPSIS
  Archive all past meetings of one NotuBiz organisation over a period (months), meeting by meeting,
  with archive_meeting.ps1. Builds the archive that the raadsarchief search index works on.

.DESCRIPTION
  Lists meetings per month through the public NotuBiz API
  (GET /organisations/{id}/events?year=YYYY&month=M) and archives each meeting that has taken place.
  Meetings already in the archive (a manifest.json with the same event_id under -Root) are skipped,
  unless -Recheck is given. -MaxMeetings limits one run; run again to continue.
  Works with Windows PowerShell 5.1 and PowerShell 7.

.EXAMPLE
  # All Stadsdeelcommissie meetings of Nieuw-West from January 2023 up to now
  ./archive_period.ps1 -OrganisationId 2328 -From 2023-01 -Category Stadsdeelcommissie -Root "$HOME/Documents/Raadsinformatie"

.EXAMPLE
  # Only list what would be archived
  ./archive_period.ps1 -OrganisationId 2328 -From 2025-01 -To 2025-06 -WhatIfOnly
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][int]$OrganisationId,
  [Parameter(Mandatory)][ValidatePattern('^\d{4}-\d{2}$')][string]$From,
  [ValidatePattern('^\d{4}-\d{2}$')][string]$To,
  [string]$Category,
  [string]$Root = $(if ($env:OPEN_OVERHEID_ARCHIVE_ROOT) { $env:OPEN_OVERHEID_ARCHIVE_ROOT } else { Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Raadsinformatie' }),
  [int]$MaxMeetings = 0,
  [switch]$Recheck,
  [switch]$WhatIfOnly,
  [string]$EventsJsonDir   # offline testing: read <dir>/<yyyy-mm>.json instead of the API
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$UserAgent = 'open-overheid/1.10 (+https://github.com/maikell/ai-openoverheid)'

$start = [datetime]::ParseExact("$From-01", 'yyyy-MM-dd', $null)
$end = if ($To) { [datetime]::ParseExact("$To-01", 'yyyy-MM-dd', $null) } else { Get-Date -Day 1 }
if ($end -lt $start) { throw '-To is before -From.' }
if ((($end.Year - $start.Year) * 12 + $end.Month - $start.Month) -gt 240) { throw 'Period too long: at most 20 years per run.' }
$today = (Get-Date).ToString('yyyy-MM-dd')

# Meetings already archived
$done = @{}
if (-not $Recheck -and (Test-Path -LiteralPath $Root)) {
  Get-ChildItem -LiteralPath $Root -Recurse -Filter manifest.json -File -ErrorAction SilentlyContinue | ForEach-Object {
    try { $m = [IO.File]::ReadAllText($_.FullName) | ConvertFrom-Json; if ($m.event_id) { $done[[string]$m.event_id] = $_.DirectoryName } } catch { }
  }
}

function Get-MonthEvents([int]$Year, [int]$Month) {
  if ($EventsJsonDir) {
    $p = Join-Path $EventsJsonDir ('{0:D4}-{1:D2}.json' -f $Year, $Month)
    if (-not (Test-Path -LiteralPath $p)) { return @() }
    $json = Get-Content -Raw -LiteralPath $p | ConvertFrom-Json
  } else {
    $wc = New-Object System.Net.WebClient
    $wc.Encoding = [Text.Encoding]::UTF8
    $wc.Headers.Add('User-Agent', $UserAgent); $wc.Headers.Add('Accept', 'application/json')
    try { $json = $wc.DownloadString("https://api.notubiz.nl/organisations/$OrganisationId/events?format=json&year=$Year&month=$Month") | ConvertFrom-Json }
    finally { $wc.Dispose() }
  }
  return @($json.events.event | Where-Object { $null -ne $_ })
}

$list = New-Object System.Collections.ArrayList
for ($d = $start; $d -le $end; $d = $d.AddMonths(1)) {
  foreach ($e in (Get-MonthEvents $d.Year $d.Month)) {
    $date = [string]$e.'@attributes'.date
    if (-not $date -or $date -gt $today) { continue }
    $cat = [string]$e.category.title
    if ($Category -and $cat -notlike "*$Category*" -and [string]$e.title -notlike "*$Category*") { continue }
    $id = [string]$e.'@attributes'.id
    if (@($list | Where-Object { $_.Id -eq $id }).Count) { continue }
    [void]$list.Add([pscustomobject]@{ Id = $id; Date = $date; Body = $(if ($cat) { $cat } else { [string]$e.title }) })
  }
}
$list = @($list | Sort-Object Date)
$todo = @($list | Where-Object { -not $done.ContainsKey($_.Id) })
$skipped = $list.Count - $todo.Count
$batch = if ($MaxMeetings -gt 0) { @($todo | Select-Object -First $MaxMeetings) } else { $todo }

Write-Output ("Organisation {0}, {1} .. {2}{3}: {4} meetings found, {5} already archived, {6} to archive in this run." -f `
  $OrganisationId, $start.ToString('yyyy-MM'), $end.ToString('yyyy-MM'), $(if ($Category) { " ($Category)" } else { '' }), $list.Count, $skipped, $batch.Count)

if ($WhatIfOnly) {
  foreach ($m in $batch) { Write-Output "would archive: $($m.Date) $($m.Body) (event $($m.Id))" }
  return
}

$script = Join-Path $PSScriptRoot 'archive_meeting.ps1'
$ok = 0; $fail = 0
foreach ($m in $batch) {
  try {
    $out = & $script -EventId ([int]$m.Id) -Root $Root *>&1 | ForEach-Object { "$_" }
    $summary = @($out | Where-Object { $_ -match '^(new|new version|unchanged|failed)\s*:' }) -join ', '
    Write-Output "archived: $($m.Date) $($m.Body) (event $($m.Id)) - $summary"
    $ok++
  } catch {
    Write-Output "FAILED: $($m.Date) $($m.Body) (event $($m.Id)): $($_.Exception.Message)"
    $fail++
  }
}
$left = $todo.Count - $batch.Count
Write-Output "Done: $ok archived, $fail failed, $left still to do$(if ($left -gt 0) { ' (run again to continue)' } else { '' })."
Write-Output 'Next step: run the raadsarchief index (archive_index) so the new documents become searchable.'
