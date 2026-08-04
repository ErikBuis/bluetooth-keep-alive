[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '')]
param()

# Copy this file to config.ps1 and fill in your values.
# config.ps1 is not tracked by git, so your personal settings will stay local.

# Replace this with the friendly names of the Bluetooth devices you want to keep awake. These are
# simply the names that show up in the list of Bluetooth devices in Windows settings. You can use
# partial names if you want, e.g. "JBL" to match any device with "JBL" somewhere in its name.
# List as many as you like; silence plays whenever any one of them is connected.
#
# Not sure what name to use? With your device connected, run this in PowerShell to list all audio
# endpoints. Yours should be the connected one (Status "OK") that isn't a speaker or microphone:
# > Get-PnpDevice -Class AudioEndpoint | Select-Object FriendlyName, Status
$targets = @(
    "YOUR DEVICE NAME HERE"
    # "ANOTHER DEVICE NAME"
)

# Replace this with the full path to your VLC Media Player executable.
$vlcPath = "C:\Program Files (x86)\VideoLAN\VLC\vlc.exe"
