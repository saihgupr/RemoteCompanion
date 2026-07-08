# RemoteCompanion

RemoteCompanion provides fast, scriptable system control for modern rootless jailbreaks. It lets you bind physical gestures and hardware buttons, or send commands remotely from your computer, to trigger system actions, control media playback, and run custom scripts.

> [!IMPORTANT]
> **What’s New in v3.4.0**
> - **Proximity Sensor & Pocket Detection**: Bind actions based on device coverage/pocket states, auto-enabling during power button holds for zero standby battery drain.
> - **Dynamic Web UI Port Selection**: Scans sequentially (8080-8099) to bind the first available port, preventing conflicts with other background web servers.
> - **Action Sequence Play Button & Else If Blocks**: Test/simulate sequences instantly with a play button in the iOS app, and build nested, sequential `else_if` logic blocks.
> - **Native-Style HUD Toasts**: Dropdown spring-physics toasts to confirm toggled states system-wide, featuring robust handling to resolve rapid-fire click conflicts.
> - **Cellular Data Control**: Enable, disable, or query cellular data natively via CLI commands, Web UI triggers, and action workflow condition evaluations.
> - **Kill App & AudioMix Actions**: Force-close apps natively with a high-fidelity iOS-style autocomplete UI, and toggle/query KingPuffdaddi's AudioMix tweak state.


<p align="center">
  <img src="images/IMG_1514.PNG" width="160" alt="Main Interface" />
  <img src="images/IMG_1515.PNG" width="160" alt="Action Picker" />
  <img src="images/IMG_1517.PNG" width="160" alt="Design Engine" />
  <img src="images/IMG_1518.PNG" width="160" alt="Settings & Backup" />
  <img src="images/IMG_1516.PNG" width="160" alt="Trigger Config" />
</p>

## Features
- **Hardware Triggers**: Bind actions to Power/Volume buttons, Home button, Touch ID (Tap/Hold), or the Ringer Switch.
- **Universal Search**: Instantly find actions, shortcuts, and devices with integrated search bars in every picker.
- **Cross-Version Support**: Full compatibility for iOS 14 through iOS 16+, supporting Rootless, Rootful, and RootHide environments.
- **Advanced Automation**: Full support for NFC tags, custom Lua scripts (with `objc_call` support), and native Siri integration.
- **AI-Assisted Scripting**: Use any AI assistant to generate action sequences from plain English — see [SCRIPTING.md](SCRIPTING.md).
- **iPad Experience**: Native landscape orientation and optimized layouts for iPad power users.
- **Live Discovery**: Discovery-based live lists for nearby AirPlay and Bluetooth hardware.
- **Trigger Favorites**: Mark any trigger as a favorite for instant access at the top of the picker.
- **True Multitasking**: Concurrent server handling powered by GCD—zero battery drain, zero blocking.

## Web UI & Automations Hub

Access the desktop-class automation hub at `http://[DEVICE_IP]:8080` from any computer or tablet on your local network.

<p align="center">
  <img src="images/webui.png" width="600" alt="Web UI Interface" />
</p>

> [!TIP]
> **To Enable**: Toggle **Web UI** in the RemoteCompanion Settings (Gear icon) or use the command `rc webui on`.

### Key Features
- **Visual Workflow Editor**: Build complex action sequences with an intuitive drag-and-drop interface.
- **Live Device Discovery**: Dynamically search and select installed Apps, nearby Bluetooth hardware, and Wi-Fi networks using integrated search bars.
- **Remote Testing**: Trigger actions and troubleshoot sequences directly from your browser with live execution buttons.
- **One-Tap API Integration**: Every trigger has a dedicated **Copy API Link** button providing a direct URL to fire that trigger from any network-connected hardware or custom scripts.
- **API Link Copying**: In the Web UI, you can swipe any trigger and tap the **Copy** icon to instantly get the full API URL (including your device's IP).
- **Negligible Battery Impact**: The Web UI server is extremely efficient, consuming zero CPU cycles when idle. It uses a background thread with a blocking `accept()` loop that sits dormant until a connection is made.
- **Configuration Management**: Import and export your entire trigger database for easy backups and migration between devices.

## What you can do

### Media & Volume
- `rc play` / `rc pause` / `rc playpause` / `rc next` / `rc prev`
- `rc volume 0-100` - Set volume level.
- `rc mute [on|off|toggle|status]` - Control media mute state.
- `rc anc [on|off|transparency]` - Control headphone ANC (requires Sonitus).

### Device Control
- `rc lock` / `rc lock toggle`
- `rc unlock <pin>` - Wakes and unlocks the device.
- `rc button [power|lock|home|volup|voldown|mute]` - Simulate physical buttons.
- `rc brightness 0-100` - Set screen brightness.
- `rc flashlight [on|off|toggle]` - Control the torch.
- `rc rotate [lock|unlock|toggle]` - Orientation lock control.
- `rc appearance [dark|light|toggle]` - Set device appearance.
- `rc dnd [on|off|toggle]` - Toggle Do Not Disturb.
- `rc low power mode [on|off|toggle]` - Toggle battery saver.
- `rc airplane [on|off|toggle]` - Control Airplane Mode.
- `rc haptic` / `rc screenshot` - Haptic feedback / Screenshot (or activate Snapper 3).
- `rc control-center` - Opens the system Control Center.
- `rc switcher` - Opens/toggles the App Switcher.
- `rc previous app` / `rc last app` - Returns to the previously active application.
- `rc vibration [silent-toggle|ring-toggle]` - System "Vibrate on Silent/Ring" settings.

### Apps & Shortcuts
- `rc open <alias|bundleID>` (e.g., `youtube`, `spotify`, `settings`, `messages`, `home`, `photos`, `camera`, `clock`, `maps`, `calendar`, `weather`, `notes`, `reminders`, `appstore`, `mail`, `music`, `phone`, `stocks`, `calculator`, `tv`, `wallet`, `facetime`, `files`).
- `rc kill <alias|bundleID>` - Force close an app.
- `rc shortcut -r "Name" [-p "Input"]` - Run any Shortcut (requires SpringCuts).
- `rc url "https://google.com"` - Open any link (with smart unlock).
- `rc spotify <playlist|album|artist> <id>` - Play specific Spotify content.
- `rc spotify play` - Resume Spotify playback.

### Connectivity
- `rc wifi [on|off|toggle]` / `rc cellular [on|off|toggle]` / `rc bluetooth [on|off|toggle]`
- `rc bluetooth [connect|disconnect] <name>` - Manage paired devices.
- `rc airplay list` - See speakers and their UIDs.
- `rc airplay connect <UID|Name>` / `rc airplay disconnect`

<details>
<summary><b>Hardware Triggers (Tweak App)</b></summary>

Configure these in the `RemoteCompanion` app for custom action sequences. Tip: **Long-press** any trigger in the app to instantly test and run its assigned actions.

- **Hardware Buttons**:
  - **Power**: Double-tap, Long-press, **Triple/Quadruple click**, or **Power + Volume Up/Down** combos.
  - **Volume**: Long hold Up/Down (0.3s) or **Volume Up + Down** combo.
  - **Home**: Double-tap (Touch ID), Double, Triple, or Quadruple click.
- **Touch ID Sensor**: **Single Tap** and **Hold (Rest Finger)** triggers.
- **NFC Triggers**: Scan physical NFC tags to run actions on screen wake (Optional toggle in Settings).
- **Ringer Switch**: Mute, Unmute, or Toggle triggers.
- **Gestures**: 
  - **Status Bar**: Hold (Left/Center/Right) or Swipe Left/Right.
  - **Edge Gestures**: Vertical swipe on left/right edges.
- **Motion Gestures**:
  - **Shake**: Fire actions when the device is physically shaken.
- **System Events**:
  - **Scheduled**: Run actions at specific times (e.g., Daily at 4 PM).
  - **WiFi/Bluetooth**: Trigger actions on network or device connectivity.
  - **App Launch**: Fire actions when a specific app is opened.

</details>

<details>
<summary><b>Blacklist (App Exclusion)</b></summary>

RemoteCompanion includes a blacklist system to prevent hardware triggers and gestures from firing while specific apps are in the foreground. This is useful for avoiding conflicts with apps that use the same buttons or gestures (e.g. games, camera apps).

### CLI Commands
Use the `rc blacklist` command to manage the list:

*   `rc blacklist list`: View currently blacklisted bundle IDs.
*   `rc blacklist add <bundleID>`: Add an app to the blacklist (e.g. `rc blacklist add com.apple.camera`).
*   `rc blacklist remove <bundleID>`: Remove an app from the blacklist.
*   `rc blacklist reset`: Reset the blacklist to the factory defaults.

</details>

### Text & Notifications
- `rc type "Text"` - Type text (supports symbols).
- `rc paste "Text"` - Paste into clipboard.
- `rc toast "Title" ["Subtitle"] ["SF Symbol"]` - Display a HUD toast notification. Note: use single quotes if passing special characters like `!` to prevent shell history expansion (e.g., `rc toast "Hello" 'World!'`).
- `rc key <hex>` - Specific keyboard keys (e.g., `0x04` for 'A', `0x28` for Enter).
- `rc log` - View the RemoteCompanion server logs.

### Status & Queries
Get instant feedback from your device state.

- `rc volume` - Returns current volume %.
- `rc app` - Returns foreground app bundle ID.
- `rc is-locked` / `rc lock status` - Returns `locked` or `unlocked`.
- `rc player status` - Returns detailed playback state (`Playing`, `Paused`, `Stopped`, etc.).
- `rc mute status` - Returns current media mute state and level.
- `rc logs` - Stream live debug logs from the device (tail `/tmp/remotecommand.log`).
- `rc vibration [silent-status|ring-status]` - Check current system vibration state (CLI only).
- `rc orientation status` - Returns `PORTRAIT` or `LANDSCAPE`.
- `rc rotate status` - Returns orientation lock state.
- `rc dnd status` - Returns Do Not Disturb state.
- `rc lpm status` - Returns Low Power Mode state.
- `rc airplane status` - Returns Airplane Mode state.
- `rc wifi status` / `rc cellular status` / `rc bt status` - Returns connectivity states.
- `rc flashlight status` - Returns torch state.
- `rc proximity` - Returns `near` or `far`. *(Note: iOS powers off the sensor when the screen is asleep. To test manually while the screen is awake, run `rc proximity on` to force it active, then `rc proximity off` to disable it.)*

<details>
<summary><b>Conditional Actions</b></summary>

Combine status queries with actions for smart automation:

- **Pocket/Proximity-Awareness**: `If Proximity Sensor is Near (Covered / Pocket)` -> `Skip Action` (perfect for preventing accidental pocket flashlight activation).
- **Orientation-Awareness**: `If Orientation is Landscape` -> `Flashlight Toggle`.
- **Bluetooth/Wi-Fi State**: `If Wi-Fi is OFF` -> `Wi-Fi ON`.

> [!NOTE]
> **Proximity Sensor Cooldown**: To conserve battery, the proximity sensor is only powered on dynamically during button holds and is shut off immediately on release. Due to iOS kernel-level hardware power-gating, rapid consecutive clicks (within ~5 seconds) may temporarily bypass proximity evaluation until the sensor's hardware cooldown window resets.

</details>

### System & Diagnostics
- `rc uicache` - Refresh the icon cache.
- `rc respring` - Restart SpringBoard.
- `rc ldrestart` - Soft-reboot the device.
- `rc userspace-reboot` - Restart userspace.
- `rc webui [on|off|status]` - Enable, disable, or check the status of the Web UI server.




## Getting Started

<details>
<summary><h3>1. Requirements</h3></summary>

- A **Jailbroken Device** (iOS 14+). Supports Rootless (iOS 15+), Rootful (iOS 14), and RootHide environments.
- The `RemoteCompanion` tweak installed.

</details>

### 2. Installation Options

#### Option 1: Repository (Recommended)
Add `https://saihgupr.github.io/remotecompanion` to Sileo or Zebra

Add to Zebra -> zbra://sources/add/https://saihgupr.github.io/remotecompanion

Add to Sileo -> sileo://source/https://saihgupr.github.io/remotecompanion

#### Option 2: Manual Install
Download the `.deb` from [Releases](https://github.com/saihgupr/remotecompanion/releases).

#### Option 3: Build from Source
`cd Tweak && make package install`.

<details>
<summary><b>3. Usage Options</b></summary>

Choose the control method that best fits your needs:

#### Option 1: CLI (Easiest)
Control your iPhone from your computer terminal using the `rc` script. It uses SSH to securely tunnel commands into a local UNIX socket on the device.

1. Copy the script to your path:
   ```bash
   chmod +x rc
   sudo cp rc /usr/local/bin/rc
   ```
2. Set your iPhone's IP (add this to your `~/.zshrc`):
   ```bash
   export RC_IPHONE_IP=iphone.local
   ```
3. Run the command:
   ```bash
   rc play
   ```

#### Option 2: SSH Direct (Secure)
Control the device directly via SSH using the `rc` command installed on the iPhone.
This method works even if the external "TCP Server" is disabled in settings.

```bash
ssh mobile@iphone.local "rc lock"
ssh mobile@iphone.local "rc volume 50"
ssh mobile@iphone.local "rc respring"
```

<details>
<summary><h4>Option 3: Shortcuts (External Triggers)</h4></summary>

Control your device using iOS Shortcuts. There are two primary ways:

**A. Using Native SSH (Localhost)**
The most reliable method without extra tweaks. Requires **OpenSSH**.
1. Add the **Run script over SSH** action.
2. Configure host settings:
   - **Host**: `localhost`
   - **Port**: `22`
   - **User**: `mobile` (or `root`)
   - **Password**: Your SSH password (default is `alpine`)
3. Enter your command:
   ```bash
   rc flashlight toggle
   rc dnd on
   ```

**B. Using Powercuts (Shell)**
If you have **Powercuts** installed, you can run `rc` commands directly via shell.
1. Add the **Run shell command** action.
2. Enter your command:
   ```bash
   rc open Music
   rc volume 50
   ```


</details>

</details>


## Advanced Developer Tools

<details>
<summary><b>Lua Scripting & Objective-C Bridge</b></summary>


RemoteCompanion introduces a powerful Lua bridge that allows you to execute arbitrary Lua scripts within the tweak's process. The exact same context is available whether you run a script file from the CLI or paste code into the "Lua Script" action in the app.

### How to Run
- **From CLI**: `rc lua /path/to/script.lua`
- **From UI**: Add Action → System → **Custom Lua Script**. Paste your code directly into the prompt.

### API Bindings

| Function | Description |
| :--- | :--- |
| `log(msg)` | Writes to the system log (syslog). |
| `delay(seconds)` | Pauses execution for `seconds`. |
| `haptic()` | Triggers a standard haptic feedback. |
| `openURL(url)` | Opens a URL scheme (e.g. `prefs:root=General`). |
| `dlopen(path)` | Loads a dynamic library. Returns `true` on success. |
| `objc_call(target, selector, args...)` | Calls an Objective-C method. `target` can be a class name string or an instance. |

### Examples

**Trigger Haptic and Log**
```lua
log("Starting haptic engine...")
haptic()
delay(0.2)
haptic()
log("Finished haptic feedback.")
```

**Call a Class Method (get a shared instance)**
```lua
-- objc_call(className, selector) returns an instance
local device = objc_call("UIDevice", "currentDevice")
if device then
    objc_call(device, "setBatteryMonitoringEnabled:", true)
    local level = objc_call(device, "batteryLevel")
    log("Battery: " .. tostring(level * 100) .. "%")
end
```

> [!NOTE]
> `objc_call` works like standard Objective-C messaging — it does not scan memory for existing instances. To call an instance method, you first need to obtain the instance via a class-level accessor (e.g. `sharedInstance`, `currentDevice`) or by allocating a new one with `alloc`/`init`.

</details>

<details>
<summary><b>AI-Assisted Sequence Builder</b></summary>

Use any AI assistant (ChatGPT, Claude, Gemini, etc.) to build action sequences from plain English, then paste the result directly into the app using **Import**.

**[→ Full guide + copy-paste AI prompt: SCRIPTING.md](SCRIPTING.md)**

Example prompt:
```
Read this guide: https://github.com/saihgupr/remotecompanion/blob/main/SCRIPTING.md

Using the action format defined there, create a RemoteCompanion sequence that:
pause music, wait 2 seconds, take a screenshot, then play music again

Return ONLY the raw JSON array. No explanation, no markdown, no code fences.
```

Copy the JSON output → open your trigger → tap **⋯** → **Import** → paste → **Import**.

</details>

<details>
<summary><b>Automations API & HTTP Server</b></summary>

Control your device from any network-connected hardware via simple HTTP calls.

> [!IMPORTANT]
> The **Web UI** toggle must be enabled in the RemoteCompanion settings (or via `rc webui on`) for the HTTP server to be active.

**1. Discover Commands & Triggers:**
Get a list of all supported system commands or your custom automation triggers:
- Commands: `http://[device_ip]:8080/api/commands`
- Triggers: `http://[device_ip]:8080/api/triggers`

**2. Execute a System Command:**
Send command strings via `GET` or `POST`. 
- **Example (GET)**: `http://[device_ip]:8080/api/command?cmd=play`
- **Example (POST)**: `curl -X POST "http://[device_ip]:8080/api/command" -d "haptic"`

**3. Fire an Automation Trigger:**
Execution URLs for your specific triggers:
- **Example**: `http://[device_ip]:8080/api/trigger/trigger_1`

#### Performance & Implementation
*   **⚡ Speed**: The HTTP API is significantly faster than SSH (~0.1s faster) by skipping the heavy SSH handshake.
*   **🔋 Efficiency**: The Web UI server sits in a dormant `accept()` loop, consuming **zero CPU cycles** when idle.
</details>

<details>
<summary><b>Home Assistant Setup</b></summary>

The most reliable way to control your device from Home Assistant is via SSH.

```yaml
shell_command:
  iphone_remote: >
    ssh -o "StrictHostKeyChecking=no" mobile@YOUR_IPHONE_IP "rc {{ cmd }}"
```
Then call it with:

```yaml
service: shell_command.iphone_remote
data:
  cmd: 'play'
```

</details>

## Security

RemoteCompanion implements several measures to ensure your device remains secure:

- **Local Execution**: Local apps and the `rc` CLI communicate securely via a local UNIX socket file, ensuring zero network exposure.
- **Web UI & Automations API**: When enabled, the Automations Hub server transmits data in **plain-text** over your local network. No authentication is required for API access. It is **highly recommended** to only enable the Web UI on trusted, private networks.

<details>
<summary><h2>Troubleshooting</h2></summary>

### Apple Pay Issues
If you experience the "Updating Cards" screen or other conflicts with Apple Pay when waking your device, you can disable the background NFC scanning feature.
1. Go to the **Settings** tab (gear icon).
2. Toggle off **NFC Scanning**.

This ensures the tweak does not attempt to access the NFC controller on wake, resolving conflicts with system services.

### iOS 14 arm64e (A12+) Compatibility
Due to Pointer Authentication Code (PAC) changes in modern toolchains, iOS 14 on **arm64e (A12 and newer)** devices is currently unsupported and may cause a Safe Mode loop.
- **Supported**: iOS 14 on A11 and below (iPhone 8/X and older, iPad Air 2, etc.)
- **Supported**: iOS 15+ on all devices.
- **Workaround**: If you are on iOS 14 with a newer device, you may need to compile the tweak using **Xcode 15.4** or earlier to ensure correct PAC signatures.

</details>


## Support & Feedback

If you encounter any issues or have feature requests, please [open an issue](https://github.com/saihgupr/remotecompanion/issues) on GitHub.

RemoteCompanion is open-source and free. If you find it useful, consider giving it a star ⭐ or making a [donation](https://ko-fi.com/saihgupr) to support development.