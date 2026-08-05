# Activates a VLC instance to play a silent audio file in a loop when a specific Bluetooth device
# connects. Runs as a scheduled task as USER at connection of any bluetooth device and at logon to
# catch devices that Windows connected before anyone logged on. Requires VLC to be installed.

# Address of the device that fired the event trigger, substituted by Task Scheduler from the event.
# A logon-triggered run has no event, so the placeholder arrives here unsubstituted.
param([string]$BthAddr)

$logFile = "$PSScriptRoot\bluetooth_keep_alive.log"
$silenceFile = "$PSScriptRoot\silence.wav"
$configFile = "$PSScriptRoot\config.ps1"

# Windows publishes the audio endpoint of a Bluetooth device roughly ten seconds after it connects,
# so a logon-triggered run gives it a generous margin to show up.
$endpointTimeoutSec = 60

# Stop on any error.
$ErrorActionPreference = 'Stop'

# Helper function to log with timestamp, keeping the log capped at 128 lines.
function Write-Log {
    param(
        [string]$message,
        [ValidateSet('TRACE', 'DEBUG', 'INFO', 'WARNING', 'ERROR', 'FATAL')]
        [string]$level = 'INFO'
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp | $level | $message" | Out-File -FilePath $logFile -Append -Encoding utf8
    $maxLines = 128
    $lines = Get-Content -Path $logFile -Encoding utf8
    if ($lines.Count -gt $maxLines) {
        $lines | Select-Object -Last $maxLines | Set-Content -Path $logFile -Encoding utf8
    }
    Write-Host $message
}

# Load user configuration.
if (-not (Test-Path $configFile)) {
    Write-Log 'config.ps1 not found. Copy example_config.ps1 to config.ps1 and fill in your values.' -level 'FATAL'
    exit 1
}
. $configFile
$targets = @($targets | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($targets.Count -eq 0) {
    Write-Log '$targets is not set in config.ps1. See example_config.ps1 for the required variables.' -level 'FATAL'
    exit 1
}
if ([string]::IsNullOrEmpty($vlcPath)) {
    Write-Log '$vlcPath is not set in config.ps1. See example_config.ps1 for the required variables.' -level 'FATAL'
    exit 1
}

try {
    Write-Log "================ Checking Bluetooth Connection ================"

    if ($BthAddr -match '^\d+$') {
        # Triggered by a connection event, which already tells us exactly which device connected.
        $address = '{0:X12}' -f [int64]$BthAddr
        Write-Log "Connection event for address 0x$address." -level 'DEBUG'

        $device = Get-PnpDevice -Class Bluetooth |
            Where-Object { $_.InstanceId -like "*DEV_$address*" } |
            Select-Object -First 1
        if (-not $device) {
            Write-Log "No Bluetooth device found for address 0x$address." -level 'ERROR'
            exit 1
        }

        if (-not ($targets | Where-Object { $device.FriendlyName -like "*$_*" })) {
            Write-Log "Connected device '$($device.FriendlyName)' is not one of: $($targets -join ', ')"
            Write-Log "No action taken."
            exit 1
        }
        Write-Log "Target device connected: '$($device.FriendlyName)'."
    }
    else {
        # Triggered at logon, so there is no event to go on. A Bluetooth audio device only exposes
        # an audio endpoint with status OK while it is actually connected, but Windows takes its
        # time to publish one, hence the wait.
        $started = Get-Date
        do {
            $connected = @(Get-PnpDevice -Class AudioEndpoint -ErrorAction SilentlyContinue |
                    Where-Object { $ep = $_; $ep.Status -eq 'OK' -and ($targets | Where-Object { $ep.FriendlyName -like "*$_*" }) })
            if ($connected.Count -gt 0) { break }
            Start-Sleep -Seconds 1
        } while (((Get-Date) - $started).TotalSeconds -lt $endpointTimeoutSec)

        if ($connected.Count -eq 0) {
            Write-Log "None of the target devices are connected: $($targets -join ', ')"
            Write-Log "No action taken."
            exit 1
        }
        Write-Log "Target device connected (endpoint: '$($connected[0].FriendlyName)')."
    }

    # Check if our silence playback VLC instance is already running by looking for a VLC process
    # whose startup command contains the silence file path.
    $existingVlc = Get-CimInstance Win32_Process -Filter "Name = 'vlc.exe'" |
        Where-Object { $_.CommandLine -like "*$silenceFile*" }

    if ($existingVlc) {
        Write-Log "Silence playback already running (PID: $($existingVlc.ProcessId)). Skipping."
        exit 0
    }

    Write-Log "Starting silence playback."
    Start-Process "$vlcPath" -ArgumentList "--intf dummy --loop `"$silenceFile`""
    exit 0
}
catch {
    $errorDetails = "$($_.InvocationInfo.InvocationName) : $($_.ToString())"
    $errorDetails += "`n$($_.InvocationInfo.PositionMessage)"
    $errorDetails += "`n    + CategoryInfo          : $($_.CategoryInfo)"
    $errorDetails += "`n    + FullyQualifiedErrorId : $($_.FullyQualifiedErrorId)"
    Write-Log $errorDetails -level 'FATAL'
    exit 1
}
