[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '')]
param()

# Copy this file to config.ps1 and fill in your values.
# config.ps1 is not tracked by git, so your personal settings will stay local.

# Replace this with the friendly name of your Bluetooth device. This is simply the name that shows
# up in the list of Bluetooth devices in Windows settings. You can use a partial name with
# wildcards if you want, e.g. "JBL" to match any device with "JBL" somewhere in its name.
$target = "YOUR DEVICE NAME HERE"  # ignore

# Replace this with the full path to your VLC Media Player executable.
$vlcPath = "C:\Program Files (x86)\VideoLAN\VLC\vlc.exe"
