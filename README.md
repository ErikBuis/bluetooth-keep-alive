# Bluetooth Keep Alive
Prevent Bluetooth devices from cutting out sound due to inactivity 🔵💀
<br><br>

This script is designed to work around a common issue where Bluetooth audio devices (like headphones or speakers) will go into a power-saving mode after a period of inactivity (JBL devices are especially prone to this and will go into power-saving mode after less than a second). When this happens, if you try to play audio, it will cut out the first ~1-2 seconds of that audio while the Bluetooth device wakes up. This can be very annoying, especially if you are using the Bluetooth device for notifications or other short audio snippets.
<br><br>

This script solves the problem by running when a Bluetooth device connects or when you log on. It checks whether your target device is connected, and if so, it starts VLC Media Player to play a silent audio file in a loop.


## Setup
1. Clone or download this repo to any folder you like (the installer picks up wherever you put it).

2. Install VLC Media Player.

3. Copy `example_config.ps1` to a new file named `config.ps1` in the same folder, then open `config.ps1` and fill in your own values:
   - Set `$targets` to the friendly names of the Bluetooth devices you want to keep awake, as shown in Windows Settings (Bluetooth & devices). You can use partial names if you want, e.g. `"JBL"` matches any device with `JBL` somewhere in its name. List as many devices as you like; silence plays whenever any one of them is connected.
   - Set `$vlcPath` to the full path to your VLC Media Player executable (the default is already filled in, only change it if you installed VLC somewhere else).

   `config.ps1` is intentionally not tracked by git, so your personal settings will stay local.

4. Run the installer from a normal (non-elevated) PowerShell window:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\install.ps1
   ```
   This registers the bluetooth-keep-alive task for your user profile, enables the `Bluetooth-Policy` event log, and registers a second task that keeps that log enabled at every boot. You will get one UAC prompt partway through, because enabling an event log requires administrator rights.

5. Connect your Bluetooth device to test it.

### Manual setup (alternative)
If you would rather not run the installer, you can do the same thing by hand:

1. Place the folder at `C:\CustomPrograms\bluetooth-keep-alive` (the XML files hardcode this path, so you can place the folder somewhere else if you manually edit the XML files).
2. Open the Task Scheduler app (installed by default on Windows), click `Action -> Import Task...`, select `bluetooth_keep_alive.xml`, and click OK. Afterwards open the task's "Triggers" tab, edit the "At log on" trigger and set it to "Specific user: <your account>". As shipped that trigger applies to *any* user, which Windows only lets an administrator register, so importing it unedited fails with "Access is denied".
3. Import `enable_bluetooth_policy.xml` the same way, but from a Task Scheduler started as administrator. This task runs as `SYSTEM` and re-enables the event log at every boot.
4. Enable the `Bluetooth-Policy` log once yourself, either from an elevated PowerShell:
   ```powershell
   wevtutil sl Microsoft-Windows-Bluetooth-Policy/Operational /e:true
   ```
   or by opening the "Event Viewer" app, going to `Applications and Services Logs -> Microsoft -> Windows -> Bluetooth-Policy -> Operational`, and clicking "Enable Log" on the right-hand side.


## Troubleshooting
- You can check the log file at `bluetooth_keep_alive.log` to see the output of the script and any errors that may have occurred.
- If you don't see any log after having connected your Bluetooth device, the `Bluetooth-Policy` log is probably disabled. Windows servicing resets it to disabled every so often, which is exactly what the "Enable Bluetooth Policy" task is there to undo. Check `enable_bluetooth_policy.log` to see what that task did, or run `wevtutil gl Microsoft-Windows-Bluetooth-Policy/Operational` to inspect the current state. You can also right-click that task in Task Scheduler and choose "Run" to fix it immediately.
- If you ran the installer from an elevated PowerShell window (this is *not* the intended way), the "Bluetooth Keep Alive" task is created with an administrator-only ACL, so a later unelevated run cannot replace it. Simply rerun the installer unelevated to fix this.
- If the sound cuts out only on the very first playback after starting your PC, check whether the logon run happened: `bluetooth_keep_alive.log` should contain an entry from roughly ten seconds after you logged on.
- If the logs seem to be correct, you can check Task Scheduler to see if VLC is running. It should only take up minimal CPU and memory.
- If VLC is running but you still have problems where the sound cuts out, you may have to update VLC to the latest version. Open VLC and go to `Help -> Check for Updates` to update it.
- If none of the above steps solve your problem, please open an issue on GitHub and include the contents of both log files.


## Reproducibility (for developers)
These steps document how the repo artifacts were originally created.

### Silence Audio File
The `silence.wav` file was created using ffmpeg:
```powershell
ffmpeg -f lavfi -i anullsrc=r=8000:cl=mono -t 600 silence.wav
```

### Task Scheduler Task
The `bluetooth_keep_alive.xml` Task Scheduler task definition was created by manually configuring a task in Task Scheduler (`Action -> Create Task...`) with the following settings, then exporting it via `Action -> Export Task...`:
- General
    - Name: "Bluetooth Keep Alive"
    - Select "Run only when user is logged on"
- Triggers
    - New...
       - Begin the task: "On an event"
           - Select "Basic"
               - Log: "Microsoft-Windows-Bluetooth-Policy/Operational"
               - Source: "Bluetooth-Policy"
               - Event ID: 9
    - New...
       - Begin the task: "At log on"
           - Select "Any user"
           - Check "Delay task for": 10 seconds
- Actions
    - New...
       - Action: "Start a program"
       - Program/script: `powershell.exe`
       - Add arguments: `-NoProfile -ExecutionPolicy Bypass -File "C:\CustomPrograms\bluetooth-keep-alive\bluetooth_keep_alive.ps1"`
       - Start in: `C:\CustomPrograms\bluetooth-keep-alive`
- Conditions
    - Uncheck "Start the task only if the computer is on AC power"

The exported XML was then edited by hand in the following ways:
- The `<UserId>` element was **deleted** from `<Principal>`. Normally, Task Scheduler writes the SID of the account that created the task, which is meaningless on anyone else's machine and makes `Action -> Import Task...` fail with *"The specified account name is not valid."* With `<UserId>` absent, Windows fills in the SID of whoever imports the task instead.
- The `<UserId>` element was **deleted** from `<LogonTrigger>` as well, for the same portability reason. Unlike `<Principal>`, Task Scheduler does *not* fill this one in on import: an absent `<UserId>` means "at any user's logon", which only an administrator may register. `install.ps1` therefore inserts the SID of the installing user before handing the XML to Task Scheduler.
- The `encoding` attribute was **removed** from the XML declaration (`<?xml version="1.0"?>`). Task Scheduler hands the XML to MSXML as an in-memory UTF-16 string, so a file that declares `encoding="UTF-8"` is rejected with *"unable to switch the encoding"*. Without the attribute the same file works both as a UTF-8 file and as a UTF-16 file.
- The action was **redirected through `conhost`**. Because the task runs in the logged-on user's session, launching `powershell.exe` directly flashes a console window on screen for a fraction of a second on every Bluetooth connection, and `-WindowStyle Hidden` does not prevent it (the window is created before PowerShell can hide it). Running `%SystemRoot%\System32\conhost.exe --headless powershell.exe ...` never creates a window at all. The trade-off is that `conhost` always exits with code 0, so the task's "Last Run Result" is no longer meaningful.

`enable_bluetooth_policy.xml` was written by hand along the same lines. It uses `<UserId>S-1-5-18</UserId>` (the `SYSTEM` account), which is safe to hardcode because that SID is identical on every Windows installation. It runs as `SYSTEM` in session 0, where no window can appear, so it calls `powershell.exe` directly.
