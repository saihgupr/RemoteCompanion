# Changelog

All notable changes to this project will be documented in this file.

## [2.0.0~beta3] - 2026-01-29

### Added
- **Search in Action Picker**: Added a search bar to the Action Selection menu, allowing users to quickly find actions by name or command.

### Fixed
- **Ringer Trigger**: Fixed an issue where ringer actions would fire on respring/reboot based on the current switch position. Actions now only fire when the state actually changes.

## [2.0.0~beta2] - 2026-01-29

### Fixed
- **Volume Button Regression**: Fixed an issue where volume buttons became unresponsive to native clicks/holds when no custom volume triggers were assigned. The system now correctly passes through events when triggers are disabled.

## [2.0.0~beta1] - 2026-01-29

### Added
- **Ringer Switch Automation**: Triggers for muting, unmuting, and toggling the ringer switch (works with hardware switch and Control Center).
- **Respring Action**: Added a native "Respring Device" action to the UI and improved the `respring` command reliability by using `killall backboardd`.

### Fixed
- **Open App Action**: Fixed "Open App" action failing by restoring the missing `uiopen` command handler in the Tweak.
- **Custom Command Repair**: Fixed "Custom Command" actions failing when using `rc <command>` by intercepting the `rc` prefix and executing it internally.

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
- **Custom Command**: You can now use `rc open Music` (or any other `rc` command) directly in the Custom Command action to open apps or trigger any system action.
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
