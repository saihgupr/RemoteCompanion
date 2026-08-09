#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <netinet/in.h>
#import <sys/socket.h>
#import <sys/un.h>
#include <sys/stat.h>
#import <unistd.h>
#include <arpa/inet.h>
#import <spawn.h>
#import <notify.h>
#import <sys/wait.h>
#import <sys/utsname.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#import <mach/mach_time.h>
#import <GraphicsServices/GraphicsServices.h>
#import "native_curl.h"
#import <CoreFoundation/CoreFoundation.h>

@class SBProximitySensorManager;

static void trigger_haptic();
static void toggle_system_vibration(BOOL silentMode, BOOL enable);
static BOOL get_system_vibration(BOOL silentMode);

static NSString *g_currentAppBundleId = nil;
static NSString *g_previousAppBundleId = nil;
static SBProximitySensorManager *g_proximitySensorManager = nil;
static BOOL g_forceProximityDetection = NO;
static int g_latestHIDProximityState = -1;

// WorkflowKit interfaces
@interface WFWorkflowDescriptor : NSObject
- (instancetype)initWithName:(NSString *)name;
@end

@interface WFWorkflowRunnerClient : NSObject
- (instancetype)initWithWorkflowDescriptor:(WFWorkflowDescriptor *)descriptor input:(id)input parseInput:(BOOL)parse output:(id)output completion:(void (^)(id output, NSError *error))completion;
- (void)start;
@end

@interface SiriPresentationOptions : NSObject
- (void)setWakeScreen:(BOOL)arg1;
- (void)setHideOtherWindowsDuringAppearance:(BOOL)arg1;
@end

@interface SBAssistantController : NSObject
+ (id)sharedInstance;
- (BOOL)isVisible;
- (void)handleVoiceAssistantButtonWithSource:(long long)arg1;
- (void)handleVoiceAssistantButtonWithSource:(long long)arg1 direct:(BOOL)arg2;
- (void)_presentForMainScreenAnimated:(BOOL)arg1 options:(id)arg2 completion:(id)arg3;
- (void)handleSiriButtonDownWithSource:(long long)arg1;
- (void)handleSiriButtonUpWithSource:(long long)arg1;
@end

// Lua interpreter
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"

// IOKit / HID Stuff
typedef struct __IOHIDEvent * IOHIDEventRef;
typedef struct __IOHIDEventSystemClient * IOHIDEventSystemClientRef;
typedef uint32_t IOHIDEventOptionBits;
typedef uint32_t IOOptionBits;

@interface UIWindow (Private)
- (uint32_t)_contextId;
+ (NSArray *)allWindowsIncludingInternalWindows:(BOOL)includeInternal onlyVisibleWindows:(BOOL)onlyVisible;
@end

@interface UIApplication (Private)
- (void)_enqueueHIDEvent:(IOHIDEventRef)event;
@end

extern void BKSHIDEventSetDigitizerInfo(IOHIDEventRef digitizerEvent, uint32_t contextID, uint8_t systemGestureisPossible, uint8_t isSystemGestureStateChangeEvent, CFStringRef displayUUID, CFTimeInterval initialTouchTimestamp, float maxForce);
static UIWindow *g_rcTapTestWindow;
static UIWindow *g_rcTapRecordWindow = nil;

void SRLog(NSString *format, ...);
#import <objc/message.h>

static IOHIDEventSystemClientRef (*_IOHIDEventSystemClientCreate)(CFAllocatorRef allocator);
static IOHIDEventRef (*_IOHIDEventCreateKeyboardEvent)(CFAllocatorRef allocator, uint64_t timestamp, uint32_t usagePage, uint32_t usage, boolean_t down, IOHIDEventOptionBits flags);
static void (*_IOHIDEventSystemClientDispatchEvent)(IOHIDEventSystemClientRef client, IOHIDEventRef event);

// Forward declarations for Siri interaction
@interface SBVoiceControlController : NSObject
- (void)handleHomeButtonHeld;
@end

@interface SBSiriHardwareButtonInteraction : NSObject
- (instancetype)initWithSiriButton:(id)arg1;
- (void)consumeInitialPressDown;
- (void)consumeSinglePressUp;
- (void)consumeLongPress;
@end

// Global captured instances
static SBVoiceControlController *sharedVoiceControl = nil;
static NSHashTable *siriInteractions = nil;

@interface LSApplicationProxy : NSObject
@property (nonatomic, readonly) NSString *applicationIdentifier;
@property (nonatomic, readonly) NSString *localizedName;
@end

@interface LSApplicationWorkspace : NSObject
+ (id)defaultWorkspace;
- (BOOL)openApplicationWithBundleID:(id)arg1;
- (NSArray *)allInstalledApplications;
@end

@interface SBControlCenterController : NSObject
+ (id)sharedInstanceIfExists;
+ (id)sharedInstance;
- (BOOL)isVisible;
- (void)presentAnimated:(BOOL)animated;
- (void)presentAnimated:(BOOL)animated completion:(id)completion;
@end

@interface NCNotificationContent : NSObject
@property (nonatomic, copy, readonly) NSString *title;
@property (nonatomic, copy, readonly) NSString *subtitle;
@property (nonatomic, copy, readonly) NSString *message;
@end

@interface NCNotificationRequest : NSObject
@property (nonatomic, copy, readonly) NSString *sectionIdentifier;
@property (nonatomic, strong, readonly) NCNotificationContent *content;
@end

@interface NCNotificationDispatcher : NSObject
- (void)postNotificationRequest:(id)arg1 forDestination:(id)arg2;
@end

%hook SBVoiceControlController
- (id)init {
    id r = %orig;
    sharedVoiceControl = r;
    SRLog(@"Captured SBVoiceControlController init: %@", r);
    return r;
}
%end

%hook SBSiriHardwareButtonInteraction
- (id)initWithSiriButton:(id)arg1 {
    id r = %orig;
    if (!siriInteractions) {
        siriInteractions = [NSHashTable weakObjectsHashTable];
    }
    [siriInteractions addObject:r];
    SRLog(@"Captured SBSiriHardwareButtonInteraction init: %@", r);
    return r;
}
%end

// Touch/Digitizer event creation
static IOHIDEventRef (*_IOHIDEventCreateDigitizerEvent)(CFAllocatorRef allocator, uint64_t timeStamp,
    uint32_t transducerType, uint32_t index, uint32_t identity, uint32_t eventMask, uint32_t buttonMask,
    double x, double y, double z, double tipPressure, double twist,
    boolean_t range, boolean_t touch, IOHIDEventOptionBits options);
static IOHIDEventRef (*_IOHIDEventCreateDigitizerFingerEvent)(CFAllocatorRef allocator, uint64_t timeStamp,
    uint32_t index, uint32_t identity, uint32_t eventMask,
    double x, double y, double z, double tipPressure, double twist,
    boolean_t range, boolean_t touch, IOHIDEventOptionBits options);
static void (*_IOHIDEventAppendEvent)(IOHIDEventRef parent, IOHIDEventRef child, IOHIDEventOptionBits options);
static void (*_IOHIDEventSetIntegerValue)(IOHIDEventRef event, uint32_t field, int32_t value);
static void (*_IOHIDEventSetIntegerValueWithOptions)(IOHIDEventRef event, uint32_t field, int32_t value, uint32_t options);
static void (*_IOHIDEventSetSenderID)(IOHIDEventRef event, uint64_t senderID);

// Usage Pages / Usages
#define kHIDPage_GenericDesktop 0x01
#define kHIDPage_Consumer       0x0C
#define kHIDUsage_GD_SystemSleep 0x82
#define kHIDUsage_Csmr_Power     0x30
#define kHIDUsage_Csmr_Menu      0x40 // Home button usually
#define kHIDUsage_Csmr_VoiceCommand 0xCF
#define kHIDPage_KeyboardOrKeypad 0x07
#define kHIDUsage_Csmr_VolumeIncrement 0xE9
#define kHIDUsage_Csmr_VolumeDecrement 0xEA
#define kHIDUsage_Csmr_Mute      0xE2
#define kHIDUsage_Csmr_PlayOrPause 0xCD

// Keyboard number keys (Usage Page 0x07)
#define kHIDUsage_Keypad_1 0x1E
#define kHIDUsage_Keypad_2 0x1F
#define kHIDUsage_Keypad_3 0x20
#define kHIDUsage_Keypad_4 0x21
#define kHIDUsage_Keypad_5 0x22
#define kHIDUsage_Keypad_6 0x23
#define kHIDUsage_Keypad_7 0x24
#define kHIDUsage_Keypad_8 0x25
#define kHIDUsage_Keypad_9 0x26
#define kHIDUsage_Keypad_0 0x27

// Private MediaRemote Declarations
// Derived from internet search for targeting specific apps
typedef unsigned int MRMediaRemoteCommand;
extern Boolean MRMediaRemoteSendCommandToApp(MRMediaRemoteCommand command, NSDictionary *userInfo, id origin, NSString *bundleIdentifier, unsigned int options, dispatch_queue_t queue, void (^completion)(NSError *));


// Passcode UI interfaces for direct interaction
@interface SBUIPasscodeLockViewBase : UIView
- (void)_noteStringEntered:(NSString *)string;
- (void)resetForFailedPasscode;
- (void)_sendDelegateKeypadKeyDown;
@end

@interface SBUIPasscodeLockViewWithKeypad : SBUIPasscodeLockViewBase
- (void)_noteStringEntered:(NSString *)string;
- (void)passcodeLockNumberPadKeyPressed:(id)key;
@end

@interface SBUINumericPasscodeEntryField : UIView
- (void)appendCharacter:(NSString *)character;
- (void)setString:(NSString *)string;
@end

@interface SBLockScreenManager : NSObject
+ (instancetype)sharedInstance;
- (BOOL)attemptUnlockWithPasscode:(NSString *)passcode;
- (BOOL)_attemptUnlockWithPasscode:(NSString *)passcode mesa:(BOOL)mesa finishUIUnlock:(BOOL)finishUI;
- (void)lockUIFromSource:(int)source withOptions:(id)options;
- (void)unlockUIFromSource:(int)source withOptions:(id)options;
- (void)_setUILocked:(BOOL)locked animated:(BOOL)animated withReason:(id)reason;
- (BOOL)isUILocked;
- (id)lockScreenViewController;
@end

@interface SBBacklightController : NSObject
+ (id)sharedInstance;
- (BOOL)screenIsOn;
- (float)backlightLevel;
@end

@interface BKOperation : NSObject
@end

@interface SBFUserAuthenticationController : NSObject
- (BOOL)authenticateUsingBiometricAuthSourceWithCompletion:(id)completion;
@end

@interface SBSystemGestureManager : NSObject
+ (instancetype)mainDisplayManager;
- (void)addGestureRecognizer:(UIGestureRecognizer *)recognizer withType:(NSUInteger)type;
@end

@interface SREdgeGestureRecognizer : UIPanGestureRecognizer
@property (nonatomic, assign) BOOL isLeftEdge;
@property (nonatomic, assign) BOOL isRightEdge;
@property (nonatomic, assign) BOOL hasTriggered;
@end



@interface SBReachabilityManager : NSObject
+ (id)sharedInstance;
- (UIGestureRecognizer *)reachabilityGestureRecognizer;
- (void)toggleReachability;
@end


// BluetoothManager APIs
@interface BluetoothManager : NSObject
+ (instancetype)sharedInstance;
- (BOOL)enabled;
- (void)setEnabled:(BOOL)enabled;
- (void)setPowered:(BOOL)powered;
- (BOOL)powered;
- (NSArray *)pairedDevices;
- (void)connectDevice:(id)device;
@end

// BluetoothDevice APIs
@interface BluetoothDevice : NSObject
- (NSString *)name;
- (NSString *)address;
- (BOOL)connected;
- (void)connect;
- (void)disconnect;
@end

// WiFiManager APIs
@interface WiFiManager : NSObject
+ (instancetype)sharedInstance;
- (BOOL)wiFiEnabled;
- (void)setWiFiEnabled:(BOOL)enabled;
@end

// Airplane Mode APIs (AppSupport)
@interface RadiosPreferences : NSObject
- (BOOL)airplaneMode;
- (void)setAirplaneMode:(BOOL)enabled;
- (void)synchronize;
@end

// SBWiFiManager API
@interface SBWiFiManager : NSObject
+ (instancetype)sharedInstance;
- (void)setWiFiEnabled:(BOOL)enabled;
- (BOOL)wiFiEnabled;
- (id)currentNetworkName;
@end

@interface SBTelephonyManager : NSObject
+ (id)sharedTelephonyManager;
- (id)_serverConnection;
@end


// MediaRemote APIs - these are stable and work on iOS 15.8
typedef enum {
    kMRPlay = 0,
    kMRTogglePlayPause = 1,
    kMRPause = 2,
    kMRNextTrack = 4,
    kMRPreviousTrack = 5
} MRCommand;

extern void MRMediaRemoteSendCommand(MRCommand command, NSDictionary *options);
extern void MRMediaRemoteGetNowPlayingApplicationIsPlaying(dispatch_queue_t queue, void (^completion)(Boolean isPlaying));
extern void MRMediaRemoteGetNowPlayingApplicationPlaybackState(dispatch_queue_t queue, void (^completion)(unsigned int state));
extern void MRMediaRemoteGetNowPlayingInfo(dispatch_queue_t queue, void (^completion)(CFDictionaryRef information));
extern void MRMediaRemoteGetNowPlayingClient(dispatch_queue_t queue, void (^completion)(void *clientObj));
extern CFStringRef MRNowPlayingClientGetBundleIdentifier(void *clientObj);

extern CFStringRef kMRMediaRemoteNowPlayingInfoTitle;
extern CFStringRef kMRMediaRemoteNowPlayingInfoArtist;

// AVOutputDevice for ANC control (used by Sonitus)
@interface AVOutputDevice : NSObject
@property (readonly, nonatomic) NSString *name;
- (NSArray *)availableBluetoothListeningModes;
- (BOOL)setCurrentBluetoothListeningMode:(NSString *)mode error:(NSError **)error;
- (NSString *)currentBluetoothListeningMode;
@end

// MPAVRoutingController (MediaPlayer)
@interface MPAVRoute : NSObject
@property (nonatomic, readonly) NSString *routeName;
@property (nonatomic, readonly) NSString *routeUID;
@property (nonatomic, readonly) BOOL isDeviceRoute;
@property (nonatomic, readonly) BOOL isPickable;
@property (nonatomic, readonly, getter=isPicked) BOOL picked;
@end

@interface MPAVRoutingController : NSObject
@property (nonatomic, weak) id delegate;
@property (nonatomic, readonly) NSArray<MPAVRoute *> *availableRoutes;
@property (nonatomic, assign) NSInteger discoveryMode;
- (void)fetchAvailableRoutesWithCompletionHandler:(void(^)(NSArray<MPAVRoute *> *routes))completion;
- (BOOL)pickRoute:(MPAVRoute *)route;
@end

// AVOutputContext for getting current output device
@interface AVOutputContext : NSObject
+ (instancetype)sharedSystemAudioContext;
- (NSArray *)outputDevices;
@end

// FrontBoardServices for fast app launching
@interface FBSOpenApplicationOptions : NSObject
+ (instancetype)optionsWithDictionary:(NSDictionary *)dictionary;
@end

@interface FBSOpenApplicationService : NSObject
+ (instancetype)serviceWithDefaultShellEndpoint;
- (void)openApplication:(NSString *)bundleID withOptions:(FBSOpenApplicationOptions *)options completion:(id)completion;
@end

// DoNotDisturb Interfaces
@interface DNDModeAssertionLifetime : NSObject
+ (instancetype)lifetimeUntilEndOfScheduleWithIdentifier:(NSString *)identifier;
@end

@interface DNDModeAssertionDetails : NSObject
+ (instancetype)detailsWithIdentifier:(NSString *)identifier modeIdentifier:(NSString *)modeIdentifier lifetime:(DNDModeAssertionLifetime *)lifetime;
+ (instancetype)userRequestedAssertionDetails; // Helper for simple toggle
@end

@interface DNDModeAssertion : NSObject
@end

@interface DNDModeAssertionService : NSObject
+ (instancetype)serviceForClientIdentifier:(NSString *)clientIdentifier;
- (DNDModeAssertion *)takeModeAssertionWithDetails:(DNDModeAssertionDetails *)details error:(NSError **)error;
- (BOOL)invalidateAllActiveModeAssertionsWithError:(NSError **)error;
- (id)activeModeAssertionWithError:(NSError **)error;
@end

// CoreDuet - Low Power Mode
@interface _CDBatterySaver : NSObject
+ (instancetype)batterySaver;
- (long long)getPowerMode;
- (BOOL)setPowerMode:(long long)mode error:(NSError **)error;
@end

// BackBoardServices for killing apps
extern void BKSTerminateApplicationForReasonAndReportWithDescription(NSString *bundleID, int reason, bool report, NSString *description);

// SpringBoard Interfaces
@interface SBApplication : NSObject
- (NSString *)bundleIdentifier;
@end

@interface SBVolumeHardwareButton : NSObject
- (id)volumeIncreaseSequenceObserver;
- (id)volumeDecreaseSequenceObserver;
@end

@interface SBVolumeHardwareButtonActions : NSObject
- (void)volumeIncreasePressDownWithModifiers:(long long)arg1;
- (void)volumeIncreasePressUp;
- (void)volumeDecreasePressDownWithModifiers:(long long)arg1;
- (void)volumeDecreasePressUp;
@end

@interface SBLockHardwareButtonActions : NSObject
- (void)performInitialButtonDownActions;
- (void)performButtonUpPreActions;
- (void)performLongPressActions;
- (void)performDoublePressActions;
@end

@interface SBUIBiometricResource : NSObject
+ (id)sharedInstance;
- (void)addObserver:(id)arg1;
- (void)removeObserver:(id)arg1;
- (BOOL)isFingerOn;
- (BOOL)hasBiometricAuthenticationCapabilityEnabled;
@end

@interface SpringBoard : UIApplication
- (UIInterfaceOrientation)activeInterfaceOrientation;
- (SBApplication *)_accessibilityFrontMostApplication;
- (void)_simulateHomeButtonPress;
- (void)_menuButtonDown:(id)arg1;
- (void)_menuButtonUp:(id)arg1;
- (void)_accessibilityHandleAppSwitcherEvent;
@end

@interface SBOrientationLockManager : NSObject
+ (instancetype)sharedInstance;
- (void)lock;
- (void)unlock;
- (BOOL)isUserLocked;
@end

@interface SBProximitySensorManager : NSObject
+ (instancetype)sharedInstance;
- (BOOL)isObjectInProximity;
- (BOOL)isProximityDetectionEnabled;
- (void)setProximityDetectionEnabled:(BOOL)enabled;
- (void)_enableProx;
- (void)_disableProx;
- (void)_setProximityDetectionEnabled:(BOOL)enabled;
@end

@interface SBScreenshotManager : NSObject
+ (instancetype)sharedInstance;
- (void)saveScreenshotToCameraRollWithCompletion:(id)completion;
@end

@interface SBUIController : NSObject
+ (instancetype)sharedInstance;
- (void)handleHomeButtonTap;
- (void)handleHomeButtonTap:(id)arg1;
- (void)clickedMenuButton;
- (void)handleScreenshotGestureFired:(id)arg1;
- (BOOL)isACPowerConnected;
- (BOOL)isOnAC;
- (void)ACPowerChanged;
- (void)updateBatteryState:(id)arg1;
- (void)setIsACPowerConnected:(BOOL)arg1;
@end

@interface UISUserInterfaceStyleMode : NSObject
- (void)setModeValue:(NSInteger)value;
- (NSInteger)modeValue;
@end

@interface SBRingerControl : NSObject
+ (instancetype)sharedInstance;
- (BOOL)isRingerMuted;
- (void)setRingerMuted:(BOOL)muted;
@end

@interface SBMainSwitcherViewController : UIViewController
+ (instancetype)sharedInstance;
- (void)_toggleSwitcher;
- (void)toggleSwitcherNoninteractively;
@end

@interface SBMainSwitcherController : NSObject
+ (instancetype)sharedInstance;
- (void)toggleSwitcherNoninteractively;
@end

@interface AVSystemController : NSObject
+ (instancetype)sharedAVSystemController;
- (BOOL)getVolume:(float *)volume forCategory:(NSString *)category;
- (BOOL)setActiveCategoryVolumeTo:(float)volume;
- (BOOL)getActiveCategoryMuted:(BOOL *)muted;
- (BOOL)setVolumeTo:(float)volume forCategory:(NSString *)category;
@end

static float sr_previous_volume = -1.0f;





// File-based logging helper
void SRLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    
    // Log to console (stderr) for syslog capture if available
    NSLog(@"[RemoteCommand] %@", message);
    
    // Write to file with synchronization
    @synchronized([NSFileManager defaultManager]) {
        NSString *logMsg = [NSString stringWithFormat:@"%@ [RemoteCommand] %@\n", [NSDate date], message];
        NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:@"/tmp/remotecommand.log"];
        if (fileHandle) {
            @try {
                [fileHandle seekToEndOfFile];
                [fileHandle writeData:[logMsg dataUsingEncoding:NSUTF8StringEncoding]];
                [fileHandle synchronizeFile]; // Force flush to disk
                [fileHandle closeFile];
            } @catch (NSException *e) {}
        } else {
            [logMsg writeToFile:@"/tmp/remotecommand.log" atomically:YES encoding:NSUTF8StringEncoding error:nil];
        }
    }
}

// Add DND Toggle Helper
// Helper to inspect current state

#import <objc/runtime.h>






__attribute__((unused))
static void toggle_dnd(BOOL state) {
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            Class ServiceClass = objc_getClass("DNDModeAssertionService");
            Class DetailsClass = objc_getClass("DNDModeAssertionDetails");
            Class StateServiceClass = objc_getClass("DNDStateService");
            
            if (!ServiceClass || !DetailsClass) {
                // Fallback for iOS 14
                if (StateServiceClass) {
                    SRLog(@"Using iOS 14 DND fallback");
                    id service = [StateServiceClass serviceForClientIdentifier:@"com.apple.donotdisturb.control-center.module"];
                    (void)service;
                    if (state) {
                        // On iOS 14, DND is often handled via specialized controllers or assertions
                        // but a quick way is often through the SBDoNotDisturbController if we can find it
                        // or just failing gracefully if private APIs changed too much.
                        // For now, we'll try to find the shared instance of the DND service.
                        // NOTE: Proper iOS 14 DND implementation usually involves SpringBoard hooks.
                    }
                }
                SRLog(@"DND toggle not fully supported on this iOS version yet");
                return;
            }

            // Use the SAME client identifier as Control Center (from Assertions.json)
            id service = [ServiceClass serviceForClientIdentifier:@"com.apple.donotdisturb.control-center.module"];
            
            // Always invalidate existing assertions first to prevent stacking/errors (Idempotency)
            NSError *invalidateErr = nil;
            [service invalidateAllActiveModeAssertionsWithError:&invalidateErr];
            
            if (state) {
                // Turn ON
                // Try to use a more robust identifier or userRequested approach if possible.
                // For now, let's stick to explicit default but log heavily.
                 id details = [DetailsClass detailsWithIdentifier:@"com.apple.control-center.manual-toggle"
                                                                     modeIdentifier:@"com.apple.donotdisturb.mode.default"
                                                                           lifetime:nil];
                NSError *err = nil;
                id assertion = [service takeModeAssertionWithDetails:details error:&err];
                if (err) SRLog(@"Failed to enable DND: %@", err);
                else SRLog(@"DND Enabled. Assertion: %@", assertion);
            } else {
                SRLog(@"DND Disabled");
            }
        } @catch (NSException *e) {
            SRLog(@"EXCEPTION in toggle_dnd: %@", e);
        }
    });
}

static void toggle_lpm(BOOL state) {
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            Class BatterySaverClass = objc_getClass("_CDBatterySaver");
            if (!BatterySaverClass) {
                SRLog(@"_CDBatterySaver class not found");
                return;
            }
            
            id saver = [BatterySaverClass batterySaver];
            if (!saver) {
                SRLog(@"Failed to get batterySaver instance");
                return;
            }
            
            NSError *err = nil;
            // Power mode: 0 = normal, 1 = low power
            BOOL result = [saver setPowerMode:(state ? 1 : 0) error:&err];
            
            if (err) {
                SRLog(@"Failed to set LPM: %@", err);
            } else {
                SRLog(@"LPM %@. Result: %d", state ? @"Enabled" : @"Disabled", result);
            }
        } @catch (NSException *e) {
            SRLog(@"EXCEPTION in toggle_lpm: %@", e);
        }
    });
}

// State detection helpers
static BOOL get_lpm_state() {
    Class BatterySaverClass = objc_getClass("_CDBatterySaver");
    if (BatterySaverClass) {
        id saver = [BatterySaverClass batterySaver];
        if (saver && [saver respondsToSelector:@selector(getPowerMode)]) {
            return [saver getPowerMode] != 0;
        }
    }
    return NO;
}

static BOOL get_dnd_state() {
    Class ServiceClass = objc_getClass("DNDModeAssertionService");
    if (ServiceClass) {
        id service = [ServiceClass serviceForClientIdentifier:@"com.apple.donotdisturb.control-center.module"];
        NSError *err = nil;
        id assertion = [service activeModeAssertionWithError:&err];
        return (assertion != nil);
    }
    return NO;
}

typedef struct __CTServerConnection *CTServerConnectionRef;
typedef CTServerConnectionRef (*CTServerConnectionCreateType)(CFAllocatorRef, void *, int *);
typedef int (*CTServerConnectionGetCellularDataIsEnabledType)(CTServerConnectionRef, uint8_t *);
typedef int (*CTServerConnectionSetCellularDataIsEnabledType)(CTServerConnectionRef, uint8_t);

static BOOL get_cellular_state() {
    BOOL isEnabled = NO;
    id telephonyManager = [(id)objc_getClass("SBTelephonyManager") sharedTelephonyManager];
    if (telephonyManager) {
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        SEL connSel = @selector(_serverConnection);
        if ([telephonyManager respondsToSelector:connSel]) {
            CTServerConnectionRef conn = (__bridge CTServerConnectionRef)[telephonyManager performSelector:connSel];
            if (conn) {
                void *ctHandle = dlopen("/System/Library/Frameworks/CoreTelephony.framework/CoreTelephony", RTLD_NOW);
                if (ctHandle) {
                    CTServerConnectionGetCellularDataIsEnabledType getFunc = (CTServerConnectionGetCellularDataIsEnabledType)dlsym(ctHandle, "_CTServerConnectionGetCellularDataIsEnabled");
                    if (getFunc) {
                        uint8_t enabled = 0;
                        getFunc(conn, &enabled);
                        isEnabled = (enabled != 0);
                    }
                    dlclose(ctHandle);
                }
            }
        }
        #pragma clang diagnostic pop
    }
    return isEnabled;
}

static BOOL set_cellular_state(BOOL state) {
    BOOL success = NO;
    id telephonyManager = [(id)objc_getClass("SBTelephonyManager") sharedTelephonyManager];
    if (telephonyManager) {
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        SEL connSel = @selector(_serverConnection);
        if ([telephonyManager respondsToSelector:connSel]) {
            CTServerConnectionRef conn = (__bridge CTServerConnectionRef)[telephonyManager performSelector:connSel];
            if (conn) {
                void *ctHandle = dlopen("/System/Library/Frameworks/CoreTelephony.framework/CoreTelephony", RTLD_NOW);
                if (ctHandle) {
                    CTServerConnectionSetCellularDataIsEnabledType setFunc = (CTServerConnectionSetCellularDataIsEnabledType)dlsym(ctHandle, "_CTServerConnectionSetCellularDataIsEnabled");
                    if (setFunc) {
                        setFunc(conn, state ? 1 : 0);
                        success = YES;
                    }
                    dlclose(ctHandle);
                }
            }
        }
        #pragma clang diagnostic pop
    }
    return success;
}

static UIWindow *g_rcHUDWindow = nil;

static NSArray<NSString *> *rc_parse_quoted_arguments(NSString *argString) {
    NSMutableArray *arguments = [NSMutableArray array];
    NSScanner *scanner = [NSScanner scannerWithString:argString];
    [scanner setCharactersToBeSkipped:nil]; // Do not skip whitespace automatically
    
    while (![scanner isAtEnd]) {
        // Skip whitespace
        [scanner scanCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:NULL];
        if ([scanner isAtEnd]) break;
        
        NSString *arg = nil;
        if ([scanner scanString:@"\"" intoString:NULL]) {
            // Scan until closing quote
            [scanner scanUpToString:@"\"" intoString:&arg];
            [scanner scanString:@"\"" intoString:NULL];
            if (!arg) arg = @"";
        } else {
            // Scan until next space
            [scanner scanUpToCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:&arg];
        }
        
        if (arg) {
            [arguments addObject:arg];
        }
    }
    return arguments;
}

static void rc_show_hud_toast(NSString *title, NSString *subtitle, NSString *iconSymbol) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (g_rcHUDWindow) {
            [g_rcHUDWindow.layer removeAllAnimations];
            g_rcHUDWindow.hidden = YES;
            g_rcHUDWindow = nil;
        }
        
        CGRect screenBounds = [UIScreen mainScreen].bounds;
        CGFloat screenWidth = screenBounds.size.width;
        
        // Define fonts matching native iOS 15 Ringer HUD
        UIFont *titleFont = [UIFont systemFontOfSize:13.0 weight:UIFontWeightMedium];
        UIFont *subtitleFont = [UIFont systemFontOfSize:12.0 weight:UIFontWeightRegular];
        
        // Measure text to determine dynamic width
        CGFloat maxTextWidth = 0;
        if (title) {
            CGSize titleSize = [title sizeWithAttributes:@{NSFontAttributeName: titleFont}];
            maxTextWidth = titleSize.width;
        }
        if (subtitle) {
            CGSize subSize = [subtitle sizeWithAttributes:@{NSFontAttributeName: subtitleFont}];
            if (subSize.width > maxTextWidth) {
                maxTextWidth = subSize.width;
            }
        }
        
        // Check if icon exists and is a valid symbol image
        BOOL hasIcon = NO;
        if (iconSymbol && ![iconSymbol isEqualToString:@""] && ![iconSymbol isEqualToString:@"none"]) {
            if ([UIImage systemImageNamed:iconSymbol]) {
                hasIcon = YES;
            }
        }
        
        CGFloat leftPadding = 16.0;
        CGFloat iconWidth = hasIcon ? 20.0 : 0.0;
        CGFloat iconGap = hasIcon ? 10.0 : 0.0;
        CGFloat leftMargin = leftPadding + iconWidth + iconGap;
        
        CGFloat pillWidth = maxTextWidth + 2 * leftMargin;
        // Enforce native-looking bounds (min 140, max screenWidth - 32)
        pillWidth = MAX(140.0, MIN(pillWidth, screenWidth - 32.0));
        
        // Determine height based on whether we have a subtitle
        BOOL hasSubtitle = (subtitle && ![subtitle isEqualToString:@""]);
        CGFloat pillHeight = hasSubtitle ? 50.0 : 40.0;
        
        CGFloat pillX = (screenWidth - pillWidth) / 2.0;
        CGFloat startY = -pillHeight - 20.0;
        
        // Query status bar height for target Y
        CGFloat statusBarHeight = 20.0;
        if (@available(iOS 13.0, *)) {
            UIWindow *keyWin = nil;
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Wdeprecated-declarations"
            keyWin = [UIApplication sharedApplication].keyWindow;
            #pragma clang diagnostic pop
            if (keyWin && keyWin.windowScene && keyWin.windowScene.statusBarManager) {
                statusBarHeight = keyWin.windowScene.statusBarManager.statusBarFrame.size.height;
            }
        }
        if (statusBarHeight == 0) {
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Wdeprecated-declarations"
            statusBarHeight = [UIApplication sharedApplication].statusBarFrame.size.height;
            #pragma clang diagnostic pop
        }
        
        // targetY places it right in status bar overlay position (matching native iOS ringer HUD)
        CGFloat targetY = (statusBarHeight > 24.0) ? 15.0 : 12.0;
        
        UIWindow *hudWindow = [[UIWindow alloc] initWithFrame:CGRectMake(pillX, startY, pillWidth, pillHeight)];
        g_rcHUDWindow = hudWindow;
        hudWindow.windowLevel = UIWindowLevelAlert + 3000.0;
        hudWindow.backgroundColor = [UIColor clearColor];
        hudWindow.userInteractionEnabled = NO;
        
        UIViewController *rootVC = [[UIViewController alloc] init];
        rootVC.view.frame = CGRectMake(0, 0, pillWidth, pillHeight);
        rootVC.view.backgroundColor = [UIColor clearColor];
        hudWindow.rootViewController = rootVC;
        
        BOOL isDarkMode = YES;
        if (@available(iOS 12.0, *)) {
            if ([UIScreen mainScreen].traitCollection.userInterfaceStyle == UIUserInterfaceStyleLight) {
                isDarkMode = NO;
            }
        }
        
        UIBlurEffectStyle blurStyle = isDarkMode ? UIBlurEffectStyleSystemMaterialDark : UIBlurEffectStyleSystemMaterialLight;
        UIColor *titleColor = isDarkMode ? [UIColor whiteColor] : [UIColor colorWithWhite:0.0 alpha:0.8];
        UIColor *subColor = isDarkMode ? [UIColor colorWithWhite:1.0 alpha:0.6] : [UIColor colorWithWhite:0.0 alpha:0.48];
        UIColor *iconColor = isDarkMode ? [UIColor whiteColor] : [UIColor colorWithWhite:0.0 alpha:0.7];
        
        // Blur background (matching native ringer HUD pill - no border)
        UIBlurEffect *blurEffect = [UIBlurEffect effectWithStyle:blurStyle];
        UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
        blurView.frame = CGRectMake(0, 0, pillWidth, pillHeight);
        blurView.layer.cornerRadius = pillHeight / 2.0;
        blurView.layer.masksToBounds = YES;
        [rootVC.view addSubview:blurView];
        
        if (hasIcon) {
            UIImage *iconImage = nil;
            if (@available(iOS 13.0, *)) {
                UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:16.0 weight:UIImageSymbolWeightMedium];
                iconImage = [UIImage systemImageNamed:iconSymbol withConfiguration:config];
            } else {
                iconImage = [UIImage systemImageNamed:iconSymbol];
            }
            
            if (iconImage) {
                UIImageView *iconView = [[UIImageView alloc] initWithImage:iconImage];
                iconView.tintColor = iconColor;
                iconView.contentMode = UIViewContentModeScaleAspectFit;
                iconView.frame = CGRectMake(leftPadding, (pillHeight - 20) / 2.0, 20, 20);
                [rootVC.view addSubview:iconView];
            }
        }
        
        // Text alignment: Center relative to the entire bubble
        NSTextAlignment alignment = NSTextAlignmentCenter;
        
        if (hasSubtitle) {
            UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 8.0, pillWidth, 18.0)];
            titleLabel.text = title;
            titleLabel.textColor = titleColor;
            titleLabel.font = titleFont;
            titleLabel.textAlignment = alignment;
            [rootVC.view addSubview:titleLabel];
            
            UILabel *subLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 26.0, pillWidth, 16.0)];
            subLabel.text = subtitle;
            subLabel.textColor = subColor;
            subLabel.font = subtitleFont;
            subLabel.textAlignment = alignment;
            [rootVC.view addSubview:subLabel];
        } else {
            UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, pillWidth, pillHeight)];
            titleLabel.text = title;
            titleLabel.textColor = titleColor;
            titleLabel.font = titleFont;
            titleLabel.textAlignment = alignment;
            [rootVC.view addSubview:titleLabel];
        }
        
        hudWindow.hidden = NO;
        
        [UIView animateWithDuration:0.5
                              delay:0.0
             usingSpringWithDamping:0.75
              initialSpringVelocity:1.0
                            options:UIViewAnimationOptionCurveEaseInOut
                         animations:^{
                             hudWindow.frame = CGRectMake(pillX, targetY, pillWidth, pillHeight);
                         }
                         completion:^(BOOL finished) {
                             if (g_rcHUDWindow != hudWindow) {
                                 hudWindow.hidden = YES;
                                 return;
                             }
                             [UIView animateWithDuration:0.4
                                                   delay:2.0
                                                 options:UIViewAnimationOptionCurveEaseInOut
                                              animations:^{
                                                  hudWindow.frame = CGRectMake(pillX, startY, pillWidth, pillHeight);
                                              }
                                              completion:^(BOOL finished2) {
                                                  hudWindow.hidden = YES;
                                                  if (g_rcHUDWindow == hudWindow) {
                                                      g_rcHUDWindow = nil;
                                                  }
                                              }];
                         }];
    });
}

static void toggle_audiomix(BOOL state) {
    @try {
        CFStringRef appID = CFSTR("com.kingpuffdaddi.audiomixprefs");
        CFPreferencesSetAppValue(CFSTR("isEnabled"), (__bridge CFNumberRef)@(state), appID);
        CFPreferencesAppSynchronize(appID);

        // Write directly to plist file paths as fallback/synchronization
        NSString *prefix = @"";
        if ([[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb/usr/bin/nc"]) {
            prefix = @"/var/jb";
        }
        NSArray *paths = @[
            @"/var/mobile/Library/Preferences/com.kingpuffdaddi.audiomixprefs.plist",
            [NSString stringWithFormat:@"%@/var/mobile/Library/Preferences/com.kingpuffdaddi.audiomixprefs.plist", prefix]
        ];
        for (NSString *path in paths) {
            NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithContentsOfFile:path];
            if (!dict) {
                dict = [NSMutableDictionary dictionary];
            }
            dict[@"isEnabled"] = @(state);
            [dict writeToFile:path atomically:YES];
        }

        // Post Darwin notification
        notify_post("com.kingpuffdaddi.audiomixprefs/settingschanged");

        SRLog(@"AudioMix Enabled toggled to: %@", state ? @"YES" : @"NO");

        rc_show_hud_toast(@"AudioMix", state ? @"Enabled" : @"Disabled", @"music.note");
    } @catch (NSException *e) {
        SRLog(@"EXCEPTION in toggle_audiomix: %@", e);
    }
}

static BOOL get_audiomix_state() {
    @try {
        Boolean valid;
        Boolean val = CFPreferencesGetAppBooleanValue(CFSTR("isEnabled"), CFSTR("com.kingpuffdaddi.audiomixprefs"), &valid);
        if (valid) return val;

        // Fallback to reading file
        NSString *prefix = @"";
        if ([[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb/usr/bin/nc"]) {
            prefix = @"/var/jb";
        }
        NSArray *paths = @[
            @"/var/mobile/Library/Preferences/com.kingpuffdaddi.audiomixprefs.plist",
            [NSString stringWithFormat:@"%@/var/mobile/Library/Preferences/com.kingpuffdaddi.audiomixprefs.plist", prefix]
        ];
        for (NSString *path in paths) {
            if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
                NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:path];
                if (dict && dict[@"isEnabled"]) {
                    return [dict[@"isEnabled"] boolValue];
                }
            }
        }
    } @catch (NSException *e) {
        SRLog(@"EXCEPTION in get_audiomix_state: %@", e);
    }
    return YES; // Default to YES if not found/error
}

static void inject_hid_event(uint32_t page, uint32_t usage, uint64_t durationNs, IOOptionBits flags) {
    static dispatch_queue_t hidQueue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        hidQueue = dispatch_queue_create("com.pizzaman.remotecommand.hid", DISPATCH_QUEUE_SERIAL);
        void *handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW);
        if (handle) {
            _IOHIDEventSystemClientCreate = (IOHIDEventSystemClientRef (*)(CFAllocatorRef))dlsym(handle, "IOHIDEventSystemClientCreate");
            _IOHIDEventCreateKeyboardEvent = (IOHIDEventRef (*)(CFAllocatorRef, uint64_t, uint32_t, uint32_t, boolean_t, IOHIDEventOptionBits))dlsym(handle, "IOHIDEventCreateKeyboardEvent");
            _IOHIDEventSystemClientDispatchEvent = (void (*)(IOHIDEventSystemClientRef, IOHIDEventRef))dlsym(handle, "IOHIDEventSystemClientDispatchEvent");
            
            // Touch/Digitizer symbols
            _IOHIDEventCreateDigitizerEvent = (IOHIDEventRef (*)(CFAllocatorRef, uint64_t, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t, double, double, double, double, double, boolean_t, boolean_t, IOHIDEventOptionBits))dlsym(handle, "IOHIDEventCreateDigitizerEvent");
            _IOHIDEventCreateDigitizerFingerEvent = (IOHIDEventRef (*)(CFAllocatorRef, uint64_t, uint32_t, uint32_t, uint32_t, double, double, double, double, double, boolean_t, boolean_t, IOHIDEventOptionBits))dlsym(handle, "IOHIDEventCreateDigitizerFingerEvent");
            _IOHIDEventAppendEvent = (void (*)(IOHIDEventRef, IOHIDEventRef, IOHIDEventOptionBits))dlsym(handle, "IOHIDEventAppendEvent");
            _IOHIDEventSetIntegerValue = (void (*)(IOHIDEventRef, uint32_t, int32_t))dlsym(handle, "IOHIDEventSetIntegerValue");
            _IOHIDEventSetSenderID = (void (*)(IOHIDEventRef, uint64_t))dlsym(handle, "IOHIDEventSetSenderID");
        }
    });

    dispatch_async(hidQueue, ^{
        IOHIDEventSystemClientRef client = _IOHIDEventSystemClientCreate(kCFAllocatorDefault);
        if (!client) {
            SRLog(@"ERROR: Could not create HID event system client");
            return;
        }

        uint64_t now = mach_absolute_time();
        
        // Key Down
        IOHIDEventRef eventDown = _IOHIDEventCreateKeyboardEvent(kCFAllocatorDefault, now, page, usage, true, flags);
        if (eventDown) {
            _IOHIDEventSystemClientDispatchEvent(client, eventDown);
            CFRelease(eventDown);
        }
        
        // Wait for usage duration
        uint64_t waitNs = (durationNs == 0) ? 50000000 : durationNs; // Default 50ms
        usleep((useconds_t)(waitNs / 1000));
        
        uint64_t later = mach_absolute_time();
        
        // Key Up
        IOHIDEventRef eventUp = _IOHIDEventCreateKeyboardEvent(kCFAllocatorDefault, later, page, usage, false, flags);
        if (eventUp) {
            _IOHIDEventSystemClientDispatchEvent(client, eventUp);
            CFRelease(eventUp);
        }
        
        if (client) CFRelease(client);
    });
}

static void toggle_system_vibration(BOOL silentMode, BOOL enable) {
    NSString *key = silentMode ? @"silent-vibrate" : @"ring-vibrate";
    CFStringRef appID = CFSTR("com.apple.springboard");
    
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFNumberRef)@(enable), appID);
    CFPreferencesAppSynchronize(appID);
    
    // Notify SpringBoard to reload prefs
    notify_post("com.apple.springboard.silent-vibrate.changed");
    notify_post("com.apple.springboard.ring-vibrate.changed");
    
    SRLog(@"Set system vibration (%@) to: %@", key, enable ? @"YES" : @"NO");
}

static BOOL get_system_vibration(BOOL silentMode) {
    NSString *key = silentMode ? @"silent-vibrate" : @"ring-vibrate";
    Boolean valid;
    Boolean val = CFPreferencesGetAppBooleanValue((__bridge CFStringRef)key, CFSTR("com.apple.springboard"), &valid);
    if (!valid) return YES;
    return val;
}

// Helper to detect rootless vs rootful
static NSString* root_prefix() {
    static NSString *prefix = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        if ([[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb/usr/bin/nc"]) {
            prefix = @"/var/jb";
        } else {
            prefix = @"";
        }
    });
    return prefix;
}

// Helper to inject a HID Consumer Page event (wrapper)
static void inject_consumer_key(int usage) {
    inject_hid_event(kHIDPage_Consumer, usage, 50000000, 0); // 50ms hold
}


static void simulate_home_press() {
    dispatch_async(dispatch_get_main_queue(), ^{
        SRLog(@"Executing Home simulation...");
        
        // 1. Try SBUIController (Modern Home Tap)
        id uiCtrl = [objc_getClass("SBUIController") sharedInstance];
        if ([uiCtrl respondsToSelector:@selector(handleHomeButtonTap)]) {
            [uiCtrl handleHomeButtonTap];
            SRLog(@"Triggered handleHomeButtonTap");
        } else if ([uiCtrl respondsToSelector:@selector(handleHomeButtonTap:)]) {
            [uiCtrl handleHomeButtonTap:nil];
            SRLog(@"Triggered handleHomeButtonTap:");
        } else if ([uiCtrl respondsToSelector:@selector(clickedMenuButton)]) {
            [uiCtrl clickedMenuButton];
            SRLog(@"Triggered clickedMenuButton");
        }
        
        // 2. Fallback: SpringBoard simulation
        SpringBoard *sb = (SpringBoard *)[UIApplication sharedApplication];
        if ([sb respondsToSelector:@selector(_simulateHomeButtonPress)]) {
            [sb _simulateHomeButtonPress];
            SRLog(@"Triggered _simulateHomeButtonPress");
        } else if ([sb respondsToSelector:@selector(_menuButtonDown:)]) {
            [sb _menuButtonDown:nil];
            [sb _menuButtonUp:nil];
            SRLog(@"Triggered _menuButtonDown/Up");
        }
        
        // 3. HID Event (Last resort)
        inject_hid_event(kHIDPage_Consumer, kHIDUsage_Csmr_Menu, 50000000, 0);
    });
}

// MediaRemote Helper Declarations
typedef void (^MRMediaRemoteGetNowPlayingApplicationPIDCompletion)(int pid);
extern void MRMediaRemoteGetNowPlayingApplicationPID(dispatch_queue_t queue, MRMediaRemoteGetNowPlayingApplicationPIDCompletion completion);

typedef void (^MRMediaRemoteGetNowPlayingApplicationIsPlayingCompletion)(Boolean isPlaying);
extern void MRMediaRemoteGetNowPlayingApplicationIsPlaying(dispatch_queue_t queue, MRMediaRemoteGetNowPlayingApplicationIsPlayingCompletion completion);
        

// Maps ASCII characters to HID usage codes
static void type_character(char c) {
    uint32_t usage = 0;
    IOOptionBits flags = 0; // 0x20000 = Shift (kIOHIDEventOptionIsShift not always available, but 131072 is standard)
    
    // Usage ID ref: https://usb.org/sites/default/files/hut1_2.pdf
    if (c >= 'a' && c <= 'z') { usage = 0x04 + (c - 'a'); } // a-z
    else if (c >= 'A' && c <= 'Z') { usage = 0x04 + (c - 'A'); flags = 0x20000; } // A-Z (Shift)
    else if (c >= '1' && c <= '9') { usage = 0x1E + (c - '1'); } // 1-9
    else if (c == '0') { usage = 0x27; }
    else if (c == '!') { usage = 0x1E; flags = 0x20000; } // Shift+1
    else if (c == '@') { usage = 0x1F; flags = 0x20000; } // Shift+2
    else if (c == '#') { usage = 0x20; flags = 0x20000; } // Shift+3
    else if (c == '$') { usage = 0x21; flags = 0x20000; } // Shift+4
    else if (c == '%') { usage = 0x22; flags = 0x20000; } // Shift+5
    else if (c == '^') { usage = 0x23; flags = 0x20000; } // Shift+6
    else if (c == '&') { usage = 0x24; flags = 0x20000; } // Shift+7
    else if (c == '*') { usage = 0x25; flags = 0x20000; } // Shift+8
    else if (c == '(') { usage = 0x26; flags = 0x20000; } // Shift+9
    else if (c == ')') { usage = 0x27; flags = 0x20000; } // Shift+0
    
    else if (c == ' ') usage = 0x2C; // Space
    else if (c == '\n' || c == '\r') usage = 0x28; // Enter
    else if (c == '-') usage = 0x2D; // Hyphen
    else if (c == '_') { usage = 0x2D; flags = 0x20000; } // Shift+Hyphen
    else if (c == '=') usage = 0x2E; // Equal
    else if (c == '+') { usage = 0x2E; flags = 0x20000; } // Shift+Equal
    else if (c == '[') usage = 0x2F;
    else if (c == '{') { usage = 0x2F; flags = 0x20000; }
    else if (c == ']') usage = 0x30;
    else if (c == '}') { usage = 0x30; flags = 0x20000; }
    else if (c == '\\') usage = 0x31;
    else if (c == '|') { usage = 0x31; flags = 0x20000; }
    else if (c == ';') usage = 0x33;
    else if (c == ':') { usage = 0x33; flags = 0x20000; }
    else if (c == '\'') usage = 0x34;
    else if (c == '"') { usage = 0x34; flags = 0x20000; }
    else if (c == ',') usage = 0x36; // Comma
    else if (c == '<') { usage = 0x36; flags = 0x20000; }
    else if (c == '.') usage = 0x37; // Period
    else if (c == '>') { usage = 0x37; flags = 0x20000; }
    else if (c == '/') usage = 0x38; // Slash
    else if (c == '?') { usage = 0x38; flags = 0x20000; }
    
    if (usage != 0) {
        inject_hid_event(0x07, usage, 0, flags); 
    }
}

// Helper to map common names to Bundle IDs
static NSString *resolve_bundle_id(NSString *input) {
    if ([input containsString:@"."]) return input; // Already a bundle ID
    
    NSDictionary *map = @{
        @"youtube": @"com.google.ios.youtube",
        @"spotify": @"com.spotify.client",
        @"settings": @"com.apple.Preferences",
        @"safari": @"com.apple.mobilesafari",
        @"messages": @"com.apple.MobileSMS",
        @"imessage": @"com.apple.MobileSMS",
        @"home": @"com.apple.Home",
        @"photos": @"com.apple.mobileslideshow",
        @"camera": @"com.apple.camera",
        @"clock": @"com.apple.mobiletimer",
        @"maps": @"com.apple.Maps",
        @"calendar": @"com.apple.mobilecal",
        @"weather": @"com.apple.weather",
        @"notes": @"com.apple.mobilenotes",
        @"reminders": @"com.apple.reminders",
        @"appstore": @"com.apple.AppStore",
        @"mail": @"com.apple.mobilemail",
        @"music": @"com.apple.Music",
        @"phone": @"com.apple.mobilephone",
        @"stocks": @"com.apple.stocks",
        @"calculator": @"com.apple.calculator",
        @"tv": @"com.apple.tv",
        @"videos": @"com.apple.videos",
        @"wallet": @"com.apple.Passbook",
        @"watch": @"com.apple.Bridge",
        @"facetime": @"com.apple.facetime",
        @"files": @"com.apple.DocumentsApp"
    };
    
    NSString *mapped = map[[input lowercaseString]];
    return mapped ? mapped : input; // Return mapped ID or original input if not found
}

// IPC for RemoteCompanion app notifications (use Documents for TrollStore access)
#define kIPCPath @"/var/mobile/Documents/rc_notify.plist"
#define kNotifyName "com.pizzaman.show_banner"

static void send_notification(NSString *title, NSString *message, BOOL urgent) {
    NSDictionary *payload = @{
        @"title": title ?: @"RemoteCommand",
        @"message": message ?: @"",
        @"urgent": @(urgent)
    };
    [payload writeToFile:kIPCPath atomically:YES];
    
    // Post Darwin notification to wake companion app
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR(kNotifyName),
        NULL, NULL, true);
    
    SRLog(@"Sent notification IPC: %@ - %@", title, message);
}

// ============ TRIGGER CONFIG SYSTEM ============
#define kTriggerConfigFilename @"rc_triggers.plist"
#define kTriggerConfigPath @"/var/mobile/Documents/rc_triggers.plist"
#define kConfigChangedNotification "com.pizzaman.rc.configchanged"

static NSDictionary *g_triggerConfig = nil;
static NSString *g_resolvedConfigPath = nil;

// Find config file - check shared path first, then search app containers
static NSString *find_config_path() {
    NSFileManager *fm = [NSFileManager defaultManager];
    
    // First try the shared path
    if ([fm fileExistsAtPath:kTriggerConfigPath]) {
        return kTriggerConfigPath;
    }
    
    // Search for RemoteCompanion app container
    NSString *containersPath = @"/var/mobile/Containers/Data/Application";
    NSArray *uuids = [fm contentsOfDirectoryAtPath:containersPath error:nil];
    
    for (NSString *uuid in uuids) {
        NSString *configPath = [NSString stringWithFormat:@"%@/%@/Documents/%@", 
                                containersPath, uuid, kTriggerConfigFilename];
        if ([fm fileExistsAtPath:configPath]) {
            SRLog(@"Found config in container: %@", configPath);
            return configPath;
        }
    }
    
    return nil;
}
// ============ BLACKLIST SYSTEM ============

static NSArray *g_blacklist = nil;
static NSTimeInterval g_lastBlacklistLoad = 0;

static void load_blacklist() {
    NSString *path = @"/var/mobile/Library/Preferences/com.saihgupr.remotecompanion.blacklist.plist";
    g_blacklist = [NSArray arrayWithContentsOfFile:path];
    if (!g_blacklist) {
        // Empty by default for new users
        g_blacklist = @[];
    }
    g_lastBlacklistLoad = [[NSDate date] timeIntervalSince1970];
}

static BOOL save_blacklist(NSArray *list) {
    NSString *path = @"/var/mobile/Library/Preferences/com.saihgupr.remotecompanion.blacklist.plist";
    g_blacklist = [list copy];
    g_lastBlacklistLoad = [[NSDate date] timeIntervalSince1970];
    return [g_blacklist writeToFile:path atomically:YES];
}

static BOOL RC_IsForegroundAppExcluded() {
    static BOOL cachedResult = NO;
    static NSTimeInterval lastCheck = 0;
    static NSString *lastBundleID = nil;
    
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (now - lastCheck < 0.5) {
        return cachedResult;
    }
    
    @autoreleasepool {
        // Reload blacklist every 10 seconds or if never loaded
        if (!g_blacklist || now - g_lastBlacklistLoad > 10.0) {
            load_blacklist();
        }

        __block NSString *frontBundleID = nil;
        void (^getBlock)(void) = ^{
            SpringBoard *sb = (SpringBoard *)[UIApplication sharedApplication];
            if (sb && [sb respondsToSelector:@selector(_accessibilityFrontMostApplication)]) {
                SBApplication *frontApp = [sb _accessibilityFrontMostApplication];
                frontBundleID = [frontApp bundleIdentifier];
            }
        };

        if ([NSThread isMainThread]) getBlock();
        else dispatch_sync(dispatch_get_main_queue(), getBlock);

        BOOL result = NO;
        if (frontBundleID) {
            if (![frontBundleID isEqualToString:lastBundleID]) {
                SRLog(@"Foreground App: %@", frontBundleID);
                lastBundleID = frontBundleID;
            }
            
            NSString *lowerID = [frontBundleID lowercaseString];
            for (NSString *excluded in g_blacklist) {
                if ([lowerID isEqualToString:[excluded lowercaseString]]) {
                    result = YES;
                    break;
                }
            }
        }
        
        lastCheck = now;
        cachedResult = result;
        return result;
    }
}

static NSString *get_human_name_for_trigger(NSString *key, NSDictionary *triggerData) {
    if (!key) return @"Unknown";
    
    // 1. Check for custom user-defined name first
    if ([triggerData isKindOfClass:[NSDictionary class]] && triggerData[@"name"]) {
        return triggerData[@"name"];
    }
    if ([triggerData isKindOfClass:[NSDictionary class]] && triggerData[@"title"]) {
        return triggerData[@"title"];
    }
    
    // 2. Built-in mappings
    static NSDictionary *builtInNames = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        builtInNames = @{
            @"shake": @"Shake Device",
            @"volume_up_hold": @"Volume Up Hold",
            @"volume_down_hold": @"Volume Down Hold",
            @"volume_both_press": @"Volume Up + Down (Both)",
            @"power_double_tap": @"Power Double-Tap",
            @"power_long_press": @"Power Long Press",
            @"power_triple_click": @"Power Triple Click",
            @"power_quadruple_click": @"Power Quadruple Click",
            @"power_volume_up": @"Power + Volume Up",
            @"power_volume_down": @"Power + Volume Down",
            @"trigger_statusbar_left_hold": @"Status Bar Left Hold",
            @"trigger_statusbar_center_hold": @"Status Bar Center Hold",
            @"trigger_statusbar_right_hold": @"Status Bar Right Hold",
            @"trigger_statusbar_swipe_left": @"Status Bar Swipe Left",
            @"trigger_statusbar_swipe_right": @"Status Bar Swipe Right",
            @"trigger_statusbar_double_tap": @"Status Bar Double Tap",
            @"trigger_home_triple_click": @"Home Button (Triple Click)",
            @"trigger_home_quadruple_click": @"Home Button (Quadruple Click)",
            @"trigger_home_double_click": @"Home Button (Double Click)",
            @"touchid_hold": @"Touch ID Hold (Rest Finger)",
            @"touchid_tap": @"Touch ID Single Tap",
            @"trigger_edge_left_swipe_up": @"Left Edge Swipe Up",
            @"trigger_edge_left_swipe_down": @"Left Edge Swipe Down",
            @"trigger_edge_right_swipe_up": @"Right Edge Swipe Up",
            @"trigger_edge_right_swipe_down": @"Right Edge Swipe Down",
            @"trigger_ringer_mute": @"Ringer Muted",
            @"trigger_ringer_unmute": @"Ringer Unmuted",
            @"trigger_ringer_toggle": @"Ringer Toggled",
            @"trigger_bottombar_swipe_left": @"Bottom Bar Swipe Left",
            @"trigger_bottombar_swipe_right": @"Bottom Bar Swipe Right"
        };
    });
    
    NSString *builtIn = builtInNames[key];
    if (builtIn) return builtIn;
    
    // 3. Prefix-based fallback
    if ([key hasPrefix:@"nfc_"]) return [NSString stringWithFormat:@"NFC Tag %@", [key substringFromIndex:4]];
    if ([key hasPrefix:@"wifi_connect_"]) return [NSString stringWithFormat:@"WiFi Connected: %@", [key substringFromIndex:13]];
    if ([key hasPrefix:@"wifi_disconnect_"]) return [NSString stringWithFormat:@"WiFi Disconnected: %@", [key substringFromIndex:16]];
    if ([key hasPrefix:@"bt_connect_"]) return [NSString stringWithFormat:@"Bluetooth Connected: %@", [key substringFromIndex:11]];
    if ([key hasPrefix:@"bt_disconnect_"]) return [NSString stringWithFormat:@"Bluetooth Disconnected: %@", [key substringFromIndex:14]];
    if ([key hasPrefix:@"app_launch_"]) return [NSString stringWithFormat:@"App Launched: %@", [key substringFromIndex:11]];
    if ([key hasPrefix:@"notif_"] || [key hasPrefix:@"notify_"]) return @"Notification Trigger";
    if ([key hasPrefix:@"sched_"]) return @"Scheduled Automation";
    
    return key;
}

static void load_trigger_config() {
    @autoreleasepool {
        // Find the config file
        NSString *path = find_config_path();
        
        if (path) {
            NSDictionary *newConfig = [NSDictionary dictionaryWithContentsOfFile:path];
            if (newConfig) {
                // Thread-safe update: replace the pointer
                g_triggerConfig = newConfig;
                g_resolvedConfigPath = path;
                SRLog(@"Loaded trigger config from %@: triggers=%lu",
                      path,
                      (unsigned long)[g_triggerConfig[@"triggers"] count]);
            } else {
                SRLog(@"Failed to parse config at %@", path);
            }
        } else {
            SRLog(@"No trigger config found at shared path or in app containers");
        }
    }
}

static void update_simulation_observers();

static float get_flash_brightness() {
    return 1.0f;
}

// Gesture management helper functions
static BOOL should_register_edge_gestures() { return NO; }
static void register_edge_gestures() {}
static void unregister_edge_gestures() {}
static void update_edge_gestures() {}
static void start_schedule_timer();

static void config_changed_callback(CFNotificationCenterRef center, void *observer,
                                    CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    SRLog(@"Config changed notification received.");
    
    // Ensure config loading and UI/Gesture updates happen on the main thread
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            SRLog(@"Reloading config on main thread...");
            load_trigger_config();
            SRLog(@"Config loaded. Updating simulation observers...");
            update_simulation_observers();
            SRLog(@"Simulation observers updated. Updating edge gestures...");
            update_edge_gestures(); 
            SRLog(@"Edge gestures updated. Checking schedule timer...");
            start_schedule_timer();
            SRLog(@"Schedule timer check complete. Config reload complete.");
        } @catch (NSException *e) {
            SRLog(@"CRITICAL ERROR in config_changed_callback: %@\nStack: %@", e, e.callStackSymbols);
        }
    });
}

static void save_trigger_config() {
    if (!g_triggerConfig) return;
    NSString *sharedPath = @"/var/mobile/Documents/rc_triggers.plist";
    NSError *error = nil;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:g_triggerConfig
                                                               format:NSPropertyListXMLFormat_v1_0
                                                              options:0
                                                                error:&error];
    if (data && !error) {
        // 1. Try atomic write to shared path
        BOOL success = [data writeToFile:sharedPath atomically:YES];
        if (!success) {
            // 2. Fallback to POSIX open/write
            int fd = open([sharedPath UTF8String], O_WRONLY | O_CREAT | O_TRUNC, 0644);
            if (fd >= 0) {
                write(fd, [data bytes], [data length]);
                close(fd);
                success = YES;
                SRLog(@"[WebUI] Saved config to shared path via POSIX: %@", sharedPath);
            } else {
                SRLog(@"[WebUI] Failed to save to shared path (errno: %d)", errno);
            }
        } else {
            SRLog(@"[WebUI] Saved config to shared path: %@", sharedPath);
        }
        
        // 3. If we have a resolved container path, try saving there too
        if (g_resolvedConfigPath && ![g_resolvedConfigPath isEqualToString:sharedPath]) {
            [data writeToFile:g_resolvedConfigPath atomically:YES];
            SRLog(@"[WebUI] Also saved to container path: %@", g_resolvedConfigPath);
        }

        if (success) {
            notify_post("com.pizzaman.rc.configchanged");
        }
    } else {
        SRLog(@"[WebUI] Failed to serialize config: %@", error);
    }
    }

    static void register_config_observer() {
    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        NULL,
        config_changed_callback,
        CFSTR(kConfigChangedNotification),
        NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately
    );
    SRLog(@"Registered for config change notifications");
}

// ============ SIMULATION SYSTEM (for testing from app) ============
#define kSimulateNotificationPrefix "com.pizzaman.rc.simulate."

// Forward declaration
static NSString *handle_command(NSString *cmd);

static BOOL rc_is_if_action_item(id item) {
    if (![item isKindOfClass:[NSDictionary class]]) return NO;
    NSString *type = [[((NSDictionary *)item)[@"type"] description] lowercaseString];
    return [type isEqualToString:@"if"];
}

static BOOL rc_is_else_action_item(id item) {
    if (![item isKindOfClass:[NSDictionary class]]) return NO;
    NSString *type = [[((NSDictionary *)item)[@"type"] description] lowercaseString];
    return [type isEqualToString:@"else"];
}

static BOOL rc_is_else_if_action_item(id item) {
    if (![item isKindOfClass:[NSDictionary class]]) return NO;
    NSString *type = [[((NSDictionary *)item)[@"type"] description] lowercaseString];
    return [type isEqualToString:@"else_if"];
}

static BOOL rc_is_end_if_action_item(id item) {
    if (![item isKindOfClass:[NSDictionary class]]) return NO;
    NSString *type = [[((NSDictionary *)item)[@"type"] description] lowercaseString];
    return [type isEqualToString:@"end_if"] || [type isEqualToString:@"end"];
}



static NSString *rc_trimmed_uppercase_string(NSString *value) {
    if (![value isKindOfClass:[NSString class]]) return @"";
    return [[value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] uppercaseString];
}

static NSString *rc_status_command_for_condition_key(NSString *conditionKey) {
    if (![conditionKey isKindOfClass:[NSString class]]) return nil;
    NSDictionary *map = @{
        @"lock": @"lock status",
        @"player": @"player status",
        @"wifi": @"wifi status",
        @"cellular": @"cell status",
        @"bluetooth": @"bluetooth status",
        @"airplane": @"airplane status",
        @"silent_vibration": @"vibration silent-status",
        @"ring_vibration": @"vibration ring-status",
        @"orientation": @"orientation status"
    };
    return map[conditionKey];
}

static NSString *rc_canonical_status_value_for_condition_key(NSString *conditionKey, NSString *statusOutput) {
    NSString *upper = rc_trimmed_uppercase_string(statusOutput);
    if (upper.length == 0) return nil;
    
    if ([conditionKey isEqualToString:@"lock"]) {
        if ([upper containsString:@"UNLOCKED"]) return @"UNLOCKED";
        if ([upper containsString:@"LOCKED"]) return @"LOCKED";
        return nil;
    }
    
    if ([conditionKey isEqualToString:@"player"]) {
        if ([upper containsString:@"PLAYING"]) return @"PLAYING";
        if ([upper containsString:@"PAUSED"]) return @"PAUSED";
        if ([upper containsString:@"STOPPED"]) return @"STOPPED";
        return nil;
    }
    
    if ([conditionKey isEqualToString:@"orientation"]) {
        if ([upper containsString:@"PORTRAIT"]) return @"PORTRAIT";
        if ([upper containsString:@"LANDSCAPE"]) return @"LANDSCAPE";
        return nil;
    }
    
    if ([upper containsString:@" OFF"]) return @"OFF";
    if ([upper hasSuffix:@"OFF"]) return @"OFF";
    if ([upper containsString:@" ON"]) return @"ON";
    if ([upper hasSuffix:@"ON"]) return @"ON";
    
    return nil;
}

static BOOL rc_evaluate_if_condition(NSDictionary *ifAction) {
    if (![ifAction isKindOfClass:[NSDictionary class]]) return NO;
    
    NSString *conditionKey = ifAction[@"conditionKey"];
    NSString *expectedValue = rc_trimmed_uppercase_string(ifAction[@"expectedValue"] ?: ifAction[@"expected"]);
    
    if (conditionKey.length == 0) {
        // Backward compatibility for older formats where "condition" contained a command.
        NSString *legacyCondition = ifAction[@"condition"];
        if (legacyCondition.length == 0) return NO;
        NSString *legacyOutput = handle_command(legacyCondition);
        NSString *legacyUpper = rc_trimmed_uppercase_string(legacyOutput);
        return [legacyUpper isEqualToString:@"YES"] ||
               [legacyUpper isEqualToString:@"TRUE"] ||
               [legacyUpper isEqualToString:@"1"] ||
               [legacyUpper hasPrefix:@"ON"] ||
               [legacyUpper hasPrefix:@"LOCKED"] ||
               [legacyUpper hasPrefix:@"PLAYING"];
    }
    
    if ([conditionKey isEqualToString:@"front_app"]) {
        NSString *expectedValue = ifAction[@"expectedValue"] ?: ifAction[@"expected"];
        if (expectedValue.length == 0) return NO;
        
        __block NSString *actualBundleId = nil;
        void (^getBlock)(void) = ^{
            SBApplication *frontApp = [(SpringBoard *)[UIApplication sharedApplication] _accessibilityFrontMostApplication];
            actualBundleId = [frontApp bundleIdentifier];
        };
        
        if ([NSThread isMainThread]) getBlock();
        else dispatch_sync(dispatch_get_main_queue(), getBlock);
        
        return [actualBundleId isEqualToString:expectedValue];
    }
    
    if ([conditionKey isEqualToString:@"proximity"] || [conditionKey isEqualToString:@"pocket"] || [conditionKey isEqualToString:@"device_in_pocket"]) {
        NSString *statusOutput = handle_command(@"proximity");
        NSString *upperOutput = rc_trimmed_uppercase_string(statusOutput);
        BOOL isNear = ([upperOutput containsString:@"OBJECTINPROXIMITY=1"] || 
                       [upperOutput containsString:@"PROXIMITYSTATE=1"] || 
                       [upperOutput containsString:@"NEAR"]);
        
        BOOL expectedBool = [expectedValue isEqualToString:@"YES"] || 
                            [expectedValue isEqualToString:@"TRUE"] || 
                            [expectedValue isEqualToString:@"1"] || 
                            [expectedValue isEqualToString:@"NEAR"] || 
                            [expectedValue isEqualToString:@"ON"];
        return (isNear == expectedBool);
    }
    
    NSString *statusCommand = rc_status_command_for_condition_key(conditionKey);
    if (statusCommand.length == 0) return NO;
    
    NSString *statusOutput = handle_command(statusCommand);
    NSString *actualValue = rc_canonical_status_value_for_condition_key(conditionKey, statusOutput);
    if (actualValue.length == 0 || expectedValue.length == 0) return NO;
    
    return [actualValue isEqualToString:expectedValue];
}

static void rc_execute_action_sequence(NSArray *actions, NSString *triggerKey, BOOL simulationMode) {
    if (![actions isKindOfClass:[NSArray class]] || actions.count == 0) return;
    
    for (NSInteger idx = 0; idx < (NSInteger)actions.count; idx++) {
        id actionItem = actions[idx];
        
        if ([actionItem isKindOfClass:[NSString class]]) {
            NSString *action = (NSString *)actionItem;
            SRLog(@"[%@] -> %@", triggerKey, action);
            handle_command(action);
            usleep(simulationMode ? 50000 : 10000);
            continue;
        }
        
        if (![actionItem isKindOfClass:[NSDictionary class]]) {
            SRLog(@"[%@] Skipping unsupported action item: %@", triggerKey, actionItem);
            continue;
        }
        
        NSDictionary *dictAction = (NSDictionary *)actionItem;
        NSString *type = [[dictAction[@"type"] description] lowercaseString];
        
        if ([type isEqualToString:@"if"]) {
            BOOL shouldRunBlock = rc_evaluate_if_condition(dictAction);
            SRLog(@"[%@] If %@ == %@ -> %@", triggerKey, dictAction[@"conditionKey"], dictAction[@"expectedValue"], shouldRunBlock ? @"TRUE" : @"FALSE");
            
            if (shouldRunBlock) {
                // TRUE branch: just continue to next item. 
            } else {
                // FALSE branch: scan ahead at current nesting depth for next sibling branch (else_if, else, or end_if).
                NSInteger depth = 0;
                BOOL foundNextBranch = NO;
                for (NSInteger skipIdx = idx + 1; skipIdx < (NSInteger)actions.count; skipIdx++) {
                    id item = actions[skipIdx];
                    if (rc_is_if_action_item(item)) {
                        depth++;
                    } else if (rc_is_end_if_action_item(item)) {
                        depth--;
                        if (depth < 0) {
                            idx = skipIdx;
                            foundNextBranch = YES;
                            break;
                        }
                    } else if (depth == 0) {
                        if (rc_is_else_if_action_item(item)) {
                            NSDictionary *elseIfDict = (NSDictionary *)item;
                            BOOL elseIfVal = rc_evaluate_if_condition(elseIfDict);
                            SRLog(@"[%@] Else If %@ == %@ -> %@", triggerKey, elseIfDict[@"conditionKey"], elseIfDict[@"expectedValue"], elseIfVal ? @"TRUE" : @"FALSE");
                            if (elseIfVal) {
                                idx = skipIdx;
                                foundNextBranch = YES;
                                break;
                            }
                        } else if (rc_is_else_action_item(item)) {
                            idx = skipIdx;
                            foundNextBranch = YES;
                            break;
                        }
                    }
                }
                if (!foundNextBranch) {
                    SRLog(@"[%@] Missing End If marker; stopping action execution.", triggerKey);
                    break;
                }
            }
        } else if ([type isEqualToString:@"else"] || [type isEqualToString:@"else_if"]) {
            // If we reached an 'else' or 'else_if' directly, it means we were executing the TRUE branch of a preceding conditional.
            // Now we must skip the remaining branches (until the matching end_if).
            NSInteger depth = 1;
            for (NSInteger skipIdx = idx + 1; skipIdx < (NSInteger)actions.count; skipIdx++) {
                id item = actions[skipIdx];
                if (rc_is_if_action_item(item)) {
                    depth++;
                } else if (rc_is_end_if_action_item(item)) {
                    depth--;
                    if (depth == 0) {
                        idx = skipIdx;
                        break;
                    }
                }
            }
        } else if ([type isEqualToString:@"end_if"] || [type isEqualToString:@"end"]) {
            continue;
        } else {
            SRLog(@"[%@] Skipping unsupported dictionary action type: %@", triggerKey, type);
        }
    }
}

// Execute actions for simulation (bypasses master/enabled checks for testing)
static void execute_actions_for_simulation(NSString *triggerKey) {
    // Reload config to get fresh data
    load_trigger_config();
    
    if (!g_triggerConfig) {
        SRLog(@"SIMULATE: No trigger config loaded");
        return;
    }
    
    NSDictionary *triggers = g_triggerConfig[@"triggers"];
    NSDictionary *trigger = triggers[triggerKey];
    
    if (!trigger) {
        SRLog(@"SIMULATE: Trigger '%@' not found in config", triggerKey);
        return;
    }
    
    NSArray *actions = trigger[@"actions"];
    if (!actions || actions.count == 0) {
        SRLog(@"SIMULATE: No actions configured for '%@'", triggerKey);
        return;
    }
    
    SRLog(@"SIMULATE: Executing %lu actions for '%@'", (unsigned long)actions.count, triggerKey);
    rc_execute_action_sequence(actions, [NSString stringWithFormat:@"SIMULATE:%@", triggerKey], YES);
}

// Callback for simulation notifications
static void simulate_trigger_callback(CFNotificationCenterRef center, void *observer,
                                       CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    NSString *notificationName = (__bridge NSString *)name;
    NSString *prefix = @kSimulateNotificationPrefix;
    
    if ([notificationName hasPrefix:prefix]) {
        NSString *triggerKey = [notificationName substringFromIndex:prefix.length];
        SRLog(@"[SIMULATE] Received request for trigger: %@", triggerKey);
        
        // Execute off-main so status checks using dispatch_sync(main) never deadlock.
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            execute_actions_for_simulation(triggerKey);
        });
    }
}

static void update_simulation_observers() {
    @try {
        static NSMutableSet *g_registeredTriggers = nil;
        if (!g_registeredTriggers) g_registeredTriggers = [[NSMutableSet alloc] init];
        
        if (!g_triggerConfig) load_trigger_config();
        if (!g_triggerConfig) return;
        
        NSDictionary *triggers = g_triggerConfig[@"triggers"];
        int count = 0;
        for (NSString *key in triggers) {
            if (![g_registeredTriggers containsObject:key]) {
                NSString *notificationName = [NSString stringWithFormat:@"%s%@", kSimulateNotificationPrefix, key];
                CFNotificationCenterAddObserver(
                    CFNotificationCenterGetDarwinNotifyCenter(),
                    NULL,
                    simulate_trigger_callback,
                    (__bridge CFStringRef)notificationName,
                    NULL,
                    CFNotificationSuspensionBehaviorDeliverImmediately
                );
                [g_registeredTriggers addObject:key];
                count++;
            }
        }
        if (count > 0) {
            SRLog(@"Registered %d NEW simulation observers (Total: %lu)", count, (unsigned long)g_registeredTriggers.count);
        }
    } @catch (NSException *e) {
         SRLog(@"ERROR in update_simulation_observers: %@", e);
    }
}

static void register_simulation_observers() {
    update_simulation_observers();
}

// Execute all actions for a trigger
void RCExecuteTrigger(NSString *triggerKey) {
    // Check for foreground exclusions (Safety/Blacklist)
    if (RC_IsForegroundAppExcluded()) {
        SRLog(@"Triggers SUPPRESSED for frontmost application (Excluded/Blacklisted)");
        return;
    }

    if (!g_triggerConfig) {
        SRLog(@"Config missing, attempting to load...");
        load_trigger_config();
        if (!g_triggerConfig) {
            SRLog(@"ERROR: Could not load trigger config for '%@'", triggerKey);
            return;
        }
    }
    
    // Check master toggle
    if (![g_triggerConfig[@"masterEnabled"] boolValue]) {
        SRLog(@"Master toggle is OFF, skipping trigger '%@'", triggerKey);
        return;
    }
    
    id triggers = g_triggerConfig[@"triggers"];
    if (!triggers || ![triggers isKindOfClass:[NSDictionary class]]) {
        SRLog(@"ERROR: Triggers dictionary is missing or invalid");
        return;
    }
    
    id trigger = ((NSDictionary *)triggers)[triggerKey];
    if (!trigger || ![trigger isKindOfClass:[NSDictionary class]]) {
        SRLog(@"TRIGGER NOT FOUND or INVALID: '%@'", triggerKey);
        return;
    }
    
    if (![trigger[@"enabled"] boolValue]) {
        SRLog(@"Trigger '%@' is DISABLED in config", triggerKey);
        return;
    }
    
    NSArray *actions = trigger[@"actions"];
    if (!actions || actions.count == 0) {
        SRLog(@"No actions configured for '%@'", triggerKey);
        return;
    }
    
    SRLog(@"TRIGGER FIRED: '%@' -> Executing %lu actions", triggerKey, (unsigned long)actions.count);
    
    // Execute on background queue to allow for delays and blocking operations
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        rc_execute_action_sequence(actions, triggerKey, NO);
    });
}

// ============ SCHEDULING SYSTEM ============
static NSInteger g_lastScheduledCheckMinute = -1;
static dispatch_source_t g_scheduleTimer = nil;

static void stop_schedule_timer() {
    if (g_scheduleTimer) {
        dispatch_source_cancel(g_scheduleTimer);
        g_scheduleTimer = nil;
        SRLog(@"[Schedule] Timer stopped (No active schedules)");
    }
}

static void check_scheduled_triggers() {
    NSDate *now = [NSDate date];
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSDateComponents *components = [calendar components:(NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitWeekday) fromDate:now];
    
    NSInteger currentHour = components.hour;
    NSInteger currentMinute = components.minute;
    NSInteger currentWeekday = components.weekday;
    
    // Prevent double firing within the same minute
    if (g_lastScheduledCheckMinute == currentMinute) {
        return;
    }
    
    if (!g_triggerConfig) {
        load_trigger_config();
    }
    
    if (!g_triggerConfig) return;
    
    NSDictionary *triggers = g_triggerConfig[@"triggers"];
    for (NSString *key in triggers) {
        if ([key hasPrefix:@"sched_"]) {
            NSDictionary *trigger = triggers[key];
            if (![trigger[@"enabled"] boolValue]) continue;
            
            NSDictionary *sched = trigger[@"schedule"];
            if (!sched) continue;
            
            NSInteger schedHour = [sched[@"hour"] integerValue];
            NSInteger schedMinute = [sched[@"minute"] integerValue];
            NSArray *schedDays = sched[@"days"];
            
            if (schedHour == currentHour && schedMinute == currentMinute) {
                if ([schedDays containsObject:@(currentWeekday)]) {
                    SRLog(@"[Schedule] FIRE: %@", key);
                    RCExecuteTrigger(key);
                }
            }
        }
    }
    
    g_lastScheduledCheckMinute = currentMinute;
}

static void start_schedule_timer() {
    // Check if any scheduled triggers actually exist before starting
    if (!g_triggerConfig) load_trigger_config();
    if (!g_triggerConfig) return;

    BOOL hasSchedules = NO;
    NSDictionary *triggers = g_triggerConfig[@"triggers"];
    for (NSString *key in triggers) {
        if ([key hasPrefix:@"sched_"]) {
            NSDictionary *trigger = triggers[key];
            if ([trigger[@"enabled"] boolValue]) {
                hasSchedules = YES;
                break;
            }
        }
    }

    if (!hasSchedules) {
        stop_schedule_timer();
        return;
    }

    // If we already have a timer running, don't start a second one.
    // The self-correcting nature of the existing timer will pick up any config changes
    // on its next tick, or the manual reload will handle it.
    if (g_scheduleTimer) return;

    SRLog(@"[Schedule] Starting self-correcting background timer...");
    
    g_scheduleTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    
    // Define the scheduling logic
    __block void (^scheduleNext)(void) = ^ {
        if (!g_scheduleTimer) return;

        NSDate *now = [NSDate date];
        NSTimeInterval currentTime = [now timeIntervalSince1970];
        
        // Calculate the next minute boundary (e.g., if it's 1:00:10, target 1:01:00)
        NSTimeInterval nextMinute = ceil(currentTime / 60.0) * 60.0;
        
        // If we are extremely close to the next minute (due to processing time), target the minute after
        if (nextMinute - currentTime < 0.1) {
            nextMinute += 60.0;
        }
        
        // Add a tiny 100ms delay to ensure the system clock has definitely rolled over the minute
        NSTimeInterval delay = (nextMinute - currentTime) + 0.1;
        dispatch_time_t start = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC));
        
        SRLog(@"[Schedule] Next precision check in %.2f seconds", delay);
        
        // Use DISPATCH_TIME_FOREVER for interval to make it a one-shot
        dispatch_source_set_timer(g_scheduleTimer, start, DISPATCH_TIME_FOREVER, 0.1 * NSEC_PER_SEC);
    };

    dispatch_source_set_event_handler(g_scheduleTimer, ^{
        check_scheduled_triggers();
        
        // Re-schedule itself for the next minute
        scheduleNext();
    });
    
    // Initial schedule
    scheduleNext();
    dispatch_resume(g_scheduleTimer);
}

BOOL RCIsNFCEnabled() {
    if (!g_triggerConfig) {
        load_trigger_config();
    }
    // Default to YES if missing
    if (!g_triggerConfig[@"nfcEnabled"]) {
        return YES;
    }
    return [g_triggerConfig[@"nfcEnabled"] boolValue];
}

// ============ SYSTEM EVENT HANDLERS (WiFi/BT Triggers) ============
#import <notify.h>

static NSString *g_lastKnownSSID = nil;

static void handle_wifi_transition() {
    SBWiFiManager *wifiManager = [objc_getClass("SBWiFiManager") sharedInstance];
    NSString *currentSSID = [wifiManager currentNetworkName];
    
    SRLog(@"[RCWiFi] Transition detected. Current SSID: %@ (Previous: %@)", currentSSID, g_lastKnownSSID);
    
    if (currentSSID && ![currentSSID isEqualToString:g_lastKnownSSID]) {
        // Connected to a new network
        NSString *triggerKey = [NSString stringWithFormat:@"wifi_connect_%@", currentSSID];
        SRLog(@"[RCWiFi] Connection trigger: %@", triggerKey);
        RCExecuteTrigger(triggerKey);
    } else if (!currentSSID && g_lastKnownSSID) {
        // Disconnected from previous network
        NSString *triggerKey = [NSString stringWithFormat:@"wifi_disconnect_%@", g_lastKnownSSID];
        SRLog(@"[RCWiFi] Disconnection trigger: %@", triggerKey);
        RCExecuteTrigger(triggerKey);
    }
    
    g_lastKnownSSID = [currentSSID copy];
}

static void handle_bluetooth_transition(NSNotification *notification, BOOL connected) {
    BluetoothDevice *device = notification.object;
    if (![device isKindOfClass:objc_getClass("BluetoothDevice")]) return;
    
    NSString *address = [device address];
    NSString *name = [device name];
    SRLog(@"[RCBT] Device %@ (%@) %@", name, address, connected ? @"Connected" : @"Disconnected");
    
    // App now saves trigger keys by name not address!
    NSString *triggerKey = [NSString stringWithFormat:@"%@_%@", connected ? @"bt_connect" : @"bt_disconnect", name];
    RCExecuteTrigger(triggerKey);
}

static void handle_wifi_notification(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        handle_wifi_transition();
    });
}

// Power State Globals & Helpers
static BOOL g_powerStateInitialized = NO;
static BOOL g_lastPowerConnectedState = NO;

static BOOL is_device_power_connected() {
    [UIDevice currentDevice].batteryMonitoringEnabled = YES;
    UIDeviceBatteryState state = [UIDevice currentDevice].batteryState;
    if (state == UIDeviceBatteryStateCharging || state == UIDeviceBatteryStateFull) {
        return YES;
    }
    if (state == UIDeviceBatteryStateUnplugged) {
        return NO;
    }
    
    Class SBUIClass = objc_getClass("SBUIController");
    if (SBUIClass) {
        id uiCtrl = [SBUIClass respondsToSelector:@selector(sharedInstance)] ? [SBUIClass performSelector:@selector(sharedInstance)] : nil;
        if (uiCtrl) {
            if ([uiCtrl respondsToSelector:@selector(isACPowerConnected)]) {
                return [uiCtrl isACPowerConnected];
            } else if ([uiCtrl respondsToSelector:@selector(isOnAC)]) {
                return [uiCtrl isOnAC];
            }
        }
    }
    return NO;
}

static void initialize_power_state() {
    if (g_powerStateInitialized) return;
    [UIDevice currentDevice].batteryMonitoringEnabled = YES;
    g_lastPowerConnectedState = is_device_power_connected();
    g_powerStateInitialized = YES;
    SRLog(@"⚡ [RCSystem] Power state successfully initialized to: %@", g_lastPowerConnectedState ? @"CONNECTED" : @"DISCONNECTED");
}

static void handle_power_state_transition(BOOL isConnected, NSString *source) {
    if (!g_powerStateInitialized) {
        initialize_power_state();
    }
    
    if (isConnected != g_lastPowerConnectedState) {
        g_lastPowerConnectedState = isConnected;
        if (isConnected) {
            SRLog(@"⚡ [RCSystem] Transition detected (%@): POWER CONNECTED. Executing trigger_power_connect.", source);
            RCExecuteTrigger(@"trigger_power_connect");
        } else {
            SRLog(@"⚡ [RCSystem] Transition detected (%@): POWER DISCONNECTED. Executing trigger_power_disconnect.", source);
            RCExecuteTrigger(@"trigger_power_disconnect");
        }
    }
}

static void handle_power_state_notification(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    NSString *notifName = (__bridge NSString *)name;
    SRLog(@"⚡ [RCSystem] Received Power State Notification: %@", notifName);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        handle_power_state_transition(is_device_power_connected(), @"Darwin Notification");
    });
}

// Biometric / Touch ID / Lock State Globals
static NSTimeInterval g_bioFingerDownTime = 0;
static BOOL g_bioHoldTriggered = NO;
static NSTimer *g_bioWatchdogTimer = nil;
static NSTimeInterval g_bioIgnoreUntil = 0;
static BOOL g_bioWasLocked = NO;
static BOOL g_lastLockedState = NO;
static BOOL g_lockStateInitialized = NO;

static void initialize_lock_state() {
    if (g_lockStateInitialized) return;
    
    Class LSMClass = objc_getClass("SBLockScreenManager");
    if (LSMClass) {
        SBLockScreenManager *lsm = [LSMClass sharedInstance];
        if (lsm) {
            g_lastLockedState = [lsm isUILocked];
            g_lockStateInitialized = YES;
            SRLog(@"🔒 [RCSystem] Lock state successfully initialized to: %@", g_lastLockedState ? @"LOCKED" : @"UNLOCKED");
        }
    }
}

static void handle_lock_state_transition(BOOL isLocked, NSString *source) {
    if (!g_lockStateInitialized) {
        initialize_lock_state();
        if (!g_lockStateInitialized) {
            g_lastLockedState = !isLocked; // Set opposite to force transition detection on fallback
            g_lockStateInitialized = YES;
            SRLog(@"🔒 [RCSystem] Lock state fallback initialized via %@ to: %@", source, g_lastLockedState ? @"LOCKED" : @"UNLOCKED");
        }
    }
    
    if (isLocked != g_lastLockedState) {
        g_lastLockedState = isLocked;
        if (isLocked) {
            SRLog(@"🔒 [RCSystem] Transition detected (%@): DEVICE LOCKED. Executing trigger_device_lock.", source);
            RCExecuteTrigger(@"trigger_device_lock");
        } else {
            SRLog(@"🔓 [RCSystem] Transition detected (%@): DEVICE UNLOCKED. Executing trigger_device_unlock.", source);
            RCExecuteTrigger(@"trigger_device_unlock");
            
            // Reset biometric / unlock-related side effects
            g_bioFingerDownTime = 0;
            g_bioHoldTriggered = NO;
            
            if (g_bioWatchdogTimer) {
                [g_bioWatchdogTimer invalidate];
                g_bioWatchdogTimer = nil;
                SRLog(@"🔐 [RCSystem] Cancelled pending Biometric trigger due to Unlock (%@)", source);
            }
            
            // Brief suppression after unlock (1.0s), without overwriting a larger existing suppression
            NSTimeInterval newIgnore = [[NSDate date] timeIntervalSince1970] + 1.0;
            if (g_bioIgnoreUntil < newIgnore) {
                g_bioIgnoreUntil = newIgnore;
            }
        }
    }
}

static void handle_lock_state_notification(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        Class LSMClass = objc_getClass("SBLockScreenManager");
        if (!LSMClass) {
            SRLog(@"⚠️ [RCSystem] SBLockScreenManager class not found in notify handler");
            return;
        }
        
        SBLockScreenManager *lsm = [LSMClass sharedInstance];
        if (!lsm) {
            SRLog(@"⚠️ [RCSystem] SBLockScreenManager instance is nil in notify handler");
            return;
        }
        
        BOOL currentLocked = [lsm isUILocked];
        SRLog(@"🔒 [RCSystem] SBLockScreenManager.isUILocked = %@", currentLocked ? @"YES" : @"NO");
        handle_lock_state_transition(currentLocked, @"Darwin Notification");
    });
}

static BOOL g_mediaStateInitialized = NO;
static BOOL g_lastMediaPlayingState = NO;
static NSString *g_lastMediaTitle = nil;
static NSString *g_lastMediaArtist = nil;
static NSString *g_lastMediaBundleID = nil;

static void handle_media_state_change() {
    MRMediaRemoteGetNowPlayingClient(dispatch_get_main_queue(), ^(void *clientObj) {
        __block NSString *bundleID = @"";
        if (clientObj) {
            CFStringRef bundleIDRef = MRNowPlayingClientGetBundleIdentifier(clientObj);
            if (bundleIDRef) {
                bundleID = (__bridge NSString *)bundleIDRef;
            }
        }
        
        MRMediaRemoteGetNowPlayingApplicationIsPlaying(dispatch_get_main_queue(), ^(Boolean isPlayingNow) {
            MRMediaRemoteGetNowPlayingInfo(dispatch_get_main_queue(), ^(CFDictionaryRef information) {
                NSDictionary *info = (__bridge NSDictionary *)information;
                NSString *title = info ? (info[(__bridge NSString *)kMRMediaRemoteNowPlayingInfoTitle] ?: @"") : @"";
                NSString *artist = info ? (info[(__bridge NSString *)kMRMediaRemoteNowPlayingInfoArtist] ?: @"") : @"";
                
                BOOL playingChanged = NO;
                BOOL trackChanged = NO;
                
                if (!g_mediaStateInitialized) {
                    g_lastMediaPlayingState = isPlayingNow;
                    g_lastMediaTitle = [title copy];
                    g_lastMediaArtist = [artist copy];
                    g_lastMediaBundleID = [bundleID copy];
                    g_mediaStateInitialized = YES;
                    SRLog(@"🎵 [RCSystem] Media state initialized: playing=%@, title='%@', artist='%@', bundleID='%@'", 
                          isPlayingNow ? @"YES" : @"NO", title, artist, bundleID);
                    return;
                }
                
                if (isPlayingNow != g_lastMediaPlayingState) {
                    playingChanged = YES;
                    g_lastMediaPlayingState = isPlayingNow;
                }
                
                if (![title isEqualToString:g_lastMediaTitle] || 
                    ![artist isEqualToString:g_lastMediaArtist] || 
                    ![bundleID isEqualToString:g_lastMediaBundleID]) {
                    trackChanged = YES;
                    g_lastMediaTitle = [title copy];
                    g_lastMediaArtist = [artist copy];
                    g_lastMediaBundleID = [bundleID copy];
                }
                
                if (playingChanged) {
                    if (isPlayingNow) {
                        SRLog(@"🎵 [RCSystem] Media Playback State -> PLAYING. Executing trigger_media_play.");
                        RCExecuteTrigger(@"trigger_media_play");
                    } else {
                        SRLog(@"🎵 [RCSystem] Media Playback State -> PAUSED. Executing trigger_media_pause.");
                        RCExecuteTrigger(@"trigger_media_pause");
                    }
                }
                
                if (trackChanged) {
                    SRLog(@"🎵 [RCSystem] Media Track Changed: %@ - %@ (%@). Executing trigger_media_track_change.", title, artist, bundleID);
                    RCExecuteTrigger(@"trigger_media_track_change");
                }
            });
        });
    });
}

static void handle_media_state_notification(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    NSString *notifName = (__bridge NSString *)name;
    SRLog(@"🎵 [RCSystem] Received Media State Notification: %@", notifName);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        handle_media_state_change();
    });
}

static void register_system_event_observers() {
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    
    // Initialize initial lock state & power state
    initialize_lock_state();
    initialize_power_state();

    // Power State: Cocoa Touch observers
    [nc addObserverForName:UIDeviceBatteryStateDidChangeNotification 
                    object:nil 
                     queue:[NSOperationQueue mainQueue] 
                usingBlock:^(NSNotification *note) {
        handle_power_state_transition(is_device_power_connected(), @"UIDeviceBatteryStateDidChangeNotification");
    }];
    [nc addObserverForName:UIDeviceBatteryLevelDidChangeNotification 
                    object:nil 
                     queue:[NSOperationQueue mainQueue] 
                usingBlock:^(NSNotification *note) {
        handle_power_state_transition(is_device_power_connected(), @"UIDeviceBatteryLevelDidChangeNotification");
    }];

    // Power State: Darwin Notifications
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), 
                                    NULL, 
                                    handle_power_state_notification, 
                                    CFSTR("com.apple.system.powersources.source"), 
                                    NULL, 
                                    CFNotificationSuspensionBehaviorDeliverImmediately);

    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), 
                                    NULL, 
                                    handle_power_state_notification, 
                                    CFSTR("com.apple.system.powersources.timeremaining"), 
                                    NULL, 
                                    CFNotificationSuspensionBehaviorDeliverImmediately);

    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), 
                                    NULL, 
                                    handle_power_state_notification, 
                                    CFSTR("com.apple.system.powersources.percent"), 
                                    NULL, 
                                    CFNotificationSuspensionBehaviorDeliverImmediately);

    // WiFi: Track network changes (Darwin Notification)
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), 
                                    NULL, 
                                    handle_wifi_notification, 
                                    CFSTR("com.apple.system.config.network_change"), 
                                    NULL, 
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
    
    // Device Lock / Unlock: Track screen transitions via Darwin Notifications
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), 
                                    NULL, 
                                    handle_lock_state_notification, 
                                    CFSTR("com.apple.springboard.lockcomplete"), 
                                    NULL, 
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
                                    
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), 
                                    NULL, 
                                    handle_lock_state_notification, 
                                    CFSTR("com.apple.springboard.lockstate"), 
                                    NULL, 
                                    CFNotificationSuspensionBehaviorDeliverImmediately);

    // Media State changes (Darwin Notifications)
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), 
                                    NULL, 
                                    handle_media_state_notification, 
                                    CFSTR("com.apple.mediaremote.nowplayinginfochanged"), 
                                    NULL, 
                                    CFNotificationSuspensionBehaviorDeliverImmediately);

    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), 
                                    NULL, 
                                    handle_media_state_notification, 
                                    CFSTR("com.apple.MediaRemote.nowPlayingApplicationIsPlayingDidChange"), 
                                    NULL, 
                                    CFNotificationSuspensionBehaviorDeliverImmediately);

    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), 
                                    NULL, 
                                    handle_media_state_notification, 
                                    CFSTR("com.apple.MediaRemote.nowPlayingApplicationPlaybackStateDidChange"), 
                                    NULL, 
                                    CFNotificationSuspensionBehaviorDeliverImmediately);

    // Initialize initial media state
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        handle_media_state_change();
    });

    // Bluetooth: Track connection/disconnection
    [nc addObserverForName:@"BluetoothDeviceConnectSuccessNotification" 
                    object:nil 
                     queue:[NSOperationQueue mainQueue] 
                usingBlock:^(NSNotification *note) {
        handle_bluetooth_transition(note, YES);
    }];
    
    [nc addObserverForName:@"BluetoothDeviceDisconnectSuccessNotification" 
                    object:nil 
                     queue:[NSOperationQueue mainQueue] 
                usingBlock:^(NSNotification *note) {
        handle_bluetooth_transition(note, NO);
    }];

    SRLog(@"[RCTweak] WiFi, Bluetooth and Media observers registered.");
}

// ============ LUA INTERPRETER ============

// ── Touch / Digitizer helper ──────────────────────────────────────────────────
// Dedicated serial queue for touch HID events (must NOT run on main thread).
static dispatch_queue_t rc_touch_queue(void) {
    static dispatch_queue_t q = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        q = dispatch_queue_create("com.pizzaman.remotecommand.touch", DISPATCH_QUEUE_SERIAL);
    });
    return q;
}

static uint32_t rc_get_target_context_id(void) {
    __block uint32_t contextID = 0;
    void (^blk)(void) = ^{
        UIWindow *win = nil;
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        win = [UIApplication sharedApplication].keyWindow;
        #pragma clang diagnostic pop
        if (!win && [UIWindow respondsToSelector:@selector(allWindowsIncludingInternalWindows:onlyVisibleWindows:)]) {
            NSArray *wins = [UIWindow allWindowsIncludingInternalWindows:YES onlyVisibleWindows:YES];
            win = [wins firstObject];
        }
        if (win && [win respondsToSelector:@selector(_contextId)]) {
            contextID = [win _contextId];
        }
    };

    if ([NSThread isMainThread]) {
        blk();
    } else {
        dispatch_sync(dispatch_get_main_queue(), blk);
    }
    return contextID;
}

static void rc_inject_touch(double x, double y, uint32_t eventMask, uint32_t phase) {
    if (!_IOHIDEventSystemClientCreate || !_IOHIDEventCreateDigitizerEvent ||
        !_IOHIDEventCreateDigitizerFingerEvent || !_IOHIDEventAppendEvent ||
        !_IOHIDEventSystemClientDispatchEvent) {
        void *handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW);
        if (handle) {
            _IOHIDEventSystemClientCreate = (IOHIDEventSystemClientRef (*)(CFAllocatorRef))dlsym(handle, "IOHIDEventSystemClientCreate");
            _IOHIDEventCreateKeyboardEvent = (IOHIDEventRef (*)(CFAllocatorRef, uint64_t, uint32_t, uint32_t, boolean_t, IOHIDEventOptionBits))dlsym(handle, "IOHIDEventCreateKeyboardEvent");
            _IOHIDEventSystemClientDispatchEvent = (void (*)(IOHIDEventSystemClientRef, IOHIDEventRef))dlsym(handle, "IOHIDEventSystemClientDispatchEvent");
            _IOHIDEventCreateDigitizerEvent = (IOHIDEventRef (*)(CFAllocatorRef, uint64_t, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t, double, double, double, double, double, boolean_t, boolean_t, IOHIDEventOptionBits))dlsym(handle, "IOHIDEventCreateDigitizerEvent");
            _IOHIDEventCreateDigitizerFingerEvent = (IOHIDEventRef (*)(CFAllocatorRef, uint64_t, uint32_t, uint32_t, uint32_t, double, double, double, double, double, boolean_t, boolean_t, IOHIDEventOptionBits))dlsym(handle, "IOHIDEventCreateDigitizerFingerEvent");
            _IOHIDEventAppendEvent = (void (*)(IOHIDEventRef, IOHIDEventRef, IOHIDEventOptionBits))dlsym(handle, "IOHIDEventAppendEvent");
            _IOHIDEventSetIntegerValue = (void (*)(IOHIDEventRef, uint32_t, int32_t))dlsym(handle, "IOHIDEventSetIntegerValue");
            _IOHIDEventSetSenderID = (void (*)(IOHIDEventRef, uint64_t))dlsym(handle, "IOHIDEventSetSenderID");
        }
    }

    if (!_IOHIDEventSystemClientCreate || !_IOHIDEventCreateDigitizerEvent ||
        !_IOHIDEventCreateDigitizerFingerEvent || !_IOHIDEventAppendEvent ||
        !_IOHIDEventSystemClientDispatchEvent) {
        SRLog(@"[RCTouch] ERROR: Digitizer HID functions not available.");
        return;
    }

    IOHIDEventSystemClientRef client = _IOHIDEventSystemClientCreate(kCFAllocatorDefault);
    if (!client) return;

    uint64_t now = mach_absolute_time();
    double normX = x / [UIScreen mainScreen].bounds.size.width;
    double normY = y / [UIScreen mainScreen].bounds.size.height;
    boolean_t isTouch = (phase != 0); // 0 = up (not touching), 1 = down/move

    IOHIDEventRef digitizerEvent = _IOHIDEventCreateDigitizerEvent(
        kCFAllocatorDefault, now,
        0, 0, 0,
        eventMask, 0,
        0, 0, 0, 0, 0,
        isTouch, isTouch, 0
    );

    if (!digitizerEvent) {
        CFRelease(client);
        return;
    }

    IOHIDEventRef fingerEvent = _IOHIDEventCreateDigitizerFingerEvent(
        kCFAllocatorDefault, now,
        1, 1, eventMask,
        normX, normY, 0,
        isTouch ? 1.0 : 0.0, 0,
        isTouch, isTouch, 0
    );

    if (fingerEvent) {
        if (_IOHIDEventSetIntegerValue) {
            _IOHIDEventSetIntegerValue(fingerEvent, 0x0B0000 + 3, (int32_t)phase);
        }
        _IOHIDEventAppendEvent(digitizerEvent, fingerEvent, 0);
        CFRelease(fingerEvent);
    }

    if (_IOHIDEventSetSenderID) {
        _IOHIDEventSetSenderID(digitizerEvent, 0xdefec80000000001ULL);
    }

    uint32_t contextID = rc_get_target_context_id();
    if (contextID != 0 && dlsym(RTLD_DEFAULT, "BKSHIDEventSetDigitizerInfo")) {
        BKSHIDEventSetDigitizerInfo(digitizerEvent, contextID, 0, 0, NULL, 0, 0);
    }

    _IOHIDEventSystemClientDispatchEvent(client, digitizerEvent);
    CFRelease(digitizerEvent);
    CFRelease(client);
}

static void perform_tap(double x, double y) {
    dispatch_async(rc_touch_queue(), ^{
        rc_inject_touch(x, y, 1 | 4, 1);
        usleep(40000);
        rc_inject_touch(x, y, 2, 0);
    });
}

static void perform_hold(double x, double y, uint32_t durationMs) {
    dispatch_async(rc_touch_queue(), ^{
        rc_inject_touch(x, y, 1 | 4, 1);
        usleep(durationMs * 1000);
        rc_inject_touch(x, y, 2, 0);
    });
}

static void perform_swipe(double startX, double startY, double endX, double endY, uint32_t steps, uint32_t durationMs) {
    dispatch_async(rc_touch_queue(), ^{
        uint32_t totalSteps = (steps == 0) ? 20 : steps;
        uint32_t stepDelayUs = (durationMs * 1000) / totalSteps;

        rc_inject_touch(startX, startY, 1 | 4, 1);
        usleep(stepDelayUs);

        for (uint32_t i = 1; i < totalSteps; i++) {
            double curX = startX + (endX - startX) * ((double)i / totalSteps);
            double curY = startY + (endY - startY) * ((double)i / totalSteps);
            rc_inject_touch(curX, curY, 4, 1);
            usleep(stepDelayUs);
        }

        rc_inject_touch(endX, endY, 2, 0);
    });
}

// Global hook to support native touch injection fallback in SpringBoard
%hook UIApplication
- (void)_enqueueHIDEvent:(IOHIDEventRef)event {
    %orig;
}
%end

static int lua_api_tap(lua_State *L) {
    double x = luaL_checknumber(L, 1);
    double y = luaL_checknumber(L, 2);
    perform_tap(x, y);
    return 0;
}

static int lua_api_hold(lua_State *L) {
    double x = luaL_checknumber(L, 1);
    double y = luaL_checknumber(L, 2);
    uint32_t durationMs = (uint32_t)luaL_optinteger(L, 3, 500);
    perform_hold(x, y, durationMs);
    return 0;
}

static int lua_api_swipe(lua_State *L) {
    double startX = luaL_checknumber(L, 1);
    double startY = luaL_checknumber(L, 2);
    double endX = luaL_checknumber(L, 3);
    double endY = luaL_checknumber(L, 4);
    uint32_t durationMs = (uint32_t)luaL_optinteger(L, 5, 300);
    perform_swipe(startX, startY, endX, endY, 20, durationMs);
    return 0;
}

static int lua_api_toast(lua_State *L) {
    const char *title = luaL_checkstring(L, 1);
    const char *sub = luaL_optstring(L, 2, NULL);
    const char *icon = luaL_optstring(L, 3, NULL);
    rc_show_hud_toast(
        [NSString stringWithUTF8String:title],
        sub ? [NSString stringWithUTF8String:sub] : nil,
        icon ? [NSString stringWithUTF8String:icon] : nil
    );
    return 0;
}

static int lua_api_exec(lua_State *L) {
    const char *cmd = luaL_checkstring(L, 1);
    NSString *output = handle_command([NSString stringWithFormat:@"exec %s", cmd]);
    lua_pushstring(L, [output UTF8String] ?: "");
    return 1;
}

static int lua_api_delay(lua_State *L) {
    double secs = luaL_checknumber(L, 1);
    usleep((useconds_t)(secs * 1000000.0));
    return 0;
}

static int lua_api_volume(lua_State *L) {
    if (lua_gettop(L) >= 1) {
        float vol = (float)luaL_checknumber(L, 1);
        AVSystemController *av = [objc_getClass("AVSystemController") sharedAVSystemController];
        [av setVolumeTo:(vol / 100.0f) forCategory:@"Audio/Video"];
        return 0;
    } else {
        AVSystemController *av = [objc_getClass("AVSystemController") sharedAVSystemController];
        float vol = 0.0f;
        [av getVolume:&vol forCategory:@"Audio/Video"];
        lua_pushnumber(L, (double)(vol * 100.0f));
        return 1;
    }
}

static void run_lua_script(NSString *script) {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        lua_State *L = luaL_newstate();
        if (!L) {
            SRLog(@"[Lua] ERROR: Failed to create Lua state.");
            return;
        }
        luaL_openlibs(L);

        lua_register(L, "tap", lua_api_tap);
        lua_register(L, "hold", lua_api_hold);
        lua_register(L, "swipe", lua_api_swipe);
        lua_register(L, "toast", lua_api_toast);
        lua_register(L, "exec", lua_api_exec);
        lua_register(L, "delay", lua_api_delay);
        lua_register(L, "volume", lua_api_volume);

        if (luaL_dostring(L, [script UTF8String]) != LUA_OK) {
            const char *err = lua_tostring(L, -1);
            SRLog(@"[Lua] Execution Error: %s", err ? err : "Unknown error");
        }
        lua_close(L);
    });
}

// Web UI HTTP Server Engine
#import <netinet/in.h>
#import <sys/socket.h>

static int g_webServerPort = 54001;
static BOOL g_webServerRunning = NO;

static NSString *get_webui_html() {
    NSString *bundlePath = [[NSBundle mainBundle] pathForResource:@"rc_webui" ofType:@"html"];
    if (bundlePath && [[NSFileManager defaultManager] fileExistsAtPath:bundlePath]) {
        return [NSString stringWithContentsOfFile:bundlePath encoding:NSUTF8StringEncoding error:nil];
    }
    NSString *trollstorePath = @"/var/mobile/Documents/rc_webui.html";
    if ([[NSFileManager defaultManager] fileExistsAtPath:trollstorePath]) {
        return [NSString stringWithContentsOfFile:trollstorePath encoding:NSUTF8StringEncoding error:nil];
    }
    NSString *rootlessPath = @"/var/jb/var/mobile/Documents/rc_webui.html";
    if ([[NSFileManager defaultManager] fileExistsAtPath:rootlessPath]) {
        return [NSString stringWithContentsOfFile:rootlessPath encoding:NSUTF8StringEncoding error:nil];
    }
    return @"<html><body><h1>RemoteCompanion Web UI</h1><p>rc_webui.html not found on device.</p></body></html>";
}

static BOOL RCIsWebUIEnabled() {
    if (!g_triggerConfig) {
        load_trigger_config();
    }
    if (!g_triggerConfig[@"webUIEnabled"]) {
        return YES; // Default to YES if missing
    }
    return [g_triggerConfig[@"webUIEnabled"] boolValue];
}

static void handle_web_client(int clientSock) {
    char buffer[8192];
    ssize_t bytesRead = read(clientSock, buffer, sizeof(buffer) - 1);
    if (bytesRead <= 0) { close(clientSock); return; }
    buffer[bytesRead] = '\0';

    NSString *reqStr = [NSString stringWithUTF8String:buffer];
    NSArray *lines = [reqStr componentsSeparatedByString:@"\r\n"];
    if (lines.count == 0) { close(clientSock); return; }

    NSString *firstLine = lines[0];
    NSArray *parts = [firstLine componentsSeparatedByString:@" "];
    if (parts.count < 2) { close(clientSock); return; }

    NSString *method = parts[0];
    NSString *url = parts[1];
    
    // Safety / Security check: Validate if Web UI is enabled
    BOOL isWebUIEnabled = RCIsWebUIEnabled();

    SRLog(@"[WebUI] %C %@ (Enabled: %s)", [method UTF8String][0], url, isWebUIEnabled ? "YES" : "NO");

    NSString *response = @"";

    if (!isWebUIEnabled) {
        response = @"HTTP/1.1 403 Forbidden\r\nContent-Type: application/json\r\nConnection: close\r\n\r\n{\"error\":\"Web UI disabled in settings\"}";
    } else if ([url isEqualToString:@"/"] || [url isEqualToString:@"/index.html"]) {
        NSString *html = get_webui_html();
        response = [NSString stringWithFormat:@"HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: %lu\r\nConnection: close\r\n\r\n%@",
                    (unsigned long)[html lengthOfBytesUsingEncoding:NSUTF8StringEncoding], html];
    } else if ([url isEqualToString:@"/api/config"] && [method isEqualToString:@"GET"]) {
        if (!g_triggerConfig) load_trigger_config();
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:g_triggerConfig options:0 error:nil];
        NSString *jsonStr = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        response = [NSString stringWithFormat:@"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: %lu\r\nConnection: close\r\n\r\n%@",
                    (unsigned long)[jsonStr lengthOfBytesUsingEncoding:NSUTF8StringEncoding], jsonStr];
    } else if ([url isEqualToString:@"/api/config"] && [method isEqualToString:@"POST"]) {
        NSRange bodyRange = [reqStr rangeOfString:@"\r\n\r\n"];
        if (bodyRange.location != NSNotFound) {
            NSString *body = [reqStr substringFromIndex:bodyRange.location + 4];
            NSData *bodyData = [body dataUsingEncoding:NSUTF8StringEncoding];
            NSDictionary *newConfig = [NSJSONSerialization JSONObjectWithData:bodyData options:0 error:nil];
            if ([newConfig isKindOfClass:[NSDictionary class]]) {
                g_triggerConfig = newConfig;
                save_trigger_config();
                response = @"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nConnection: close\r\n\r\n{\"success\":true}";
            } else {
                response = @"HTTP/1.1 400 Bad Request\r\nContent-Type: application/json\r\nConnection: close\r\n\r\n{\"error\":\"Invalid JSON\"}";
            }
        }
    } else if ([url hasPrefix:@"/api/trigger/"]) {
        NSString *key = [[url substringFromIndex:13] stringByRemovingPercentEncoding];
        // Strip any trailing query string if present
        NSRange qMark = [key rangeOfString:@"?"];
        if (qMark.location != NSNotFound) {
            key = [key substringToIndex:qMark.location];
        }
        RCExecuteTrigger(key);
        response = @"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nConnection: close\r\n\r\n{\"success\":true}";
    } else if ([url hasPrefix:@"/api/command"] && [method isEqualToString:@"POST"]) {
        // Query param command execution: /api/command?cmd=flashlight%20toggle
        NSRange qRange = [url rangeOfString:@"?cmd="];
        if (qRange.location != NSNotFound) {
            NSString *cmdEncoded = [url substringFromIndex:qRange.location + 5];
            NSString *cmd = [cmdEncoded stringByRemovingPercentEncoding];
            NSString *result = handle_command(cmd);
            NSData *jsonData = [NSJSONSerialization dataWithJSONObject:@{@"result": result ?: @""} options:0 error:nil];
            NSString *jsonStr = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
            response = [NSString stringWithFormat:@"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: %lu\r\nConnection: close\r\n\r\n%@",
                        (unsigned long)[jsonStr lengthOfBytesUsingEncoding:NSUTF8StringEncoding], jsonStr];
        } else {
            response = @"HTTP/1.1 400 Bad Request\r\nContent-Type: application/json\r\nConnection: close\r\n\r\n{\"error\":\"Missing cmd parameter\"}";
        }
    } else if ([url isEqualToString:@"/api/apps"] && [method isEqualToString:@"GET"]) {
        NSMutableArray *appArray = [NSMutableArray array];
        Class workspaceClass = objc_getClass("LSApplicationWorkspace");
        if (workspaceClass) {
            id workspace = [workspaceClass performSelector:@selector(defaultWorkspace)];
            NSArray *apps = [workspace performSelector:@selector(allInstalledApplications)];
            for (id appProxy in apps) {
                NSString *bid = [appProxy performSelector:@selector(applicationIdentifier)];
                NSString *name = [appProxy performSelector:@selector(localizedName)];
                if (bid && name) {
                    [appArray addObject:@{@"bundleId": bid, @"name": name}];
                }
            }
        }
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:appArray options:0 error:nil];
        NSString *jsonStr = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        response = [NSString stringWithFormat:@"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: %lu\r\nConnection: close\r\n\r\n%@",
                    (unsigned long)[jsonStr lengthOfBytesUsingEncoding:NSUTF8StringEncoding], jsonStr];
    } else if ([url isEqualToString:@"/api/logs"] && [method isEqualToString:@"GET"]) {
        NSString *logPath = @"/tmp/remotecommand.log";
        NSString *logContent = @"";
        if ([[NSFileManager defaultManager] fileExistsAtPath:logPath]) {
            NSError *err = nil;
            NSString *fullLog = [NSString stringWithContentsOfFile:logPath encoding:NSUTF8StringEncoding error:&err];
            if (fullLog) {
                NSArray<NSString *> *lines = [fullLog componentsSeparatedByString:@"\n"];
                NSUInteger count = lines.count;
                NSUInteger startIdx = (count > 150) ? (count - 150) : 0;
                NSArray<NSString *> *recentLines = [lines subarrayWithRange:NSMakeRange(startIdx, count - startIdx)];
                logContent = [recentLines componentsJoinedByString:@"\n"];
            }
        }
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:@{@"logs": logContent ?: @""} options:0 error:nil];
        NSString *jsonStr = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        response = [NSString stringWithFormat:@"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: %lu\r\nConnection: close\r\n\r\n%@",
                    (unsigned long)[jsonStr lengthOfBytesUsingEncoding:NSUTF8StringEncoding], jsonStr];
    } else if ([url isEqualToString:@"/api/version"] && [method isEqualToString:@"GET"]) {
        NSString *version = @"3.5.0";
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:@{@"version": version} options:0 error:nil];
        NSString *jsonStr = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        response = [NSString stringWithFormat:@"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: %lu\r\nConnection: close\r\n\r\n%@",
                    (unsigned long)[jsonStr lengthOfBytesUsingEncoding:NSUTF8StringEncoding], jsonStr];
    } else {
        response = @"HTTP/1.1 404 Not Found\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\n404 Not Found";
    }

    write(clientSock, [response UTF8String], [response lengthOfBytesUsingEncoding:NSUTF8StringEncoding]);
    close(clientSock);
}

static void start_web_server() {
    if (g_webServerRunning) return;
    g_webServerRunning = YES;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        int serverSock = socket(AF_INET, SOCK_STREAM, 0);
        if (serverSock < 0) return;

        int opt = 1;
        setsockopt(serverSock, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

        struct sockaddr_in addr;
        memset(&addr, 0, sizeof(addr));
        addr.sin_family = AF_INET;
        addr.sin_addr.s_addr = INADDR_ANY;
        addr.sin_port = htons(g_webServerPort);

        if (bind(serverSock, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
            close(serverSock);
            return;
        }

        listen(serverSock, 10);
        SRLog(@"Web UI Server running on port %d", g_webServerPort);

        while (g_webServerRunning) {
            struct sockaddr_in clientAddr;
            socklen_t clientLen = sizeof(clientAddr);
            int clientSock = accept(serverSock, (struct sockaddr *)&clientAddr, &clientLen);
            if (clientSock >= 0) {
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                    handle_web_client(clientSock);
                });
            }
        }
        close(serverSock);
    });
}

// Master Handler for all Trigger Commands
static NSString *handle_command(NSString *cmd) {
    if (!cmd || cmd.length == 0) return @"Error: Empty command";
    
    NSString *trimmed = [cmd stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *lowCmd = [trimmed lowercaseString];
    
    SRLog(@"Executing Command: %@", trimmed);
    
    // Flashlight Intensity (Percent 1-100)
    if ([lowCmd hasPrefix:@"flashlight "]) {
        NSString *valStr = [trimmed substringFromIndex:11];
        float level = [valStr floatValue] / 100.0f;
        level = MAX(0.01f, MIN(1.0f, level));
        
        Class captureDeviceClass = objc_getClass("AVCaptureDevice");
        if (captureDeviceClass) {
            AVCaptureDevice *device = [captureDeviceClass defaultDeviceWithMediaType:AVMediaTypeVideo];
            if ([device hasTorch] && [device isTorchAvailable]) {
                [device lockForConfiguration:nil];
                [device setTorchModeOnWithLevel:level error:nil];
                [device unlockForConfiguration];
                SRLog(@"Set Flashlight Intensity to %.2f", level);
                return [NSString stringWithFormat:@"Flashlight set to %d%%", (int)(level * 100)];
            }
        }
        return @"Flashlight unavailable";
    }

    // AudioMix Toggle
    if ([lowCmd isEqualToString:@"audiomix toggle"]) {
        BOOL currentState = get_audiomix_state();
        toggle_audiomix(!currentState);
        return [NSString stringWithFormat:@"AudioMix set to %@", !currentState ? @"ON" : @"OFF"];
    }
    if ([lowCmd isEqualToString:@"audiomix on"]) {
        toggle_audiomix(YES);
        return @"AudioMix ON";
    }
    if ([lowCmd isEqualToString:@"audiomix off"]) {
        toggle_audiomix(NO);
        return @"AudioMix OFF";
    }

    // SneakyCam Controls
    if ([lowCmd isEqualToString:@"sneakycam photo"] || [lowCmd isEqualToString:@"sneakycam takephoto"]) {
        SRLog(@"[SneakyCam] Triggering Photo Notification...");
        notify_post("com.spark.SneakyCam.takephoto");
        notify_post("com.spark.sneakycam.takephoto");
        notify_post("com.spark.SneakyCam.takePhoto");
        FILE *p = popen("/var/jb/usr/bin/notifyutil -p com.spark.SneakyCam.takephoto 2>/dev/null || /usr/bin/notifyutil -p com.spark.SneakyCam.takephoto 2>/dev/null || notifyutil -p com.spark.SneakyCam.takephoto 2>/dev/null", "r");
        if (p) pclose(p);
        rc_show_hud_toast(@"SneakyCam", @"Photo Triggered", @"camera.fill");
        return @"SneakyCam: Photo trigger sent";
    }
    if ([lowCmd isEqualToString:@"sneakycam video"] || [lowCmd isEqualToString:@"sneakycam record"] || [lowCmd isEqualToString:@"sneakycam startstopvideo"]) {
        SRLog(@"[SneakyCam] Triggering Video Notification...");
        notify_post("com.spark.SneakyCam.startstopvideo");
        notify_post("com.spark.sneakycam.startstopvideo");
        notify_post("com.spark.SneakyCam.startStopVideo");
        FILE *p = popen("/var/jb/usr/bin/notifyutil -p com.spark.SneakyCam.startstopvideo 2>/dev/null || /usr/bin/notifyutil -p com.spark.SneakyCam.startstopvideo 2>/dev/null || notifyutil -p com.spark.SneakyCam.startstopvideo 2>/dev/null", "r");
        if (p) pclose(p);
        rc_show_hud_toast(@"SneakyCam", @"Video Toggled", @"video.fill");
        return @"SneakyCam: Video trigger sent";
    }

    // Silent Vibration Toggle
    if ([lowCmd isEqualToString:@"vibration silent-toggle"]) {
        BOOL cur = get_system_vibration(YES);
        toggle_system_vibration(YES, !cur);
        rc_show_hud_toast(@"Silent Vibrate", !cur ? @"ON" : @"OFF", !cur ? @"bell.slash.fill" : @"bell.slash");
        return [NSString stringWithFormat:@"Silent Vibrate set to %@", !cur ? @"ON" : @"OFF"];
    }
    if ([lowCmd isEqualToString:@"vibration silent-on"]) {
        toggle_system_vibration(YES, YES);
        rc_show_hud_toast(@"Silent Vibrate", @"ON", @"bell.slash.fill");
        return @"Silent Vibrate ON";
    }
    if ([lowCmd isEqualToString:@"vibration silent-off"]) {
        toggle_system_vibration(YES, NO);
        rc_show_hud_toast(@"Silent Vibrate", @"OFF", @"bell.slash");
        return @"Silent Vibrate OFF";
    }

    // Ring Vibration Toggle
    if ([lowCmd isEqualToString:@"vibration ring-toggle"]) {
        BOOL cur = get_system_vibration(NO);
        toggle_system_vibration(NO, !cur);
        rc_show_hud_toast(@"Ring Vibrate", !cur ? @"ON" : @"OFF", !cur ? @"bell.fill" : @"bell");
        return [NSString stringWithFormat:@"Ring Vibrate set to %@", !cur ? @"ON" : @"OFF"];
    }
    if ([lowCmd isEqualToString:@"vibration ring-on"]) {
        toggle_system_vibration(NO, YES);
        rc_show_hud_toast(@"Ring Vibrate", @"ON", @"bell.fill");
        return @"Ring Vibrate ON";
    }
    if ([lowCmd isEqualToString:@"vibration ring-off"]) {
        toggle_system_vibration(NO, NO);
        rc_show_hud_toast(@"Ring Vibrate", @"OFF", @"bell");
        return @"Ring Vibrate OFF";
    }

    // HUD Toast command
    if ([lowCmd hasPrefix:@"toast "]) {
        NSString *argStr = [trimmed substringFromIndex:6];
        NSArray<NSString *> *args = rc_parse_quoted_arguments(argStr);
        
        NSString *title = (args.count > 0) ? args[0] : @"";
        NSString *subtitle = (args.count > 1) ? args[1] : nil;
        NSString *icon = (args.count > 2) ? args[2] : nil;
        
        rc_show_hud_toast(title, subtitle, icon);
        return [NSString stringWithFormat:@"Toast: %@", title];
    }
    
    // Lua Script execution
    if ([lowCmd hasPrefix:@"lua:"]) {
        NSString *script = [trimmed substringFromIndex:4];
        run_lua_script(script);
        return @"Lua Script Executed";
    }
    
    // Touch Gestures
    if ([lowCmd hasPrefix:@"tap "]) {
        NSArray *pts = [[trimmed substringFromIndex:4] componentsSeparatedByString:@" "];
        if (pts.count >= 2) {
            perform_tap([pts[0] doubleValue], [pts[1] doubleValue]);
            return @"Tap Executed";
        }
    }
    if ([lowCmd hasPrefix:@"hold "]) {
        NSArray *pts = [[trimmed substringFromIndex:5] componentsSeparatedByString:@" "];
        if (pts.count >= 2) {
            uint32_t dur = (pts.count >= 3) ? (uint32_t)[pts[2] integerValue] : 500;
            perform_hold([pts[0] doubleValue], [pts[1] doubleValue], dur);
            return @"Hold Executed";
        }
    }
    if ([lowCmd hasPrefix:@"swipe "]) {
        NSArray *pts = [[trimmed substringFromIndex:6] componentsSeparatedByString:@" "];
        if (pts.count >= 4) {
            uint32_t dur = (pts.count >= 5) ? (uint32_t)[pts[4] integerValue] : 300;
            perform_swipe([pts[0] doubleValue], [pts[1] doubleValue], [pts[2] doubleValue], [pts[3] doubleValue], 20, dur);
            return @"Swipe Executed";
        }
    }
    if ([lowCmd isEqualToString:@"swipeu"] || [lowCmd isEqualToString:@"swipeup"]) {
        perform_swipe(200, 600, 200, 200, 20, 300);
        return @"Swipe Up Executed";
    }
    if ([lowCmd isEqualToString:@"swiped"] || [lowCmd isEqualToString:@"swipedown"]) {
        perform_swipe(200, 200, 200, 600, 20, 300);
        return @"Swipe Down Executed";
    }
    if ([lowCmd isEqualToString:@"swipel"] || [lowCmd isEqualToString:@"swipeleft"]) {
        perform_swipe(300, 400, 50, 400, 20, 300);
        return @"Swipe Left Executed";
    }
    if ([lowCmd isEqualToString:@"swiper"] || [lowCmd isEqualToString:@"swiperight"]) {
        perform_swipe(50, 400, 300, 400, 20, 300);
        return @"Swipe Right Executed";
    }

    // Media Controls (MediaRemote)
    if ([lowCmd isEqualToString:@"play"]) {
        MRMediaRemoteSendCommand(kMRPlay, nil);
        return @"Media: Play";
    }
    if ([lowCmd isEqualToString:@"pause"]) {
        MRMediaRemoteSendCommand(kMRPause, nil);
        return @"Media: Pause";
    }
    if ([lowCmd isEqualToString:@"playpause"]) {
        MRMediaRemoteSendCommand(kMRTogglePlayPause, nil);
        return @"Media: Play/Pause Toggled";
    }
    if ([lowCmd isEqualToString:@"next"]) {
        MRMediaRemoteSendCommand(kMRNextTrack, nil);
        return @"Media: Next Track";
    }
    if ([lowCmd isEqualToString:@"prev"]) {
        MRMediaRemoteSendCommand(kMRPreviousTrack, nil);
        return @"Media: Previous Track";
    }

    // System Commands
    if ([lowCmd isEqualToString:@"home"]) {
        simulate_home_press();
        return @"Home Button Pressed";
    }
    if ([lowCmd isEqualToString:@"switcher"]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            Class switcherClass = objc_getClass("SBMainSwitcherController");
            if (switcherClass) {
                id switcher = [switcherClass performSelector:@selector(sharedInstance)];
                if ([switcher respondsToSelector:@selector(toggleSwitcherNoninteractively)]) {
                    [switcher performSelector:@selector(toggleSwitcherNoninteractively)];
                }
            }
        });
        return @"App Switcher Opened";
    }
    if ([lowCmd isEqualToString:@"lock"]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            Class LSMClass = objc_getClass("SBLockScreenManager");
            if (LSMClass) {
                SBLockScreenManager *lsm = [LSMClass sharedInstance];
                if ([lsm respondsToSelector:@selector(lockUIFromSource:withOptions:)]) {
                    [lsm lockUIFromSource:1 withOptions:nil];
                }
            }
        });
        return @"Device Locked";
    }
    if ([lowCmd isEqualToString:@"respring"]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            pid_t pid;
            const char *args[] = {"sbreload", NULL};
            posix_spawn(&pid, "/var/jb/usr/bin/sbreload", NULL, NULL, (char *const *)args, NULL);
        });
        return @"Respringing...";
    }
    if ([lowCmd isEqualToString:@"haptic"]) {
        trigger_haptic();
        return @"Haptic Feedback Triggered";
    }
    if ([lowCmd isEqualToString:@"screenshot"]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            Class SMClass = objc_getClass("SBScreenshotManager");
            if (SMClass) {
                SBScreenshotManager *sm = [SMClass sharedInstance];
                if ([sm respondsToSelector:@selector(saveScreenshotToCameraRollWithCompletion:)]) {
                    [sm saveScreenshotToCameraRollWithCompletion:nil];
                }
            }
        });
        return @"Screenshot Taken";
    }

    // Volume Control
    if ([lowCmd isEqualToString:@"volume up"]) {
        inject_consumer_key(kHIDUsage_Csmr_VolumeIncrement);
        return @"Volume Up";
    }
    if ([lowCmd isEqualToString:@"volume down"]) {
        inject_consumer_key(kHIDUsage_Csmr_VolumeDecrement);
        return @"Volume Down";
    }
    if ([lowCmd hasPrefix:@"set-vol "]) {
        float vol = [[trimmed substringFromIndex:8] floatValue] / 100.0f;
        vol = MAX(0.0f, MIN(1.0f, vol));
        AVSystemController *av = [objc_getClass("AVSystemController") sharedAVSystemController];
        [av setVolumeTo:vol forCategory:@"Audio/Video"];
        return [NSString stringWithFormat:@"Volume set to %d%%", (int)(vol * 100)];
    }

    // Brightness Control
    if ([lowCmd hasPrefix:@"brightness "]) {
        float level = [[trimmed substringFromIndex:11] floatValue] / 100.0f;
        level = MAX(0.0f, MIN(1.0f, level));
        dispatch_async(dispatch_get_main_queue(), ^{
            [[UIScreen mainScreen] setBrightness:level];
        });
        return [NSString stringWithFormat:@"Brightness set to %d%%", (int)(level * 100)];
    }

    // Run iOS Shortcut
    if ([lowCmd hasPrefix:@"shortcut:"]) {
        NSString *shortcutName = [trimmed substringFromIndex:9];
        dispatch_async(dispatch_get_main_queue(), ^{
            Class descriptorClass = objc_getClass("WFWorkflowDescriptor");
            Class runnerClass = objc_getClass("WFWorkflowRunnerClient");
            if (descriptorClass && runnerClass) {
                id descriptor = [[descriptorClass alloc] initWithName:shortcutName];
                id client = [[runnerClass alloc] initWithWorkflowDescriptor:descriptor input:nil parseInput:YES output:nil completion:nil];
                [client performSelector:@selector(start)];
            }
        });
        return [NSString stringWithFormat:@"Shortcut Started: %@", shortcutName];
    }

    // Open App by Bundle ID
    if ([lowCmd hasPrefix:@"uiopen "]) {
        NSString *bundleID = resolve_bundle_id([trimmed substringFromIndex:7]);
        dispatch_async(dispatch_get_main_queue(), ^{
            Class openServiceClass = objc_getClass("FBSOpenApplicationService");
            Class openOptionsClass = objc_getClass("FBSOpenApplicationOptions");
            if (openServiceClass && openOptionsClass) {
                id service = [openServiceClass serviceWithDefaultShellEndpoint];
                id options = [openOptionsClass optionsWithDictionary:@{}];
                [service openApplication:bundleID withOptions:options completion:nil];
            } else {
                LSApplicationWorkspace *workspace = [objc_getClass("LSApplicationWorkspace") defaultWorkspace];
                [workspace openApplicationWithBundleID:bundleID];
            }
        });
        return [NSString stringWithFormat:@"Opened App: %@", bundleID];
    }

    // Kill App by Bundle ID
    if ([lowCmd hasPrefix:@"kill "]) {
        NSString *bundleID = resolve_bundle_id([trimmed substringFromIndex:5]);
        dispatch_async(dispatch_get_main_queue(), ^{
            BKSTerminateApplicationForReasonAndReportWithDescription(bundleID, 5, false, @"RemoteCompanion Kill Command");
        });
        return [NSString stringWithFormat:@"Killed App: %@", bundleID];
    }

    // DND Control
    if ([lowCmd isEqualToString:@"dnd toggle"]) {
        BOOL cur = get_dnd_state();
        toggle_dnd(!cur);
        return [NSString stringWithFormat:@"Do Not Disturb set to %@", !cur ? @"ON" : @"OFF"];
    }
    if ([lowCmd isEqualToString:@"dnd on"]) {
        toggle_dnd(YES);
        return @"Do Not Disturb ON";
    }
    if ([lowCmd isEqualToString:@"dnd off"]) {
        toggle_dnd(NO);
        return @"Do Not Disturb OFF";
    }

    // Low Power Mode Control
    if ([lowCmd isEqualToString:@"low power toggle"] || [lowCmd isEqualToString:@"lpm toggle"]) {
        BOOL cur = get_lpm_state();
        toggle_lpm(!cur);
        return [NSString stringWithFormat:@"Low Power Mode set to %@", !cur ? @"ON" : @"OFF"];
    }
    if ([lowCmd isEqualToString:@"low power on"] || [lowCmd isEqualToString:@"lpm on"]) {
        toggle_lpm(YES);
        return @"Low Power Mode ON";
    }
    if ([lowCmd isEqualToString:@"low power off"] || [lowCmd isEqualToString:@"lpm off"]) {
        toggle_lpm(NO);
        return @"Low Power Mode OFF";
    }

    // Wi-Fi Control
    if ([lowCmd isEqualToString:@"wifi toggle"]) {
        SBWiFiManager *wm = [objc_getClass("SBWiFiManager") sharedInstance];
        BOOL cur = [wm wiFiEnabled];
        [wm setWiFiEnabled:!cur];
        return [NSString stringWithFormat:@"WiFi set to %@", !cur ? @"ON" : @"OFF"];
    }
    if ([lowCmd isEqualToString:@"wifi on"]) {
        SBWiFiManager *wm = [objc_getClass("SBWiFiManager") sharedInstance];
        [wm setWiFiEnabled:YES];
        return @"WiFi ON";
    }
    if ([lowCmd isEqualToString:@"wifi off"]) {
        SBWiFiManager *wm = [objc_getClass("SBWiFiManager") sharedInstance];
        [wm setWiFiEnabled:NO];
        return @"WiFi OFF";
    }

    // Cellular Data Control
    if ([lowCmd isEqualToString:@"cellular toggle"] || [lowCmd isEqualToString:@"cell toggle"]) {
        BOOL cur = get_cellular_state();
        set_cellular_state(!cur);
        return [NSString stringWithFormat:@"Cellular Data set to %@", !cur ? @"ON" : @"OFF"];
    }
    if ([lowCmd isEqualToString:@"cellular on"] || [lowCmd isEqualToString:@"cell on"]) {
        set_cellular_state(YES);
        return @"Cellular Data ON";
    }
    if ([lowCmd isEqualToString:@"cellular off"] || [lowCmd isEqualToString:@"cell off"]) {
        set_cellular_state(NO);
        return @"Cellular Data OFF";
    }

    // Bluetooth Control
    if ([lowCmd isEqualToString:@"bluetooth toggle"] || [lowCmd isEqualToString:@"bt toggle"]) {
        BluetoothManager *bm = [objc_getClass("BluetoothManager") sharedInstance];
        BOOL cur = [bm enabled];
        [bm setEnabled:!cur];
        [bm setPowered:!cur];
        return [NSString stringWithFormat:@"Bluetooth set to %@", !cur ? @"ON" : @"OFF"];
    }
    if ([lowCmd isEqualToString:@"bluetooth on"] || [lowCmd isEqualToString:@"bt on"]) {
        BluetoothManager *bm = [objc_getClass("BluetoothManager") sharedInstance];
        [bm setEnabled:YES];
        [bm setPowered:YES];
        return @"Bluetooth ON";
    }
    if ([lowCmd isEqualToString:@"bluetooth off"] || [lowCmd isEqualToString:@"bt off"]) {
        BluetoothManager *bm = [objc_getClass("BluetoothManager") sharedInstance];
        [bm setEnabled:NO];
        [bm setPowered:NO];
        return @"Bluetooth OFF";
    }

    // Delay command
    if ([lowCmd hasPrefix:@"delay "]) {
        double secs = [[trimmed substringFromIndex:6] doubleValue];
        usleep((useconds_t)(secs * 1000000.0));
        return [NSString stringWithFormat:@"Delayed %.1fs", secs];
    }

    // Status Queries
    if ([lowCmd isEqualToString:@"lock status"]) {
        Class LSMClass = objc_getClass("SBLockScreenManager");
        if (LSMClass) {
            SBLockScreenManager *lsm = [LSMClass sharedInstance];
            return [lsm isUILocked] ? @"LOCKED" : @"UNLOCKED";
        }
        return @"UNKNOWN";
    }
    if ([lowCmd isEqualToString:@"wifi status"]) {
        SBWiFiManager *wm = [objc_getClass("SBWiFiManager") sharedInstance];
        return [wm wiFiEnabled] ? @"ON" : @"OFF";
    }
    if ([lowCmd isEqualToString:@"cell status"] || [lowCmd isEqualToString:@"cellular status"]) {
        return get_cellular_state() ? @"ON" : @"OFF";
    }
    if ([lowCmd isEqualToString:@"bluetooth status"] || [lowCmd isEqualToString:@"bt status"]) {
        BluetoothManager *bm = [objc_getClass("BluetoothManager") sharedInstance];
        return [bm enabled] ? @"ON" : @"OFF";
    }
    if ([lowCmd isEqualToString:@"orientation status"]) {
        UIInterfaceOrientation orientation = [(SpringBoard *)[UIApplication sharedApplication] activeInterfaceOrientation];
        return UIInterfaceOrientationIsLandscape(orientation) ? @"LANDSCAPE" : @"PORTRAIT";
    }
    
    // General Shell Command (Exec)
    if ([lowCmd hasPrefix:@"exec "]) {
        NSString *shellCmd = [trimmed substringFromIndex:5];
        char buffer[128];
        NSMutableString *result = [NSMutableString string];
        FILE *pipe = popen([shellCmd UTF8String], "r");
        if (pipe) {
            while (fgets(buffer, sizeof(buffer), pipe) != NULL) {
                [result appendString:[NSString stringWithUTF8String:buffer]];
            }
            pclose(pipe);
        }
        return result.length > 0 ? result : @"Command Executed (No Output)";
    }

    // Trigger Key Execution Fallback
    if ([lowCmd hasPrefix:@"trigger:"]) {
        NSString *trigKey = [[trimmed substringFromIndex:8] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        RCExecuteTrigger(trigKey);
        return [NSString stringWithFormat:@"Trigger '%@' executed", trigKey];
    }
    if (g_triggerConfig && g_triggerConfig[@"triggers"] && g_triggerConfig[@"triggers"][trimmed]) {
        RCExecuteTrigger(trimmed);
        return [NSString stringWithFormat:@"Trigger '%@' executed", trimmed];
    }

    return [NSString stringWithFormat:@"Unknown Command: %@", trimmed];
}

static void trigger_haptic() {
    dispatch_async(dispatch_get_main_queue(), ^{
        AudioServicesPlaySystemSound(1519); // Peek haptic
    });
}

// Background Socket IPC Server (/tmp/remotecompanion.sock)
static void start_server() {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        unlink("/tmp/remotecompanion.sock");
        int serverSock = socket(AF_UNIX, SOCK_STREAM, 0);
        if (serverSock < 0) return;

        struct sockaddr_un addr;
        memset(&addr, 0, sizeof(addr));
        addr.sun_family = AF_UNIX;
        strcpy(addr.sun_path, "/tmp/remotecompanion.sock");

        if (bind(serverSock, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
            close(serverSock);
            return;
        }

        chmod("/tmp/remotecompanion.sock", 0777);
        listen(serverSock, 5);
        SRLog(@"IPC Server Listening on /tmp/remotecompanion.sock");

        while (1) {
            int clientSock = accept(serverSock, NULL, NULL);
            if (clientSock >= 0) {
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                    char buffer[1024];
                    ssize_t bytesRead = read(clientSock, buffer, sizeof(buffer) - 1);
                    if (bytesRead > 0) {
                        buffer[bytesRead] = '\0';
                        NSString *cmd = [NSString stringWithUTF8String:buffer];
                        NSString *res = handle_command(cmd);
                        write(clientSock, [res UTF8String], [res lengthOfBytesUsingEncoding:NSUTF8StringEncoding]);
                    }
                    close(clientSock);
                });
            }
        }
    });
}

// Background HID Listener for hardware volume buttons & triggers
static void setup_background_hid_listener() {
    static BOOL initialized = NO;
    if (initialized) return;
    initialized = YES;

    void *handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW);
    if (!handle) return;

    _IOHIDEventSystemClientCreate = (IOHIDEventSystemClientRef (*)(CFAllocatorRef))dlsym(handle, "IOHIDEventSystemClientCreate");
    _IOHIDEventSystemClientDispatchEvent = (void (*)(IOHIDEventSystemClientRef, IOHIDEventRef))dlsym(handle, "IOHIDEventSystemClientDispatchEvent");

    SRLog(@"Background HID Listener Initialized.");
}

%ctor {
    @autoreleasepool {
        SRLog(@"[RemoteCompanion] Initializing Tweak Constructor...");
        load_trigger_config();
        start_web_server();
        start_server();
        setup_background_hid_listener();
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            config_changed_callback,
            CFSTR("com.pizzaman.rc.configchanged"),
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately
        );
    }
}
