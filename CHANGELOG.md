# Changelog

All notable changes to this project will be documented in this file.

## [1.1]

### Added
- Shortcuts (via Powercuts)
- **Custom Command**: You can now use `rc open Music` (or any other `rc` command) directly in the Custom Command action to open apps or trigger any system action.

## [1.0.3] - 2026-01-22

### Added
- **Settings UI**: Added version label (e.g., `v1.0.3`) to the bottom of the Settings menu.
- **Improved Layout**: Refactored Settings screen to pin the version label to the bottom of the view, ensuring consistent positioning regardless of screen size.
- **UI Details**: Matched version label styling to native table view footers (font, color).

## [1.0.2] - 2026-01-22

### Added
- **Toggle Support**: Added `toggle` command for various system features:
  - Low Power Mode (`rc lpm toggle`)
  - Do Not Disturb (`rc dnd toggle`)
  - Flashlight (`rc flashlight toggle`)
  - Orientation Lock (`rc orientation toggle`)
  - Mute (`rc mute toggle`)
- **Better SpringCuts Error Handling**: Added user-friendly notifications and UI alerts if SpringCuts is missing instead of silent failure.
- **Sileo Compatibility**: Added SHA256 checksums and ZST compression to the repository metadata to fix 404 errors in Sileo.

### Fixed
- **UI Consistency**: Fixed missing icons for new toggle commands in the action sequence list.
- **Custom Command Flexibility**: Supported `rc` and `sudo` prefixes in custom commands, allowing commands like `rc open Music` to work directly from the app.
- **Improved Labels**: Renamed "Vol Up/Down" to "Volume Up/Down" in the main panel for better clarity.
- **Edge Gesture Interference**: Fixed issue where edge gestures would interfere with native iOS gestures (Back gesture, swipe-to-type, etc.) even when disabled.

### Changed
- Bumped version to 1.0.2.
