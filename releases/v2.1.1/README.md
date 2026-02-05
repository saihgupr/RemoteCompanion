# RemoteCompanion v2.1.1 Release

## What's Fixed

This release fixes installation issues on **Bootstrap Roothide** and other rootless jailbreaks.

### Changes
- ✅ **Fixed dpkg installation failure** - Added proper DEBIAN scripts (preinst, postinst, prerm) to create directories automatically
- ✅ **arm64e Support** - Package now natively supports both arm64 and arm64e architectures
- ✅ **Universal Compatibility** - Works on both rootless (`/var/jb/Applications`) and rootful (`/Applications`) layouts

## Downloads

### Rootless (iOS 15+)
**File:** `RemoteCompanion_2.1.1_rootless.deb`

Compatible with:
- Dopamine
- palera1n (rootless mode)  
- NathanLR
- Bootstrap Roothide (fixed in this version!)
- Most modern jailbreaks on iOS 15+

### Installation
```bash
# Via package manager (Zebra, Sileo, Cydia)
Add repo: https://saihgupr.github.io/RemoteCompanion

# Or manual installation
dpkg -i RemoteCompanion_2.1.1_rootless.deb
uicache -a
```

## Changelog

- **Installation Failure on Rootless Jailbreaks**: Added proper `preinst`, `postinst`, and `prerm` scripts to fix dpkg "No such file or directory" error on Bootstrap Roothide and other rootless jailbreaks
- **arm64e Support**: Package now properly supports both arm64 and arm64e architectures without requiring manual conversion
- Directory creation is now automatic for both rootless and rootful layouts

## Reporting Issues

If you encounter any problems, please [open an issue](https://github.com/saihgupr/RemoteCompanion/issues) with:
- Your jailbreak name and version
- iOS version
- Device model
- Error messages or screenshots
