# Replace this with the friendly name of your Bluetooth device. This is simply the name that shows
# up in the list of Bluetooth devices in Windows settings. You can use a partial name with
# wildcards if you want, e.g. "JBL" to match any device with "JBL" somewhere in its name.
$target = "JBL Xtreme 4"
$logFile = "$PSScriptRoot\bluetooth_check.log"
$silenceFile = "$PSScriptRoot\silence.wav"
$vlcPath = "C:\Program Files (x86)\VideoLAN\VLC\vlc.exe"

# Helper function to log with timestamp, keeping the log capped at 128 lines.
function Write-Log {
    param([string]$message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp | $message" | Out-File -FilePath $logFile -Append -Encoding utf8
    $maxLines = 128
    $lines = Get-Content -Path $logFile -Encoding utf8
    if ($lines.Count -gt $maxLines) {
        $lines | Select-Object -Last $maxLines | Set-Content -Path $logFile -Encoding utf8
    }
    Write-Host $message
}

Write-Log "=== Script started ==="

# Look at the latest Event ID 9 message in the Bluetooth-Policy Operational log.
# The message will look something like:
# "A connection to a remote device 0x<instanceID> was successfully established."
$evt = Get-WinEvent -FilterHashtable @{
    LogName = 'Microsoft-Windows-Bluetooth-Policy/Operational'
    Id      = 9
} -MaxEvents 1
$msg = $evt.Message

# Extract the instance ID from the event message (e.g. "6C9308612315" from "0x6C9308612315").
if ($msg -match '0x([0-9A-F]+)') {
    $instanceID = $Matches[1]
    Write-Log "Extracted instance ID: $instanceID"
}
else {
    Write-Log "Could not extract instance ID from event message. Exiting."
    exit 1
}

# Get all Bluetooth devices and check if our target is connected.
$devices = Get-PnpDevice -Class Bluetooth

$matchingDevice = $devices | Where-Object {
    $_.Status -eq 'OK' -and
    $_.FriendlyName -like "*$target*" -and
    $_.InstanceId -like "*$instanceID*"
}

if ($matchingDevice) {
    # Check if our silence playback VLC instance is already running by looking for a VLC process
    # whose command line contains the silence file path.
    $existingVlc = Get-CimInstance Win32_Process -Filter "Name = 'vlc.exe'" |
        Where-Object { $_.CommandLine -like "*$silenceFile*" }

    if ($existingVlc) {
        Write-Log "Silence playback already running (PID: $($existingVlc.ProcessId)). Skipping."
        exit 0
    }

    Write-Log "Target device connected. Starting silence playback."
    Start-Process "$vlcPath" -ArgumentList "--intf dummy --loop `"$silenceFile`""
    exit 0
}
else {
    Write-Log "Target device not connected. Exiting."
    exit 1
}
