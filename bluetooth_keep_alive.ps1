# Activates a VLC instance to play a silent audio file in a loop when a specific Bluetooth device
# connects. Runs as a scheduled task as USER at connection of any bluetooth device and at logon to
# catch devices that Windows connected before anyone logged on. Requires VLC to be installed.

$logFile = "$PSScriptRoot\bluetooth_keep_alive.log"
$silenceFile = "$PSScriptRoot\silence.wav"
$configFile = "$PSScriptRoot\config.ps1"

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

    # A Bluetooth audio device only exposes an audio endpoint with status OK while it is actually
    # connected, so this holds regardless of which trigger started the task.
    $connected = @(Get-PnpDevice -Class AudioEndpoint -ErrorAction SilentlyContinue |
            Where-Object { $ep = $_; $ep.Status -eq 'OK' -and ($targets | Where-Object { $ep.FriendlyName -like "*$_*" }) })

    if ($connected.Count -eq 0) {
        Write-Log "None of the target devices are connected: $($targets -join ', ')"
        Write-Log "No action taken."
        exit 1
    }
    Write-Log "Target device connected (endpoint: '$($connected[0].FriendlyName)')."

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
