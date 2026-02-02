#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <netinet/in.h>
#import <sys/socket.h>
#import <sys/un.h>
#import <unistd.h>
#include <arpa/inet.h>
#import <spawn.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#import <mach/mach_time.h>
#import "native_curl.h"

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

void SRLog(NSString *format, ...);

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

@interface LSApplicationWorkspace : NSObject
+ (id)defaultWorkspace;
- (BOOL)openApplicationWithBundleID:(id)arg1;
@end

%hook SBVoiceControlController
- (id)init {
    id r = %orig;
    sharedVoiceControl = r;
    SRLog(@"[SpringRemote] Captured SBVoiceControlController init: %@", r);
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
    SRLog(@"[SpringRemote] Captured SBSiriHardwareButtonInteraction init: %@", r);
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
- (void)unlockUIFromSource:(int)source withOptions:(id)options;
- (BOOL)isUILocked;
- (id)lockScreenViewController;
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
- (SBApplication *)_accessibilityFrontMostApplication;
@end

@interface SBOrientationLockManager : NSObject
+ (instancetype)sharedInstance;
- (void)lock;
- (void)unlock;
- (BOOL)isUserLocked;
@end

@interface SBScreenshotManager : NSObject
+ (instancetype)sharedInstance;
- (void)saveScreenshotToCameraRollWithCompletion:(id)completion;
@end

@interface SBUIController : NSObject
+ (instancetype)sharedInstance;
- (void)handleScreenshotGestureFired:(id)arg1;
@end

@interface SBRingerControl : NSObject
+ (instancetype)sharedInstance;
- (BOOL)isRingerMuted;
- (void)setRingerMuted:(BOOL)muted;
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
    
    NSLog(@"[RemoteCommand] %@", message);
    
    NSString *logMsg = [NSString stringWithFormat:@"%@ [RemoteCommand] %@\n", [NSDate date], message];
    NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:@"/tmp/remotecommand.log"];
    if (fileHandle) {
        @try {
            [fileHandle seekToEndOfFile];
            [fileHandle writeData:[logMsg dataUsingEncoding:NSUTF8StringEncoding]];
            [fileHandle closeFile];
        } @catch (NSException *e) {}
    } else {
        [logMsg writeToFile:@"/tmp/remotecommand.log" atomically:YES encoding:NSUTF8StringEncoding error:nil];
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
            
            if (!ServiceClass || !DetailsClass) {
                SRLog(@"[SpringRemote] DND classes not found");
                return;
            }

            // Use the SAME client identifier as Control Center (from Assertions.json)
            DNDModeAssertionService *service = [ServiceClass serviceForClientIdentifier:@"com.apple.donotdisturb.control-center.module"];
            
            // Always invalidate existing assertions first to prevent stacking/errors (Idempotency)
            NSError *invalidateErr = nil;
            [service invalidateAllActiveModeAssertionsWithError:&invalidateErr];
            
            if (state) {
                // Turn ON
                // Try to use a more robust identifier or userRequested approach if possible.
                // For now, let's stick to explicit default but log heavily.
                 DNDModeAssertionDetails *details = [DetailsClass detailsWithIdentifier:@"com.apple.control-center.manual-toggle"
                                                                     modeIdentifier:@"com.apple.donotdisturb.mode.default"
                                                                           lifetime:nil];
                NSError *err = nil;
                id assertion = [service takeModeAssertionWithDetails:details error:&err];
                if (err) SRLog(@"[SpringRemote] Failed to enable DND: %@", err);
                else SRLog(@"[SpringRemote] DND Enabled. Assertion: %@", assertion);
            } else {
                SRLog(@"[SpringRemote] DND Disabled");
            }
        } @catch (NSException *e) {
            SRLog(@"[SpringRemote] EXCEPTION in toggle_dnd: %@", e);
        }
    });
}

static void toggle_lpm(BOOL state) {
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            Class BatterySaverClass = objc_getClass("_CDBatterySaver");
            if (!BatterySaverClass) {
                SRLog(@"[SpringRemote] _CDBatterySaver class not found");
                return;
            }
            
            id saver = [BatterySaverClass batterySaver];
            if (!saver) {
                SRLog(@"[SpringRemote] Failed to get batterySaver instance");
                return;
            }
            
            NSError *err = nil;
            // Power mode: 0 = normal, 1 = low power
            BOOL result = [saver setPowerMode:(state ? 1 : 0) error:&err];
            
            if (err) {
                SRLog(@"[SpringRemote] Failed to set LPM: %@", err);
            } else {
                SRLog(@"[SpringRemote] LPM %@. Result: %d", state ? @"Enabled" : @"Disabled", result);
            }
        } @catch (NSException *e) {
            SRLog(@"[SpringRemote] EXCEPTION in toggle_lpm: %@", e);
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
        DNDModeAssertionService *service = [ServiceClass serviceForClientIdentifier:@"com.apple.donotdisturb.control-center.module"];
        NSError *err = nil;
        id assertion = [service activeModeAssertionWithError:&err];
        return (assertion != nil);
    }
    return NO;
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

// Helper to inject a HID Consumer Page event (wrapper)
static void inject_consumer_key(int usage) {
    inject_hid_event(kHIDPage_Consumer, usage, 50000000, 0); // 50ms hold
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
            SRLog(@"[SpringRemote] Found config in container: %@", configPath);
            return configPath;
        }
    }
    
    return nil;
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
                SRLog(@"[SpringRemote] Loaded trigger config from %@: masterEnabled=%@, triggers=%lu",
                      path,
                      g_triggerConfig[@"masterEnabled"],
                      (unsigned long)[g_triggerConfig[@"triggers"] count]);
            } else {
                SRLog(@"[SpringRemote] Failed to parse config at %@", path);
            }
        } else {
            SRLog(@"[SpringRemote] No trigger config found at shared path or in app containers");
        }
    }
}
static void update_simulation_observers();

// Forward declarations for gesture management functions
static BOOL should_register_edge_gestures();
static void register_edge_gestures();
static void unregister_edge_gestures();
static void update_edge_gestures();

static void config_changed_callback(CFNotificationCenterRef center, void *observer,
                                    CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    SRLog(@"[SpringRemote] Config changed notification received.");
    
    // Ensure config loading and UI/Gesture updates happen on the main thread
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            SRLog(@"[SpringRemote] Reloading config on main thread...");
            load_trigger_config();
            SRLog(@"[SpringRemote] Config loaded. Updating simulation observers...");
            update_simulation_observers();
            SRLog(@"[SpringRemote] Simulation observers updated. Updating edge gestures...");
            update_edge_gestures(); 
            SRLog(@"[SpringRemote] Edge gestures updated. Config reload complete.");
        } @catch (NSException *e) {
            SRLog(@"[SpringRemote] CRITICAL ERROR in config_changed_callback: %@\nStack: %@", e, e.callStackSymbols);
        }
    });
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
    SRLog(@"[SpringRemote] Registered for config change notifications");
}

// ============ SIMULATION SYSTEM (for testing from app) ============
#define kSimulateNotificationPrefix "com.pizzaman.rc.simulate."

// Forward declaration
static NSString *handle_command(NSString *cmd);

// Execute actions for simulation (bypasses master/enabled checks for testing)
static void execute_actions_for_simulation(NSString *triggerKey) {
    // Reload config to get fresh data
    load_trigger_config();
    
    if (!g_triggerConfig) {
        SRLog(@"[SpringRemote] SIMULATE: No trigger config loaded");
        return;
    }
    
    NSDictionary *triggers = g_triggerConfig[@"triggers"];
    NSDictionary *trigger = triggers[triggerKey];
    
    if (!trigger) {
        SRLog(@"[SpringRemote] SIMULATE: Trigger '%@' not found in config", triggerKey);
        return;
    }
    
    NSArray *actions = trigger[@"actions"];
    if (!actions || actions.count == 0) {
        SRLog(@"[SpringRemote] SIMULATE: No actions configured for '%@'", triggerKey);
        return;
    }
    
    SRLog(@"[SpringRemote] SIMULATE: Executing %lu actions for '%@'", (unsigned long)actions.count, triggerKey);
    
    // Execute each action in sequence
    for (NSString *action in actions) {
        SRLog(@"[SpringRemote] SIMULATE: -> Executing: %@", action);
        handle_command(action);
        // Small delay between actions to let them complete
        usleep(50000); // 50ms
    }
}

// Callback for simulation notifications
static void simulate_trigger_callback(CFNotificationCenterRef center, void *observer,
                                       CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    NSString *notificationName = (__bridge NSString *)name;
    NSString *prefix = @kSimulateNotificationPrefix;
    
    if ([notificationName hasPrefix:prefix]) {
        NSString *triggerKey = [notificationName substringFromIndex:prefix.length];
        SRLog(@"[SIMULATE] Received request for trigger: %@", triggerKey);
        
        // Execute on main thread
        dispatch_async(dispatch_get_main_queue(), ^{
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
         SRLog(@"[SpringRemote] ERROR in update_simulation_observers: %@", e);
    }
}

static void register_simulation_observers() {
    update_simulation_observers();
}

// Execute all actions for a trigger
void RCExecuteTrigger(NSString *triggerKey) {
    if (!g_triggerConfig) {
        SRLog(@"[SpringRemote] Config missing, attempting to load...");
        load_trigger_config();
        if (!g_triggerConfig) {
            SRLog(@"[SpringRemote] ERROR: Could not load trigger config for '%@'", triggerKey);
            return;
        }
    }
    
    // Check master toggle
    if (![g_triggerConfig[@"masterEnabled"] boolValue]) {
        SRLog(@"[SpringRemote] Master toggle is OFF, skipping trigger '%@'", triggerKey);
        return;
    }
    
    NSDictionary *triggers = g_triggerConfig[@"triggers"];
    NSDictionary *trigger = triggers[triggerKey];
    
    if (!trigger) {
        SRLog(@"[SpringRemote] TRIGGER NOT FOUND: '%@'", triggerKey);
        // Special case: if it's an NFC tag not in config, maybe log UID?
        return;
    }
    
    if (![trigger[@"enabled"] boolValue]) {
        SRLog(@"[SpringRemote] Trigger '%@' is DISABLED in config", triggerKey);
        return;
    }
    
    NSArray *actions = trigger[@"actions"];
    if (!actions || actions.count == 0) {
        SRLog(@"[SpringRemote] No actions configured for '%@'", triggerKey);
        return;
    }
    
    SRLog(@"[SpringRemote] TRIGGER FIRED: '%@' -> Executing %lu actions", triggerKey, (unsigned long)actions.count);
    
    // Execute on background queue to allow for delays and blocking operations
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // Execute each action in sequence
        for (NSString *action in actions) {
            SRLog(@"[SpringRemote] [%@] -> % @", triggerKey, action);
            handle_command(action);
            // Small default delay between actions
            usleep(10000); 
        }
    });
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

// ============ LUA INTERPRETER ============

// Lua binding: openURL(urlString)
static int lua_openURL(lua_State *L) {
    const char *urlStr = luaL_checkstring(L, 1);
    NSString *urlString = [NSString stringWithUTF8String:urlStr];
    
    SRLog(@"[SpringRemote] Lua openURL: %@", urlString);
    
    dispatch_async(dispatch_get_main_queue(), ^{
        NSURL *url = [NSURL URLWithString:urlString];
        if (url) {
            [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        }
    });
    
    return 0;
}

// Lua binding: curl(urlString) - synchronous HTTP GET
static int lua_curl(lua_State *L) {
    const char *urlStr = luaL_checkstring(L, 1);
    NSString *urlString = [NSString stringWithUTF8String:urlStr];
    
    SRLog(@"[SpringRemote] Lua curl: %@", urlString);
    
    // Use native curl implementation
    NSString *curlCmd = [NSString stringWithFormat:@"curl %@", urlString];
    perform_native_curl(curlCmd);
    
    return 0;
}

// Lua binding: delay(seconds)
static int lua_delay(lua_State *L) {
    double seconds = luaL_checknumber(L, 1);
    SRLog(@"[SpringRemote] Lua delay: %.2f seconds", seconds);
    usleep((useconds_t)(seconds * 1000000));
    return 0;
}

// Lua binding: haptic()
static int lua_haptic(lua_State *L) {
    AudioServicesPlaySystemSound(1520);
    return 0;
}

// Lua binding: log(message)
static int lua_log(lua_State *L) {
    const char *msg = luaL_checkstring(L, 1);
    SRLog(@"[Lua] %s", msg);
    return 0;
}

// Execute a Lua script file
static lua_State *setup_lua_environment() {
    lua_State *L = luaL_newstate();
    if (!L) return NULL;
    
    luaL_openlibs(L);
    lua_pushcfunction(L, lua_openURL);
    lua_setglobal(L, "openURL");
    lua_pushcfunction(L, lua_curl);
    lua_setglobal(L, "curl");
    lua_pushcfunction(L, lua_delay);
    lua_setglobal(L, "delay");
    lua_pushcfunction(L, lua_haptic);
    lua_setglobal(L, "haptic");
    lua_pushcfunction(L, lua_log);
    lua_setglobal(L, "log");
    
    return L;
}

static NSString *execute_lua_script(NSString *scriptPath) {
    lua_State *L = setup_lua_environment();
    if (!L) return @"[SpringRemote] Error: Could not create Lua state";
    
    SRLog(@"[SpringRemote] Executing Lua script: %@", scriptPath);
    
    int result = luaL_dofile(L, [scriptPath UTF8String]);
    NSString *output = nil;
    
    if (result != LUA_OK) {
        const char *error = lua_tostring(L, -1);
        SRLog(@"[SpringRemote] Lua error: %s", error);
        output = [NSString stringWithFormat:@"[SpringRemote] Lua Error: %s", error];
        lua_pop(L, 1);
    } else {
        SRLog(@"[SpringRemote] Lua script completed successfully");
    }
    
    lua_close(L);
    return output;
}

static NSString *evaluate_lua_code(NSString *code) {
    lua_State *L = setup_lua_environment();
    if (!L) return @"[SpringRemote] Error: Could not create Lua state";
    
    int result = luaL_dostring(L, [code UTF8String]);
    NSString *output = nil;
    
    if (result != LUA_OK) {
        const char *error = lua_tostring(L, -1);
        output = [NSString stringWithFormat:@"[SpringRemote] Lua Error: %s", error];
        lua_pop(L, 1);
    }
    
    lua_close(L);
    return output;
}

static NSString *handle_command(NSString *cmd) {
    NSString *cleanCmd = [cmd stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    SRLog(@"Received command: %@", cleanCmd);
    
    // Debug hex dump of command
    NSMutableString *hex = [NSMutableString string];
    const char *utf = [cleanCmd UTF8String];
    for (size_t i = 0; i < strlen(utf); i++) {
        [hex appendFormat:@"%02X ", (unsigned char)utf[i]];
    }
    SRLog(@"Command HEX: %@", hex);
    
    // Log file retrieval command
    if ([cleanCmd isEqualToString:@"log"]) {
        SRLog(@"Log request");
        return nil;
    }

    // Media commands - these work reliably via MediaRemote
    if ([cleanCmd isEqualToString:@"pause"]) {
        // Only pause if currently playing (prevents toggle behavior)
        MRMediaRemoteGetNowPlayingApplicationIsPlaying(dispatch_get_main_queue(), ^(Boolean isPlaying) {
            if (isPlaying) {
                MRMediaRemoteSendCommand(kMRPause, nil);
            }
        });
    } else if ([cleanCmd isEqualToString:@"play"]) {
        // Only play if currently paused (prevents toggle behavior)
        MRMediaRemoteGetNowPlayingApplicationIsPlaying(dispatch_get_main_queue(), ^(Boolean isPlaying) {
            if (!isPlaying) {
                MRMediaRemoteSendCommand(kMRPlay, nil);
            }
        });
    } else if ([cleanCmd isEqualToString:@"playpause"] || [cleanCmd isEqualToString:@"toggle"]) {
        MRMediaRemoteGetNowPlayingApplicationIsPlaying(dispatch_get_main_queue(), ^(Boolean isPlaying) {
            if (isPlaying) {
                MRMediaRemoteSendCommand(kMRPause, nil);
            } else {
                MRMediaRemoteSendCommand(kMRPlay, nil);
            }
        });
    } else if ([cleanCmd isEqualToString:@"debug-media"]) {
        // Introspect Media State
        MRMediaRemoteGetNowPlayingApplicationPID(dispatch_get_main_queue(), ^(int pid) {
            SRLog(@"[SpringRemote] DEBUG: Now Playing PID: %d", pid);
            if (pid > 0) {
                 // Try to get process name?
                 // Simple check if it's Spotify (we don't have proc_name here easily without more headers)
                 SRLog(@"[SpringRemote] DEBUG: System thinks an app is Now Playing (PID %d)", pid);
            } else {
                 SRLog(@"[SpringRemote] DEBUG: No Now Playing Application detected (PID 0)");
            }
        });
        
        MRMediaRemoteGetNowPlayingApplicationIsPlaying(dispatch_get_main_queue(), ^(Boolean isPlaying) {
             SRLog(@"[SpringRemote] DEBUG: Is Playing Status: %@", isPlaying ? @"YES" : @"NO");
        });
        
        return @"Dumping generic media state to logs...\n";
    } else if ([cleanCmd isEqualToString:@"next"]) {
        MRMediaRemoteSendCommand(kMRNextTrack, nil);
    } else if ([cleanCmd isEqualToString:@"prev"]) {
        MRMediaRemoteSendCommand(kMRPreviousTrack, nil);
    } else if ([cleanCmd isEqualToString:@"flashlight"] || [cleanCmd isEqualToString:@"torch"]) {
        SRLog(@"[SpringRemote] Toggling flashlight");
        AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
        if ([device hasTorch]) {
            [device lockForConfiguration:nil];
            if (device.torchMode == AVCaptureTorchModeOn) {
                [device setTorchMode:AVCaptureTorchModeOff];
            } else {
                [device setTorchMode:AVCaptureTorchModeOn];
            }
            [device unlockForConfiguration];
        }
    } else if ([cleanCmd isEqualToString:@"flashlight on"]) {
        SRLog(@"[SpringRemote] Flashlight ON");
        AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
        if ([device hasTorch]) {
            [device lockForConfiguration:nil];
            [device setTorchMode:AVCaptureTorchModeOn];
            [device unlockForConfiguration];
        }
    } else if ([cleanCmd isEqualToString:@"flashlight off"]) {
        SRLog(@"[SpringRemote] Flashlight OFF");
        AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
        if ([device hasTorch]) {
            [device lockForConfiguration:nil];
            [device setTorchMode:AVCaptureTorchModeOff];
            [device unlockForConfiguration];
        }
    } else if ([cleanCmd isEqualToString:@"flashlight toggle"]) {
        return handle_command(@"flashlight");
    } else if ([cleanCmd hasPrefix:@"notify "]) {
        // notify "Title" "Body" [--urgent]
        // Parse: notify "Title" "Message" OR notify Title Message
        NSString *args = [[cleanCmd substringFromIndex:7] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        NSString *title = @"RemoteCommand";
        NSString *body = @"";
        BOOL urgent = NO;
        
        // Check for --urgent flag
        if ([args hasSuffix:@" --urgent"]) {
            urgent = YES;
            args = [[args substringToIndex:args.length - 9] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        }
        
        // Parse quoted strings: "Title" "Body"
        if ([args hasPrefix:@"\""]) {
            NSRange endTitle = [args rangeOfString:@"\"" options:0 range:NSMakeRange(1, args.length - 1)];
            if (endTitle.location != NSNotFound) {
                title = [args substringWithRange:NSMakeRange(1, endTitle.location - 1)];
                NSString *rest = [[args substringFromIndex:endTitle.location + 1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                if ([rest hasPrefix:@"\""]) {
                    NSRange endBody = [rest rangeOfString:@"\"" options:0 range:NSMakeRange(1, rest.length - 1)];
                    if (endBody.location != NSNotFound) {
                        body = [rest substringWithRange:NSMakeRange(1, endBody.location - 1)];
                    } else {
                        body = [rest substringFromIndex:1];
                    }
                } else {
                    body = rest;
                }
            }
        } else {
            // Simple split: notify Title Body
            NSArray *parts = [args componentsSeparatedByString:@" "];
            if (parts.count >= 1) title = parts[0];
            if (parts.count >= 2) body = [[parts subarrayWithRange:NSMakeRange(1, parts.count - 1)] componentsJoinedByString:@" "];
        }
        
        send_notification(title, body, urgent);
        return @"OK\n";
    } else if ([cleanCmd hasPrefix:@"shortcut-direct "] || [cleanCmd hasPrefix:@"sd "]) {
        // Direct posix_spawn of springcuts binary for fastest execution
        NSString *argsString;
        if ([cleanCmd hasPrefix:@"sd "]) {
            argsString = [[cleanCmd substringFromIndex:3] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        } else {
            argsString = [[cleanCmd substringFromIndex:16] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        }
        
        // Build arguments: springcuts -r "ShortcutName" [-p "Input"]
        NSMutableArray *args = [NSMutableArray array];
        [args addObject:@"-r"];
        
        // Parse the shortcut name (may be quoted)
        if ([argsString hasPrefix:@"\""]) {
            NSRange endQuote = [argsString rangeOfString:@"\"" options:0 range:NSMakeRange(1, argsString.length - 1)];
            if (endQuote.location != NSNotFound) {
                NSString *name = [argsString substringWithRange:NSMakeRange(1, endQuote.location - 1)];
                [args addObject:name];
                
                // Check for -p parameter
                NSString *remaining = [argsString substringFromIndex:endQuote.location + 1];
                remaining = [remaining stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                if ([remaining hasPrefix:@"-p "]) {
                    [args addObject:@"-p"];
                    NSString *input = [remaining substringFromIndex:3];
                    input = [input stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                    if ([input hasPrefix:@"\""]) {
                        NSRange inputEnd = [input rangeOfString:@"\"" options:0 range:NSMakeRange(1, input.length - 1)];
                        if (inputEnd.location != NSNotFound) {
                            [args addObject:[input substringWithRange:NSMakeRange(1, inputEnd.location - 1)]];
                        } else {
                            [args addObject:[input substringFromIndex:1]];
                        }
                    } else {
                        [args addObject:input];
                    }
                }
            } else {
                [args addObject:[argsString substringFromIndex:1]];
            }
        } else {
            // No quotes - find -p if present
            NSRange pRange = [argsString rangeOfString:@" -p "];
            if (pRange.location != NSNotFound) {
                // Split at -p
                NSString *name = [[argsString substringToIndex:pRange.location] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                [args addObject:name];
                [args addObject:@"-p"];
                
                NSString *input = [[argsString substringFromIndex:pRange.location + 4] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                // Remove quotes if present
                if ([input hasPrefix:@"\""] && [input hasSuffix:@"\""]) {
                    input = [input substringWithRange:NSMakeRange(1, input.length - 2)];
                } else if ([input hasPrefix:@"\""]) {
                    NSRange endQuote = [input rangeOfString:@"\"" options:0 range:NSMakeRange(1, input.length - 1)];
                    if (endQuote.location != NSNotFound) {
                        input = [input substringWithRange:NSMakeRange(1, endQuote.location - 1)];
                    }
                }
                [args addObject:input];
            } else {
                // Just the shortcut name
                [args addObject:argsString];
            }
        }
        
        SRLog(@"Direct spawn springcuts with: %@", args);
        
        const char *springcutsPath = "/var/jb/usr/bin/springcuts";
        if (access(springcutsPath, X_OK) != 0) {
            springcutsPath = "/usr/bin/springcuts";
        }
        
        // Check if binary exists
        if (access(springcutsPath, X_OK) != 0) {
            SRLog(@"ERROR: springcuts binary not found");
            send_notification(@"RemoteCompanion", @"Please install SpringCuts to use shortcuts.", YES);
            return @"Error: SpringCuts not installed\n";
        }
        SRLog(@"springcuts binary found, preparing spawn...");
        
        char **argv = (char **)malloc((args.count + 2) * sizeof(char *));
        argv[0] = (char *)springcutsPath;
        for (NSUInteger i = 0; i < args.count; i++) {
            argv[i + 1] = (char *)[args[i] UTF8String];
        }
        argv[args.count + 1] = NULL;
        
        // Log the full command
        NSMutableString *cmdStr = [NSMutableString stringWithString:@"spawning:"];
        for (int i = 0; argv[i] != NULL; i++) {
            [cmdStr appendFormat:@" %s", argv[i]];
        }
        SRLog(@"%@", cmdStr);
        
        pid_t pid;
        extern char **environ;
        int result = posix_spawn(&pid, springcutsPath, NULL, NULL, argv, environ);
        free(argv);
        
        if (result == 0) {
            SRLog(@"Spawned springcuts pid=%d", pid);
        } else {
            SRLog(@"posix_spawn failed with error: %d (%s)", result, strerror(result));
        }
    } else if ([cleanCmd hasPrefix:@"shortcut "] || [cleanCmd hasPrefix:@"springcut "]) {
        // Direct spawn of springcuts - parse the args from the full command
        NSString *argsString;
        if ([cleanCmd hasPrefix:@"springcut "]) {
            argsString = [[cleanCmd substringFromIndex:10] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        } else {
            argsString = [[cleanCmd substringFromIndex:9] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        }
        
        // The args string is in springcuts format: -r "Name" [-p "Input"]
        // Just pass it through to springcuts
        NSMutableArray *args = [NSMutableArray array];
        
        // Simple parsing: split by spaces but respect quotes
        NSScanner *scanner = [NSScanner scannerWithString:argsString];
        scanner.charactersToBeSkipped = nil;
        
        while (![scanner isAtEnd]) {
            [scanner scanCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:nil];
            if ([scanner isAtEnd]) break;
            
            NSString *arg = nil;
            if ([argsString characterAtIndex:scanner.scanLocation] == '"') {
                scanner.scanLocation++;
                [scanner scanUpToString:@"\"" intoString:&arg];
                if (![scanner isAtEnd]) scanner.scanLocation++;
            } else {
                [scanner scanUpToCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:&arg];
            }
            if (arg) [args addObject:arg];
        }
        
        SRLog(@"Shortcut spawn with args: %@", args);
        
        const char *springcutsPath = "/var/jb/usr/bin/springcuts";
        if (access(springcutsPath, X_OK) != 0) {
            springcutsPath = "/usr/bin/springcuts";
        }
        
        if (access(springcutsPath, X_OK) != 0) {
            SRLog(@"ERROR: springcuts not found");
            send_notification(@"RemoteCompanion", @"Please install SpringCuts to use shortcuts.", YES);
            return @"Error: SpringCuts not installed\n";
        }
        
        char **argv = (char **)malloc((args.count + 2) * sizeof(char *));
        argv[0] = (char *)springcutsPath;
        for (NSUInteger i = 0; i < args.count; i++) {
            argv[i + 1] = (char *)[args[i] UTF8String];
        }
        argv[args.count + 1] = NULL;
        
        pid_t pid;
        extern char **environ;
        int result = posix_spawn(&pid, springcutsPath, NULL, NULL, argv, environ);
        free(argv);
        
        if (result == 0) {
            SRLog(@"Spawned springcuts pid=%d", pid);
        } else {
            SRLog(@"posix_spawn failed: %d (%s)", result, strerror(result));
        }
    } else if ([cleanCmd hasPrefix:@"anc "]) {
        // ANC control - triggers Sonitus hooks
        NSString *mode = [[cleanCmd substringFromIndex:4] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSString *listeningMode = nil;
        
        if ([mode isEqualToString:@"on"] || [mode isEqualToString:@"nc"]) {
            listeningMode = @"AVOutputDeviceBluetoothListeningModeActiveNoiseCancellation";
        } else if ([mode isEqualToString:@"off"]) {
            listeningMode = @"AVOutputDeviceBluetoothListeningModeNormal";
        } else if ([mode isEqualToString:@"transparency"] || [mode isEqualToString:@"ambient"]) {
            listeningMode = @"AVOutputDeviceBluetoothListeningModeAudioTransparency";
        } else {
            SRLog(@"Unknown ANC mode: %@. Use: on, off, transparency", mode);
            return nil;
        }
        
        SRLog(@"Setting ANC mode: %@ -> %@", mode, listeningMode);
        
        dispatch_async(dispatch_get_main_queue(), ^{
            Class AVOutputContextClass = objc_getClass("AVOutputContext");
            if (!AVOutputContextClass) {
                SRLog(@"ERROR: AVOutputContext class not found");
                return;
            }
            
            AVOutputContext *context = [AVOutputContextClass sharedSystemAudioContext];
            NSArray *devices = [context outputDevices];
            SRLog(@"Found %lu output devices", (unsigned long)devices.count);
            
            for (AVOutputDevice *device in devices) {
                NSArray *modes = [device availableBluetoothListeningModes];
                if (modes.count > 0) {
                    SRLog(@"Device '%@' supports listening modes: %@", device.name, modes);
                    NSError *error = nil;
                    BOOL success = [device setCurrentBluetoothListeningMode:listeningMode error:&error];
                    if (success) {
                        SRLog(@"ANC mode set successfully on %@", device.name);
                    } else {
                        SRLog(@"Failed to set ANC mode: %@", error);
                    }
                    return;
                }
            }
            SRLog(@"No device with ANC support found");
        });
    } else if ([cleanCmd hasPrefix:@"button "]) {
        // Hardware button simulation
        NSString *btn = [[cleanCmd substringFromIndex:7] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        
        if ([btn isEqualToString:@"power"] || [btn isEqualToString:@"lock"]) {
            inject_hid_event(kHIDPage_Consumer, kHIDUsage_Csmr_Power, 0, 0);
        } else if ([btn isEqualToString:@"home"]) {
            inject_hid_event(kHIDPage_Consumer, kHIDUsage_Csmr_Menu, 0, 0);
        } else if ([btn isEqualToString:@"volup"]) {
            inject_hid_event(kHIDPage_Consumer, kHIDUsage_Csmr_VolumeIncrement, 0, 0);
        } else if ([btn isEqualToString:@"voldown"]) {
            inject_hid_event(kHIDPage_Consumer, kHIDUsage_Csmr_VolumeDecrement, 0, 0);
        } else if ([btn isEqualToString:@"mute"]) {
            inject_hid_event(kHIDPage_Consumer, kHIDUsage_Csmr_Mute, 0, 0);
        } else if ([btn isEqualToString:@"siri"]) {

            
            // Use HID Voice Command (0xCF) - Acts like a headset button, typically no "Home" side-effects
            inject_hid_event(kHIDPage_Consumer, kHIDUsage_Csmr_VoiceCommand, 600000000, 0); // 0.6s hold
            
            // Fallback: Bundle Launch (Reliable but loses context)
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                Class SBAssistantControllerClass = objc_getClass("SBAssistantController");
                id assistant = [SBAssistantControllerClass sharedInstance];
                if ([assistant respondsToSelector:@selector(isVisible)] && ![assistant isVisible]) {

                    Class LSWorkspace = objc_getClass("LSApplicationWorkspace");
                    if (LSWorkspace) {
                        [[LSWorkspace defaultWorkspace] openApplicationWithBundleID:@"com.apple.SiriViewService"];
                    }
                }
            });
        } else {
            SRLog(@"Unknown button: %@. Supported: power, home, volup, voldown, mute, siri", btn);
        }
    } else if ([cleanCmd isEqualToString:@"siri"]) {
        return handle_command(@"button siri");
    } else if ([cleanCmd isEqualToString:@"is-locked"]) {
        // Query lock state
        // Use dispatch_sync to wait for result from main thread
        __block NSString *result = @"error";
        dispatch_sync(dispatch_get_main_queue(), ^{
            Class SBLockScreenManagerClass = objc_getClass("SBLockScreenManager");
            SBLockScreenManager *manager = nil;
            if (SBLockScreenManagerClass) {
                manager = [SBLockScreenManagerClass sharedInstance];
            }
            
            if (manager && [manager respondsToSelector:@selector(isUILocked)]) {
                 BOOL locked = [manager isUILocked];
                 result = locked ? @"locked" : @"unlocked";
            }
        });
        return [NSString stringWithFormat:@"%@\n", result];
    } else if ([cleanCmd hasPrefix:@"debug-class "]) {
        NSString *className = [[cleanCmd substringFromIndex:12] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        SRLog(@"[SpringRemote] Debugging class: %@", className);
        Class cls = objc_getClass([className UTF8String]);
        if (!cls) {
            SRLog(@"[SpringRemote] Class not found: %@", className);
            return @"Class not found\n";
        }
        
        unsigned int count = 0;
        Method *methods = class_copyMethodList(cls, &count);
        SRLog(@"[SpringRemote] Class %@ has %u methods:", className, count);
        for (unsigned int i = 0; i < count; i++) {
            SEL sel = method_getName(methods[i]);
            SRLog(@"[SpringRemote]   - %@", NSStringFromSelector(sel));
        }
        free(methods);
        return [NSString stringWithFormat:@"Found %u methods for %@. Check logs.\n", count, className];
    } else if ([cleanCmd hasPrefix:@"debug-classes "]) {
        NSString *search = [[cleanCmd substringFromIndex:14] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        SRLog(@"[SpringRemote] Searching for classes containing: %@", search);
        
        int numClasses = objc_getClassList(NULL, 0);
        if (numClasses > 0) {
            Class *classes = (Class *)malloc(sizeof(Class) * numClasses);
            numClasses = objc_getClassList(classes, numClasses);
            SRLog(@"[SpringRemote] Found %d total classes. Filtering...", numClasses);
            for (int i = 0; i < numClasses; i++) {
                NSString *className = NSStringFromClass(classes[i]);
                if ([className rangeOfString:search options:NSCaseInsensitiveSearch].location != NSNotFound) {
                    SRLog(@"[SpringRemote]   * %@", className);
                }
            }
            free(classes);
        }
        return @"Search complete. Check logs.\n";
    } else if ([cleanCmd hasPrefix:@"debug-call "]) {
        // debug-call ClassName selectorName
        NSString *args = [cleanCmd substringFromIndex:11];
        NSArray *parts = [args componentsSeparatedByString:@" "];
        if (parts.count >= 2) {
            NSString *className = parts[0];
            NSString *selName = parts[1];
            Class cls = objc_getClass([className UTF8String]);
            if (cls) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    id target = nil;
                    if ([cls respondsToSelector:@selector(sharedInstance)]) {
                        target = [cls performSelector:@selector(sharedInstance)];
                    } else if ([cls respondsToSelector:@selector(sharedController)]) {
                        target = [cls performSelector:@selector(sharedController)];
                    }
                    
                    if (target) {
                        SEL sel = NSSelectorFromString(selName);
                        if ([target respondsToSelector:sel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                            id result = [target performSelector:sel];
#pragma clang diagnostic pop
                            SRLog(@"[SpringRemote] debug-call [%@ %@] returned: %@", className, selName, result);
                        } else {
                            SRLog(@"[SpringRemote] debug-call: Target does not respond to %@", selName);
                        }
                    } else {
                        SRLog(@"[SpringRemote] debug-call: Could not get instance for %@", className);
                    }
                });
            }
        }
        return @"Call initiated. Check logs.\n";
    } else if ([cleanCmd isEqualToString:@"lock status"]) {
        __block NSString *result = @"error";
        dispatch_sync(dispatch_get_main_queue(), ^{
            Class SBLockScreenManagerClass = objc_getClass("SBLockScreenManager");
            SBLockScreenManager *manager = nil;
            if (SBLockScreenManagerClass) {
                manager = [SBLockScreenManagerClass sharedInstance];
            }
            if (manager && [manager respondsToSelector:@selector(isUILocked)]) {
                 BOOL locked = [manager isUILocked];
                 result = locked ? @"locked" : @"unlocked";
            }
        });
        return [NSString stringWithFormat:@"%@\n", result];
    } else if ([cleanCmd isEqualToString:@"lock"]) {
        // Smart lock: Only lock if currently unlocked
        // ensure we run on main thread for UI/SB checks
        dispatch_async(dispatch_get_main_queue(), ^{
            Class SBLockScreenManagerClass = objc_getClass("SBLockScreenManager");
            SBLockScreenManager *manager = nil;
            if (SBLockScreenManagerClass) {
                manager = [SBLockScreenManagerClass sharedInstance];
            }
            
            SRLog(@"[SmartLock] Debug: Manager=%@, Checking isUILocked...", manager);

            if (manager && [manager respondsToSelector:@selector(isUILocked)]) {
                 BOOL locked = [manager isUILocked];
                 SRLog(@"[SmartLock] isUILocked returned: %@", locked ? @"YES" : @"NO");
                 
                 if (locked) {
                     SRLog(@"[SmartLock] Device already locked. Skipping power button.");
                 } else {
                     SRLog(@"[SmartLock] Device unlocked. Sending power button event...");
                     inject_hid_event(kHIDPage_Consumer, kHIDUsage_Csmr_Power, 0, 0);
                 }
            } else {
                SRLog(@"[SmartLock] ERROR: manager is nil or does not respond to isUILocked. Forcing lock.");
                 inject_hid_event(kHIDPage_Consumer, kHIDUsage_Csmr_Power, 0, 0);
            }
        });
    } else if ([cleanCmd isEqualToString:@"unlock"] || [cleanCmd hasPrefix:@"unlock "]) {
        // Unlock phone: Only if currently locked!
        
        SRLog(@"[SmartUnlock] Checking lock state before unlocking...");
        
        __block BOOL isLocked = NO;
        dispatch_sync(dispatch_get_main_queue(), ^{
            Class SBLockScreenManagerClass = objc_getClass("SBLockScreenManager");
            SBLockScreenManager *manager = nil;
            if (SBLockScreenManagerClass) {
                manager = [SBLockScreenManagerClass sharedInstance];
            }
            if (manager && [manager respondsToSelector:@selector(isUILocked)]) {
                 isLocked = [manager isUILocked];
            }
        });

        if (!isLocked) {
             SRLog(@"[SmartUnlock] Device already unlocked. Doing nothing.");
             return @"already_unlocked\n";
        }
        
        SRLog(@"[SmartUnlock] Device is locked. Proceeding with unlock sequence...");

        // Default PIN is 2569, can be overridden with: unlock 1234
        NSString *pin = @"2569";
        if ([cleanCmd hasPrefix:@"unlock "]) {
            pin = [[cleanCmd substringFromIndex:7] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        }
        
        // Ensure screen is on (wake)
        inject_hid_event(kHIDPage_Consumer, kHIDUsage_Csmr_Power, 0, 0);
        
        // Wait for screen to wake/process (0.3s delay - increased for reliability)
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            // Get lock screen manager
            Class SBLockScreenManagerClass = objc_getClass("SBLockScreenManager");
            if (!SBLockScreenManagerClass) return;
            
            SBLockScreenManager *manager = [SBLockScreenManagerClass sharedInstance];
            if (!manager) return;
            
            // Try the direct unlock method
            if ([manager respondsToSelector:@selector(attemptUnlockWithPasscode:)]) {
                SRLog(@"Trying attemptUnlockWithPasscode...");
                [manager attemptUnlockWithPasscode:pin];
                SRLog(@"attemptUnlockWithPasscode called");
            } else if ([manager respondsToSelector:@selector(unlockUIFromSource:withOptions:)]) {
                 SRLog(@"Using fallback unlockUIFromSource...");
                 [manager unlockUIFromSource:0 withOptions:nil];
            }
        });
        return @"unlocking_started\n";
    }

    else if ([cleanCmd hasPrefix:@"key "]) {
        // Keyboard event simulation
        // Usage: key <usage_in_hex_or_dec>
        NSString *usageStr = [[cleanCmd substringFromIndex:4] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        unsigned int usage = 0;
        NSScanner *scanner = [NSScanner scannerWithString:usageStr];
        if ([usageStr hasPrefix:@"0x"]) {
            [scanner scanHexInt:&usage];
        } else {
            int val = 0;
            if ([scanner scanInt:&val]) usage = (unsigned int)val;
        }
        
        if (usage > 0) {
            inject_hid_event(kHIDPage_KeyboardOrKeypad, usage, 0, 0);
        } else {
            SRLog(@"Invalid key usage: %@", usageStr);
        }

    } else if ([cleanCmd isEqualToString:@"lock-toggle"] || [cleanCmd isEqualToString:@"lock toggle"]) {
        // Toggle Lock State
        __block BOOL isLocked = NO;
        dispatch_sync(dispatch_get_main_queue(), ^{
            Class SBLockScreenManagerClass = objc_getClass("SBLockScreenManager");
            SBLockScreenManager *manager = nil;
            if (SBLockScreenManagerClass) {
                manager = [SBLockScreenManagerClass sharedInstance];
            }
            if (manager && [manager respondsToSelector:@selector(isUILocked)]) {
                isLocked = [manager isUILocked];
            }
        });
        
        SRLog(@"[LockToggle] Current State: %@", isLocked ? @"Locked" : @"Unlocked");
        
        if (isLocked) {
             // Unlock Logic
             return handle_command(@"unlock");
        } else {
             // Lock Logic
             return handle_command(@"lock");
        }

    } else if ([cleanCmd hasPrefix:@"url "]) {
        NSString *urlString = [cleanCmd substringFromIndex:4];
        urlString = [urlString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        
        __block BOOL isLocked = NO;
        dispatch_sync(dispatch_get_main_queue(), ^{
            Class SBLockScreenManagerClass = objc_getClass("SBLockScreenManager");
            SBLockScreenManager *manager = nil;
            if (SBLockScreenManagerClass) {
                manager = [SBLockScreenManagerClass sharedInstance];
            }
            if (manager && [manager respondsToSelector:@selector(isUILocked)]) {
                isLocked = [manager isUILocked];
            }
        });
        
        if (isLocked) {
             SRLog(@"[SmartURL] Device locked. Initiating unlock sequence for URL...");
             
             // 1. Wake Screen
             inject_hid_event(kHIDPage_Consumer, kHIDUsage_Csmr_Power, 0, 0);
             
             // 2. Wait 0.5s then Unlock AND Open URL
             dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                 Class SBLockScreenManagerClass = objc_getClass("SBLockScreenManager");
                 if (SBLockScreenManagerClass) {
                     SBLockScreenManager *manager = [SBLockScreenManagerClass sharedInstance];
                     if (manager && [manager respondsToSelector:@selector(attemptUnlockWithPasscode:)]) {
                         [manager attemptUnlockWithPasscode:@"2569"];
                     }
                 }
                 
                 // Open URL immediately after unlock attempt
                 NSURL *url = [NSURL URLWithString:urlString];
                 if (url) {
                     [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
                 }
             });
             
             return @"unlocking_and_opening_url\n";
        } else {
             // Device unlocked, open immediately
             dispatch_async(dispatch_get_main_queue(), ^{
                 NSURL *url = [NSURL URLWithString:urlString];
                 if (url) {
                     [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
                 }
             });
             return @"opening_url\n";
        }
    } else if ([cleanCmd hasPrefix:@"spotify playlist "] || 
               [cleanCmd hasPrefix:@"spotify album "] || 
               [cleanCmd hasPrefix:@"spotify artist "] || 
               [cleanCmd hasPrefix:@"spotify play "] || 
               [cleanCmd hasPrefix:@"spotify "]) {
        NSString *arg = nil;
        if ([cleanCmd hasPrefix:@"spotify playlist "]) arg = [cleanCmd substringFromIndex:17];
        else if ([cleanCmd hasPrefix:@"spotify album "]) arg = [cleanCmd substringFromIndex:14];
        else if ([cleanCmd hasPrefix:@"spotify artist "]) arg = [cleanCmd substringFromIndex:15];
        else if ([cleanCmd hasPrefix:@"spotify play "]) arg = [cleanCmd substringFromIndex:13];
        else arg = [cleanCmd substringFromIndex:8];
        
        arg = [arg stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        
        // Support full URIs or just IDs with intelligent defaulting
        NSString *spotifyURI = nil;
        
        // Check for specific command prefixes to determine URI type
        if ([cleanCmd hasPrefix:@"spotify album "]) {
             if ([arg hasPrefix:@"spotify:"]) spotifyURI = arg;
             else spotifyURI = [NSString stringWithFormat:@"spotify:album:%@", arg];
        } else if ([cleanCmd hasPrefix:@"spotify artist "]) {
             if ([arg hasPrefix:@"spotify:"]) spotifyURI = arg;
             else spotifyURI = [NSString stringWithFormat:@"spotify:artist:%@", arg];
        } else if ([arg hasPrefix:@"spotify:"]) {
            spotifyURI = arg;
        } else {
            // Default to playlist if it's just an ID and command was generic "spotify" or "spotify playlist"
            spotifyURI = [NSString stringWithFormat:@"spotify:playlist:%@", arg];
        }
        
        // Append :play suffix to trigger autoplay (Spotify-specific feature)
        NSString *playableURI = [spotifyURI stringByAppendingString:@":play"];
        SRLog(@"[SpringRemote] Spotify Request: %@ (playable: %@)", spotifyURI, playableURI);
        
        // Forwarding to main queue for UI/URL operations
        void (^launchSpotify)(void) = ^{
            NSURL *url = [NSURL URLWithString:playableURI];
            [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:^(BOOL success) {
                if (success) {
                    // Aggressive play trigger with multiple attempts
                    // Strategy: Use explicit Play command (not toggle) with multiple fallbacks
                    
                    NSArray *delays = @[@0.5, @1.0, @1.5, @2.5];
                    for (NSNumber *delayNum in delays) {
                        float delay = [delayNum floatValue];
                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                            SRLog(@"[SpringRemote] Spotify play attempt at %.1fs", delay);
                            
                            // Get MediaRemote handle
                            void *mrHandle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
                            if (mrHandle) {
                                Boolean (*SendCommandToApp)(unsigned int, NSDictionary *, id, NSString *, unsigned int, dispatch_queue_t, void (^)(NSError *)) = dlsym(mrHandle, "MRMediaRemoteSendCommandToApp");
                                if (SendCommandToApp) {
                                    // Send explicit PLAY command (kMRPlay = 0) to Spotify
                                    SRLog(@"[SpringRemote] Sending kMRPlay to com.spotify.client");
                                    SendCommandToApp(kMRPlay, nil, nil, @"com.spotify.client", 0, dispatch_get_main_queue(), ^(NSError *err){
                                         if (err) SRLog(@"[SpringRemote] MR Play Error: %@", err);
                                         else SRLog(@"[SpringRemote] MR Play sent successfully");
                                    });
                                }
                            }
                            
                            // Also try global Play command as fallback
                            MRMediaRemoteSendCommand(kMRPlay, nil);
                            
                            // And HID Play key (not toggle - use dedicated Play usage if available)
                            inject_consumer_key(kHIDUsage_Csmr_PlayOrPause);
                        });
                    }
                }
            }];
        };

        // Use same logic as 'url' for smart unlock
        Class SBLockScreenManagerClass = objc_getClass("SBLockScreenManager");
        SBLockScreenManager *manager = SBLockScreenManagerClass ? [SBLockScreenManagerClass sharedInstance] : nil;
        
        if (manager && [manager isUILocked]) {
            SRLog(@"[SpringRemote] Device locked, attempting smart unlock for Spotify");
            dispatch_async(dispatch_get_main_queue(), ^{
                // Wake screen using HID Power button (simulated)
                inject_hid_event(kHIDPage_Consumer, kHIDUsage_Csmr_Power, 0, 0);
                
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    if ([manager respondsToSelector:@selector(attemptUnlockWithPasscode:)]) {
                        [manager attemptUnlockWithPasscode:@"2569"];
                    }
                    
                    launchSpotify();
                });
            });
            return @"unlocking_and_playing_spotify\n";
        } else {
            dispatch_async(dispatch_get_main_queue(), launchSpotify);
            return @"playing_spotify\n";
        }
    } else if ([cleanCmd hasPrefix:@"dnd "]) {
        NSString *subCmd = [[cleanCmd substringFromIndex:4] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([subCmd isEqualToString:@"on"]) {
            toggle_dnd(YES);
            return @"DND Enabled\n";
        } else if ([subCmd isEqualToString:@"off"]) {
            toggle_dnd(NO);
            return @"DND Disabled\n";
        } else if ([subCmd isEqualToString:@"toggle"]) {
            BOOL current = get_dnd_state();
            toggle_dnd(!current);
            return [NSString stringWithFormat:@"DND %@\n", !current ? @"Enabled" : @"Disabled"];
        }
    } else if ([cleanCmd hasPrefix:@"lpm "]) {
        NSString *subCmd = [[cleanCmd substringFromIndex:4] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([subCmd isEqualToString:@"on"]) {
            toggle_lpm(YES);
            return @"Low Power Mode Enabled\n";
        } else if ([subCmd isEqualToString:@"off"]) {
            toggle_lpm(NO);
            return @"Low Power Mode Disabled\n";
        } else if ([subCmd isEqualToString:@"toggle"]) {
            BOOL current = get_lpm_state();
            toggle_lpm(!current);
            return [NSString stringWithFormat:@"Low Power Mode %@\n", !current ? @"Enabled" : @"Disabled"];
        }
    } else if ([cleanCmd hasPrefix:@"low power mode "]) {
        NSString *subCmd = [[cleanCmd substringFromIndex:15] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([subCmd isEqualToString:@"on"]) {
            toggle_lpm(YES);
            return @"Low Power Mode Enabled\n";
        } else if ([subCmd isEqualToString:@"off"]) {
            toggle_lpm(NO);
            return @"Low Power Mode Disabled\n";
        } else if ([subCmd isEqualToString:@"toggle"]) {
            BOOL current = get_lpm_state();
            toggle_lpm(!current);
            return [NSString stringWithFormat:@"Low Power Mode %@\n", !current ? @"Enabled" : @"Disabled"];
        }
    } else if ([cleanCmd hasPrefix:@"low power "]) {
        NSString *subCmd = [[cleanCmd substringFromIndex:10] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([subCmd isEqualToString:@"on"]) {
            toggle_lpm(YES);
            return @"Low Power Mode Enabled\n";
        } else if ([subCmd isEqualToString:@"off"]) {
            toggle_lpm(NO);
            return @"Low Power Mode Disabled\n";
        } else if ([subCmd isEqualToString:@"toggle"]) {
            BOOL current = get_lpm_state();
            toggle_lpm(!current);
            return [NSString stringWithFormat:@"Low Power Mode %@\n", !current ? @"Enabled" : @"Disabled"];
        }
    } else if ([cleanCmd isEqualToString:@"orientation lock"] || [cleanCmd isEqualToString:@"orientation"] || [cleanCmd isEqualToString:@"rotation"] || [cleanCmd isEqualToString:@"rotate"]) {
        return handle_command(@"orientation toggle");
    } else if ([cleanCmd hasPrefix:@"orientation "] || [cleanCmd hasPrefix:@"rotation "] || [cleanCmd hasPrefix:@"rotate "]) {
        NSString *subCmd = [[cleanCmd componentsSeparatedByString:@" "] lastObject];
        dispatch_async(dispatch_get_main_queue(), ^{
            Class managerClass = objc_getClass("SBOrientationLockManager");
            if (managerClass) {
                id manager = [managerClass sharedInstance];
                if ([subCmd isEqualToString:@"on"] || [subCmd isEqualToString:@"lock"]) {
                    [manager lock];
                } else if ([subCmd isEqualToString:@"off"] || [subCmd isEqualToString:@"unlock"]) {
                    [manager unlock];
                } else if ([subCmd isEqualToString:@"toggle"]) {
                    if ([manager isUserLocked]) [manager unlock];
                    else [manager lock];
                }
            }
        });
        return @"OK\n";
    } else if ([cleanCmd isEqualToString:@"mute"]) {
        return @"Usage: rc mute [on|off|status]\n";
    } else if ([cleanCmd hasPrefix:@"mute "]) {
        NSString *subCmd = [[cleanCmd substringFromIndex:5] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        
        // Try AVSystemController first (Media State)
        void *celestialHandle = dlopen("/System/Library/PrivateFrameworks/Celestial.framework/Celestial", RTLD_NOW);
        if (celestialHandle) {
             Class AVSystemControllerClass = objc_getClass("AVSystemController");
             if (AVSystemControllerClass) {
                 @try {
                     id controller = [AVSystemControllerClass sharedAVSystemController];
                     if (controller) {
                         if ([subCmd isEqualToString:@"status"]) {
                             float currentVol = 0;
                             if ([controller respondsToSelector:@selector(getVolume:forCategory:)]) {
                                 [controller getVolume:&currentVol forCategory:@"Audio/Video"];
                             }
                             
                             // Also check mute state
                             BOOL isMuted = NO;
                             if ([controller respondsToSelector:@selector(getActiveCategoryMuted:)]) {
                                 [controller getActiveCategoryMuted:&isMuted];
                             }
                             
                             if (isMuted || currentVol == 0.0f) {
                                 return @"Muted (Media)\n";
                             } else {
                                 return [NSString stringWithFormat:@"Unmuted (Media, Vol: %d%%)\n", (int)(currentVol * 100)];
                             }
                             
                         } else if ([subCmd isEqualToString:@"on"]) {
                             // Save current volume if we haven't already
                             float currentVol = 0;
                             if ([controller respondsToSelector:@selector(getVolume:forCategory:)]) {
                                 [controller getVolume:&currentVol forCategory:@"Audio/Video"];
                                 if (currentVol > 0) {
                                     sr_previous_volume = currentVol;
                                     SRLog(@"[SpringRemote] Saved previous volume: %f", sr_previous_volume);
                                 }
                             }
                             
                             // Set volume to 0
                             if ([controller respondsToSelector:@selector(setActiveCategoryVolumeTo:)]) {
                                 [controller setActiveCategoryVolumeTo:0.0f];
                                 return @"Muted (Media)\n";
                             }
                             
                         } else if ([subCmd isEqualToString:@"off"]) {
                             // Check if already unmuted (vol > 0)
                             float currentVol = 0;
                             if ([controller respondsToSelector:@selector(getVolume:forCategory:)]) {
                                 [controller getVolume:&currentVol forCategory:@"Audio/Video"];
                             }
                             
                             if (currentVol > 0) {
                                  return @"Already Unmuted\n";
                             }

                             // Restore volume
                             float targetVol = (sr_previous_volume > 0) ? sr_previous_volume : 0.5f; // Default 50%
                             
                             if ([controller respondsToSelector:@selector(setActiveCategoryVolumeTo:)]) {
                                 [controller setActiveCategoryVolumeTo:targetVol];
                                 sr_previous_volume = -1.0f; // Reset
                                 return @"Unmuted (Media)\n";
                             }
                         } else if ([subCmd isEqualToString:@"toggle"]) {
                             float currentVol = 0;
                             if ([controller respondsToSelector:@selector(getVolume:forCategory:)]) {
                                 [controller getVolume:&currentVol forCategory:@"Audio/Video"];
                             }
                             BOOL isMuted = NO;
                             if ([controller respondsToSelector:@selector(getActiveCategoryMuted:)]) {
                                 [controller getActiveCategoryMuted:&isMuted];
                             }
                             
                             if (isMuted || currentVol == 0.0f) {
                                 return handle_command(@"mute off");
                             } else {
                                 return handle_command(@"mute on");
                             }
                         }
                     }
                 } @catch (NSException *e) {
                     SRLog(@"[SpringRemote] Exception in mute: %@", e);
                 }
             }
        }
        
        return @"Error: AVSystemController failed. Cannot control media mute.\n";
    } else if ([cleanCmd isEqualToString:@"volume up"] || [cleanCmd isEqualToString:@"vol up"]) {
        inject_hid_event(kHIDPage_Consumer, kHIDUsage_Csmr_VolumeIncrement, 0, 0);
        return @"OK\n";
    } else if ([cleanCmd isEqualToString:@"volume down"] || [cleanCmd isEqualToString:@"vol down"]) {
        inject_hid_event(kHIDPage_Consumer, kHIDUsage_Csmr_VolumeDecrement, 0, 0);
        return @"OK\n";
    } else if ([cleanCmd hasPrefix:@"volume "] || [cleanCmd hasPrefix:@"volume"]) { // Matches "volume" and "volume <N>"
        NSString *arg = nil;
        if (cleanCmd.length > 7) {
             arg = [[cleanCmd substringFromIndex:7] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        } else if (cleanCmd.length > 6) {
             arg = [[cleanCmd substringFromIndex:6] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        }
        
        void *celestialHandle = dlopen("/System/Library/PrivateFrameworks/Celestial.framework/Celestial", RTLD_NOW);
        if (celestialHandle) {
             Class AVSystemControllerClass = objc_getClass("AVSystemController");
             if (AVSystemControllerClass) {
                 @try {
                     id controller = [AVSystemControllerClass sharedAVSystemController];
                     if (controller) {
                         // Set Volume
                         if (arg && arg.length > 0) {
                             // Safety check: ensure arg starts with a digit before using floatValue
                             // as floatValue returns 0.0 for non-numeric strings like "up"
                             if ([[NSCharacterSet decimalDigitCharacterSet] characterIsMember:[arg characterAtIndex:0]]) {
                                 float target = [arg floatValue] / 100.0f;
                                 if (target < 0) target = 0;
                                 if (target > 1) target = 1;
                                 
                                 if ([controller respondsToSelector:@selector(setActiveCategoryVolumeTo:)]) {
                                     [controller setActiveCategoryVolumeTo:target];
                                     return [NSString stringWithFormat:@"Volume set to %d%%\n", (int)(target * 100)];
                                 }
                             } else {
                                 SRLog(@"[SpringRemote] Ignored non-numeric volume argument: %@", arg);
                                 return [NSString stringWithFormat:@"Error: Invalid volume level '%@'\n", arg];
                             }
                         }
                         
                         // Get Volume (default)
                         float volume = 0;
                         if ([controller respondsToSelector:@selector(getVolume:forCategory:)]) {
                             [controller getVolume:&volume forCategory:@"Audio/Video"];
                             int volumePercent = (int)(volume * 100);
                             return [NSString stringWithFormat:@"Volume: %d%%\n", volumePercent];
                         }
                     }
                 } @catch (NSException *e) {
                     SRLog(@"[SpringRemote] Exception volume: %@", e);
                 }
             }
        }
        return @"Error: AVSystemController failed.\n";
    } else if ([cleanCmd hasPrefix:@"uiopen "]) {
        NSString *bundleId = [[cleanCmd substringFromIndex:7] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSLog(@"[RemoteCommand] UIOPEN Bundle ID: %@", bundleId);
        dispatch_async(dispatch_get_main_queue(), ^{
             FBSOpenApplicationService *service = [FBSOpenApplicationService serviceWithDefaultShellEndpoint];
             [service openApplication:bundleId withOptions:nil completion:nil];
        });
        return [NSString stringWithFormat:@"Opened %@", bundleId];
    } else if ([cleanCmd hasPrefix:@"open "]) {
        // Open app by name or Bundle ID
        NSString *appName = [[cleanCmd substringFromIndex:5] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        
        // If it looks like a Bundle ID (contains dot), use FBSOpenApplicationService (faster)
        if ([appName containsString:@"."]) {
             NSLog(@"[RemoteCommand] Opening Bundle ID via FBS: %@", appName);
             dispatch_async(dispatch_get_main_queue(), ^{
                 FBSOpenApplicationService *service = [FBSOpenApplicationService serviceWithDefaultShellEndpoint];
                 [service openApplication:appName withOptions:nil completion:nil];
             });
             return [NSString stringWithFormat:@"Opened %@", appName];
        }

        NSString *lowerName = [appName lowercaseString];
        NSString *urlString = nil;
        
        // Common app URL schemes
        if ([lowerName isEqualToString:@"spotify"]) urlString = @"spotify://";
        else if ([lowerName isEqualToString:@"music"]) urlString = @"music://";
        else if ([lowerName isEqualToString:@"youtube"]) urlString = @"youtube://";
        else if ([lowerName isEqualToString:@"safari"]) urlString = @"x-web-search://";
        else if ([lowerName isEqualToString:@"settings"]) urlString = @"App-prefs://";
        else if ([lowerName isEqualToString:@"camera"]) urlString = @"camera://";
        else if ([lowerName isEqualToString:@"photos"]) urlString = @"photos-redirect://";
        else if ([lowerName isEqualToString:@"maps"]) urlString = @"maps://";
        else if ([lowerName isEqualToString:@"messages"]) urlString = @"sms://";
        else if ([lowerName isEqualToString:@"phone"]) urlString = @"tel://";
        else if ([lowerName isEqualToString:@"mail"]) urlString = @"mailto://";
        else if ([lowerName isEqualToString:@"notes"]) urlString = @"mobilenotes://";
        else if ([lowerName isEqualToString:@"reminders"]) urlString = @"x-apple-reminderkit://";
        else if ([lowerName isEqualToString:@"calendar"]) urlString = @"calshow://";
        else if ([lowerName isEqualToString:@"clock"]) urlString = @"clock-alarm://";
        else if ([lowerName isEqualToString:@"weather"]) urlString = @"weather://";
        else if ([lowerName isEqualToString:@"shortcuts"]) urlString = @"shortcuts://";
        else urlString = [NSString stringWithFormat:@"%@://", lowerName]; // Try app name as scheme
        
        NSLog(@"[RemoteCommand] Opening app: %@ via %@", appName, urlString);
        dispatch_async(dispatch_get_main_queue(), ^{
            NSURL *url = [NSURL URLWithString:urlString];
            if (url) {
                [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
            }
        });
    } else if ([cleanCmd isEqualToString:@"bluetooth-on"] || [cleanCmd isEqualToString:@"bt-on"] || [cleanCmd isEqualToString:@"bluetooth on"] || [cleanCmd isEqualToString:@"bt on"]) {
        void *btHandle = dlopen("/System/Library/PrivateFrameworks/BluetoothManager.framework/BluetoothManager", RTLD_NOW);
        if (btHandle) {
            Class BluetoothManagerClass = objc_getClass("BluetoothManager");
            if (BluetoothManagerClass) {
                BluetoothManager *btManager = [BluetoothManagerClass sharedInstance];
                [btManager setEnabled:YES];
                [btManager setPowered:YES];
                SRLog(@"[SpringRemote] Bluetooth enabled");
                return @"Bluetooth Enabled\n";
            }
        }
        return @"Error: BluetoothManager not found\n";
    } else if ([cleanCmd isEqualToString:@"bluetooth-off"] || [cleanCmd isEqualToString:@"bt-off"] || [cleanCmd isEqualToString:@"bluetooth off"] || [cleanCmd isEqualToString:@"bt off"]) {
        void *btHandle = dlopen("/System/Library/PrivateFrameworks/BluetoothManager.framework/BluetoothManager", RTLD_NOW);
        if (btHandle) {
            Class BluetoothManagerClass = objc_getClass("BluetoothManager");
            if (BluetoothManagerClass) {
                BluetoothManager *btManager = [BluetoothManagerClass sharedInstance];
                [btManager setEnabled:NO];
                [btManager setPowered:NO];
                SRLog(@"[SpringRemote] Bluetooth disabled");
                return @"Bluetooth Disabled\n";
            }
        }
        return @"Error: BluetoothManager not found\n";
        return @"Error: BluetoothManager not found\n";
    } else if ([cleanCmd hasPrefix:@"bt-connect "] || [cleanCmd hasPrefix:@"bt connect "] || [cleanCmd hasPrefix:@"bluetooth connect "]) {
        NSString *deviceName;
        if ([cleanCmd hasPrefix:@"bt connect "]) deviceName = [cleanCmd substringFromIndex:11];
        else if ([cleanCmd hasPrefix:@"bluetooth connect "]) deviceName = [cleanCmd substringFromIndex:18];
        else deviceName = [cleanCmd substringFromIndex:11];
        deviceName = [deviceName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        
        void *btHandle = dlopen("/System/Library/PrivateFrameworks/BluetoothManager.framework/BluetoothManager", RTLD_NOW);
        if (btHandle) {
            Class BluetoothManagerClass = objc_getClass("BluetoothManager");
            if (BluetoothManagerClass) {
                BluetoothManager *btManager = [BluetoothManagerClass sharedInstance];
                for (BluetoothDevice *device in [btManager pairedDevices]) {
                    if ([[device name] localizedCaseInsensitiveContainsString:deviceName]) {
                        [device connect];
                        SRLog(@"[SpringRemote] Connecting to BT device: %@", [device name]);
                        return [NSString stringWithFormat:@"Connecting to %@\n", [device name]];
                    }
                }
            }
        }
        return @"Error: Device not found or BluetoothManager failed\n";
    } else if ([cleanCmd hasPrefix:@"bt-disconnect "] || [cleanCmd hasPrefix:@"bt disconnect "] || [cleanCmd hasPrefix:@"bluetooth disconnect "]) {
        NSString *deviceName;
        if ([cleanCmd hasPrefix:@"bt disconnect "]) deviceName = [cleanCmd substringFromIndex:14];
        else if ([cleanCmd hasPrefix:@"bluetooth disconnect "]) deviceName = [cleanCmd substringFromIndex:21];
        else deviceName = [cleanCmd substringFromIndex:14];
        deviceName = [deviceName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        
        void *btHandle = dlopen("/System/Library/PrivateFrameworks/BluetoothManager.framework/BluetoothManager", RTLD_NOW);
        if (btHandle) {
            Class BluetoothManagerClass = objc_getClass("BluetoothManager");
            if (BluetoothManagerClass) {
                BluetoothManager *btManager = [BluetoothManagerClass sharedInstance];
                for (BluetoothDevice *device in [btManager pairedDevices]) {
                    if ([[device name] localizedCaseInsensitiveContainsString:deviceName]) {
                        [device disconnect];
                        SRLog(@"[SpringRemote] Disconnecting BT device: %@", [device name]);
                        return [NSString stringWithFormat:@"Disconnecting %@\n", [device name]];
                    }
                }
            }
        }
        return @"Error: Device not found or BluetoothManager failed\n";
    } else if ([cleanCmd isEqualToString:@"wifi-on"] || [cleanCmd isEqualToString:@"wi-on"] || [cleanCmd isEqualToString:@"wifi on"]) {
        SBWiFiManager *manager = [objc_getClass("SBWiFiManager") sharedInstance];
        if (manager) {
            [manager setWiFiEnabled:YES];
            SRLog(@"[SpringRemote] WiFi enabled");
            return @"WiFi Enabled\n";
        }
        return @"Error: SBWiFiManager not found\n";
    } else if ([cleanCmd isEqualToString:@"wifi-off"] || [cleanCmd isEqualToString:@"wi-off"] || [cleanCmd isEqualToString:@"wifi off"]) {
        SBWiFiManager *manager = [objc_getClass("SBWiFiManager") sharedInstance];
        if (manager) {
            [manager setWiFiEnabled:NO];
            SRLog(@"[SpringRemote] WiFi disabled");
            return @"WiFi Disabled\n";
        }
        return @"Error: SBWiFiManager not found\n";
    } else if ([cleanCmd isEqualToString:@"airplane on"]) {
        SRLog(@"[SpringRemote] Executing airplane ON...");
        dlopen("/System/Library/PrivateFrameworks/AppSupport.framework/AppSupport", RTLD_NOW);
        Class RPClass = objc_getClass("RadiosPreferences");
        if (RPClass) {
            RadiosPreferences *prefs = [[RPClass alloc] init];
            [prefs setAirplaneMode:YES];
            [prefs synchronize];
            SRLog(@"[SpringRemote] Airplane Mode ON");
            return @"Airplane Mode ON\n";
        }
        return @"Error: RadiosPreferences not found\n";
    } else if ([cleanCmd isEqualToString:@"airplane off"]) {
        SRLog(@"[SpringRemote] Executing airplane OFF...");
        dlopen("/System/Library/PrivateFrameworks/AppSupport.framework/AppSupport", RTLD_NOW);
        Class RPClass = objc_getClass("RadiosPreferences");
        if (RPClass) {
            RadiosPreferences *prefs = [[RPClass alloc] init];
            [prefs setAirplaneMode:NO];
            [prefs synchronize];
            SRLog(@"[SpringRemote] Airplane Mode OFF");
            return @"Airplane Mode OFF\n";
        }
        return @"Error: RadiosPreferences not found\n";
    } else if ([cleanCmd isEqualToString:@"airplane"] || [cleanCmd isEqualToString:@"airplane toggle"]) {
        SRLog(@"[SpringRemote] Executing airplane toggle...");
        dlopen("/System/Library/PrivateFrameworks/AppSupport.framework/AppSupport", RTLD_NOW);
        Class RPClass = objc_getClass("RadiosPreferences");
        if (RPClass) {
            RadiosPreferences *prefs = [[RPClass alloc] init];
            BOOL current = [prefs airplaneMode];
            [prefs setAirplaneMode:!current];
            [prefs synchronize];
            SRLog(@"[SpringRemote] Airplane Mode Toggled: %d -> %d", current, !current);
            return [NSString stringWithFormat:@"Airplane Mode Toggled: %@\n", !current ? @"ON" : @"OFF"];
        }
    } else if ([cleanCmd hasPrefix:@"brightness "]) {
        // Set screen brightness (0-100) using BackBoardServices
        NSString *valueStr = [[cleanCmd substringFromIndex:11] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        float value = [valueStr floatValue];
        // Clamp to 0-100 and convert to 0.0-1.0
        value = fmaxf(0, fminf(100, value)) / 100.0f;
        
        void *bbHandle = dlopen("/System/Library/PrivateFrameworks/BackBoardServices.framework/BackBoardServices", RTLD_NOW);
        if (bbHandle) {
            void (*BKSDisplayBrightnessSet)(float, int) = dlsym(bbHandle, "BKSDisplayBrightnessSet");
            if (BKSDisplayBrightnessSet) {
                BKSDisplayBrightnessSet(value, 1);
                NSLog(@"[RemoteCommand] Brightness set to: %.0f%%", value * 100);
            }
        }

    } else if ([cleanCmd hasPrefix:@"set-vol "]) {
        NSString *valStr = [[cleanCmd substringFromIndex:8] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        float val = [valStr floatValue];
        // Clamp 0-100 -> 0.0-1.0
        val = fmaxf(0, fminf(100, val)) / 100.0f;
        
        SRLog(@"[SpringRemote] Setting volume to %.2f", val);
        
        // Use AVSystemController
        AVSystemController *av = [objc_getClass("AVSystemController") sharedAVSystemController];
        if (av) {
            [av setVolumeTo:val forCategory:@"Audio/Video"];
            return [NSString stringWithFormat:@"Volume set to %.0f%%\n", val * 100];
        } else {
            return @"Error: AVSystemController not found\n";
        }    
    } else if ([cleanCmd isEqualToString:@"haptic"]) {
        // Haptic feedback using UIImpactFeedbackGenerator
        dispatch_async(dispatch_get_main_queue(), ^{
            UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleHeavy];
            [generator prepare];
            [generator impactOccurred];
        });
        NSLog(@"[RemoteCommand] Haptic triggered");
    } else if ([cleanCmd isEqualToString:@"flash-on"] || [cleanCmd isEqualToString:@"flash on"]) {
        // Flashlight on using AVCaptureDevice
        AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
        if ([device hasTorch] && [device isTorchAvailable]) {
            [device lockForConfiguration:nil];
            [device setTorchMode:AVCaptureTorchModeOn];
            [device unlockForConfiguration];
            NSLog(@"[RemoteCommand] Flashlight on");
        }
    } else if ([cleanCmd isEqualToString:@"flash-off"] || [cleanCmd isEqualToString:@"flash off"]) {
        // Flashlight off
        AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
        if ([device hasTorch]) {
            [device lockForConfiguration:nil];
            [device setTorchMode:AVCaptureTorchModeOff];
            [device unlockForConfiguration];
            NSLog(@"[RemoteCommand] Flashlight off");
        }
    } else if ([cleanCmd isEqualToString:@"flashlight toggle"]) {
        AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
        if ([device hasTorch] && [device isTorchAvailable]) {
            [device lockForConfiguration:nil];
            if ([device torchMode] == AVCaptureTorchModeOn) {
                [device setTorchMode:AVCaptureTorchModeOff];
                NSLog(@"[RemoteCommand] Flashlight toggled OFF");
            } else {
                [device setTorchMode:AVCaptureTorchModeOn];
                NSLog(@"[RemoteCommand] Flashlight toggled ON");
            }
            [device unlockForConfiguration];
        }
    } else if ([cleanCmd isEqualToString:@"flashlight on"]) {
        AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
        if ([device hasTorch] && [device isTorchAvailable]) {
            [device lockForConfiguration:nil];
            [device setTorchMode:AVCaptureTorchModeOn];
            [device unlockForConfiguration];
        }
    } else if ([cleanCmd isEqualToString:@"flashlight off"]) {
        AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
        if ([device hasTorch]) {
            [device lockForConfiguration:nil];
            [device setTorchMode:AVCaptureTorchModeOff];
            [device unlockForConfiguration];
        }
    } else if ([cleanCmd hasPrefix:@"kill "]) {
        NSString *arg = [[cleanCmd substringFromIndex:5] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSString *bundleID = resolve_bundle_id(arg);
        
        SRLog(@"[SpringRemote] Killing app: %@ (mapped from %@)", bundleID, arg);
        // Reason 5 = Quit via App Switcher (clean kill)
        BKSTerminateApplicationForReasonAndReportWithDescription(bundleID, 5, false, nil);
        return [NSString stringWithFormat:@"Killed %@\n", bundleID];
    } else if ([cleanCmd isEqualToString:@"app"]) {
        __block NSString *pid = nil;
        void (^getBlock)(void) = ^{
            SBApplication *frontApp = [(SpringBoard *)[UIApplication sharedApplication] _accessibilityFrontMostApplication];
            pid = [frontApp bundleIdentifier];
        };
        
        if ([NSThread isMainThread]) getBlock();
        else dispatch_sync(dispatch_get_main_queue(), getBlock);
        
        if (pid) {
            return [NSString stringWithFormat:@"%@\n", pid];
        }
        return @"com.apple.springboard\n"; // Fallback
    } else if ([cleanCmd hasPrefix:@"rotate "]) {
        NSString *arg = [[cleanCmd substringFromIndex:7] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        
        __block NSString *result = nil;
        void (^rotateBlock)(void) = ^{
            SBOrientationLockManager *manager = [objc_getClass("SBOrientationLockManager") sharedInstance];
            if ([arg isEqualToString:@"lock"]) {
                [manager lock];
                result = @"Orientation Locked\n";
            } else if ([arg isEqualToString:@"unlock"]) {
                [manager unlock];
                result = @"Orientation Unlocked\n";
            } else {
                BOOL isLocked = [manager isUserLocked];
                result = [NSString stringWithFormat:@"Orientation Lock Status: %@\n", isLocked ? @"Locked" : @"Unlocked"]; // Fallback to status
            }
        };
        
        if ([NSThread isMainThread]) rotateBlock();
        else dispatch_sync(dispatch_get_main_queue(), rotateBlock);
        return result;
    } else if ([cleanCmd isEqualToString:@"rotate"]) {
         __block NSString *result = nil;
         void (^statusBlock)(void) = ^{
             SBOrientationLockManager *manager = [objc_getClass("SBOrientationLockManager") sharedInstance];
             BOOL isLocked = [manager isUserLocked];
             result = [NSString stringWithFormat:@"Orientation Lock Status: %@\n", isLocked ? @"Locked" : @"Unlocked"];
         };
         
         if ([NSThread isMainThread]) statusBlock();
         else dispatch_sync(dispatch_get_main_queue(), statusBlock);
         return result;
    } else if ([cleanCmd hasPrefix:@"paste "]) {
        NSString *content = [[cleanCmd substringFromIndex:6] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        dispatch_block_t pasteBlock = ^{
             UIPasteboard *pb = [UIPasteboard generalPasteboard];
             pb.string = content;
        };
        
        if ([NSThread isMainThread]) pasteBlock();
        else dispatch_sync(dispatch_get_main_queue(), pasteBlock);
        return [NSString stringWithFormat:@"Clipboard set to: %@\n", content];
    } else if ([cleanCmd hasPrefix:@"type "]) {
        NSString *text = [[cleanCmd substringFromIndex:5] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        SRLog(@"Typing text: %@", text);
        const char *utf8 = [text UTF8String];
        size_t len = strlen(utf8);
        for (size_t i = 0; i < len; i++) {
            type_character(utf8[i]);
            usleep(50000); // 50ms delay between keys
        }
        return @"Typing completed\n";
    } else if ([cleanCmd isEqualToString:@"screenshot"]) {
         dispatch_async(dispatch_get_main_queue(), ^{
             @try {
                 SRLog(@"[SpringRemote] Attempting screenshot via SpringBoard takeScreenshot...");
                 SpringBoard *sb = (SpringBoard *)[UIApplication sharedApplication];
                 if ([sb respondsToSelector:@selector(takeScreenshot)]) {
                     [sb performSelector:@selector(takeScreenshot)];
                     SRLog(@"[SpringRemote] Screenshot triggered via [SpringBoard takeScreenshot]");
                 } else {
                     SRLog(@"[SpringRemote] [SpringBoard takeScreenshot] selector missing");
                     
                     // Fallback check for new screenshot manager location
                     if ([sb respondsToSelector:@selector(screenshotManager)]) {
                         id manager = [sb performSelector:@selector(screenshotManager)];
                         if (manager && [manager respondsToSelector:@selector(saveScreenshotToCameraRollWithCompletion:)]) {
                             [manager saveScreenshotToCameraRollWithCompletion:nil];
                             SRLog(@"[SpringRemote] Screenshot triggered via [SB screenshotManager]");
                         }
                     }
                 }
             } @catch (NSException *e) {
                 SRLog(@"[SpringRemote] Exception triggering screenshot: %@", e);
             }
         });
         return @"Screenshot triggered\n";
    } else if ([cleanCmd hasPrefix:@"delay "]) {
        NSString *delayStr = [cleanCmd substringFromIndex:6];
        float seconds = [delayStr floatValue];
        if (seconds > 0) {
            SRLog(@"[SpringRemote] Delaying for %.2f seconds...", seconds);
            usleep((useconds_t)(seconds * 1000000));
        }
        return nil;
    } else if ([cleanCmd hasPrefix:@"exec "]) {
        NSString *shellCmd = [[cleanCmd substringFromIndex:5] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        SRLog(@"[SpringRemote] Processing command: %@", shellCmd);
        
        if ([shellCmd hasPrefix:@"rc "]) {
             NSString *internalCmd = [shellCmd substringFromIndex:3];
             SRLog(@"[SpringRemote] Intercepting 'rc' command, executing internally: %@", internalCmd);
             return handle_command(internalCmd);
        } else if ([shellCmd hasPrefix:@"curl "]) {
            SRLog(@"[SpringRemote] Detected curl command, using native implementation");
            perform_native_curl(shellCmd);
            return [NSString stringWithFormat:@"Executing via native curl: %@\n", shellCmd];
        } else {
            // Fallback to system()
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                int (*sys)(const char *) = dlsym(RTLD_DEFAULT, "system");
                int result = -1;
                if (sys) {
                     result = sys([shellCmd UTF8String]);
                }
                SRLog(@"[SpringRemote] Shell command finished with exit code: %d", result);
            });
            return [NSString stringWithFormat:@"Executing via system(): %@\n", shellCmd];
        }
    } else if ([cleanCmd hasPrefix:@"lua_eval "] || [cleanCmd hasPrefix:@"Lua "]) {
        NSString *code = [cleanCmd substringFromIndex:([cleanCmd hasPrefix:@"Lua "] ? 4 : 9)];
        return evaluate_lua_code(code);
    } else if ([cleanCmd hasPrefix:@"lua "]) {
        NSString *scriptPath = [[cleanCmd substringFromIndex:4] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        return execute_lua_script(scriptPath);
    } else if ([cleanCmd isEqualToString:@"airplay list"]) {
        __block NSString *result = nil;
        dispatch_semaphore_t sema = dispatch_semaphore_create(0);
        
        dispatch_async(dispatch_get_main_queue(), ^{
            MPAVRoutingController *ctrl = [[objc_getClass("MPAVRoutingController") alloc] init];
            ctrl.discoveryMode = 3; // Detailed
            [ctrl fetchAvailableRoutesWithCompletionHandler:^(NSArray<MPAVRoute *> *routes) {
                NSMutableString *output = [NSMutableString string];
                if (routes.count == 0) {
                    [output appendString:@"No AirPlay devices found.\n"];
                } else {
                    for (MPAVRoute *route in routes) {
                        NSString *name = route.routeName ?: @"Unknown";
                        NSString *uid = route.routeUID ?: @"No UID";
                        // Mark picked route
                        NSString *prefix = route.picked ? @"* " : @"  ";
                        [output appendFormat:@"%@%@ [%@]\n", prefix, name, uid];
                    }
                }
                result = output;
                dispatch_semaphore_signal(sema);
            }];
        });
        
        // Wait up to 4 seconds
        dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, 4 * NSEC_PER_SEC));
        return result ?: @"Error: Timeout fetching AirPlay devices\n";

    } else if ([cleanCmd hasPrefix:@"airplay connect "]) {
        NSString *target = [[cleanCmd substringFromIndex:16] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        // Strip outer quotes if present
        if ([target hasPrefix:@"\""] && [target hasSuffix:@"\""] && target.length >= 2) {
            target = [target substringWithRange:NSMakeRange(1, target.length - 2)];
        }

        __block NSString *result = nil;
        dispatch_semaphore_t sema = dispatch_semaphore_create(0);
        
        dispatch_async(dispatch_get_main_queue(), ^{
            MPAVRoutingController *ctrl = [[objc_getClass("MPAVRoutingController") alloc] init];
            ctrl.discoveryMode = 3; // Detailed discovery
            
            // Recursive block for retrying
            __block int attempts = 0;
            __block void (^attemptConnection)(void) = nil;
            
            attemptConnection = ^void(void) {
                [ctrl fetchAvailableRoutesWithCompletionHandler:^(NSArray<MPAVRoute *> *routes) {
                    MPAVRoute *foundRoute = nil;
                    for (MPAVRoute *route in routes) {
                        if ([route.routeUID isEqualToString:target] || [route.routeName localizedCaseInsensitiveContainsString:target]) {
                            foundRoute = route;
                            break;
                        }
                    }
                    
                    if (foundRoute) {
                        if ([ctrl pickRoute:foundRoute]) {
                            result = [NSString stringWithFormat:@"Connected to %@\n", foundRoute.routeName];
                        } else {
                            result = [NSString stringWithFormat:@"Failed to connect to %@\n", foundRoute.routeName];
                        }
                        dispatch_semaphore_signal(sema);
                        attemptConnection = nil; // Break retain cycle
                    } else {
                        attempts++;
                        if (attempts < 10) { // Try for 5 seconds (10 * 0.5s)
                            SRLog(@"[SpringRemote] AirPlay target '%@' not found yet, retrying (%d/10)...", target, attempts);
                            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                                if (attemptConnection) attemptConnection(); // Retry
                            });
                        } else {
                            // Final failure
                            NSMutableString *debugList = [NSMutableString string];
                            for (MPAVRoute *r in routes) {
                                [debugList appendFormat:@"- %@ [%@]\n", r.routeName, r.routeUID];
                            }
                            result = [NSString stringWithFormat:@"Device '%@' not found after 5s. Available:\n%@", target, debugList];
                            dispatch_semaphore_signal(sema);
                            attemptConnection = nil; // Break retain cycle
                        }
                    }
                }];
            };
            
            // Start the first attempt
            attemptConnection();
        });
        
        // Wait up to 6 seconds (allowing for the 5s retry loop + buffer)
        dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, 6 * NSEC_PER_SEC));
        return result ?: @"Error: Timeout connecting to AirPlay device\n";

    } else if ([cleanCmd isEqualToString:@"respring"]) {
        SRLog(@"[SpringRemote] Triggering Respring via killbackboardd");
        
        dispatch_async(dispatch_get_main_queue(), ^{
            // Reliable Tweak way: Kill backboardd
            pid_t pid;
            const char* args[] = { "killall", "-9", "backboardd", NULL };
            posix_spawn(&pid, "/var/jb/usr/bin/killall", NULL, NULL, (char* const*)args, NULL);
            
            // Fallback for non-rootless
            if (pid <= 0) {
                 const char* args2[] = { "killall", "-9", "backboardd", NULL };
                 posix_spawn(&pid, "/usr/bin/killall", NULL, NULL, (char* const*)args2, NULL);
            }
        });
        return @"Device Respringing...\n";
    } else if ([cleanCmd hasPrefix:@"shortcut:"]) {
        NSString *shortcutName = [[cleanCmd substringFromIndex:9] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        
        SRLog(@"[SpringRemote] Attempting to run shortcut: %@", shortcutName);
        
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            @try {
                 Class NSTaskClass = NSClassFromString(@"NSTask");
                 if (NSTaskClass) {
                     id task = [[NSTaskClass alloc] init];
                     
                     NSString *binPath = @"/var/jb/usr/bin/springcuts";
                     if (![[NSFileManager defaultManager] fileExistsAtPath:binPath]) {
                         binPath = @"/usr/bin/springcuts";
                     }
                     
                     if ([[NSFileManager defaultManager] fileExistsAtPath:binPath]) {
                         [task performSelector:@selector(setLaunchPath:) withObject:binPath];
                         [task performSelector:@selector(setArguments:) withObject:@[@"-r", shortcutName]];
                         [task performSelector:@selector(launch)];
                         SRLog(@"[SpringRemote] Launched springcuts for '%@'", shortcutName);
                     } else {
                         SRLog(@"[SpringRemote] Error: springcuts binary not found");
                         send_notification(@"RemoteCompanion", @"Please install SpringCuts to use shortcuts.", YES);
                     }
                 } else {
                     SRLog(@"[SpringRemote] Error: NSTask class not found");
                 }
            } @catch (NSException *e) {
                SRLog(@"[SpringRemote] Crash launching shortcut: %@", e);
            }
        });
        
        return [NSString stringWithFormat:@"Triggered shortcut: %@\n", shortcutName];
    }
    return nil;
}


static void start_server() {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // Server starts always, but will refuse commands if disabled in config
        
        int server_fd, new_socket;
        struct sockaddr_in address;
        int opt = 1;
        int addrlen = sizeof(address);
        char buffer[1024] = {0};
        
        // Ports to try in order
        int ports[] = {1234, 1235, 1236, 1237, 1238};
        int num_ports = sizeof(ports) / sizeof(ports[0]);
        int bound_port = 0;

        if ((server_fd = socket(AF_INET, SOCK_STREAM, 0)) == 0) {
            SRLog(@"[RemoteCommand] ERROR: Failed to create socket");
            return;
        }

        // Set both SO_REUSEADDR and SO_REUSEPORT for faster rebind after respring
        if (setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt))) {
            SRLog(@"[RemoteCommand] WARNING: Failed to set SO_REUSEADDR");
        }
        #ifdef SO_REUSEPORT
        if (setsockopt(server_fd, SOL_SOCKET, SO_REUSEPORT, &opt, sizeof(opt))) {
            SRLog(@"[RemoteCommand] WARNING: Failed to set SO_REUSEPORT");
        }
        #endif

        address.sin_family = AF_INET;
        address.sin_addr.s_addr = INADDR_ANY;
        
        // Try each port until one works
        for (int i = 0; i < num_ports; i++) {
            address.sin_port = htons(ports[i]);
            
            if (bind(server_fd, (struct sockaddr *)&address, sizeof(address)) == 0) {
                bound_port = ports[i];
                SRLog(@"[RemoteCommand] Successfully bound to port %d", bound_port);
                break;
            } else {
                SRLog(@"[RemoteCommand] Failed to bind to port %d (errno: %d - %s), trying next...", 
                      ports[i], errno, strerror(errno));
            }
        }
        
        if (bound_port == 0) {
            SRLog(@"[RemoteCommand] ERROR: Failed to bind to any port!");
            close(server_fd);
            return;
        }
        
        if (listen(server_fd, 3) < 0) {
            SRLog(@"[RemoteCommand] ERROR: Failed to listen (errno: %d)", errno);
            close(server_fd);
            return;
        }

        SRLog(@"[RemoteCommand] Server listening on port %d", bound_port);

        while (1) {
            if ((new_socket = accept(server_fd, (struct sockaddr *)&address, (socklen_t*)&addrlen)) < 0) continue;
            
            // Get client IP
            char *client_ip = inet_ntoa(address.sin_addr);
            BOOL isLocalhost = (strcmp(client_ip, "127.0.0.1") == 0);
            
            // Check config if not localhost
            if (!isLocalhost) {
                // Check if TCP server is enabled in config (dynamic reload)
                load_trigger_config();
                BOOL tcpEnabled = NO; // Default
                if (g_triggerConfig) {
                    id tcpVal = g_triggerConfig[@"tcpEnabled"];
                    tcpEnabled = (tcpVal == nil) ? NO : [tcpVal boolValue];
                }
                
                if (!tcpEnabled) {
                    // Connection rejected by policy (only allow localhost)
                    close(new_socket);
                    continue;
                }
            }
            
            ssize_t valread = read(new_socket, buffer, 1024);
            if (valread > 0) {
                NSString *cmd = [[NSString alloc] initWithBytes:buffer length:valread encoding:NSUTF8StringEncoding];
                NSString *response = handle_command(cmd);
                if (response) {
                     write(new_socket, [response UTF8String], [response lengthOfBytesUsingEncoding:NSUTF8StringEncoding]);
                }
            }
            close(new_socket);
            memset(buffer, 0, 1024);
        }
    });
}

// --- REPLACEMENT NOTE: Removed %ctor from here to move to the end ---



// --- ROBUST HOOKS ---

static NSTimer *g_volUpTimer = nil;
static BOOL g_volUpTriggered = NO;
static BOOL g_volIsReplaying = NO; // Recursion guard for replay

static NSTimer *g_volDownTimer = nil;
static BOOL g_volDownTriggered = NO;

static BOOL g_volUpIsDown = NO;
static BOOL g_volDownIsDown = NO;
static BOOL g_volComboTriggered = NO;

static NSTimer *g_lockButtonTimer = nil;
static BOOL g_lockButtonTriggered = NO;
static NSTimer *g_systemPowerOffTimer = nil; // New for dual-stage
static BOOL g_forceSystemLongPress = NO;     // New for dual-stage
static BOOL g_powerIsDown = NO;
static BOOL g_powerVolComboTriggered = NO;

// Biometric / Touch ID Globals
static NSTimeInterval g_bioFingerDownTime = 0;
static BOOL g_bioHoldTriggered = NO;
static NSTimer *g_bioWatchdogTimer = nil;
static NSTimeInterval g_bioIgnoreUntil = 0;
static BOOL g_bioWasLocked = NO;


// static NSTimeInterval g_lastPowerUpTime = 0; // Removed unused variable



// Helper to trigger haptic feedback
static void trigger_haptic() {
    AudioServicesPlaySystemSound(1520);
}

// --- SAFE VOLUME HOLD IMPLEMENTATION ---


static int g_lastRingerState = -1;

%hook SBRingerControl

-(void)setRingerMuted:(BOOL)muted {
    %orig;

    if (g_lastRingerState == -1) {
        // First initialization (respring/reboot) - just track state, don't fire
        SRLog(@"[SpringRemote] SBRingerControl Initial State: %d", muted);
        g_lastRingerState = (int)muted;
        return;
    }

    if (g_lastRingerState == (int)muted) {
        // State hasn't changed, ignore
        return;
    }

    // State changed
    g_lastRingerState = (int)muted;
    SRLog(@"[SpringRemote] SBRingerControl setRingerMuted: %d", muted);
    
    // Fire generic toggle status
    RCExecuteTrigger(@"trigger_ringer_toggle");

    if (muted) {
        RCExecuteTrigger(@"trigger_ringer_mute");
    } else {
        RCExecuteTrigger(@"trigger_ringer_unmute");
    }
}

%end

%hook SBVolumeHardwareButtonActions

- (void)volumeIncreasePressDownWithModifiers:(long long)arg1 {
    if (g_volIsReplaying) {
        %orig;
        return;
    }

    if (g_powerIsDown) {
        load_trigger_config();
        if ([g_triggerConfig[@"masterEnabled"] boolValue] && [g_triggerConfig[@"triggers"][@"power_volume_up"][@"enabled"] boolValue]) {
            SRLog(@"[SpringRemote] Suppressing Volume Up because Power is DOWN (Combo)");
            return;
        }
    }

    g_volUpIsDown = YES;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        load_trigger_config();
        BOOL masterEnabled = [g_triggerConfig[@"masterEnabled"] boolValue];
        BOOL comboEnabled = masterEnabled && [g_triggerConfig[@"triggers"][@"volume_both_press"][@"enabled"] boolValue];
        BOOL holdEnabled = masterEnabled && [g_triggerConfig[@"triggers"][@"volume_up_hold"][@"enabled"] boolValue];

        if (holdEnabled || comboEnabled) {
            if (g_volUpTimer) [g_volUpTimer invalidate];
            g_volUpTimer = [NSTimer scheduledTimerWithTimeInterval:0.35 repeats:NO block:^(NSTimer *timer) {
                if (g_volComboTriggered) return;
                g_volUpTimer = nil;
                if (holdEnabled) {
                    g_volUpTriggered = YES;
                    trigger_haptic();
                    RCExecuteTrigger(@"volume_up_hold");
                }
            }];
        } else {
            g_volIsReplaying = YES;
            [self volumeIncreasePressDownWithModifiers:arg1];
            g_volIsReplaying = NO;
        }
    });
}

- (void)volumeIncreasePressUp {
    g_volUpIsDown = NO;
    if (g_volIsReplaying) {
        %orig;
        return;
    }

    if (g_volComboTriggered) {
        if (!g_volDownIsDown) g_volComboTriggered = NO;
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        load_trigger_config();
        BOOL masterEnabled = [g_triggerConfig[@"masterEnabled"] boolValue];
        BOOL holdEnabled = masterEnabled && [g_triggerConfig[@"triggers"][@"volume_up_hold"][@"enabled"] boolValue];
        BOOL comboEnabled = masterEnabled && [g_triggerConfig[@"triggers"][@"volume_both_press"][@"enabled"] boolValue];

        if (holdEnabled || comboEnabled) {
            if (g_volUpTimer) {
                [g_volUpTimer invalidate];
                g_volUpTimer = nil;
                g_volIsReplaying = YES;
                [self volumeIncreasePressDownWithModifiers:0];
                [self volumeIncreasePressUp];
                g_volIsReplaying = NO;
            }
            if (g_volUpTriggered) {
                g_volUpTriggered = NO;
            }
        } else {
            g_volIsReplaying = YES;
            [self volumeIncreasePressUp];
            g_volIsReplaying = NO;
        }
    });
}

- (void)volumeDecreasePressDownWithModifiers:(long long)arg1 {
    if (g_volIsReplaying) {
        %orig;
        return;
    }

    if (g_powerIsDown) {
        load_trigger_config();
        if ([g_triggerConfig[@"masterEnabled"] boolValue] && [g_triggerConfig[@"triggers"][@"power_volume_down"][@"enabled"] boolValue]) {
            SRLog(@"[SpringRemote] Suppressing Volume Down because Power is DOWN (Combo)");
            return;
        }
    }

    g_volDownIsDown = YES;

    dispatch_async(dispatch_get_main_queue(), ^{
        load_trigger_config();
        BOOL masterEnabled = [g_triggerConfig[@"masterEnabled"] boolValue];
        BOOL comboEnabled = masterEnabled && [g_triggerConfig[@"triggers"][@"volume_both_press"][@"enabled"] boolValue];
        BOOL holdEnabled = masterEnabled && [g_triggerConfig[@"triggers"][@"volume_down_hold"][@"enabled"] boolValue];

        if (holdEnabled || comboEnabled) {
            if (g_volDownTimer) [g_volDownTimer invalidate];
            g_volDownTimer = [NSTimer scheduledTimerWithTimeInterval:0.35 repeats:NO block:^(NSTimer *timer) {
                if (g_volComboTriggered) return;
                g_volDownTimer = nil;
                if (holdEnabled) {
                    g_volDownTriggered = YES;
                    trigger_haptic();
                    RCExecuteTrigger(@"volume_down_hold");
                }
            }];
        } else {
            g_volIsReplaying = YES;
            [self volumeDecreasePressDownWithModifiers:arg1];
            g_volIsReplaying = NO;
        }
    });
}

- (void)volumeDecreasePressUp {
    g_volDownIsDown = NO;
    if (g_volIsReplaying) {
        %orig;
        return;
    }

    if (g_volComboTriggered) {
        if (!g_volUpIsDown) g_volComboTriggered = NO;
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        load_trigger_config();
        BOOL masterEnabled = [g_triggerConfig[@"masterEnabled"] boolValue];
        BOOL holdEnabled = masterEnabled && [g_triggerConfig[@"triggers"][@"volume_down_hold"][@"enabled"] boolValue];
        BOOL comboEnabled = masterEnabled && [g_triggerConfig[@"triggers"][@"volume_both_press"][@"enabled"] boolValue];

        if (holdEnabled || comboEnabled) {
            if (g_volDownTimer) {
                [g_volDownTimer invalidate];
                g_volDownTimer = nil;
                g_volIsReplaying = YES;
                [self volumeDecreasePressDownWithModifiers:0];
                [self volumeDecreasePressUp];
                g_volIsReplaying = NO;
            }
            if (g_volDownTriggered) {
                g_volDownTriggered = NO;
            }
        } else {
            g_volIsReplaying = YES;
            [self volumeDecreasePressUp];
            g_volIsReplaying = NO;
        }
    });
}

%end


// --- IOHID Definitions for Background Listener ---
typedef struct __IOHIDEvent * IOHIDEventRef;
typedef struct __IOHIDEventSystemClient * IOHIDEventSystemClientRef;
typedef uint32_t IOHIDEventOptionBits;
typedef uint32_t IOOptionBits;

extern IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator);
extern int IOHIDEventGetType(IOHIDEventRef event);
extern int IOHIDEventGetIntegerValue(IOHIDEventRef event, int field);
extern void IOHIDEventSystemClientRegisterEventCallback(IOHIDEventSystemClientRef client, void* callback, void* target, void* refcon);
extern void IOHIDEventSystemClientScheduleWithRunLoop(IOHIDEventSystemClientRef client, CFRunLoopRef runLoop, CFStringRef runLoopMode);

typedef void (*IOHIDEventSystemClientEventCallback)(void* target, void* refcon, void* queue, IOHIDEventRef event);

// Usage Pages / Usages
#define kHIDPage_GenericDesktop 0x01
#define kHIDPage_Consumer       0x0C
#define kHIDUsage_GD_SystemSleep 0x82
#define kHIDUsage_Csmr_Power     0x30
#define kHIDUsage_Csmr_Menu      0x40
#define kHIDUsage_Csmr_VolumeIncrement 0xE9
#define kHIDUsage_Csmr_VolumeDecrement 0xEA
#define kHIDUsage_Csmr_PlayOrPause 0xCD

#define kIOHIDEventTypeKeyboard 3
#define kIOHIDEventFieldKeyboardUsagePage 0x30000
#define kIOHIDEventFieldKeyboardUsage 0x30001
#define kIOHIDEventFieldKeyboardDown 0x30002

// --- BACKGROUND HID LISTENER (Safe for NFC) ---
// Restores reliable Home Button counting without crashing NearField

static int g_homeClickCount = 0;
static NSTimer *g_homeClickTimer = nil;

// Power Button Multi-Click Globals
static int g_powerClickCount = 0;
static NSTimer *g_powerClickTimer = nil;
static NSTimeInterval g_lastHIDTime = 0;
static BOOL g_hidButtonDown = NO;
static IOHIDEventSystemClientRef g_hidClient = NULL;

static void RC_CheckAndFire();

static void RC_ProcessHomeClick() {
    g_homeClickCount++;
    SRLog(@"[SpringRemote-HID] 🔵 CLICK DETECTED (Up)! Count: %d", g_homeClickCount);
    
    // Dispatch timer scheduling to Main Thread to be safe with Timers/RunLoops
    dispatch_async(dispatch_get_main_queue(), ^{
        RC_CheckAndFire();
    });
}

static void RC_CheckAndFire() {
    // 1. Reset existing timer
    if (g_homeClickTimer) {
        [g_homeClickTimer invalidate];
        g_homeClickTimer = nil;
    }
    
    // 2. Load Config
    load_trigger_config();
    BOOL masterEnabled = [g_triggerConfig[@"masterEnabled"] boolValue];
    BOOL quadEnabled = masterEnabled && [g_triggerConfig[@"triggers"][@"trigger_home_quadruple_click"][@"enabled"] boolValue];

    // 3. IMMEDIATE FIRE CHECK (Quadruple)
    if (quadEnabled && g_homeClickCount >= 4) {
        SRLog(@"[SpringRemote] 🚀 QUAD CLICK (4+) REACHED! Firing immediately.");
        trigger_haptic();
        RCExecuteTrigger(@"trigger_home_quadruple_click");
        g_homeClickCount = 0; // Reset Sequence
        return;
    }
    
    // 4. Determines Timeout
    NSTimeInterval timeout = 0.35; 
    if (quadEnabled) timeout = 0.55; 
    
    // 5. Schedule Timer
    g_homeClickTimer = [NSTimer scheduledTimerWithTimeInterval:timeout repeats:NO block:^(NSTimer *timer) {
        g_homeClickTimer = nil;
        SRLog(@"[SpringRemote] 🔵 SEQUENCE ENDED. Final count: %d", g_homeClickCount);
        
        NSString *triggerKey = nil;
        
        if (g_homeClickCount == 4 && quadEnabled) triggerKey = @"trigger_home_quadruple_click";
        else if (g_homeClickCount == 3) triggerKey = @"trigger_home_triple_click";
        else if (g_homeClickCount == 2) triggerKey = @"trigger_home_double_click";
        
        if (triggerKey && masterEnabled) {
            BOOL enabled = [g_triggerConfig[@"triggers"][triggerKey][@"enabled"] boolValue];
            if (enabled) {
                SRLog(@"[SpringRemote] ✅ FIRING TRIGGER: %@", triggerKey);
                trigger_haptic();
                RCExecuteTrigger(triggerKey);
            }
        }
        g_homeClickCount = 0;
    }];
}

static void RC_CheckAndFirePower();

static void RC_ProcessPowerClick() {
    // 1. Reset timer
    if (g_powerClickTimer) {
        [g_powerClickTimer invalidate];
        g_powerClickTimer = nil;
    }
    
    g_powerClickCount++;
    SRLog(@"[SpringRemote-HID] ⚡️ POWER CLICK DETECTED. Count: %d", g_powerClickCount);
    
    // Dispatch timer scheduling to Main Thread to be safe with Timers/RunLoops
    dispatch_async(dispatch_get_main_queue(), ^{
        RC_CheckAndFirePower();
    });
}

// Power Button Multi-Click Logic
static void RC_CheckAndFirePower() {
    // 1. Reset timer
    if (g_powerClickTimer) {
        [g_powerClickTimer invalidate];
        g_powerClickTimer = nil;
    }
    
    load_trigger_config();
    BOOL masterEnabled = [g_triggerConfig[@"masterEnabled"] boolValue];
    BOOL quadEnabled = masterEnabled && [g_triggerConfig[@"triggers"][@"power_quadruple_click"][@"enabled"] boolValue];
    
    // 3. IMMEDIATE FIRE CHECK (Quadruple)
    if (quadEnabled && g_powerClickCount >= 4) {
        SRLog(@"[SpringRemote] 🚀 POWER QUAD CLICK (4+) REACHED! Firing.");
        trigger_haptic();
        RCExecuteTrigger(@"power_quadruple_click");
        g_powerClickCount = 0;
        return;
    }
    
    // 4. Timeout
    NSTimeInterval timeout = 0.4; 
    
    // 5. Schedule Timer
    g_powerClickTimer = [NSTimer scheduledTimerWithTimeInterval:timeout repeats:NO block:^(NSTimer *timer) {
        g_powerClickTimer = nil;
        SRLog(@"[SpringRemote] POWER SEQUENCE ENDED. Final count: %d", g_powerClickCount);
        
        NSString *triggerKey = nil;
        
        if (g_powerClickCount == 4) triggerKey = @"power_quadruple_click"; // Backup if immediate failed or disabled? No, if disabled we land here.
        else if (g_powerClickCount == 3) triggerKey = @"power_triple_click";
        else if (g_powerClickCount == 2) triggerKey = @"power_double_tap";
        
        if (triggerKey && masterEnabled) {
            BOOL enabled = [g_triggerConfig[@"triggers"][triggerKey][@"enabled"] boolValue];
            if (enabled) {
                SRLog(@"[SpringRemote] ✅ FIRING POWER TRIGGER: %@", triggerKey);
                trigger_haptic();
                RCExecuteTrigger(triggerKey);
            }
        }
        g_powerClickCount = 0;
    }];
}

static void handle_hid_event(void* target, void* refcon, IOHIDEventSystemClientRef service, IOHIDEventRef event) {
    int type = IOHIDEventGetType(event);
    
    if (type == 29) { // Biometric Event (Finger on sensor)
        // Toggle Logic for "Hold" (Fire by itself after 1.0s)
        // Assumption: Sensor sends event on DOWN ... (Silence) ... and UP.
        
        NSTimeInterval now = [[NSDate date] timeIntervalSince1970];

        dispatch_async(dispatch_get_main_queue(), ^{
            load_trigger_config();
            BOOL enabled = [g_triggerConfig[@"masterEnabled"] boolValue] && 
                ([g_triggerConfig[@"triggers"][@"touchid_hold"][@"enabled"] boolValue] || 
                 [g_triggerConfig[@"triggers"][@"touchid_tap"][@"enabled"] boolValue]);
            if (!enabled) return;

            // DEBOUNCE CHECK:
            if (now < g_bioIgnoreUntil) {
                // SRLog(@"[SpringRemote-Bio] Ignoring Event (Debounce)");
                return;
            }

            // STATE-BASED TOGGLE LOGIC:
            NSTimeInterval diff = (g_bioFingerDownTime == 0) ? 0 : (now - g_bioFingerDownTime);
            BOOL isStale = (diff > 5.0); // If >5s, assume we missed a lift event and reset.

            if (g_bioFingerDownTime != 0 && !isStale) {
                // STATE = DOWN. This event must be LIFT.
                
                // VARIABLE DELAY:
                // If we started on the lockscreen, we need a bigger window (0.4s) for biometrics to "win" the race.
                // If we're already unlocked, we want it fast (0.05s) for responsiveness.
                NSTimeInterval liftDelay = g_bioWasLocked ? 0.4 : 0.05;

                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(liftDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    if (g_bioFingerDownTime == 0) return; // Already handled or reset

                    // Cancel timer if running.
                    if (g_bioWatchdogTimer) {
                        [g_bioWatchdogTimer invalidate];
                        g_bioWatchdogTimer = nil;

                        NSTimeInterval now_lift = [[NSDate date] timeIntervalSince1970];
                        if (now_lift < g_bioIgnoreUntil) {
                            SRLog(@"[SpringRemote-Bio] Suppressing Tap (Finger Lift within Ignore Window)");
                            g_bioFingerDownTime = 0;
                            g_bioHoldTriggered = NO;
                            return;
                        }

                        // STATE-AWARE SUPPRESSION:
                        // If we were locked when we put our finger down, but we are now UNLOCKED, 
                        // this was an unlock attempt. Skip the tap.
                        Class LSMC = objc_getClass("SBLockScreenManager");
                        SBLockScreenManager *lsm = LSMC ? [LSMC sharedInstance] : nil;
                        BOOL currentlyLocked = lsm ? [lsm isUILocked] : NO;
                        
                        if (g_bioWasLocked && !currentlyLocked) {
                            SRLog(@"[SpringRemote-Bio] Suppressing Tap (Finger Lift after Unlock Match Detected)");
                            g_bioFingerDownTime = 0;
                            g_bioHoldTriggered = NO;
                            return;
                        }

                        if ([g_triggerConfig[@"triggers"][@"touchid_tap"][@"enabled"] boolValue]) {
                            trigger_haptic();
                            RCExecuteTrigger(@"touchid_tap");
                        }
                    }
                    g_bioFingerDownTime = 0; // Reset State to UP.
                    g_bioHoldTriggered = NO;
                    
                    // START DEBOUNCE (Ignore subsequent events for 0.5s to squash "bouncing")
                    g_bioIgnoreUntil = [[NSDate date] timeIntervalSince1970] + 0.5;
                });

            } else {
                // STATE = UP (or Stale). This event must be DOWN.
                // Start Timer!
                g_bioFingerDownTime = now; // Set State to DOWN.
                
                // Track initial lock state
                Class LSMC = objc_getClass("SBLockScreenManager");
                SBLockScreenManager *lsm = LSMC ? [LSMC sharedInstance] : nil;
                g_bioWasLocked = lsm ? [lsm isUILocked] : NO;

                
                if (g_bioWatchdogTimer) [g_bioWatchdogTimer invalidate];
                g_bioWatchdogTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:NO block:^(NSTimer *timer) {

                    g_bioWatchdogTimer = nil; // Timer is done.
                    
                    // ADD DECISION WINDOW FOR HOLD (0.3s)
                    // Similar to the Tap fix, we wait a moment on the lockscreen to let biometrics "win".
                    NSTimeInterval holdDecisionDelay = g_bioWasLocked ? 0.3 : 0.0;
                    
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(holdDecisionDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        // Check ignore window first
                        if ([[NSDate date] timeIntervalSince1970] < g_bioIgnoreUntil) {
                            SRLog(@"[SpringRemote-Bio] Suppressing Hold (Inside Ignore Window)");
                            return;
                        }

                        // STATE-AWARE SUPPRESSION (Hold):
                        Class LSMC2 = objc_getClass("SBLockScreenManager");
                        SBLockScreenManager *lsm2 = LSMC2 ? [LSMC2 sharedInstance] : nil;
                        BOOL currentlyLocked2 = lsm2 ? [lsm2 isUILocked] : NO;
                        
                        if (g_bioWasLocked && !currentlyLocked2) {
                            SRLog(@"[SpringRemote-Bio] Suppressing Hold (Unlock succeeded during decision window)");
                            return;
                        }

                        // Check if trigger is enabled and has actions BEFORE firing haptics
                        if (g_triggerConfig) {
                            NSDictionary *holdTrigger = g_triggerConfig[@"triggers"][@"touchid_hold"];
                            if ([holdTrigger[@"enabled"] boolValue] && [holdTrigger[@"actions"] count] > 0) {
                                trigger_haptic();
                                RCExecuteTrigger(@"touchid_hold");
                            }
                        }
                    });
                }];
            }
        });

    }
    
    // Log Biometric/Mesa events specifically?
    // kIOHIDEventTypeBiometric = 29?
    // Let's just log everything that isn't accelerometer (usually high freq)
    // Accelerometer is... often type 13?
    
    if (type == kIOHIDEventTypeKeyboard) {
        int usagePage = IOHIDEventGetIntegerValue(event, kIOHIDEventFieldKeyboardUsagePage);
        int usage = IOHIDEventGetIntegerValue(event, kIOHIDEventFieldKeyboardUsage);
        int down = IOHIDEventGetIntegerValue(event, kIOHIDEventFieldKeyboardDown);
        
        // SRLog(@"[SpringRemote-HID] KEYBOARD (1) -> Page: 0x%X Usage: 0x%X Down: %d", usagePage, usage, down);
        
        // Home Button (Page 0x0C, Usage 0x40)
        if (usagePage == kHIDPage_Consumer && usage == kHIDUsage_Csmr_Menu) {
            NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
            
            if (down) {
                if (!g_hidButtonDown) {
                    g_hidButtonDown = YES;
                    g_lastHIDTime = now;

                    
                    // SUPPRESS TOUCH ID HOLD:
                    // If user is clicking, they are not "Holding" for the gesture.
                    // Suppress bio events for 1.5s (covers triple clicks).
                    g_bioIgnoreUntil = now + 1.5;
                    
                    // Dispatch state reset to Main Thread to ensure synchronization with Bio handlers
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (g_bioWatchdogTimer) {
                            [g_bioWatchdogTimer invalidate];
                            g_bioWatchdogTimer = nil;
                        }
                        g_bioFingerDownTime = 0;
                        g_bioHoldTriggered = NO;
                    });
                }
            } else { // UP
                if (g_hidButtonDown) {
                    if (now - g_lastHIDTime > 0.05) { // 50ms Debounce
                        g_hidButtonDown = NO;
                        g_lastHIDTime = now;

                        RC_ProcessHomeClick();
                    }
                }
            }
        }
        
        // Power Button (Page 0x0C, Usage 0x30)
        if (usagePage == kHIDPage_Consumer && usage == kHIDUsage_Csmr_Power) {
            NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
            static NSTimeInterval lastPowerDownTime = 0;

            if (down) {
                if (!g_powerIsDown) {
                    g_powerIsDown = YES;
                    lastPowerDownTime = now;
                    SRLog(@"[SpringRemote-HID] ⚡️ Power DOWN");
                    
                    // SUPPRESS TOUCH ID HOLD (on Power Wake/Press):
                    // If user is pressing power, they might be waking to unlock.
                    // Suppress bio events for 1.5s.
                    NSTimeInterval now_power = [[NSDate date] timeIntervalSince1970];
                    g_bioIgnoreUntil = now_power + 1.5;
                    // Also cancel any pending hold timer
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (g_bioWatchdogTimer) {
                            [g_bioWatchdogTimer invalidate];
                            g_bioWatchdogTimer = nil;
                        }
                    });
                    g_bioFingerDownTime = 0;
                    g_bioHoldTriggered = NO;

                    // Check for simultaneous press if Volume is already down
                    if (g_volUpIsDown || g_volDownIsDown) {
                        NSString *triggerKey = g_volUpIsDown ? @"power_volume_up" : @"power_volume_down";
                        load_trigger_config();
                        BOOL masterEnabled = [g_triggerConfig[@"masterEnabled"] boolValue];
                        BOOL enabled = masterEnabled && [g_triggerConfig[@"triggers"][triggerKey][@"enabled"] boolValue];
                        
                        if (enabled && !g_powerVolComboTriggered) {
                            SRLog(@"[SpringRemote-HID] ⚡️+🔊 POWER + VOLUME COMBINATION DETECTED (Power after Volume): %@", triggerKey);
                            g_powerVolComboTriggered = YES;
                            dispatch_async(dispatch_get_main_queue(), ^{
                                 if (g_volUpTimer) { [g_volUpTimer invalidate]; g_volUpTimer = nil; }
                                 if (g_volDownTimer) { [g_volDownTimer invalidate]; g_volDownTimer = nil; }
                                 trigger_haptic();
                                 RCExecuteTrigger(triggerKey);
                            });
                        }
                    }
                }
            } else { // UP
                if (g_powerIsDown) {
                    if (now - lastPowerDownTime > 0.05) { // 50ms Debounce
                        g_powerIsDown = NO;
                        SRLog(@"[SpringRemote-HID] ⚡️ Power UP");
                        
                        // If a combo was triggered, DON'T count this as a click for multi-tap
                        if (g_powerVolComboTriggered) {
                            SRLog(@"[SpringRemote-HID] Combo was triggered, resetting power click count.");
                            g_powerClickCount = 0;
                            g_powerVolComboTriggered = NO;
                        } else {
                            RC_ProcessPowerClick();
                        }
                    }
                    g_powerIsDown = NO; // Handle fast bounce
                }
            }
        }
        
        // Volume Buttons (Page 0x0C, Usage 0xE9/0xEA)
        if (usagePage == kHIDPage_Consumer && (usage == kHIDUsage_Csmr_VolumeIncrement || usage == kHIDUsage_Csmr_VolumeDecrement)) {
            if (usage == kHIDUsage_Csmr_VolumeIncrement) g_volUpIsDown = !!down;
            if (usage == kHIDUsage_Csmr_VolumeDecrement) g_volDownIsDown = !!down;
            
            // Check for Power + Volume combination
            if (down && g_powerIsDown) {
                NSString *triggerKey = (usage == kHIDUsage_Csmr_VolumeIncrement) ? @"power_volume_up" : @"power_volume_down";
                load_trigger_config();
                BOOL masterEnabled = [g_triggerConfig[@"masterEnabled"] boolValue];
                BOOL enabled = masterEnabled && [g_triggerConfig[@"triggers"][triggerKey][@"enabled"] boolValue];
                
                if (enabled) {
                    SRLog(@"[SpringRemote-HID] ⚡️+🔊 POWER + VOLUME COMBINATION DETECTED: %@", triggerKey);
                    g_powerVolComboTriggered = YES;
                    
                    // Invalidate standard timers in Main Thread
                    dispatch_async(dispatch_get_main_queue(), ^{
                         if (g_volUpTimer) { [g_volUpTimer invalidate]; g_volUpTimer = nil; }
                         if (g_volDownTimer) { [g_volDownTimer invalidate]; g_volDownTimer = nil; }
                         trigger_haptic();
                         RCExecuteTrigger(triggerKey);
                    });
                    
                    // We might want to swallow the volume event here, but HID listener is just a listener.
                    // The Volume hooks will also fire, we handle suppression there too.
                }
            }
            
            if (g_volUpIsDown && g_volDownIsDown) {
                if (!g_volComboTriggered) {
                    load_trigger_config();
                    if ([g_triggerConfig[@"masterEnabled"] boolValue] && [g_triggerConfig[@"triggers"][@"volume_both_press"][@"enabled"] boolValue]) {
                        g_volComboTriggered = YES;
                        
                        // Invalidate standard timers in Main Thread
                        dispatch_async(dispatch_get_main_queue(), ^{
                             if (g_volUpTimer) { [g_volUpTimer invalidate]; g_volUpTimer = nil; }
                             if (g_volDownTimer) { [g_volDownTimer invalidate]; g_volDownTimer = nil; }
                             trigger_haptic();
                             RCExecuteTrigger(@"volume_both_press");
                        });
                    }
                }
            } else if (!g_volUpIsDown && !g_volDownIsDown) {
                if (g_volComboTriggered) {
                    g_volComboTriggered = NO;
                }
            }
        }
    }
}

static void setup_background_hid_listener() {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        SRLog(@"[SpringRemote] 🔌 Setting up BACKGROUND HID Listener...");
        
        // Create client
        g_hidClient = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
        if (!g_hidClient) {
            SRLog(@"[SpringRemote] ❌ Failed to create HID Client");
            return;
        }
        
        // Register callback
        IOHIDEventSystemClientRegisterEventCallback(g_hidClient, (IOHIDEventSystemClientEventCallback)handle_hid_event, NULL, NULL);
        
        // Create RunLoop for this background thread
        NSRunLoop *runLoop = [NSRunLoop currentRunLoop];
        
        // Schedule client
        IOHIDEventSystemClientScheduleWithRunLoop(g_hidClient, [runLoop getCFRunLoop], kCFRunLoopDefaultMode);
        
        SRLog(@"[SpringRemote] ✅ HID Listener Scheduled on Background RunLoop. Running...");
        
        // Run the runloop indefinitely
        while (YES) {
            [runLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
        }
    });
}


%hook SBLockScreenManager

- (BOOL)_attemptUnlockWithPasscode:(id)passcode mesa:(BOOL)mesa finishUIUnlock:(BOOL)finishUI {
    BOOL result = %orig;
    if (mesa) {
        SRLog(@"[SpringRemote] 🧬 Biometric (Mesa) Match Detected - setting immediate suppression flag");
        g_bioIgnoreUntil = [[NSDate date] timeIntervalSince1970] + 2.0;
        
        // Cancel pending timers immediately
        if (g_bioWatchdogTimer) {
            [g_bioWatchdogTimer invalidate];
            g_bioWatchdogTimer = nil;
        }
    }
    return result;
}

- (void)unlockUIFromSource:(int)source withOptions:(id)options {
    %orig;
    SRLog(@"[SpringRemote] 🔓 Device Unlocked via SBLockScreenManager (Source: %d)", source);
    
    // Reset biometric state immediately upon unlock to prevent stray triggers
    g_bioFingerDownTime = 0;
    g_bioHoldTriggered = NO;
    
    if (g_bioWatchdogTimer) {
        [g_bioWatchdogTimer invalidate];
        g_bioWatchdogTimer = nil;
        SRLog(@"[SpringRemote] 🔐 Cancelled pending Biometric trigger due to Unlock");
    }
    
    // Brief suppression after unlock (1.0s)
    g_bioIgnoreUntil = [[NSDate date] timeIntervalSince1970] + 1.0;
}

%end

%hook SBLockHardwareButtonActions

- (void)performInitialButtonDownActions {
    SRLog(@"[SpringRemote] performInitialButtonDownActions on %@", [self class]);
    // Removed g_powerBtnActive
    load_trigger_config();
    BOOL enabled = [g_triggerConfig[@"masterEnabled"] boolValue] && 
                   [g_triggerConfig[@"triggers"][@"power_long_press"][@"enabled"] boolValue];

    SRLog(@"[SpringRemote] Power Button DOWN (Actions) - enabled=%d", enabled);

    if (enabled) {
        if (g_lockButtonTimer == nil && !g_lockButtonTriggered) {
            g_lockButtonTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:NO block:^(NSTimer *timer) {
                g_lockButtonTriggered = YES;
                g_lockButtonTimer = nil;
                trigger_haptic();
                RCExecuteTrigger(@"power_long_press");
                SRLog(@"[SpringRemote] Power Long Press Fired (Stage 1)!");
                
                // Start Stage 2 Timer (System Power Off) - 2.0s later (2.5s total hold)
                g_systemPowerOffTimer = [NSTimer scheduledTimerWithTimeInterval:2.0 repeats:NO block:^(NSTimer *t) {
                     SRLog(@"[SpringRemote] Power Long Press (Stage 2) - Forcing System Power Off Screen");
                     g_forceSystemLongPress = YES;
                     g_systemPowerOffTimer = nil;
                     
                     // Manually invoke the action again, but this time g_forceSystemLongPress is YES
                     // We need an instance to call it on. 'self' inside this block is captured? 
                     // No, 'self' in block refers to captured SBLockHardwareButtonActions instance.
                     // IMPORTANT: 'self' in block is valid.
                     [self performLongPressActions];
                }];
            }];
        }
    }

    // SUPPRESSION: If a multi-click sequence is in progress, swallow the DOWN event.
    // This stops the phone from waking/locking on subsequent clicks.
    if (g_powerClickCount >= 1) {
        SRLog(@"[SpringRemote] Suppressing system DOWN for click sequence (count=%d)", g_powerClickCount);
        return;
    }

    %orig;
}

- (void)performButtonUpPreActions {
    SRLog(@"[SpringRemote] performButtonUpPreActions on %@", [self class]);
    // Removed g_powerBtnActive access
    SRLog(@"[SpringRemote] Power Button UP (Actions)");

    if (g_lockButtonTimer) {
        [g_lockButtonTimer invalidate];
        g_lockButtonTimer = nil;
    }
    if (g_systemPowerOffTimer) {
        [g_systemPowerOffTimer invalidate];
        g_systemPowerOffTimer = nil;
    }
    g_forceSystemLongPress = NO;
    
    if (g_lockButtonTriggered) {
        g_lockButtonTriggered = NO;
        SRLog(@"[SpringRemote] Power Button Release: Long press already fired, resetting.");
        return; 
    }

    // SUPPRESSION: Swallow UP events for 2nd click onwards.
    // Click 1 passes %orig so system can lock/wake normally if sequence stops.
    if (g_powerClickCount >= 2) {
        SRLog(@"[SpringRemote] Suppressing system UP for click #%d", g_powerClickCount);
        return;
    }

    // SUPPRESSION: If a Power + Volume combo was triggered, swallow the Power UP as well.
    if (g_powerVolComboTriggered) {
        SRLog(@"[SpringRemote] Suppressing system UP because a Power + Volume combo was triggered.");
        // g_powerVolComboTriggered will be reset in handle_hid_event UP
        return;
    }

    %orig;
}

- (void)performLongPressActions {
    SRLog(@"[SpringRemote] performLongPressActions called - g_lockButtonTriggered=%d, force=%d", g_lockButtonTriggered, g_forceSystemLongPress);
    
    if (g_forceSystemLongPress) {
        SRLog(@"[SpringRemote] Allowing System Power Off (Stage 2)");
        g_forceSystemLongPress = NO; // Reset immediately
        %orig;
        return;
    }

    if (g_lockButtonTriggered) {
        SRLog(@"[SpringRemote] Power Long Press Actions (Default) Suppressed (Stage 1 active)");
        return; 
    }
    %orig;
}

- (void)performDoublePressActions {
    SRLog(@"[SpringRemote] performDoublePressActions called (System)");
    // We handle double press manually in performButtonUpPreActions to support Triple/Quad clicks.
    // So we do NOT fire "power_double_tap" here to avoid duplicates.
    // However, if we suppress %orig completely, we might break Wallet double-click.
    // For now, let's just allow orig so system features work, 
    // relying on our manual counter for OUR actions.
    
    // Logic: If we have a configured double tap action, our manual handler will fire it.
    // If not, this does nothing related to us.
    
    /*
    load_trigger_config();
    BOOL enabled = [g_triggerConfig[@"masterEnabled"] boolValue] && 
                   [g_triggerConfig[@"triggers"][@"power_double_tap"][@"enabled"] boolValue];

    if (enabled) {
        // Don't fire here, manual handler does it.
    }
    */
    /*
        trigger_haptic();
        RCExecuteTrigger(@"power_double_tap");
        SRLog(@"[SpringRemote] Power Double Tap Fired (Actions)");
        return; 
    }
    */
    %orig;
}

%end

// [Generic simulation registration handled by catch-all observer in register_simulation_observers]

%hook SBLockHardwareButton
- (void)doublePress:(id)arg1 {
    SRLog(@"[SpringRemote] SBLockHardwareButton doublePress: called");
    load_trigger_config();
    BOOL enabled = [g_triggerConfig[@"masterEnabled"] boolValue] && 
                   [g_triggerConfig[@"triggers"][@"power_double_tap"][@"enabled"] boolValue];
    if (enabled) {
        // We already handled it in Actions (hopefully), or we handle it here if Actions wasn't called
        // But to be safe, let's see if this one fires.
        %orig; 
    } else {
        %orig;
    }
}
%end



// [Removed unused biometric hooks]


// --- Cleanup: Removed failed biometric logic ---

// [Removed unused SBHomeHardwareButton hook]

// --- REPLACEMENT NOTE: Removed %ctor from here to move to the end ---



// ============ STATUS BAR GESTURES (HOLD + SWIPE) ============
// Hook UIApplication - uses screen coordinates for reliable detection

static NSTimer *g_statusBarHoldTimer = nil;
static BOOL g_statusBarHoldTriggered = NO;
static NSString *g_pendingStatusBarTrigger = nil;

// Swipe tracking
static CGFloat g_statusBarSwipeStartX = 0;
static CGFloat g_statusBarSwipeStartY = 0;
static BOOL g_statusBarTouchActive = NO;

%hook UIApplication

- (void)sendEvent:(UIEvent *)event {
    // Only process touch events
    if (event.type == UIEventTypeTouches) {
        UITouch *touch = [[event allTouches] anyObject];
        
        if (touch && touch.phase == UITouchPhaseBegan) {
            CGPoint loc = [touch locationInView:nil];
            CGFloat screenWidth = [[UIScreen mainScreen] bounds].size.width;
            
            // Status bar region = top 50pts
            BOOL isStatusBarRegion = (loc.y < 50);
            
            if (isStatusBarRegion) {
                // Track swipe start position
                g_statusBarSwipeStartX = loc.x;
                g_statusBarSwipeStartY = loc.y;
                g_statusBarTouchActive = YES;
                
                // Hold zones: left (first 50pts), right (last 50pts), center (middle)
                NSString *triggerKey = nil;
                
                if (loc.x < 50) {
                    triggerKey = @"trigger_statusbar_left_hold";
                } else if (loc.x > screenWidth - 50) {
                    triggerKey = @"trigger_statusbar_right_hold";
                } else {
                    triggerKey = @"trigger_statusbar_center_hold";
                }
                
                g_statusBarHoldTriggered = NO;
                g_pendingStatusBarTrigger = triggerKey;
                
                // Cancel any existing timer
                if (g_statusBarHoldTimer) {
                    [g_statusBarHoldTimer invalidate];
                    g_statusBarHoldTimer = nil;
                }
                
                // Start 0.3s hold timer
                g_statusBarHoldTimer = [NSTimer scheduledTimerWithTimeInterval:0.3 repeats:NO block:^(NSTimer *timer) {
                    g_statusBarHoldTimer = nil;
                    
                    if (g_pendingStatusBarTrigger) {
                        load_trigger_config();
                        BOOL enabled = [g_triggerConfig[@"masterEnabled"] boolValue] && 
                                       [g_triggerConfig[@"triggers"][g_pendingStatusBarTrigger][@"enabled"] boolValue];
                        
                        if (enabled) {
                            g_statusBarHoldTriggered = YES;
                            trigger_haptic();
                            RCExecuteTrigger(g_pendingStatusBarTrigger);
                            SRLog(@"[SpringRemote] %@ FIRED!", g_pendingStatusBarTrigger);
                        }
                    }
                }];
            }
        }
        else if (touch && touch.phase == UITouchPhaseMoved) {
            CGPoint loc = [touch locationInView:nil];
            
            // Status bar: Cancel hold timer if significant movement detected (it's a swipe, not a hold)
            if (g_statusBarTouchActive && !g_statusBarHoldTriggered) {
                CGFloat deltaX = fabs(loc.x - g_statusBarSwipeStartX);
                
                // If moved more than 30pts, cancel the hold and give haptic feedback - this is a swipe
                if (deltaX > 30 && g_statusBarHoldTimer) {
                    trigger_haptic();  // Haptic NOW during swipe motion
                    [g_statusBarHoldTimer invalidate];
                    g_statusBarHoldTimer = nil;
                    g_pendingStatusBarTrigger = nil;
                }
            }
        }
        else if (touch && touch.phase == UITouchPhaseEnded) {
            CGPoint loc = [touch locationInView:nil];
            
            // Status bar swipe check
            if (g_statusBarTouchActive && !g_statusBarHoldTriggered) {
                CGFloat deltaX = loc.x - g_statusBarSwipeStartX;
                CGFloat deltaY = fabs(loc.y - g_statusBarSwipeStartY);
                
                // Swipe threshold: 80pts horizontal, less than 50pts vertical
                if (fabs(deltaX) > 80 && deltaY < 50) {
                    NSString *swipeTrigger = (deltaX > 0) ? @"trigger_statusbar_swipe_right" : @"trigger_statusbar_swipe_left";
                    
                    load_trigger_config();
                    BOOL enabled = [g_triggerConfig[@"masterEnabled"] boolValue] && 
                                   [g_triggerConfig[@"triggers"][swipeTrigger][@"enabled"] boolValue];
                    
                    if (enabled) {
                        // Haptic already fired mid-swipe, just execute actions
                        RCExecuteTrigger(swipeTrigger);
                        SRLog(@"[SpringRemote] %@ FIRED!", swipeTrigger);
                    }
                }
            }
            
            // Clean up status bar
            if (g_statusBarHoldTimer) {
                [g_statusBarHoldTimer invalidate];
                g_statusBarHoldTimer = nil;
            }
            g_statusBarHoldTriggered = NO;
            g_pendingStatusBarTrigger = nil;
            g_statusBarTouchActive = NO;
        }
        else if (touch && touch.phase == UITouchPhaseCancelled) {
            if (g_statusBarHoldTimer) {
                [g_statusBarHoldTimer invalidate];
                g_statusBarHoldTimer = nil;
            }
            g_statusBarHoldTriggered = NO;
            g_pendingStatusBarTrigger = nil;
            g_statusBarTouchActive = NO;
        }
    }
    
    %orig;
}

%end

@implementation SREdgeGestureRecognizer

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    // Early exit: Check if edge gestures should even be active
    if (!should_register_edge_gestures()) {
        self.state = UIGestureRecognizerStateFailed;
        return;
    }
    
    UITouch *touch = [touches anyObject];
    CGPoint loc = [touch locationInView:nil];
    CGSize screenSize = [UIScreen mainScreen].bounds.size;
    
    // Check if touch is near edge (within 25pt) - narrower as requested
    CGFloat edgeThreshold = 25.0;
    
    // Check vertical margins to avoid interference with Control Center (top) and Home Swipe (bottom)
    CGFloat verticalMargin = 100.0;
    
    BOOL isNearLeft = (loc.x < edgeThreshold);
    BOOL isNearRight = (loc.x > screenSize.width - edgeThreshold);
    BOOL isWithinVerticalBounds = (loc.y > verticalMargin) && (loc.y < screenSize.height - verticalMargin);
    
    if (!isWithinVerticalBounds) {
        self.state = UIGestureRecognizerStateFailed;
        return;
    }
    
    if (self.isLeftEdge && !isNearLeft) {
        self.state = UIGestureRecognizerStateFailed;
        return;
    }
    
    if (self.isRightEdge && !isNearRight) {
        self.state = UIGestureRecognizerStateFailed;
        return;
    }

    [super touchesBegan:touches withEvent:event];
    self.hasTriggered = NO;
    SRLog(@"[SpringRemote] Edge Gesture touchesBegan: X=%.2f Y=%.2f", loc.x, loc.y);
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesMoved:touches withEvent:event];
    // State tracking and haptics now handled in handleEdgeGesture:
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    SRLog(@"[SpringRemote] Edge Gesture touchesEnded - State before super: %ld", (long)self.state);
    [super touchesEnded:touches withEvent:event];
    SRLog(@"[SpringRemote] Edge Gesture touchesEnded - State after super: %ld", (long)self.state);
}

@end

// --- SYSTEM GESTURE MANAGER HOOK ---

@interface SRGestureHelper : NSObject
+ (instancetype)sharedInstance;
- (void)handleEdgeGesture:(SREdgeGestureRecognizer *)gesture;
@end

@implementation SRGestureHelper
+ (instancetype)sharedInstance {
    static SRGestureHelper *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[SRGestureHelper alloc] init];
    });
    return sharedInstance;
}

- (void)handleEdgeGesture:(SREdgeGestureRecognizer *)gesture {
    // Instant Fire: Trigger as soon as Changed state hits threshold
    if (gesture.state == UIGestureRecognizerStateChanged && !gesture.hasTriggered) {
        CGPoint translation = [gesture translationInView:nil];
        CGFloat verticalSwipeDistance = fabs(translation.y);
        CGFloat horizontalDrift = fabs(translation.x);
        
        // Threshold: 30pt for instant trigger
        if (verticalSwipeDistance > 30 && horizontalDrift < 100) {
            SRLog(@"[SpringRemote] Instant Edge Trigger! V=%.2f H=%.2f", verticalSwipeDistance, horizontalDrift);
            
            // Haptic feedback
            AudioServicesPlaySystemSound(1520);
            gesture.hasTriggered = YES;

            NSString *triggerKey = nil;
            if (gesture.isLeftEdge) {
                triggerKey = (translation.y < 0) ? @"trigger_edge_left_swipe_up" : @"trigger_edge_left_swipe_down";
            } else if (gesture.isRightEdge) {
                triggerKey = (translation.y < 0) ? @"trigger_edge_right_swipe_up" : @"trigger_edge_right_swipe_down";
            }
            
            if (triggerKey) {
                load_trigger_config();
                BOOL enabled = [g_triggerConfig[@"masterEnabled"] boolValue] && 
                               [g_triggerConfig[@"triggers"][triggerKey][@"enabled"] boolValue];
                
                if (enabled) {
                    RCExecuteTrigger(triggerKey);
                    SRLog(@"[SpringRemote] %@ FIRED INSTANTLY!", triggerKey);
                } else {
                    SRLog(@"[SpringRemote] %@ detected (disabled)", triggerKey);
                }
            }
        }
    }
    
    // Reset state on finish/fail
    if (gesture.state == UIGestureRecognizerStateEnded || 
        gesture.state == UIGestureRecognizerStateCancelled || 
        gesture.state == UIGestureRecognizerStateFailed) {
        SRLog(@"[SpringRemote] Edge Gesture Finished (State %ld): hasTriggered=%d", (long)gesture.state, gesture.hasTriggered);
        gesture.hasTriggered = NO;
    }
}
@end

static SREdgeGestureRecognizer *leftEdgeRecognizer;
static SREdgeGestureRecognizer *rightEdgeRecognizer;
static SBSystemGestureManager *g_gestureManager = nil;

// Helper: Check if any edge gestures are enabled
static BOOL should_register_edge_gestures() {
    if (!g_triggerConfig) return NO;
    if (![g_triggerConfig[@"masterEnabled"] boolValue]) return NO;
    
    NSDictionary *triggers = g_triggerConfig[@"triggers"];
    NSArray *edgeTriggers = @[@"trigger_edge_left_swipe_up", 
                               @"trigger_edge_left_swipe_down",
                               @"trigger_edge_right_swipe_up",
                               @"trigger_edge_right_swipe_down"];
    
    for (NSString *key in edgeTriggers) {
        NSDictionary *trigger = triggers[key];
        if (trigger && [trigger[@"enabled"] boolValue]) {
            return YES; // At least one edge gesture is enabled
        }
    }
    
    return NO;
}

// Register gesture recognizers
static void register_edge_gestures() {
    if (!g_gestureManager) {
        g_gestureManager = [%c(SBSystemGestureManager) mainDisplayManager];
        if (!g_gestureManager) {
            SRLog(@"[SpringRemote] ERROR: Could not find mainDisplayManager");
            return;
        }
    }
    
    // Left Edge
    if (!leftEdgeRecognizer) {
        leftEdgeRecognizer = [[SREdgeGestureRecognizer alloc] initWithTarget:[SRGestureHelper sharedInstance] action:@selector(handleEdgeGesture:)];
        leftEdgeRecognizer.isLeftEdge = YES;
        leftEdgeRecognizer.cancelsTouchesInView = NO; // Don't block other touches by default
        leftEdgeRecognizer.delaysTouchesBegan = NO;   // Don't add lag
        [g_gestureManager addGestureRecognizer:leftEdgeRecognizer withType:120];
        SRLog(@"[SpringRemote] Registered LEFT edge gesture recognizer");
    }
    
    // Right Edge
    if (!rightEdgeRecognizer) {
        rightEdgeRecognizer = [[SREdgeGestureRecognizer alloc] initWithTarget:[SRGestureHelper sharedInstance] action:@selector(handleEdgeGesture:)];
        rightEdgeRecognizer.isRightEdge = YES;
        rightEdgeRecognizer.cancelsTouchesInView = NO; // Don't block other touches by default
        rightEdgeRecognizer.delaysTouchesBegan = NO;   // Don't add lag
        [g_gestureManager addGestureRecognizer:rightEdgeRecognizer withType:121];
        SRLog(@"[SpringRemote] Registered RIGHT edge gesture recognizer");
    }
}

// Unregister gesture recognizers
static void unregister_edge_gestures() {
    if (leftEdgeRecognizer) {
        if (leftEdgeRecognizer.view) {
            [leftEdgeRecognizer.view removeGestureRecognizer:leftEdgeRecognizer];
        }
        leftEdgeRecognizer = nil;
        SRLog(@"[SpringRemote] Unregistered LEFT edge gesture recognizer");
    }
    
    if (rightEdgeRecognizer) {
        if (rightEdgeRecognizer.view) {
            [rightEdgeRecognizer.view removeGestureRecognizer:rightEdgeRecognizer];
        }
        rightEdgeRecognizer = nil;
        SRLog(@"[SpringRemote] Unregistered RIGHT edge gesture recognizer");
    }
}

// Update gesture registration based on config
static void update_edge_gestures() {
    @try {
        BOOL shouldRegister = should_register_edge_gestures();
        BOOL currentlyRegistered = (leftEdgeRecognizer != nil || rightEdgeRecognizer != nil);
        
        if (shouldRegister && !currentlyRegistered) {
            SRLog(@"[SpringRemote] Edge gestures enabled - registering...");
            register_edge_gestures();
        } else if (!shouldRegister && currentlyRegistered) {
            SRLog(@"[SpringRemote] Edge gestures disabled - unregistering...");
            unregister_edge_gestures();
        } else if (shouldRegister && currentlyRegistered) {
            // SRLog(@"[SpringRemote] Edge gestures already registered and should be");
        } else {
            // SRLog(@"[SpringRemote] Edge gestures not needed and not registered");
        }
    } @catch (NSException *e) {
        SRLog(@"[SpringRemote] ERROR in update_edge_gestures: %@", e);
    }
}


%hook SBSystemGestureManager

- (void)addGestureRecognizer:(UIGestureRecognizer *)recognizer withType:(NSUInteger)type {
    %orig;
}

%end

%ctor {
    %init(_ungrouped);
    
    SRLog(@"[SpringRemote] Tweak Loaded - Starting Initialization...");
    
    // Start Background HID Listener immediately (safe for NFC)
    setup_background_hid_listener();
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        SRLog(@"[SpringRemote] Delayed Initialization & Gesture Setup...");
        
        load_trigger_config();
        register_config_observer();
        register_simulation_observers();
        start_server();
        
        // Conditionally register edge gestures based on config
        update_edge_gestures();
        
        SRLog(@"[SpringRemote] Initialization Complete.");
    });
}


