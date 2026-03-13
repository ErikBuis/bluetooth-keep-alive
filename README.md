# Bluetooth Keep Alive
Prevent Bluetooth devices from cutting out sound due to inactivity 🔵💀
<br><br>

This script is designed to work around a common issue where Bluetooth audio devices (like headphones or speakers) will go into a power-saving mode after a period of inactivity (JBL devices are especially prone to this and will go into power-saving mode after less than a second). When this happens, if you try to play audio, it will cut out the first ~1-2 seconds of that audio while the Bluetooth device wakes up. This can be very annoying, especially if you are using the Bluetooth device for notifications or other short audio snippets.
<br><br>

This script solves the problem and is meant to be run by Windows Task Scheduler when a Bluetooth device connects. It checks if the connected device matches the target friendly name, and if so, it starts VLC Media Player to play a silent audio file in a loop.


## Setup
1. Clone or download this repo and place the folder at `C:\bluetooth-keep-alive`. Make sure it contains `start_silence.ps1`, `silence.wav`, and `bluetooth_keep_alive.xml`.

2. Install VLC Media Player at `C:\Program Files (x86)\VideoLAN\VLC\vlc.exe` (this is the default installation path). If you installed it somewhere else, update the path in `start_silence.ps1`.

3. Open the "Task Scheduler" app, click `Action -> Import Task...`, and select `bluetooth_keep_alive.xml`. Click OK.

4. Enable the `Bluetooth-Policy` log (it's disabled by default) by opening the "Event Viewer" app, going to `Applications and Services Logs -> Microsoft -> Windows -> Bluetooth-Policy -> Operational`, and clicking "Enable Log" on the right-hand side.


## Troubleshooting
- You can check the log file at `C:\bluetooth-keep-alive\bluetooth_check.log` to see the output of the script and any errors that may have occurred.
- If the logs seem to be correct, you can check Task Scheduler to see if VLC is running. It should only take up minimal CPU and memory.
- Sometimes after a Windows update, the `Bluetooth-Policy` log may have been disabled again, which will cause this script to fail. If that happens, just go to the Event Viewer and enable the `Bluetooth-Policy` log again (see above).
- If VLC is running but you still have problems where the sound cuts out, you may have to update VLC to the latest version. Open VLC and go to `Help -> Check for Updates` to update it.


## Reproducibility (for developers)
These steps document how the repo artifacts were originally created.

### Silence Audio File
The `silence.wav` file was created using ffmpeg:
```powershell
ffmpeg -f lavfi -i anullsrc=r=44100:cl=stereo -t 10 silence.wav
```

### Task Scheduler Task
The `bluetooth_keep_alive.xml` Task Scheduler task definition was created by manually configuring a task in Task Scheduler (`Action -> Create Task...`) with the following settings, then exporting it via `Action -> Export Task...`:
 - General
     - Name: "Bluetooth Keep Alive"
     - Select "Run whether user is logged on or not"
         - Check "Do not store password"
     - "Run with highest privileges"
 - Triggers
     - New...
         - Begin the task: "On an event"
             - Select "Basic"
                 - Log: "Microsoft-Windows-Bluetooth-Policy/Operational"
                 - Source: "Bluetooth-Policy"
                 - Event ID: 9
 - Actions
     - New...
         - Action: "Start a program"
         - Program/script: `powershell.exe`
         - Add arguments: `-ExecutionPolicy Bypass -File "C:\bluetooth-keep-alive\start_silence.ps1"`
         - Start in: `C:\bluetooth-keep-alive`
 - Conditions
     - Uncheck "Start the task only if the computer is on AC power"
