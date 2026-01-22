# Changelog

All notable changes to this project will be documented in this file.

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
- **Improved Labels**: Renamed "Vol Up/Down" to "Volume Up/Down" in the main panel for better clarity.
- **Edge Gesture Interference**: Fixed issue where edge gestures would interfere with native iOS gestures (Back gesture, swipe-to-type, etc.) even when disabled.

### Changed
- Bumped version to 1.0.2.
