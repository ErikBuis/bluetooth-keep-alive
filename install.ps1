# One-shot installer for Bluetooth Keep Alive.
#
# Run it from a normal (non-elevated) PowerShell window:
#     powershell -ExecutionPolicy Bypass -File .\install.ps1
#
# It performs three steps:
# 1. Registers the "Bluetooth Keep Alive" task for the user running this script, so that the
#    hardcoded SID problem of a hand-imported XML disappears.
# 2. Enables the Bluetooth-Policy Operational event log (needs administrator rights).
# 3. Registers the "Enable Bluetooth Policy" task, which re-enables that log at every boot, so
#    Windows updates can no longer silently break the setup.
#
# Only steps 2 and 3 need administrator rights, so the script asks for elevation once, halfway
# through. Step 1 deliberately runs unelevated so that the task belongs to the account that is
# actually logged on rather than to whichever administrator answered the UAC prompt.

[CmdletBinding()]
param(
    # Internal. Set when the script relaunches itself elevated to run the admin-only steps.
    [switch]$AdminPhase,
    # Internal. File that the elevated instance writes its output to, so the original
    # (unelevated) window can show it after the elevated instance exits.
    [string]$TranscriptPath
)

$ErrorActionPreference = 'Stop'

$repoDir = $PSScriptRoot
$channel = 'Microsoft-Windows-Bluetooth-Policy/Operational'
$userTaskName = 'Bluetooth Keep Alive'
$logTaskName = 'Enable Bluetooth Policy'
# Task name used by older versions of this repo, removed on install to avoid a duplicate task that
# would start a second VLC instance.
$legacyTaskNames = @('bluetooth_keep_alive')

# When the script runs elevated on behalf of the unelevated one, every message is also appended to
# $TranscriptPath so the original window can replay it after the elevated instance exits.
function Write-Line {
    param([string]$text, [string]$colour = 'Gray')
    Write-Host $text -ForegroundColor $colour
    if ($TranscriptPath) { Add-Content -Path $TranscriptPath -Value $text -Encoding utf8 }
}
function Write-Step { param([string]$m) Write-Line "`n==> $m" 'Cyan' }
function Write-Ok { param([string]$m) Write-Line "    [ok] $m" 'Green' }
function Write-Warn { param([string]$m) Write-Line "    [!!] $m" 'Yellow' }
function Write-Fail { param([string]$m) Write-Line "    [xx] $m" 'Red' }

function Test-Elevated {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return ([Security.Principal.WindowsPrincipal]$id).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Loads a task definition from the repo and points its <Arguments> and <WorkingDirectory> at the
# directory this script lives in, so the repo does not have to sit in a hardcoded location.
function Get-TaskXml {
    param([string]$fileName)
    $path = Join-Path $repoDir $fileName
    if (-not (Test-Path $path)) {
        throw "Task definition '$fileName' is missing from '$repoDir'."
    }
    $xml = Get-Content -Path $path -Raw
    $placeholder = 'C:\CustomPrograms\bluetooth-keep-alive'
    $escapedRepoDir = [System.Security.SecurityElement]::Escape($repoDir.TrimEnd('\'))
    $xml = $xml.Replace($placeholder, $escapedRepoDir)
    # A <LogonTrigger> without a <UserId> means "at any user's logon", which only an administrator
    # is allowed to register. Unlike <Principal>, Task Scheduler does not fill this one in itself.
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $xml = $xml -replace '<LogonTrigger>', "<LogonTrigger>`r`n      <UserId>$sid</UserId>"
    # Task Scheduler receives this as an in-memory (UTF-16) string, so any encoding declaration
    # left behind by an editor would make it fail with "unable to switch the encoding".
    return $xml -replace '(?<=<\?xml\s+version="1\.0")\s+encoding="[^"]*"', ''
}

# Returns $true when the task is gone afterwards. Deleting a task that an older, elevated
# install created can fail for a standard user, in which case the elevated phase retries.
function Remove-TaskIfPresent {
    param([string]$name)
    if (-not (Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue)) { return $true }
    try {
        Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction Stop
        Write-Ok "Removed existing task '$name'."
        return $true
    }
    catch {
        return $false
    }
}

# ---------------------------------------------------------------------------------------------
# Elevated phase: everything that a standard user is not allowed to do.
# ---------------------------------------------------------------------------------------------

function Invoke-AdminPhase {
    # All removals happen here rather than in the normal phase, because a task that a previous
    # elevated run created is not readable or deletable by a standard user, which would otherwise
    # make the re-registration below fail with "Cannot create a file when that file already exists".
    Write-Step 'Removing previously installed tasks'
    $removed = $false
    foreach ($name in ($legacyTaskNames + $userTaskName + $logTaskName)) {
        if (-not (Remove-TaskIfPresent $name)) {
            Write-Warn "Could not remove the task '$name'; please delete it in Task Scheduler."
        }
        else { $removed = $true }
    }
    if (-not $removed) { Write-Ok 'Nothing to remove.' }

    Write-Step "Enabling the '$channel' event log"
    $enableScript = Join-Path $repoDir 'enable_bluetooth_policy.ps1'
    if (-not (Test-Path $enableScript)) {
        throw "enable_bluetooth_policy.ps1 is missing from '$repoDir'."
    }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $enableScript
    if ($LASTEXITCODE -ne 0) {
        throw "Could not enable the event log (exit code $LASTEXITCODE)."
    }
    Write-Ok "The event log is enabled."

    Write-Step "Registering the '$logTaskName' task"
    Register-ScheduledTask -TaskName $logTaskName -Xml (Get-TaskXml 'enable_bluetooth_policy.xml') | Out-Null
    Write-Ok "Registered. The log is now re-enabled at every boot."

    # Older versions ran the keep-alive task elevated, which left VLC in session 0 where the new
    # unelevated task can neither see nor stop it. Clear those out so it can be restarted
    # properly on the next connect.
    Write-Step 'Cleaning up leftover elevated VLC instances'
    $silenceFile = Join-Path $repoDir 'silence.wav'
    $stale = @(Get-CimInstance Win32_Process -Filter "Name = 'vlc.exe'" |
        Where-Object { $_.SessionId -eq 0 -or $_.CommandLine -like "*$silenceFile*" })
    if ($stale.Count -eq 0) {
        Write-Ok 'Nothing to clean up.'
    }
    else {
        foreach ($p in $stale) {
            Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
            Write-Ok "Stopped stale VLC instance (PID $($p.ProcessId), session $($p.SessionId))."
        }
    }
}

if ($AdminPhase) {
    if ($TranscriptPath) { Set-Content -Path $TranscriptPath -Value '' -Encoding utf8 }
    try {
        Invoke-AdminPhase
        exit 0
    }
    catch {
        Write-Fail $_.Exception.Message
        exit 1
    }
}

# ---------------------------------------------------------------------------------------------
# Normal phase: validation.
# ---------------------------------------------------------------------------------------------

Write-Host 'Bluetooth Keep Alive installer' -ForegroundColor White
Write-Host "Repository: $repoDir"

Write-Step 'Checking prerequisites'

$configFile = Join-Path $repoDir 'config.ps1'
if (-not (Test-Path $configFile)) {
    Write-Fail "config.ps1 not found. Copy example_config.ps1 to config.ps1 and fill in your values."
    exit 1
}
. $configFile
$targets = @($targets | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($targets.Count -eq 0) {
    Write-Fail '$targets is not set in config.ps1.'
    exit 1
}
if ([string]::IsNullOrEmpty($vlcPath)) {
    Write-Fail '$vlcPath is not set in config.ps1.'
    exit 1
}
if (-not (Test-Path $vlcPath)) {
    Write-Fail "VLC not found at '$vlcPath'. Install VLC or correct `$vlcPath in config.ps1."
    exit 1
}
Write-Ok "Target device names: $($targets -join ', ')"
Write-Ok "VLC: '$vlcPath'"

if (-not (Test-Path (Join-Path $repoDir 'silence.wav'))) {
    Write-Fail "silence.wav not found in '$repoDir'."
    exit 1
}
Write-Ok 'silence.wav found.'

# ---------------------------------------------------------------------------------------------
# Hand over to the elevated phase. This runs first, because it is also what removes any task an
# earlier install left behind, and a standard user cannot delete a task an elevated run created.
# ---------------------------------------------------------------------------------------------

if (Test-Elevated) {
    Invoke-AdminPhase
}
else {
    Write-Step 'Requesting administrator rights for part of the installation'
    Write-Host '    Enabling the bluetooth event log requires elevation. Please accept the UAC prompt.'
    $transcript = Join-Path $env:TEMP 'bluetooth_keep_alive_install.log'
    Remove-Item $transcript -ErrorAction SilentlyContinue
    try {
        $proc = Start-Process -FilePath 'powershell.exe' -Verb RunAs -Wait -PassThru -WindowStyle Hidden `
            -ArgumentList @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass',
            '-File', "`"$PSCommandPath`"",
            '-AdminPhase',
            '-TranscriptPath', "`"$transcript`""
        )
    }
    catch {
        Write-Fail 'Elevation was declined, so the event log steps were skipped.'
        Write-Warn 'Rerun this script and accept the UAC prompt to finish the installation.'
        exit 1
    }

    if (Test-Path $transcript) {
        Get-Content $transcript | ForEach-Object { Write-Host $_ }
    }
    if ($proc.ExitCode -ne 0) {
        Write-Fail "The elevated steps failed (exit code $($proc.ExitCode))."
        exit 1
    }
}

# ---------------------------------------------------------------------------------------------
# The task that must belong to the logged-on user.
# ---------------------------------------------------------------------------------------------

Write-Step "Registering the '$userTaskName' task"
$currentUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
if (Test-Elevated) {
    Write-Warn "This window is elevated, so the task will be registered for '$currentUser'."
    Write-Warn 'If that is not the account you log on with, rerun this script unelevated.'
}
# The XML omits <UserId>, so Windows fills in whichever account registers the task.
try {
    Register-ScheduledTask -TaskName $userTaskName -Xml (Get-TaskXml 'bluetooth_keep_alive.xml') -Force -ErrorAction Stop | Out-Null
}
catch {
    Write-Fail "Could not register '$userTaskName': $($_.Exception.Message)"
    Write-Warn "Delete '$userTaskName' by hand in Task Scheduler (started as administrator), then rerun this script."
    exit 1
}
$registered = Get-ScheduledTask -TaskName $userTaskName
Write-Ok "Registered for '$($registered.Principal.UserId)' (runs unelevated, only while logged on)."

Write-Step 'Done'
Write-Host '    Connect your Bluetooth device to test it. Check bluetooth_keep_alive.log for details.'
