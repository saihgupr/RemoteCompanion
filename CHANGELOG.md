# Changelog

All notable changes to this project will be documented in this file.

## [2.0.0] - 2026-02-02

### Fixed
- **Safe Mode Crash**: Resolved a race condition and main-thread violation when re-enabling triggers from Settings.

## [1.1.2] - 2026-01-30

### Fixed
- **Volume Button Responsiveness**: Improved reliability of native volume buttons when custom triggers are disabled.

## [1.1.1] - 2026-01-29

### Fixed
- **Open App Action**: Fixed "Open App" action failing by restoring the missing `uiopen` command handler in the Tweak.
- **Custom Command Repair**: Fixed "Custom Command" actions failing when using `rc <command>` by intercepting the `rc` prefix and executing it internally.

## [2.0.0~beta5] - 2026-01-31

### UI Overhaul (Visual Refresh)
- **Modern Header**: Updated the main navigation bar to use Large Titles with a native translucent blur effect (frosted glass), moving away from the "web-view" look.
- **Improved Readability**: Command strings (like `curl`) now use a Monospace font and are middle-truncated (e.g., `curl -X...7DB5fjv`) to keep the UI clean.
- **Visual Contrast**: Added SF Symbols (icons) to every trigger row for faster scanning.
- **Section Polish**: Refined section headers with smaller, all-caps styling and better spacing.
- **Action Sequence**: Overhauled the action list with Large Titles, subtitle-style rows for commands (showing code neatly), and a proper Edit button.
- **Action Selection**: Updated the "Add Action" screen with Large Titles, larger touch targets (60pt), and visual cues (chevrons) for actions that require input.
- **Settings**: Polished the Settings page with Large Titles, consistent headers, and a **sticky footer** for version info.
- **App Icon**: Updated with a new modern design and flattened assets to resolve system rendering artifacts.
- **NFC Scanning Toggle**: Added a toggle in Settings to enable/disable NFC scanning, preventing conflicts with Apple Pay.

## [2.0.0~beta4] - 2026-01-30

### Removed
- **Volume Combo Trigger**: Removed "Volume Up + Down" trigger due to conflicts with NFC scanning logic.
    - **Home Button (Double Tap)**: Removed this trigger to prevent conflicts with native Reachability and improve system stability. Since Double Click exists, Double Tap (Touch) was redundant and problematic.

### Added
- **Siri Activation**: Added the `button siri` command and a native "Activate Siri" action in the Action Picker. Uses a robust multi-stage activation sequence (HID + Programmatic Fallbacks) for maximum reliability on iOS 15+.
- **Power + Volume Triggers**: Added support for **Power + Volume Up** and **Power + Volume Down** combos.
- **Touch ID Triggers**: Added support for **Single Tap** and **Hold** triggers on Touch ID devices.
- **Shortcuts Picker Search**: Added a search bar to the "Select Shortcut" screen, making it easier to find specific shortcuts in your library.
- **UI Polish**: Shortcuts picker icons now match the system accent color (grey).

### Fixed
- **Touch ID Stability**: Fixed a crash related to background thread event access in the biometric handler.
- **Rootless Injection (iOS 15)**: Fixed a critical architecture mismatch in the Tweak control file (`iphoneos-arm` -> `iphoneos-arm64`) that prevented the tweak from loading on rootless jailbreaks.
- **Shortcuts Menu Regression**: Fixed an issue where selecting "Run Shortcut..." would immediately close the menu without showing the picker.
- **Search Selection Bug**: Fixed a bug where selecting an action from search results in the Action Picker would fail to correctly dismiss the view.

## [2.0.0~beta3] - 2026-01-29

### Added
- **Search in Action Picker**: Added a search bar to the Action Selection menu, allowing users to quickly find actions by name or command. 
- **UI Polish**: Reduced the header gap in the Action Selection menu for a cleaner look. 

### Fixed
- **Ringer Trigger**: Fixed an issue where ringer actions would fire on respring/reboot based on the current switch position. Actions now only fire when the state actually changes.

## [2.0.0~beta2] - 2026-01-29

### Added
- **Ringer Switch Automation**: Triggers for muting, unmuting, and toggling the ringer switch (works with hardware switch and Control Center).
- **Respring Action**: Added a native "Respring Device" action to the UI and improved the `respring` command reliability by using `killall backboardd`.

## [1.1.0] - 2026-01-29

### Added
- **Volume Combo Trigger**: Added support for **Volume Up + Down** simultaneous press.

### Fixed
- **NFC Scanning Regression**: Resolved an issue where NFC scanning would fail to start after waking the device by reverting conflicting HID listener changes in `Tweak.x`.
- **System Resource Unavailable**: Fixed error when adding tags in the App by restoring IPC callbacks to properly release NFC hardware.

## [1.0.4] - 2026-01-28

### Added
- **Home Button Triggers**: Added support for **Double Click**, **Triple Click**, and **Quadruple Click**.
- **Improved Multi-Click Detection**: Re-engineered logic to handle rapid multi-clicks reliably without interference.
- **Open App Action**: New application picker to launch any installed app directly from a trigger.
- **Native RC Commands**: Run `rc` commands directly from the terminal or the Custom Command action.
- **Connectivity Toggles**: Wi-Fi and Bluetooth toggle commands (`wifi toggle`, `bluetooth toggle`).

### Fixed
- **Apple Pay Conflict**: Fixed "System Failure" when using Apple Pay by moving logging to an asynchronous background queue, eliminating main-thread blocking.
- **UI Consistency**: Fixed missing labels and sections for new triggers in the app.

## [1.0.3] - 2026-01-22

### Added
- Shortcuts (via Powercuts)
- **Custom Command**: You can now use `rc haptic` / `rc screenshot` / `rc siri` (or any other `rc` command) directly in the Custom Command action to open apps or trigger any system action.
- **Settings UI**: Added version label (e.g., `v1.0.3`) to the bottom of the Settings menu.
- **Improved Layout**: Refactored Settings screen to pin the version label to the bottom of the view, ensuring consistent positioning regardless of screen size.
- **UI Details**: Matched version label styling to native table view footers (font, color).

### Fixed
- **Home Button Interference**: Fixed an issue where the Double Click trigger would fire before you could complete a Triple Click. Double Click now waits briefly if Triple Click is enabled.

## [1.0.2] - 2026-01-22

### Added
- **Toggle Support**: Added `toggle` command for various system features:
  - Low Power Mode (`rc lpm toggle`)
  - Do Not Disturb (`rc dnd toggle`)
  - Orientation Lock (`rc orientation toggle`)
  - Mute (`rc mute toggle`)
- **Better SpringCuts Error Handling**: Added user-friendly notifications and UI alerts if SpringCuts is missing instead of silent failure.

### Fixed
- **UI Consistency**: Fixed missing icons for new toggle commands in the action sequence list.
- **Custom Command Flexibility**: Supported `rc` and `sudo` prefixes in custom commands, allowing commands like `rc open Music` to work directly from the app.
- **Improved Labels**: Renamed "Vol Up/Down" to "Volume Up/Down" in the main panel for better clarity.
- **Edge Gesture Interference**: Fixed issue where edge gestures would interfere with native iOS gestures (Back gesture, swipe-to-type, etc.) even when disabled.

### Changed
- Bumped version to 1.0.2.
