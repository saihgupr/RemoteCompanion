#import "RCNFCTriggerViewController.h"
#import <CoreNFC/CoreNFC.h>
#import "RCConfigManager.h"
#import "RCActionsViewController.h"

@interface RCNFCTriggerViewController () <NFCTagReaderSessionDelegate, NFCNDEFReaderSessionDelegate>
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) NFCTagReaderSession *tagSession;
@property (nonatomic, strong) NFCNDEFReaderSession *ndefSession;
@end

@implementation RCNFCTriggerViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Scan NFC Tag";
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    
    self.statusLabel = [[UILabel alloc] initWithFrame:self.view.bounds];
    self.statusLabel.text = @"Ready to Scan";
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.font = [UIFont systemFontOfSize:24 weight:UIFontWeightMedium];
    [self.view addSubview:self.statusLabel];
    
    UIBarButtonItem *scanButton = [[UIBarButtonItem alloc] initWithTitle:@"Start Scan" style:UIBarButtonItemStyleDone target:self action:@selector(startScanning)];
    self.navigationItem.rightBarButtonItem = scanButton;
    
    [self startScanning];
}

- (void)startScanning {
    if (self.tagSession) {
        [self.tagSession invalidateSession];
        self.tagSession = nil;
    }
    if (self.ndefSession) {
        [self.ndefSession invalidateSession];
        self.ndefSession = nil;
    }
    
    if ([NFCTagReaderSession readingAvailable]) {
        // Preferred: Raw Tag Reading
        self.tagSession = [[NFCTagReaderSession alloc] initWithPollingOption:(NFCPollingISO14443 | NFCPollingISO15693) delegate:self queue:dispatch_get_main_queue()];
        self.tagSession.alertMessage = @"Hold nearest NFC tag to back of iPhone.";
        [self.tagSession beginSession];
        self.statusLabel.text = @"Ready to Scan (Tag Mode)...";
    } else if ([NFCNDEFReaderSession readingAvailable]) {
        // Fallback: NDEF Reading (iPhone 7/iOS 15 limitation?)
        self.ndefSession = [[NFCNDEFReaderSession alloc] initWithDelegate:self queue:dispatch_get_main_queue() invalidateAfterFirstRead:NO];
        self.ndefSession.alertMessage = @"Hold nearest NFC tag to back of iPhone.";
        [self.ndefSession beginSession];
        self.statusLabel.text = @"Ready to Scan (NDEF Mode)...";
    } else {
        self.statusLabel.text = @"NFC Not Supported";
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"NFC Error"
            message:@"This device does not support NFC reading."
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}

#pragma mark - Shared Processing

- (NSString *)hexStringFromData:(NSData *)data {
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
        NSString *uidString = [self hexStringFromData:uidData];
        NSString *triggerKey = [NSString stringWithFormat:@"nfc_%@", uidString];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([session isKindOfClass:[NFCTagReaderSession class]]) {
                [(NFCTagReaderSession *)session invalidateSession];
            } else if ([session isKindOfClass:[NFCNDEFReaderSession class]]) {
                [(NFCNDEFReaderSession *)session invalidateSession];
            }
            [self handleTagDetected:triggerKey];
        });
    } else {
        NSString *errorMsg = @"Could not read Tag UID";
        if ([session isKindOfClass:[NFCTagReaderSession class]]) {
            [(NFCTagReaderSession *)session invalidateSessionWithErrorMessage:errorMsg];
        } else if ([session isKindOfClass:[NFCNDEFReaderSession class]]) {
            [(NFCNDEFReaderSession *)session invalidateSessionWithErrorMessage:errorMsg];
        }
    }
}

#pragma mark - NFCTagReaderSessionDelegate

- (void)tagReaderSession:(NFCTagReaderSession *)session didDetectTags:(NSArray<__kindof id<NFCTag>> *)tags {
    if (tags.count > 0) {
        id<NFCTag> tag = tags.firstObject;
        [session connectToTag:tag completionHandler:^(NSError * _Nullable error) {
            if (error) {
                [session invalidateSessionWithErrorMessage:@"Connection failed"];
                return;
            }
            [self processTag:tag session:session];
        }];
    }
}

- (void)tagReaderSession:(NFCTagReaderSession *)session didInvalidateWithError:(NSError *)error {
    if (error.code != NFCReaderSessionInvalidationErrorUserCanceled) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.statusLabel.text = [NSString stringWithFormat:@"Error: %@", error.localizedDescription];
        });
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.statusLabel.text = @"Scan Cancelled";
        });
    }
}

#pragma mark - NFCNDEFReaderSessionDelegate

- (void)readerSession:(NFCNDEFReaderSession *)session didDetectTags:(NSArray<__kindof id<NFCNDEFTag>> *)tags {
    if (tags.count > 0) {
        id<NFCNDEFTag> tag = tags.firstObject;
        [session connectToTag:tag completionHandler:^(NSError * _Nullable error) {
            if (error) {
                [session invalidateSessionWithErrorMessage:@"Connection failed"];
                return;
            }
            // Attempt to treat NFCNDEFTag as NFCTag to extract UID
            if ([tag conformsToProtocol:@protocol(NFCTag)]) {
                [self processTag:(id<NFCTag>)tag session:session];
            } else {
                [session invalidateSessionWithErrorMessage:@"Tag does not support UID reading"];
            }
        }];
    }
}

- (void)readerSession:(NFCNDEFReaderSession *)session didInvalidateWithError:(NSError *)error {
    if (error.code != NFCReaderSessionInvalidationErrorUserCanceled) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.statusLabel.text = [NSString stringWithFormat:@"Error (NDEF): %@", error.localizedDescription];
        });
    }
    // No explicit cancel message needed for NDEF usually, but consistency is good
}

- (void)readerSession:(NFCNDEFReaderSession *)session didDetectNDEFs:(NSArray<NFCNDEFMessage *> *)messages {
    // Legacy method, not used if didDetectTags is implemented
}

- (void)handleTagDetected:(NSString *)triggerKey {
    self.statusLabel.text = [NSString stringWithFormat:@"Found: %@", triggerKey];
    
    RCConfigManager *config = [RCConfigManager sharedManager];
    
    // Add to config if new
    NSDictionary *triggerData = @{
        @"name": [NSString stringWithFormat:@"NFC Tag %@", [triggerKey substringFromIndex:4]],
        @"enabled": @YES,
        @"actions": @[]
    };
    
    if (![[config allTriggerKeys] containsObject:triggerKey]) {
        [config updateTrigger:triggerKey withData:triggerData];
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        RCActionsViewController *vc = [[RCActionsViewController alloc] initWithTriggerKey:triggerKey];
        NSMutableArray *vcs = [self.navigationController.viewControllers mutableCopy];
        [vcs removeLastObject];
        [vcs addObject:vc];
        [self.navigationController setViewControllers:vcs animated:YES];
    });
}

@end

