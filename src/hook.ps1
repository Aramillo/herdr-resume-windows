# herdr-resume-windows - Claude Code SessionStart / SessionEnd hook.
#
# Records which Claude Code conversation is running in each herdr terminal by
# setting hc labels on it. Labels live in herdr-core's state on disk, so they
# survive a reboot; resume.ps1 reads them when herdr restores the terminal.
#
#   claude.resume = <session id>   conversation to bring back
#   claude.cwd    = <folder>       where it was running
#   claude.tries  = <n>            resume attempts since the last good start
#
# Must never block or fail Claude Code: every error is swallowed, exit code 0.

$ErrorActionPreference = 'SilentlyContinue'

$LogDir  = Join-Path $env:LOCALAPPDATA 'herdr-resume'
$LogFile = Join-Path $LogDir 'hook.log'

function Write-Log([string]$msg) {
    try {
        if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Force $LogDir | Out-Null }
        if ((Test-Path $LogFile) -and ((Get-Item $LogFile).Length -gt 256KB)) {
            Move-Item $LogFile "$LogFile.old" -Force
        }
        Add-Content -Path $LogFile -Value ("{0:yyyy-MM-dd HH:mm:ss} {1}" -f (Get-Date), $msg)
    } catch {}
}

try {
    if (-not $env:HC_TERMINAL_ID) { exit 0 }   # not inside a herdr terminal

    [Console]::InputEncoding = New-Object System.Text.UTF8Encoding $false
    $raw = [Console]::In.ReadToEnd()
    if (-not $raw) { exit 0 }
    $in = $raw | ConvertFrom-Json

    $hc = (Get-Command hc -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source
    if (-not $hc) { $hc = Join-Path $env:LOCALAPPDATA 'Programs\herdr-core\hc.exe' }
    if (-not (Test-Path $hc)) { Write-Log "hc not found"; exit 0 }

    $t     = $env:HC_TERMINAL_ID
    $evName = [string]$in.hook_event_name   # not $event: that is an automatic variable
    $sid    = [string]$in.session_id

    switch ($evName) {
        'SessionStart' {
            if ($sid -notmatch '^[0-9A-Za-z-]{8,64}$') { Write-Log "$t start: bad session id '$sid'"; break }
            # A trailing backslash would break native argument quoting ("C:\" -> C:").
            $cwd = ([string]$in.cwd).TrimEnd('\')
            & $hc label $t "claude.resume=$sid" "claude.cwd=$cwd" 'claude.tries=' | Out-Null
            Write-Log "$t start ($($in.source)) $sid $cwd"
        }
        'SessionEnd' {
            $reason = [string]$in.reason
            # The user left on purpose: forget the conversation.
            # clear / resume are followed by a SessionStart with the new id.
            # other (killed, shutdown, terminal closed) keeps it for resume.
            if ($reason -in @('prompt_input_exit', 'logout', 'bypass_permissions_disabled')) {
                & $hc label $t 'claude.resume=' 'claude.cwd=' 'claude.tries=' | Out-Null
                Write-Log "$t end ($reason) $sid -> forgotten"
            } else {
                Write-Log "$t end ($reason) $sid -> kept"
            }
        }
    }
} catch {
    Write-Log "error: $($_.Exception.Message)"
}
exit 0
