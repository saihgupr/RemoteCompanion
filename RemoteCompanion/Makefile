FINALPACKAGE=1
THEOS ?= /opt/theos
ARCHS = arm64 arm64e
TARGET := iphone:clang:latest:14.0
THEOS_PACKAGE_SCHEME ?= rootless

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = RemoteCompanion

RemoteCompanion_FILES = main.m RCAppDelegate.m RCConfigManager.m RCTriggersViewController.m RCActionsViewController.m RCActionPickerViewController.m RCSettingsViewController.m RCNFCTriggerViewController.m RCShortcutPickerViewController.m RCTextInputViewController.m RCAppPickerViewController.m RCServerClient.m
RemoteCompanion_FRAMEWORKS = UIKit Foundation UserNotifications CoreNFC MobileCoreServices
RemoteCompanion_CFLAGS = -fobjc-arc
RemoteCompanion_CODESIGN_FLAGS = -SEntitlements.plist
RemoteCompanion_RESOURCE_FILES = Info.plist AppIcon60x60@2x.png AppIcon60x60@3x.png Entitlements.plist
RemoteCompanion_INSTALL_PATH = /Applications

include $(THEOS_MAKE_PATH)/application.mk
