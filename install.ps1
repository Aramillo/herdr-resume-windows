# herdr-resume-windows installer.
#
# Install (one line, PowerShell):
#   irm https://raw.githubusercontent.com/__OWNER__/herdr-resume-windows/main/install.ps1 | iex
# Uninstall:
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/__OWNER__/herdr-resume-windows/main/install.ps1))) -Uninstall
# From a clone:
#   .\install.ps1            /   .\install.ps1 -Uninstall
#
# What it touches (and nothing else):
#   %LOCALAPPDATA%\herdr-resume\        hook.ps1, resume.ps1, hook.log
#   ~\.claude\settings.json             SessionStart + SessionEnd hooks (backup made first)
#   PowerShell 5 and 7 profiles         one marked block that loads resume.ps1

param([switch]$Uninstall)

$ErrorActionPreference = 'Stop'

$RepoRaw  = 'https://raw.githubusercontent.com/__OWNER__/herdr-resume-windows/main'
$Dir      = Join-Path $env:LOCALAPPDATA 'herdr-resume'
$Settings = Join-Path $env:USERPROFILE '.claude\settings.json'
$Docs     = [Environment]::GetFolderPath('MyDocuments')
$Profiles = @(
    (Join-Path $Docs 'WindowsPowerShell\Microsoft.PowerShell_profile.ps1'),  # Windows PowerShell 5.1
    (Join-Path $Docs 'PowerShell\Microsoft.PowerShell_profile.ps1')          # PowerShell 7+
)
$HookCmd    = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' + ($Dir -replace '\\', '/') + '/hook.ps1"'
$BlockStart = '# >>> herdr-resume >>>'
$BlockEnd   = '# <<< herdr-resume <<<'
$Utf8NoBom  = New-Object System.Text.UTF8Encoding $false
$Utf8Bom    = New-Object System.Text.UTF8Encoding $true

function Say([string]$msg, [string]$color = 'Gray') { Write-Host "herdr-resume: $msg" -ForegroundColor $color }

# ---------------------------------------------------------------- files
function Install-Files {
    New-Item -ItemType Directory -Force $Dir | Out-Null
    $local = if ($PSScriptRoot) { Join-Path $PSScriptRoot 'src' } else { $null }
    foreach ($f in 'hook.ps1', 'resume.ps1') {
        $dest = Join-Path $Dir $f
        if ($local -and (Test-Path (Join-Path $local $f))) {
            Copy-Item (Join-Path $local $f) $dest -Force
        } else {
            Invoke-WebRequest -UseBasicParsing -Uri "$RepoRaw/src/$f" -OutFile $dest
        }
        Unblock-File $dest -ErrorAction SilentlyContinue
    }
    Say "files in $Dir"
}

# ---------------------------------------------------------------- Claude Code hooks
function Test-OurHook($entry) {
    foreach ($h in @($entry.hooks)) { if ([string]$h.command -match 'herdr-resume[/\\]hook\.ps1') { return $true } }
    return $false
}

function Set-ClaudeHooks([bool]$add) {
    $s = $null
    if (Test-Path $Settings) {
        $text = [IO.File]::ReadAllText($Settings)
        if ($text.Trim()) {
            try { $s = $text | ConvertFrom-Json }
            catch { throw "Cannot parse $Settings ($($_.Exception.Message)). Fix it and run again; nothing was changed." }
        }
        $backup = "$Settings.bak-herdr-resume"
        Copy-Item $Settings $backup -Force
        Say "backup of settings.json -> $backup"
    } elseif (-not $add) {
        return
    }
    if (-not $s) { $s = New-Object PSObject }

    if (-not $s.PSObject.Properties['hooks']) { $s | Add-Member -NotePropertyName hooks -NotePropertyValue (New-Object PSObject) }
    foreach ($ev in 'SessionStart', 'SessionEnd') {
        $list = @()
        if ($s.hooks.PSObject.Properties[$ev]) {
            $list = @(@($s.hooks.$ev) | Where-Object { -not (Test-OurHook $_) })
        }
        if ($add) {
            $list += New-Object PSObject -Property @{
                hooks = @(New-Object PSObject -Property ([ordered]@{ type = 'command'; command = $HookCmd; timeout = 10 }))
            }
        }
        if ($list.Count -gt 0) {
            $s.hooks | Add-Member -NotePropertyName $ev -NotePropertyValue ([object[]]$list) -Force
        } elseif ($s.hooks.PSObject.Properties[$ev]) {
            $s.hooks.PSObject.Properties.Remove($ev)
        }
    }
    if (@($s.hooks.PSObject.Properties).Count -eq 0) { $s.PSObject.Properties.Remove('hooks') }

    New-Item -ItemType Directory -Force (Split-Path $Settings) | Out-Null
    [IO.File]::WriteAllText($Settings, ($s | ConvertTo-Json -Depth 64), $Utf8NoBom)
    if ($add) { Say "Claude Code hooks added to $Settings" } else { Say "Claude Code hooks removed from $Settings" }
}

# ---------------------------------------------------------------- PowerShell profiles
function Set-ProfileBlock([string]$path, [bool]$add) {
    $text = if (Test-Path $path) { [IO.File]::ReadAllText($path) } else { '' }
    $pattern = '(?s)\r?\n?' + [regex]::Escape($BlockStart) + '.*?' + [regex]::Escape($BlockEnd) + '\r?\n?'
    $clean = [regex]::Replace($text, $pattern, "`r`n").TrimEnd()
    if ($add) {
        $block = @(
            $BlockStart,
            '$__hr = Join-Path $env:LOCALAPPDATA ''herdr-resume\resume.ps1''; if (Test-Path $__hr) { . $__hr }; Remove-Variable __hr -ErrorAction SilentlyContinue',
            $BlockEnd
        ) -join "`r`n"
        $clean = if ($clean) { "$clean`r`n`r`n$block`r`n" } else { "$block`r`n" }
    } elseif (-not (Test-Path $path)) {
        return
    } elseif ($clean) {
        $clean += "`r`n"
    }
    New-Item -ItemType Directory -Force (Split-Path $path) | Out-Null
    [IO.File]::WriteAllText($path, $clean, $Utf8Bom)
    if ($add) { Say "profile hooked: $path" } else { Say "profile cleaned: $path" }
}

# ---------------------------------------------------------------- main
if ($Uninstall) {
    Set-ClaudeHooks $false
    foreach ($p in $Profiles) { Set-ProfileBlock $p $false }
    if (Test-Path $Dir) { Remove-Item $Dir -Recurse -Force }
    Say 'uninstalled. Open terminals keep their labels until their next Claude session; they are harmless.' 'Green'
    return
}

if (-not (Get-Command hc -ErrorAction SilentlyContinue) -and -not (Test-Path (Join-Path $env:LOCALAPPDATA 'Programs\herdr-core\hc.exe'))) {
    Say 'herdr-core (hc) was not found. Install herdr first: https://herdr.dev' 'Yellow'
}
if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    Say "Claude Code ('claude') was not found on PATH. It is needed to resume sessions." 'Yellow'
}
$policy = Get-ExecutionPolicy -Scope CurrentUser
if ($policy -in @('Restricted', 'AllSigned') -or ($policy -eq 'Undefined' -and (Get-ExecutionPolicy -Scope LocalMachine) -in @('Restricted', 'AllSigned', 'Undefined'))) {
    Set-ExecutionPolicy -Scope CurrentUser RemoteSigned -Force
    Say 'execution policy for CurrentUser set to RemoteSigned so the profile can load'
}

Install-Files
Set-ClaudeHooks $true
foreach ($p in $Profiles) { Set-ProfileBlock $p $true }

Say 'installed. Claude sessions started in herdr terminals from now on will come back after a reboot.' 'Green'
Say 'Restart running Claude sessions (or open new ones) so they register.' 'Green'
