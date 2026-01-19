THEOS ?= /opt/theos
THEOS_DEVICE_IP = iphone.local
INSTALL_TARGET_USER = mobile
TARGET := iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = SpringBoard
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = RemoteCompanion

# Lua source files
LUA_FILES = $(wildcard lua/*.c)

RemoteCompanion_FILES = Tweak.x RCNFCManager.x $(LUA_FILES)
RemoteCompanion_CFLAGS = -fobjc-arc -Ilua -DLUA_USE_IOS
RemoteCompanion_FRAMEWORKS = UIKit CoreNFC
RemoteCompanion_PRIVATE_FRAMEWORKS = AppSupport MediaRemote MobileCoreServices FrontBoardServices BackBoardServices MediaPlayer DoNotDisturb BiometricKit
RemoteCompanion_LDFLAGS += -F/opt/theos/sdks/iPhoneOS16.5.sdk/System/Library/PrivateFrameworks

include $(THEOS_MAKE_PATH)/tweak.mk
