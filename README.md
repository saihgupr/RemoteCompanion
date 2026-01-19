# RemoteCompanion

A high-performance remote control system for jailbroken iOS devices. It allows you to trigger media controls, system actions, and Shortcuts instantly from your computer or Home Assistant via TCP.

## Requirements
- **Rootless Jailbroken Device** (iOS 15+)

## Features

- **Instant Response**: Uses a lightweight TCP server tweak (`RemoteCompanion`) for sub-millisecond latency.
- **Safe Execution**: complicated actions (like Shortcuts) are offloaded to a background script (`rc_server.sh`) to prevent SpringBoard crashes/Safe Mode.
- **Home Assistant Ready**: Works natively with HA `shell_command` using `nc` (Netcat).

## Supported Commands

These commands can be sent to `iphone.local:1234` via TCP.

### Media Controls
- `play` / `pause` / `next` / `prev` / `playpause`

### System Controls
- `bluetooth on` / `bluetooth off`
- `bluetooth connect <name>` / `bluetooth disconnect <name>` - Connect/disconnect paired Bluetooth device
- `wifi on` / `wifi off`
- `brightness <0-100>` - Set screen brightness
- `haptic` - Trigger haptic tap
- `flashlight on` / `flashlight off` / `flashlight toggle`
- `rotate status` - Get orientation lock status
- `rotate lock` / `rotate unlock` - Toggle orientation lock
- `anc on` / `anc off` / `anc transparency` - Control headphone ANC (requires Sonitus)
- `unlock <pin>` - Unlock device (wakes screen). i.e. `unlock 1234`
- `lock` - Lock device
- `lock toggle` - Toggle between locked and unlocked state
- `lock status` - Check lock state (returns "locked" or "unlocked")
- `dnd on` / `dnd off` - Toggle Do Not Disturb (Focus Mode)
- `low power mode on` / `low power mode off` - Toggle Low Power Mode
- `airplane on` / `airplane off` / `airplane toggle` - Control Airplane Mode

### AirPlay
- `airplay list` - List available AirPlay devices with names and UIDs
- `airplay connect <UID>` - Connect to an AirPlay device by UID (from list output)

**AirPlay Workflow:**
```bash
rc airplay list              # Get list of devices and UIDs
# Output: Computer Speaker : 123ABC-456DEF

rc airplay connect 123ABC-456DEF   # Connect to that device by UID
rc airplay connect "Computer Speaker"   # Connect to that device by name
```

### Text Input
- `type "<text>"` - Type text (supports uppercase and symbols)

### Hardware Buttons
- `button power` / `button lock` - Simulate Power/Lock button
- `button home` - Simulate Home button
- `button volup` - Simulate Volume Up
- `button voldown` - Simulate Volume Down
- `button mute` - Simulate Mute toggle
- `key <usage_hex>` - Simulate specific keyboard key (e.g. `key 0x04` for 'A', `key 0x28` for Enter)

### Hardware Triggers (RemoteCompanion App)
Configure these triggers via the companion app to execute custom action sequences:

**Home Button:**
- `Home Button Double Tap` - Double-tap Home button (Touch ID).
    - **Requirement:** "Reachability" must be ENABLED in Settings > Accessibility > Touch.
    - **Behavior:** Suppresses the default screen lowering when a custom action is triggered.

**Volume Buttons:**
- `Volume Up Hold` - Hold Volume Up for 0.3s
- `Volume Down Hold` - Hold Volume Down for 0.3s

**Power Button:**
- `Power Double-Tap` - Double-tap the power button
- `Power Long Press` - Long press the power button

**Status Bar Gestures:**
- `Status Bar Left Hold` - Hold left side (first 50pts) for 0.3s
- `Status Bar Center Hold` - Hold center area for 0.3s  
- `Status Bar Right Hold` - Hold right side (last 50pts) for 0.3s
- `Status Bar Swipe Left` - Swipe left across status bar (80pt+ movement)
- `Status Bar Swipe Right` - Swipe right across status bar (80pt+ movement)

**Edge Gestures:**
- `Left Edge Swipe Up/Down` - Vertical swipe within 50pt of the left edge
- `Right Edge Swipe Up/Down` - Vertical swipe within 50pt of the right edge

#### Available Action Types:
You can assign sequences of actions to any trigger, including:
- **Media**: Play, Pause, Play/Pause, Next/Prev Track, Volume Up/Down
- **Device**: Flashlight, Rotation Lock, Screenshot, Haptic Feedback
- **Connectivity**: WiFi, Bluetooth, AirPlay Disconnect
- **System**: DND, Low Power Mode, Lock Device, ANC Modes
- **App**: Open App, Run Shortcut, Execute Terminal Command

### App Interface

<p align="center">
  <img src="images/IMG_1331.PNG" width="250" />
  <img src="images/IMG_1332.PNG" width="250" />
  <img src="images/IMG_1333.PNG" width="250" />
</p>
<p align="center">
  <img src="images/IMG_1334.PNG" width="250" />
  <img src="images/IMG_1336.PNG" width="250" />
  <img src="images/IMG_1338.PNG" width="250" />
</p>

### Volume/Mute Control
- `mute [on|off|status]` - Control media mute state (uses Volume 0%).
- `volume [0-100]` - Set system volume percentage.
- `volume` - Get system volume percentage.

### URL & App Management
- `spotify playlist <id>` - Open and play a Spotify playlist (e.g. `rc spotify playlist 37i9dQZEVXcD7gSzbo8drB`)
- `url <link>` - Open a URL (e.g. `rc url https://google.com`)
    - **Smart Unlock**: Automatically wakes and unlocks device (PIN 2569) if locked before opening.
- `open <bundleID>` - Open an app by bundle ID (e.g. `rc open com.apple.Preferences`)
    - **Supported Aliases**: `youtube`, `spotify`, `settings`, `safari`, `messages`, `home`, `photos`, `camera`, `clock`, `maps`, `calendar`, `weather`, `notes`, `reminders`, `appstore`, `mail`, `music`, `phone`, `stocks`, `calculator`, `tv`, `wallet`, `facetime`, `files`.
- `kill <bundleID>` - Force close an app (e.g. `rc kill com.apple.Preferences`)
    - Also supports the aliases above.
- `app` - Get bundle ID of the current foreground app
- `paste "<text>"` - Paste text into clipboard
- `screenshot` - Take a screenshot

### Push Notifications (via ntfy)
Send push notifications to your iPhone and Apple Watch from the terminal.

```bash
rc notify -t "Title" -m "Message"           # Standard notification
rc notify -t "Alert!" -m "Urgent" -p urgent # Max priority
rc notify -t "Info" -m "FYI" -p low         # Quiet notification
```

**Options:**
- `-t` / `--title` - Notification title
- `-m` / `--message` - Notification body
- `-p` / `--priority` - Priority level: `min`, `low`, `default`, `high` (default), `urgent`
- `-i` / `--icon` - Custom icon URL

**Setup:**
1. Install [ntfy](https://apps.apple.com/app/ntfy/id1625396347) from the App Store
2. Subscribe to topic: `remotecompanion-notify`
3. Send notifications from your Mac!

### Shortcuts (Handled by Helper Script)
- `shortcut -r "My Shortcut Name"`
- `shortcut -r "My Shortcut Name" -p "Input Arguments"` 

## Installation

### 1. RemoteCompanion Tweak
Compile and install the tweak to your iPhone.
```bash
cd Tweak
make package install
```
*Requires Theos and a jailbroken device.*

### 2. Helper Script (rc_server.sh)
This script runs in the background to handle Shortcuts safely.
```bash
./deploy.sh
```
*This will copy `rc_server.sh` to `/var/mobile/` and start it.*

## Usage

### Quick CLI (Recommended)
Install the `rc` command for easy access:
```bash
sudo cp /usr/local/bin/rc /usr/local/bin/  # Already installed if you used the setup
```

Then simply:
```bash
rc button power      # Press power button
rc play              # Play media
rc shortcut "Name"   # Run a shortcut
rc anc transparency  # Set ANC mode
```

Configure via environment variables:
```bash
export RC_IPHONE_IP=192.168.1.2  # Your iPhone's IP
```

### From Terminal (Mac/Linux)
Use the included client script:
```bash
rc pause
rc shortcut -r "Turn Lights On"
```

Or using raw Netcat (`nc`):
```bash
echo -n "pause" | nc -w 1 iphone.local 1234
```

### From Home Assistant

Usage:
```yaml
service: shell_command.iphone_remote
data:
cmd: 'play'
```

**Shell_Command:**
```yaml
shell_command:
  iphone_remote: 'echo -n "{{ cmd }}" | nc -w 1 192.168.1.2 1234'
```