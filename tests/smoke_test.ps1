<#
.SYNOPSIS
  Smoke test for all MCP servers of the open-overheid toolkit.

.DESCRIPTION
  Reads the server list from .mcp.json, starts every server the same way a client does
  (stdio, JSON-RPC 2.0) and checks per server:
    1. initialize answers with serverInfo
    2. tools/list returns the expected tools, each with a name, description and inputSchema
    3. an unknown tool gives error -32601 and invalid input gives error -32602
    4. (unless -Offline) one or two real calls against the live source return data
  The raadsarchief server is tested against a small temporary archive, so it needs no network.

  Prints a table and exits with code 0 when everything passed, 1 otherwise.
  Works with Windows PowerShell 5.1 and PowerShell 7 (pwsh) on Windows, macOS and Linux.

.EXAMPLE
  # From the plugin folder, all servers, including live calls
  powershell -NoProfile -ExecutionPolicy Bypass -File tests\smoke_test.ps1

.EXAMPLE
  # Without network calls, one server, with pwsh
  pwsh tests/smoke_test.ps1 -Offline -Server bag

.EXAMPLE
  # Start servers with pwsh instead of powershell.exe, longer timeout, JSON report
  ./tests/smoke_test.ps1 -Shell pwsh -TimeoutSeconds 120 -JsonReport ./smoke.json
#>
[CmdletBinding()]
param(
  [string[]]$Server,
  [switch]$Offline,
  [ValidateSet('auto', 'powershell', 'pwsh')][string]$Shell = 'auto',
  [int]$TimeoutSeconds = 60,
  [string]$JsonReport
)

$ErrorActionPreference = 'Stop'
$pluginRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).ProviderPath
$config = Get-Content -Raw -LiteralPath (Join-Path $pluginRoot '.mcp.json') | ConvertFrom-Json

# Which shell starts the servers: the one in .mcp.json (powershell.exe) when present, else pwsh
function Resolve-Shell {
  if ($Shell -eq 'pwsh') { return (Get-Command pwsh -ErrorAction Stop).Source }
  if ($Shell -eq 'powershell') { return (Get-Command powershell.exe -ErrorAction Stop).Source }
  $ps = Get-Command powershell.exe -ErrorAction SilentlyContinue
  if ($ps) { return $ps.Source }
  return (Get-Command pwsh -ErrorAction Stop).Source
}
$exe = Resolve-Shell

# ---- expected tools and test calls per server
$archiveRoot = Join-Path ([IO.Path]::GetTempPath()) ("oo-smoke-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$meeting = Join-Path (Join-Path $archiveRoot 'Stadsdeel Nieuw-West') '2026-11-10 Stadsdeelcommissie'
$plan = @{
  'amsterdam-woo' = @{
    Tools = @('search_woo_decisions', 'get_woo_document')
    Invalid = $null
    Live = @(@{ Name = 'search_woo_decisions'; Args = @{ query = 'Amstel'; rows = 1 }; Expect = '.' })
  }
  'amsterdam-subsidies' = @{
    Tools = @('search_subsidies', 'get_subsidies_summary')
    Invalid = $null
    Live = @(@{ Name = 'search_subsidies'; Args = @{ cluster = 'Stadsdeel Nieuw-West'; limit = 1 }; Expect = '.' })
  }
  'amsterdam-raadsinformatie' = @{
    Tools = @('get_meetings', 'get_meeting_agenda', 'archive_meeting', 'archive_period')
    Invalid = @{ Name = 'get_meeting_agenda'; Args = @{ event_id = 'abc' } }
    Live = @(
      @{ Name = 'get_meetings'; Args = @{ organisation_id = 2328 }; Expect = 'event' },
      @{ Name = 'archive_period'; Args = @{ organisation_id = 2328; from = '2023-03'; to = '2023-03'; dry_run = $true; root = $archiveRoot }; Expect = 'meetings found' }
    )
  }
  'cbs' = @{
    Tools = @('cbs_search_tables', 'cbs_get_table_info', 'cbs_find_codes', 'cbs_get_observations')
    Invalid = @{ Name = 'cbs_get_table_info'; Args = @{ table_id = '../x' } }
    Live = @(@{ Name = 'cbs_search_tables'; Args = @{ query = 'wijken en buurten'; top = 1 }; Expect = 'NED' })
  }
  'lokale-regelgeving' = @{
    Tools = @('lr_zoek_regelingen', 'lr_inhoudsopgave', 'lr_artikel')
    Invalid = @{ Name = 'lr_inhoudsopgave'; Args = @{ regeling_id = 'x;y' } }
    Live = @(@{ Name = 'lr_zoek_regelingen'; Args = @{ titel = 'Algemene Plaatselijke Verordening'; max = 1 }; Expect = 'CVDR' })
  }
  'bag' = @{
    Tools = @('bag_zoek_adres', 'bag_adresinfo', 'bag_plannen_op_adres', 'bag_pand')
    Invalid = @{ Name = 'bag_zoek_adres'; Args = @{ postcode = '12'; huisnummer = 1 } }
    Live = @(
      @{ Name = 'bag_adresinfo'; Args = @{ postcode = '1011PN'; huisnummer = 1 }; Expect = 'Amstel' },
      @{ Name = 'bag_plannen_op_adres'; Args = @{ postcode = '1011PN'; huisnummer = 1 }; Expect = 'plannen' }
    )
  }
  'raadsarchief' = @{
    Tools = @('archive_index', 'archive_search', 'motions_sync', 'motions_search')
    Invalid = @{ Name = 'archive_search'; Args = @{ query = 'x'; mode = 'bad' } }
    Local = @(
      @{ Name = 'archive_index'; Args = @{ root = $archiveRoot }; Expect = '"complete":\s*true' },
      @{ Name = 'archive_search'; Args = @{ root = $archiveRoot; query = 'Meervaart'; mode = 'first' }; Expect = '2026-11-10' },
      @{ Name = 'archive_search'; Args = @{ root = $archiveRoot; query = 'afval'; mode = 'timeline' }; Expect = '"period":\s*"2026"' }
    )
    Live = @()
  }
}

# Small archive for the raadsarchief test (one meeting, one Markdown agenda)
New-Item -ItemType Directory -Force -Path $meeting | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText((Join-Path $meeting 'Agenda Stadsdeelcommissie 10-11-2026.md'), "# Agenda Stadsdeelcommissie 10-11-2026`n`n- 4. Nieuwe Meervaart`n- 5. Afvalinzameling Osdorp`n", $utf8)
[IO.File]::WriteAllText((Join-Path $meeting 'manifest.json'), '{"organisation":"Stadsdeel Nieuw-West","organisation_id":2328,"body":"Stadsdeelcommissie","event_id":1,"date":"2026-11-10","files":[]}', $utf8)

# ---- JSON-RPC client
function Start-McpServer([string]$Script) {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $exe
  $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$Script`""
  $psi.UseShellExecute = $false
  $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
  $psi.StandardOutputEncoding = [Text.Encoding]::UTF8
  $psi.CreateNoWindow = $true
  $p = [Diagnostics.Process]::Start($psi)
  $p.StandardInput.AutoFlush = $true
  $p | Add-Member -NotePropertyName ErrTask -NotePropertyValue $p.StandardError.ReadToEndAsync()
  return $p
}

$script:nextId = 0
function Invoke-Rpc($proc, [string]$Method, $Params) {
  $script:nextId++
  $req = [ordered]@{ jsonrpc = '2.0'; id = $script:nextId; method = $Method }
  if ($null -ne $Params) { $req.params = $Params }
  $proc.StandardInput.WriteLine(($req | ConvertTo-Json -Depth 10 -Compress))
  $sw = [Diagnostics.Stopwatch]::StartNew()
  while ($true) {
    $task = $proc.StandardOutput.ReadLineAsync()
    $remaining = [Math]::Max(1, $TimeoutSeconds * 1000 - $sw.ElapsedMilliseconds)
    if (-not $task.Wait([int]$remaining)) { throw "timeout after $TimeoutSeconds s" }
    $line = $task.Result
    if ($null -eq $line) { throw 'server stopped (stdout closed)' }
    if (-not $line.Trim()) { continue }
    try { $resp = $line | ConvertFrom-Json } catch { throw "not JSON on stdout: $($line.Substring(0, [Math]::Min(120, $line.Length)))" }
    if ($resp.id -eq $script:nextId) { return [pscustomobject]@{ Response = $resp; Ms = $sw.ElapsedMilliseconds } }
  }
}

$results = New-Object System.Collections.ArrayList
function Add-Result($srv, $check, [bool]$ok, $detail, $ms) {
  [void]$results.Add([pscustomobject]@{ Server = $srv; Check = $check; Result = $(if ($ok) { 'PASS' } else { 'FAIL' }); Ms = $ms; Detail = $detail })
}

function Test-Call($proc, $srv, $label, $name, $toolArgs, $expect) {
  try {
    $r = Invoke-Rpc $proc 'tools/call' @{ name = $name; arguments = $toolArgs }
    if ($r.Response.error) { Add-Result $srv $label $false ("error $($r.Response.error.code): $($r.Response.error.message)") $r.Ms; return }
    $text = [string]$r.Response.result.content[0].text
    $ok = $text.Length -gt 0 -and ($null -eq $expect -or $text -match $expect)
    $detail = ($text -replace '\s+', ' ')
    if ($detail.Length -gt 90) { $detail = $detail.Substring(0, 90) + '...' }
    Add-Result $srv $label $ok $detail $r.Ms
  } catch { Add-Result $srv $label $false $_.Exception.Message $null }
}

$names = @($config.mcpServers.PSObject.Properties.Name)
if ($Server) {
  $Server = @($Server -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })   # -File passes 'a,b' as one string
  $unknown = @($Server | Where-Object { $names -notcontains $_ })
  if ($unknown) { throw "Unknown server(s): $($unknown -join ', '). Known: $($names -join ', ')" }
  $names = @($names | Where-Object { $Server -contains $_ })
}
Write-Host "open-overheid MCP smoke test - $($names.Count) servers - shell: $exe - $(if ($Offline) { 'offline' } else { 'with live calls' })"

foreach ($srv in $names) {
  $def = $config.mcpServers.$srv
  $scriptArg = @($def.args)[-1] -replace '\$\{CLAUDE_PLUGIN_ROOT\}', $pluginRoot
  $p = $plan[$srv]
  if (-not (Test-Path -LiteralPath $scriptArg)) { Add-Result $srv 'script exists' $false $scriptArg $null; continue }
  $proc = $null
  try {
    $proc = Start-McpServer $scriptArg
    # 1. initialize
    try {
      $r = Invoke-Rpc $proc 'initialize' @{ protocolVersion = '2024-11-05'; capabilities = @{}; clientInfo = @{ name = 'smoke-test'; version = '1' } }
      Add-Result $srv 'initialize' ([bool]$r.Response.result.serverInfo.name) ("serverInfo.name = $($r.Response.result.serverInfo.name)") $r.Ms
    } catch { Add-Result $srv 'initialize' $false $_.Exception.Message $null; continue }
    $proc.StandardInput.WriteLine('{"jsonrpc":"2.0","method":"notifications/initialized"}')

    # 2. tools/list
    $r = Invoke-Rpc $proc 'tools/list' $null
    $tools = @($r.Response.result.tools)
    $bad = @($tools | Where-Object { -not $_.name -or -not $_.description -or -not $_.inputSchema })
    $listed = @($tools | ForEach-Object { $_.name })
    $missing = @(); if ($p) { $missing = @($p.Tools | Where-Object { $listed -notcontains $_ }) }
    $ok = $tools.Count -gt 0 -and $bad.Count -eq 0 -and $missing.Count -eq 0
    $detail = "$($tools.Count) tools: $($listed -join ', ')"
    if ($missing) { $detail += " | missing: $($missing -join ', ')" }
    if ($bad) { $detail += " | incomplete definitions: $($bad.Count)" }
    Add-Result $srv 'tools/list' $ok $detail $r.Ms

    # 3. error handling
    $r = Invoke-Rpc $proc 'tools/call' @{ name = 'no_such_tool'; arguments = @{} }
    Add-Result $srv 'unknown tool -> -32601' ($r.Response.error.code -eq -32601) ("code $($r.Response.error.code)") $r.Ms
    if ($p -and $p.Invalid) {
      $r = Invoke-Rpc $proc 'tools/call' @{ name = $p.Invalid.Name; arguments = $p.Invalid.Args }
      Add-Result $srv 'invalid input -> -32602' ($r.Response.error.code -eq -32602) ("code $($r.Response.error.code): $($r.Response.error.message)") $r.Ms
    }

    # 4. local and live calls
    if ($p -and $p.Local) { foreach ($c in $p.Local) { Test-Call $proc $srv "local: $($c.Name)" $c.Name $c.Args $c.Expect } }
    if (-not $Offline -and $p -and $p.Live) { foreach ($c in $p.Live) { Test-Call $proc $srv "live: $($c.Name)" $c.Name $c.Args $c.Expect } }
    if (-not $p) { Add-Result $srv 'known to smoke test' $false 'no test plan for this server: add it to $plan in tests/smoke_test.ps1' $null }
  } catch {
    Add-Result $srv 'run' $false $_.Exception.Message $null
  } finally {
    if ($proc) {
      try { $proc.StandardInput.Close() } catch { }
      if (-not $proc.WaitForExit(5000)) { try { $proc.Kill() } catch { } }
      $err = ''
      try { if ($proc.ErrTask.Wait(2000)) { $err = $proc.ErrTask.Result } } catch { }
      if ($err -and $err.Trim()) { Add-Result $srv 'stderr empty' $false (($err -replace '\s+', ' ').Substring(0, [Math]::Min(150, ($err -replace '\s+', ' ').Length))) $null }
    }
  }
}

Remove-Item -LiteralPath $archiveRoot -Recurse -Force -ErrorAction SilentlyContinue

$results | Format-Table Server, Check, Result, Ms, Detail -AutoSize -Wrap | Out-String -Width 220 | Write-Host
$failed = @($results | Where-Object { $_.Result -eq 'FAIL' })
Write-Host ("{0} checks, {1} passed, {2} failed." -f $results.Count, ($results.Count - $failed.Count), $failed.Count)
if ($JsonReport) { $results | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $JsonReport -Encoding UTF8 }
if ($failed.Count -gt 0) { exit 1 } else { exit 0 }
