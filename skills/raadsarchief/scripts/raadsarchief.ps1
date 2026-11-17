<#
.SYNOPSIS
  Command line for the raadsarchief: index and search archived council documents, sync and search motions.

.EXAMPLE
  ./raadsarchief.ps1 index -Root "$HOME/Documents/Raadsinformatie"
.EXAMPLE
  ./raadsarchief.ps1 search -Query "Meervaart" -Mode first -Organisation "Nieuw-West"
.EXAMPLE
  ./raadsarchief.ps1 search -Query "afval" -Mode timeline -DateFrom 2022 -GroupBy year
.EXAMPLE
  ./raadsarchief.ps1 motions-sync -OrganisationId 281
.EXAMPLE
  ./raadsarchief.ps1 motions-search -Query "afval" -DateFrom 2024-01-01 -SummaryBy fractie
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory, Position = 0)][ValidateSet('index', 'search', 'motions-sync', 'motions-search')][string]$Action,
  [string]$Root,
  [string]$Query,
  [ValidateSet('documents', 'first', 'timeline')][string]$Mode = 'documents',
  [string]$Organisation,
  [string]$Body,
  [string]$DateFrom,
  [string]$DateTo,
  [string]$DocType,
  [ValidateSet('year', 'month')][string]$GroupBy = 'year',
  [ValidateSet('newest', 'oldest')][string]$Sort = 'newest',
  [int]$Limit = 20,
  [int]$OrganisationId = 281,
  [string]$Fractie,
  [string]$Indiener,
  [string]$Uitslag,
  [string]$Type,
  [ValidateSet('none', 'uitslag', 'fractie', 'indiener', 'jaar', 'tegenstemmers', 'voorstemmers')][string]$SummaryBy = 'uitslag',
  [string]$StemdeTegen,
  [string]$StemdeVoor,
  [switch]$AlleTypen,
  [int]$MaxSeconds = 0,
  [switch]$Full,
  [switch]$BuiltInOnly
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
. (Join-Path $PSScriptRoot 'raadsarchief_lib.ps1')

function Expand-DateTo([string]$d) {
  if ($d -match '^\d{4}$') { return "$d-12-31" }
  if ($d -match '^\d{4}-\d{2}$') { return "$d-31" }
  return $d
}

switch ($Action) {
  'index' { $r = Update-ArchiveIndex -Root $Root -MaxSeconds $MaxSeconds -BuiltInOnly:$BuiltInOnly }
  'search' {
    if (-not $Query) { throw 'Give -Query.' }
    $p = @{ Root = $Root; Query = $Query; Mode = $Mode; GroupBy = $GroupBy; Sort = $Sort; Limit = $Limit }
    if ($Organisation) { $p.Organisation = $Organisation }
    if ($Body) { $p.Body = $Body }
    if ($DateFrom) { $p.DateFrom = $DateFrom }
    if ($DateTo) { $p.DateTo = (Expand-DateTo $DateTo) }
    if ($DocType) { $p.DocType = $DocType }
    $r = Search-Archive @p
  }
  'motions-sync' { $r = Sync-Motions -OrganisationId $OrganisationId -Root $Root -Full:$Full -MaxSeconds $MaxSeconds }
  'motions-search' {
    $p = @{ Root = $Root; OrganisationId = $OrganisationId; SummaryBy = $SummaryBy; Sort = $Sort; Limit = $Limit }
    foreach ($k in @('Query', 'Fractie', 'Indiener', 'Uitslag', 'Type', 'DateFrom', 'StemdeTegen', 'StemdeVoor')) { $v = Get-Variable -Name $k -ValueOnly; if ($v) { $p[$k] = $v } }
    if ($DateTo) { $p.DateTo = (Expand-DateTo $DateTo) }
    if ($AlleTypen) { $p.AlleTypen = $true }
    $r = Search-Motions @p
  }
}
$r | ConvertTo-Json -Depth 6
