<#
.SYNOPSIS
  Install or update the open-overheid toolkit for Google Antigravity on this computer, whatever
  the user name or device, and check that every MCP server works.

.DESCRIPTION
  1. Clones the repository into <plugins>\open-overheid, or runs `git pull --ff-only` when it is
     already there. Default plugins folder: %USERPROFILE%\.gemini\config\plugins (Windows) or
     ~/.gemini/config/plugins (macOS/Linux).
  2. Creates or completes mcp_config.json. The open-overheid entries contain no user name: they
     start PowerShell with -Command and let it resolve $HOME, so the same file works on every
     computer. Servers you added yourself are kept. An existing UTF-8 BOM is preserved.
  3. Runs tests/smoke_test.ps1 against mcp_config.json, exactly as Antigravity starts the servers
     (skip with -SkipTest, no network calls with -Offline). If the user-name independent form
     fails on this computer, it falls back to absolute paths and tests again.
  Optional -UpdateClaudeCode also refreshes the Claude Code marketplace when the `claude` command exists.
  Claude Desktop updates its plugin itself: Customize > Plugins.

  Works with Windows PowerShell 5.1 and PowerShell 7. Needs git.

.EXAMPLE
  # Any computer, one line (Windows PowerShell):
  & ([scriptblock]::Create((irm https://raw.githubusercontent.com/maikell/ai-openoverheid/main/install.ps1)))

.EXAMPLE
  # From an existing clone, without network tests
  powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1 -Offline
#>
[CmdletBinding()]
param(
  [string]$PluginsDir,
  [string]$RepoUrl = 'https://github.com/maikell/ai-openoverheid.git',
  [switch]$SkipTest,
  [switch]$Offline,
  [switch]$UpdateClaudeCode
)

$ErrorActionPreference = 'Stop'
$onWindows = ($PSVersionTable.PSVersion.Major -lt 6) -or $IsWindows
$homeDir = if ($onWindows) { $env:USERPROFILE } else { $HOME }
if (-not $PluginsDir) { $PluginsDir = Join-Path (Join-Path (Join-Path $homeDir '.gemini') 'config') 'plugins' }
$target = Join-Path $PluginsDir 'open-overheid'

function Step([string]$msg) { Write-Host "==> $msg" }

if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw 'git is not installed. Install Git (https://git-scm.com) and run this again.' }

# ---- 1. clone or pull
if (Test-Path -LiteralPath (Join-Path $target '.git')) {
  Step "Updating $target"
  $before = (& git -C $target rev-parse --short HEAD).Trim()
  & git -C $target pull --ff-only
  if ($LASTEXITCODE -ne 0) { throw "git pull failed in $target. Local changes? Check 'git -C `"$target`" status'." }
  $after = (& git -C $target rev-parse --short HEAD).Trim()
  if ($before -eq $after) { Write-Host "    already up to date ($after)" } else { Write-Host "    $before -> $after" }
} elseif (Test-Path -LiteralPath $target) {
  throw "$target exists but is not a git clone. Move it aside and run this again."
} else {
  Step "Cloning into $target"
  New-Item -ItemType Directory -Force -Path $PluginsDir | Out-Null
  & git clone $RepoUrl $target
  if ($LASTEXITCODE -ne 0) { throw 'git clone failed.' }
}
$version = ((Get-Content -Raw -LiteralPath (Join-Path $target 'plugin.json')) | ConvertFrom-Json).version
Write-Host "    open-overheid $version"

# ---- 2. mcp_config.json
Step 'Checking mcp_config.json'
$examplePath = Join-Path $target 'mcp_config.example.json'
$configPath = Join-Path $target 'mcp_config.json'
$example = (Get-Content -Raw -LiteralPath $examplePath) | ConvertFrom-Json
$mcpDir = Join-Path $target 'mcp'

$hasBom = $false
$config = $null
if (Test-Path -LiteralPath $configPath) {
  $raw = [IO.File]::ReadAllBytes($configPath)
  $hasBom = ($raw.Length -ge 3 -and $raw[0] -eq 0xEF -and $raw[1] -eq 0xBB -and $raw[2] -eq 0xBF)
  $config = ([Text.Encoding]::UTF8.GetString($raw).TrimStart([char]0xFEFF)) | ConvertFrom-Json
}
if (-not $config) { $config = [pscustomobject]@{ mcpServers = [pscustomobject]@{} } }
if (-not $config.mcpServers) { $config | Add-Member -NotePropertyName mcpServers -NotePropertyValue ([pscustomobject]@{}) -Force }

# Entries are user-name independent: PowerShell itself resolves $HOME when the server starts, so the
# same mcp_config.json works on every computer. Only a custom -PluginsDir needs an absolute path.
$defaultDir = Join-Path (Join-Path (Join-Path $homeDir '.gemini') 'config') 'plugins'
$portable = ((Resolve-Path -LiteralPath $PluginsDir).ProviderPath.TrimEnd('\', '/') -eq $defaultDir.TrimEnd('\', '/'))
$cmd = if ($onWindows) { 'powershell.exe' } else { 'pwsh' }
function New-Entry([string]$scriptName, [bool]$usePortable) {
  if ($usePortable) {
    return [pscustomobject]@{ command = $cmd; args = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-Command',
      "& (Join-Path `$HOME '.gemini/config/plugins/open-overheid/mcp/$scriptName')") }
  }
  return [pscustomobject]@{ command = $cmd; args = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $mcpDir $scriptName)) }
}
function Write-Config($cfgObj) {
  $enc = New-Object System.Text.UTF8Encoding($hasBom)
  [IO.File]::WriteAllText($configPath, ($cfgObj | ConvertTo-Json -Depth 10), $enc)
}

$changes = @()
$scripts = @{}
foreach ($p in $example.mcpServers.PSObject.Properties) {
  $name = $p.Name
  $scriptName = [regex]::Match((@($p.Value.args) -join ' '), '[A-Za-z0-9_]+_mcp\.ps1').Value
  $scripts[$name] = $scriptName
  $want = New-Entry $scriptName $portable
  $existing = $config.mcpServers.PSObject.Properties[$name]
  if (-not $existing) {
    $config.mcpServers | Add-Member -NotePropertyName $name -NotePropertyValue $want
    $changes += "added $name"
  } elseif (((@($existing.Value.args) -join ' ') -ne (@($want.args) -join ' ')) -or $existing.Value.command -ne $want.command) {
    $existing.Value = $want
    $changes += "updated $name"
  }
}
if ($changes.Count -gt 0 -or -not (Test-Path -LiteralPath $configPath)) {
  Write-Config $config
  Write-Host "    $($changes -join ', ')"
} else {
  Write-Host '    all servers present and user-name independent'
}

# ---- 3. Claude Code (optional)
if ($UpdateClaudeCode) {
  if (Get-Command claude -ErrorAction SilentlyContinue) {
    Step 'Updating Claude Code marketplace'
    & claude plugin marketplace update open-overheid
  } else { Write-Host '    claude command not found; skipped' }
}

# ---- 4. smoke test
if (-not $SkipTest) {
  Step 'Running smoke test'
  $testArgs = @{}
  if ($Offline) { $testArgs.Offline = $true }
  if (-not $onWindows) { $testArgs.Shell = 'pwsh' }
  $testArgs.Config = $configPath   # test the servers exactly as Antigravity will start them
  $smoke = Join-Path (Join-Path $target 'tests') 'smoke_test.ps1'
  & $smoke @testArgs
  $code = $LASTEXITCODE
  if ($code -ne 0 -and $portable) {
    # Fallback: if this PowerShell does not start servers via -Command, use absolute -File paths
    Step 'Some checks failed; retrying with absolute paths (-File) in mcp_config.json'
    foreach ($name in @($scripts.Keys)) { $config.mcpServers.$name = New-Entry $scripts[$name] $false }
    Write-Config $config
    & $smoke @testArgs
    $code = $LASTEXITCODE
    if ($code -eq 0) { Write-Host '    works with absolute paths; mcp_config.json now contains this computer''s path.' }
  }
  Write-Host ''
  Write-Host 'Restart Antigravity (or reload plugins) to load new servers. Claude Desktop: Customize > Plugins > update open-overheid.'
  $global:LASTEXITCODE = $code   # no 'exit': this script may run inside your own shell
  return
}
Write-Host 'Done. Restart Antigravity (or reload plugins) to load new servers.'
