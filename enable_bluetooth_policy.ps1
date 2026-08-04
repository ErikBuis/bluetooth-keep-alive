# Re-enables the Bluetooth-Policy Operational event log, which Windows servicing periodically
# resets to disabled. Runs as a scheduled task as SYSTEM at boot. Requires administrator rights.

$logFile = "$PSScriptRoot\enable_bluetooth_policy.log"
$channel = 'Microsoft-Windows-Bluetooth-Policy/Operational'

# Stop on any error.
$ErrorActionPreference = 'Stop'

# Helper function to log with timestamp, keeping the log capped at 128 lines.
function Write-Log {
    param(
        [string]$message,
        [ValidateSet('TRACE', 'DEBUG', 'INFO', 'WARNING', 'ERROR', 'FATAL')]
        [string]$level = 'INFO'
    )
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    "$timestamp | $level | $message" | Out-File -FilePath $logFile -Append -Encoding utf8
    $maxLines = 128
    $lines = Get-Content -Path $logFile -Encoding utf8
    if ($lines.Count -gt $maxLines) {
        $lines | Select-Object -Last $maxLines | Set-Content -Path $logFile -Encoding utf8
    }
    Write-Host $message
}

# Runs wevtutil without letting PowerShell turn its stderr into a terminating NativeCommandError,
# so the exit code stays readable.
function Invoke-Wevtutil {
    param([string[]]$arguments)
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & wevtutil.exe @arguments 2>&1 | ForEach-Object { $_.ToString() }
        return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($output -join "`n") }
    }
    finally {
        $ErrorActionPreference = $previous
    }
}

# Reads the channel configuration and returns $true when the channel is currently enabled.
function Test-ChannelEnabled {
    $result = Invoke-Wevtutil @('gl', $channel)
    if ($result.ExitCode -ne 0) {
        throw "wevtutil gl failed with exit code $($result.ExitCode): $($result.Output)"
    }
    return [bool]($result.Output -split "`n" | Select-String -Pattern '^\s*enabled:\s*true\s*$')
}

try {
    if (Test-ChannelEnabled) {
        Write-Log "Channel '$channel' is already enabled. Nothing to do." -level 'DEBUG'
        exit 0
    }

    Write-Log "Channel '$channel' is disabled. Re-enabling it now." -level 'WARNING'
    $result = Invoke-Wevtutil @('sl', $channel, '/e:true')
    if ($result.ExitCode -ne 0) {
        Write-Log "wevtutil sl failed with exit code $($result.ExitCode): $($result.Output)" -level 'ERROR'
        exit 1
    }

    if (Test-ChannelEnabled) {
        Write-Log "Channel '$channel' was successfully re-enabled."
        exit 0
    }
    Write-Log "wevtutil reported success but '$channel' is still disabled." -level 'ERROR'
    exit 1
}
catch {
    $errorDetails = "$($_.InvocationInfo.InvocationName) : $($_.ToString())"
    $errorDetails += "`n$($_.InvocationInfo.PositionMessage)"
    $errorDetails += "`n    + CategoryInfo          : $($_.CategoryInfo)"
    $errorDetails += "`n    + FullyQualifiedErrorId : $($_.FullyQualifiedErrorId)"
    Write-Log $errorDetails -level 'FATAL'
    exit 1
}
