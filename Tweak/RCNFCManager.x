#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreNFC/CoreNFC.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <AudioToolbox/AudioToolbox.h>

// Declare the external trigger function from Tweak.x
extern void RCExecuteTrigger(NSString *triggerKey);

// Declare the external logging function from Tweak.x
extern void SRLog(NSString *format, ...);

// Declare the external NFC enabled check
extern BOOL RCIsNFCEnabled();

// ============ Private NearField API ============
@class NFReaderSession, NFTag;

@protocol NFReaderSessionDelegate <NSObject>
@optional
- (void)readerSession:(id)session didDetectTags:(NSArray *)tags;
- (void)readerSession:(id)session didDetectTags:(NSArray *)tags connectedTagIndex:(id)index;
- (void)readerSessionDidEndUnexpectedly:(id)session;
@end

@interface NFHardwareManager : NSObject
+ (instancetype)sharedHardwareManager;
- (id)startReaderSessionWithDelegate:(id<NFReaderSessionDelegate>)delegate;
@end

@protocol NFTag <NSObject>
- (NSData *)tagID;
- (unsigned int)type;
@end

// ============ RCNFCManager Interface ============

@interface RCNFCManager : NSObject <NFCTagReaderSessionDelegate, NFReaderSessionDelegate>
@property (nonatomic, strong) NFCTagReaderSession *tagSession;
@property (nonatomic, strong) id privateSession; // NFReaderSession
@property (nonatomic, assign) BOOL isScanning;
@property (nonatomic, strong) NSDate *lastScanTime;
@property (nonatomic, assign) BOOL wakeHandled;

+ (instancetype)sharedInstance;
- (void)startScanning;
- (void)stopScanning;
- (void)handleScreenWake;
@end

@implementation RCNFCManager

+ (instancetype)sharedInstance {
    static RCNFCManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _isScanning = NO;
        _wakeHandled = NO;
        SRLog(@"RCNFCManager initialized");
    }
    return self;
}

- (void)startScanning {
    if (!RCIsNFCEnabled()) {
        SRLog(@"[NFC] Scanning is DISABLED in settings, skipping");
        return;
    }

    if (self.isScanning) {
        SRLog(@"[NFC] Already scanning, skipping");
        return;
    }

    // Debounce
    if (self.lastScanTime && [[NSDate date] timeIntervalSinceDate:self.lastScanTime] < 2.0) {
        SRLog(@"[NFC] Skipping scan (debounce)");
        return;
    }

    SRLog(@"[NFC] Starting NFC Session...");
    self.isScanning = YES;
    self.lastScanTime = [NSDate date];

    [self stopScanning];

    // Force load NearField
    void *nfHandle = dlopen("/System/Library/PrivateFrameworks/NearField.framework/NearField", RTLD_NOW);
    SRLog(@"[NFC] NearField framework loaded: %@", nfHandle ? @"YES" : @"NO");

    // Try Private API
    Class nfManager = NSClassFromString(@"NFHardwareManager");
    SRLog(@"[NFC] NFHardwareManager class: %@", nfManager ? @"FOUND" : @"NOT FOUND");
    
    BOOL privateStarted = NO;
    if (nfManager && [nfManager respondsToSelector:@selector(sharedHardwareManager)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        id manager = [nfManager performSelector:@selector(sharedHardwareManager)];
        SRLog(@"[NFC] sharedHardwareManager: %@", manager ? @"GOT" : @"NIL");
        
        if (manager) {
            SEL startWithDelSel = NSSelectorFromString(@"startReaderSessionWithDelegate:");
            SEL startSel = NSSelectorFromString(@"startReaderSession:");
            id session = nil;

            if ([manager respondsToSelector:startWithDelSel]) {
                session = [manager performSelector:startWithDelSel withObject:self];
                SRLog(@"[NFC] Private Session started via startReaderSessionWithDelegate: %@", session ? @"SUCCESS" : @"FAILED");
            } else if ([manager respondsToSelector:startSel]) {
                session = [manager performSelector:startSel withObject:nil];
                SRLog(@"[NFC] Private Session started via startReaderSession: %@", session ? @"SUCCESS" : @"FAILED");
            } else {
                SRLog(@"[NFC] No known start session selector found!");
            }

            if (session) {
                self.privateSession = session;
                
                // Try various delegate setters
                if ([session respondsToSelector:NSSelectorFromString(@"setDelegate:")]) {
                    [session performSelector:NSSelectorFromString(@"setDelegate:") withObject:self];
                    SRLog(@"[NFC] Set delegate via setDelegate:");
                } else if ([session respondsToSelector:NSSelectorFromString(@"setSessionDelegate:")]) {
                    [session performSelector:NSSelectorFromString(@"setSessionDelegate:") withObject:self];
                    SRLog(@"[NFC] Set delegate via setSessionDelegate:");
                }

                if ([session respondsToSelector:NSSelectorFromString(@"startPolling")]) {
                    [session performSelector:NSSelectorFromString(@"startPolling")];
                    SRLog(@"[NFC] Private NFC Polling Started! SUCCESS");
                    privateStarted = YES;
                } else {
                    SRLog(@"[NFC] Session doesn't respond to startPolling!");
                }
            }
        }
#pragma clang diagnostic pop
    }

    if (privateStarted) {
        SRLog(@"[NFC] Using Private API - scan active");
        return;
    }

    // Fallback to Public API
    SRLog(@"[NFC] Private API failed, trying Public CoreNFC...");
    if ([NFCTagReaderSession readingAvailable]) {
        self.tagSession = [[NFCTagReaderSession alloc] initWithPollingOption:(NFCPollingISO14443 | NFCPollingISO15693) delegate:self queue:dispatch_get_main_queue()];
        self.tagSession.alertMessage = @"Scan tag...";
        [self.tagSession beginSession];
        SRLog(@"[NFC] Started Public Tag Session");
    } else {
        SRLog(@"[NFC] NFC not supported (CoreNFC)");
        self.isScanning = NO;
        return;
    }

    // Auto-stop after 5 seconds to save battery
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (self.isScanning) {
            SRLog(@"[NFC] Scan timed out (5s limit) - Stopping to save battery.");
            [self stopScanning];
        }
    });
}

- (void)stopScanning {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    if (self.tagSession) { 
        [self.tagSession invalidateSession]; 
        self.tagSession = nil; 
        SRLog(@"[NFC] Stopped public tag session");
    }
    if (self.privateSession) {
        if ([self.privateSession respondsToSelector:NSSelectorFromString(@"endSession")]) {
            [self.privateSession performSelector:NSSelectorFromString(@"endSession")];
        }
        self.privateSession = nil;
        SRLog(@"[NFC] Stopped private session");
    }
#pragma clang diagnostic pop
    self.isScanning = NO;
}

- (void)handleScreenWake {
    if (!RCIsNFCEnabled()) {
        return;
    }

    // Prevent duplicate handling within short window
    if (self.wakeHandled) {
        // [NFC-WAKE] Wake already handled recently, skipping
    // SRLog(@"[NFC-WAKE] Wake already handled recently, skipping");
        return;
    }
    self.wakeHandled = YES;
    
    // Reset wake flag after 3 seconds
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self.wakeHandled = NO;
    });
    
    // SRLog(@"[NFC-WAKE] Screen wake detected - waiting 500ms before NFC...");
    
    // Delay before starting NFC to let hardware warm up after sleep
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(500 * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
        // SRLog(@"[NFC-WAKE] Delay complete, starting NFC scan");
        [self startScanning];
    });
}

// MARK: - Shared Processing

// Helper to get clean hex string from data
static NSString *sr_hexStringFromData(NSData *data) {
    const unsigned char *dataBuffer = (const unsigned char *)[data bytes];
    if (!dataBuffer) return @"";
    NSUInteger dataLength = [data length];
    NSMutableString *hexString = [NSMutableString stringWithCapacity:(dataLength * 2)];
    for (int i = 0; i < dataLength; ++i) {
        [hexString appendFormat:@"%02X", (unsigned int)dataBuffer[i]];
    }
    return [hexString copy];
}

- (void)processTag:(id<NFCTag>)tag session:(id)session {
    NSData *uidData = nil;
    if (tag.type == NFCTagTypeMiFare) {
        if ([tag conformsToProtocol:@protocol(NFCMiFareTag)]) {
            uidData = [(id<NFCMiFareTag>)tag identifier];
        }
    } else if (tag.type == NFCTagTypeISO15693) {
        if ([tag conformsToProtocol:@protocol(NFCISO15693Tag)]) {
            uidData = [(id<NFCISO15693Tag>)tag identifier];
        }
    } else if (tag.type == NFCTagTypeISO7816Compatible) {
        if ([tag conformsToProtocol:@protocol(NFCISO7816Tag)]) {
            uidData = [(id<NFCISO7816Tag>)tag identifier];
        }
    }
    
    if (uidData) {
        NSString *uidString = sr_hexStringFromData(uidData);
        NSString *triggerKey = [NSString stringWithFormat:@"nfc_%@", uidString];
        // SRLog(@"Tag UID: %@ -> Trigger Key: %@", uidString, triggerKey);
        
        dispatch_async(dispatch_get_main_queue(), ^{
            SRLog(@"Executing trigger: %@", triggerKey);
            // Haptic Feedback
            AudioServicesPlaySystemSound(1520);
            RCExecuteTrigger(triggerKey);
            
            if ([session isKindOfClass:[NFCTagReaderSession class]]) {
                ((NFCTagReaderSession *)session).alertMessage = [NSString stringWithFormat:@"Triggered: %@", uidString];
                [(NFCTagReaderSession *)session invalidateSession];
            } else if ([session isKindOfClass:[NFCNDEFReaderSession class]]) {
                ((NFCNDEFReaderSession *)session).alertMessage = [NSString stringWithFormat:@"Triggered: %@", uidString];
                [(NFCNDEFReaderSession *)session invalidateSession];
            }
        });
    } else {
        // SRLog(@"Could not read UID");
        if ([session isKindOfClass:[NFCTagReaderSession class]]) {
            [(NFCTagReaderSession *)session invalidateSessionWithErrorMessage:@"Unknown ID"];
        } else if ([session isKindOfClass:[NFCNDEFReaderSession class]]) {
            [(NFCNDEFReaderSession *)session invalidateSessionWithErrorMessage:@"Unknown ID"];
        }
    }
}

// MARK: - NFCTagReaderSessionDelegate

- (void)tagReaderSession:(NFCTagReaderSession *)session didDetectTags:(NSArray<__kindof id<NFCTag>> *)tags {
    // SRLog(@"Tag Detected (Tag Session): %lu tags found", (unsigned long)tags.count);
    if (tags.count > 0) {
        id<NFCTag> tag = tags.firstObject;
        // SRLog(@"Connecting to tag type: %ld", (long)tag.type);
        [session connectToTag:tag completionHandler:^(NSError * _Nullable error) {
            if (error) {
                // SRLog(@"Connection to tag failed: %@", error);
                [session invalidateSessionWithErrorMessage:@"Connection failed"];
                return;
            }
            // SRLog(@"Connected to tag successfully");
            [self processTag:tag session:session];
        }];
    }
}

- (void)tagReaderSession:(NFCTagReaderSession *)session didInvalidateWithError:(NSError *)error {
    // SRLog(@"Tag Session Invalidated: %@", error);
    if (session == self.tagSession) self.isScanning = NO;
}



// MARK: - NFReaderSessionDelegate (Private)

- (void)readerSession:(id)session didDetectTags:(NSArray *)tags connectedTagIndex:(id)index {
    // SRLog(@"Private API (3-arg): didDetectTags count=%lu", (unsigned long)tags.count);
    [self readerSession:session didDetectTags:tags];
}

- (void)didDetectTags:(NSArray *)tags connectedTagIndex:(id)index {
    // SRLog(@"Private API (short 2-arg): didDetectTags count=%lu", (unsigned long)tags.count);
    [self readerSession:nil didDetectTags:tags];
}

- (void)didDetectTags:(NSArray *)tags {
    // SRLog(@"Private API (short 1-arg): didDetectTags count=%lu", (unsigned long)tags.count);
    [self readerSession:nil didDetectTags:tags];
}

- (void)readerSession:(id)session didDetectTags:(NSArray *)tags {
    // SRLog(@"Private API (2-arg): didDetectTags count=%lu", (unsigned long)tags.count);
    for (id tag in tags) {
        // SRLog(@"Detected private tag: %@", tag);
        NSData *uidData = nil;
        
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        if ([tag respondsToSelector:@selector(tagID)]) {
            uidData = [tag performSelector:NSSelectorFromString(@"tagID")];
        } else if ([tag respondsToSelector:@selector(UID)]) {
            uidData = [tag performSelector:NSSelectorFromString(@"UID")];
        } else if ([tag respondsToSelector:@selector(identifier)]) {
            uidData = [tag performSelector:NSSelectorFromString(@"identifier")];
        }
#pragma clang diagnostic pop
        
        if (uidData) {
            NSString *uidString = sr_hexStringFromData(uidData);
            NSString *triggerKey = [NSString stringWithFormat:@"nfc_%@", uidString];
            // SRLog(@"Private Tag UID: %@ -> Trigger Key: %@", uidString, triggerKey);
            
            dispatch_async(dispatch_get_main_queue(), ^{
                // Haptic Feedback
                AudioServicesPlaySystemSound(1520);
                RCExecuteTrigger(triggerKey);
                [self stopScanning];
            });
        } else {
            // SRLog(@"Could not extract UID from private tag: %@", tag);
        }
    }
}

- (void)didEndUnexpectedly {
    // SRLog(@"Private API (short): didEndUnexpectedly");
    [self readerSessionDidEndUnexpectedly:nil];
}

- (void)readerSessionDidEndUnexpectedly:(id)session {
    // SRLog(@"Private NFC Session ended unexpectedly");
    if (session == self.privateSession) self.isScanning = NO;
}

@end


// ============ HOOKS ============

// OPTION 1: Multiple wake detection hooks for reliability

%hook CSCoverSheetViewController
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    // SRLog(@"[NFC-WAKE] CSCoverSheetViewController viewWillAppear");
    [[RCNFCManager sharedInstance] handleScreenWake];
}
%end

%hook SBBacklightController
- (void)turnOnScreenIsUserAction:(BOOL)isUserAction {
    %orig;
    // SRLog(@"[NFC-WAKE] SBBacklightController turnOnScreenIsUserAction: %d", isUserAction);
    if (isUserAction) {
        [[RCNFCManager sharedInstance] handleScreenWake];
    }
}
%end

// Additional hook: SBScreenWakeAnimationController - fires during wake animation
%hook SBScreenWakeAnimationController
- (void)_handleAnimationCompletionIfNeeded {
    %orig;
    // SRLog(@"[NFC-WAKE] SBScreenWakeAnimationController _handleAnimationCompletionIfNeeded");
    [[RCNFCManager sharedInstance] handleScreenWake];
}
%end

// Additional hook: SBLockScreenManager - early wake detection
%hook SBLockScreenManager
- (void)_handleBacklightLevelWillChange:(id)notification {
    %orig;
    // SRLog(@"[NFC-WAKE] SBLockScreenManager _handleBacklightLevelWillChange");
    [[RCNFCManager sharedInstance] handleScreenWake];
}
%end

#import <notify.h>

static void stop_nfc_callback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    // SRLog(@"[NFC] Received stop_nfc notification - yielding to app");
    [[RCNFCManager sharedInstance] stopScanning];
}

%ctor {
    %init;
    
    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        NULL,
        stop_nfc_callback,
        CFSTR("com.pizzaman.rc.stop_nfc"),
        NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately);
        
    SRLog(@"[NFC-WAKE] RCNFCManager hooks initialized - multi-hook wake detection active");
}


