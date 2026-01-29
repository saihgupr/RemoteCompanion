# Title
[Update] [Free Release] RemoteCompanion v1.1 - The Activator replacement for modern rootless jailbreaks. Now with Improved Home Button Gestures.

# Body
RemoteCompanion brings fast, scriptable system control and automation to modern rootless jailbreaks. 

I've just released v1.1 which adds several highly requested hardware triggers and better connectivity controls.

**What's New in v1.1:**
- New Hardware Triggers: Home Button clicks (Double, Triple, and Quadruple).
- Smart App Picker: Search and select any installed app directly within the trigger config.
- Connectivity Toggles: Dedicated actions for Wi-Fi, Bluetooth, DND, Low Power Mode, Orientation Lock, and Mute.
- Powercuts Support: Full compatibility with Powercuts to trigger any RemoteCompanion action directly from iOS Shortcuts.
- Native CLI: The `rc` command can now be used directly on-device for local scripting.

**Full Feature List:**
- AirPlay & Bluetooth Connect / Disconnect
- NFC Scanning Triggers (scans on screen wake)
- System Controls: Wi-Fi, Bluetooth, Brightness, DND, Airplane Mode, LPM, Flashlight, Rotation Lock
- Media Controls: Play / Pause, Next / Previous, Volume, Mute
- Text Input, Hardware Button Simulation, HID Key Codes
- ANC Control (On / Off / Transparency via Sonitus)
- Script Execution (Bash & Lua)
- Companion App for Binding Physical Triggers to Actions
- Power, Volume, Home Button, Status Bar, and Edge Gestures Supported
- Custom Action Sequences per Trigger
- Sub-Millisecond TCP Command Execution or SSH

**Tested on:**
- iPhone 7 Plus, iOS 15.8.5, Dopamine (rootless)
- Works on iOS 15, 16, and 17.

I decided to make this app open-source and free. Donate if you like.

[https://github.com/saihgupr/RemoteCompanion](https://github.com/saihgupr/RemoteCompanion)

# First Comment
For the technical crowd: the TCP server is built to be extremely minimal to avoid the latency and overhead of SSH. This is ideal if you are triggering actions from a PC or Home Assistant and want them to feel instant.

I've included a script called `rc` in the repo that you can use on your computer to control the phone over the network. 

Setup guide: [https://github.com/saihgupr/RemoteCompanion#usage-options](https://github.com/saihgupr/RemoteCompanion#usage-options)
