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
- **Sileo Compatibility**: Added SHA256 checksums and ZST compression to the repository metadata to fix 404 errors in Sileo.

### Fixed
- **Edge Gesture Interference**: Fixed issue where edge gestures would interfere with native iOS gestures (Back gesture, swipe-to-type, etc.) even when disabled.
- **Improved Repository Metadata**: Fixed issues with repository refreshing in modern package managers.

### Changed
- Bumped version to 1.0.2.
