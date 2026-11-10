# herdr-resume-windows - dot-sourced from the PowerShell profile.
#
# When herdr-core restores a terminal (after a reboot or a core restart) it
# starts a fresh shell in it. If that terminal had a Claude Code conversation
# (hc label claude.resume, written by hook.ps1), resume it in place.
#
# Only acts in shells started directly by herdr-core: never in nested shells,
# never in shells spawned by Claude Code itself. Set HERDR_RESUME=0 to disable.

& {
    if (-not $env:HC_TERMINAL_ID) { return }
    if ($env:CLAUDECODE) { return }
    if ($env:HERDR_RESUME -eq '0') { return }
    if ($Host.Name -ne 'ConsoleHost') { return }

    try {
        $ppid = (Get-CimInstance Win32_Process -Filter "ProcessId=$PID" -Property ParentProcessId -ErrorAction Stop).ParentProcessId
        if ((Get-Process -Id $ppid -ErrorAction Stop).ProcessName -ne 'herdr-core') { return }
    } catch { return }

    $hc = (Get-Command hc -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source
    if (-not $hc) { $hc = Join-Path $env:LOCALAPPDATA 'Programs\herdr-core\hc.exe' }
    if (-not (Test-Path $hc)) { return }

    $t = $env:HC_TERMINAL_ID
    try { $info = (& $hc get $t --json 2>$null | Out-String) | ConvertFrom-Json } catch { return }
    if (-not $info -or -not $info.labels) { return }

    $id = [string]$info.labels.'claude.resume'
    if (-not $id) { return }

    $forget = { & $hc label $t 'claude.resume=' 'claude.cwd=' 'claude.tries=' | Out-Null }

    if ($id -notmatch '^[0-9A-Za-z-]{8,64}$') { & $forget; return }

    $tries = 0
    [void][int]::TryParse([string]$info.labels.'claude.tries', [ref]$tries)
    if ($tries -ge 2) {
        Write-Host "herdr-resume: Claude session $id failed to resume twice, forgetting it." -ForegroundColor Yellow
        Write-Host "              Run 'claude --resume' to pick it by hand." -ForegroundColor Yellow
        & $forget
        return
    }
    & $hc label $t "claude.tries=$($tries + 1)" | Out-Null

    $cwd = [string]$info.labels.'claude.cwd'
    if ($cwd -match '^[A-Za-z]:$') { $cwd += '\' }
    if ($cwd -and (Test-Path -LiteralPath $cwd)) { Set-Location -LiteralPath $cwd }

    if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
        Write-Host "herdr-resume: 'claude' is not on PATH, cannot resume $id." -ForegroundColor Yellow
        return
    }

    Write-Host "herdr-resume: resuming Claude session $id  (Esc to cancel)" -ForegroundColor Cyan
    try {
        $deadline = (Get-Date).AddSeconds(3)
        while ((Get-Date) -lt $deadline) {
            if ([Console]::KeyAvailable -and [Console]::ReadKey($true).Key -eq 'Escape') {
                & $forget
                Write-Host "herdr-resume: cancelled, session forgotten for this terminal." -ForegroundColor DarkGray
                return
            }
            Start-Sleep -Milliseconds 50
        }
    } catch {}

    & claude --resume $id
}
