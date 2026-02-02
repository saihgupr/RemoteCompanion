#import <Foundation/Foundation.h>

@interface RCConfigManager : NSObject

@property (nonatomic, assign) BOOL masterEnabled;
@property (nonatomic, assign) BOOL tcpEnabled;
@property (nonatomic, assign) BOOL nfcEnabled;

+ (instancetype)sharedManager;

- (NSArray<NSString *> *)allTriggerKeys;
- (NSString *)displayNameForTrigger:(NSString *)triggerKey;
- (BOOL)isTriggerEnabled:(NSString *)triggerKey;
- (void)setTriggerEnabled:(BOOL)enabled forTrigger:(NSString *)triggerKey;
- (NSArray<NSString *> *)actionsForTrigger:(NSString *)triggerKey;
- (void)setActions:(NSArray<NSString *> *)actions forTrigger:(NSString *)triggerKey;
- (void)updateTrigger:(NSString *)triggerKey withData:(NSDictionary *)data;
- (void)removeTrigger:(NSString *)triggerKey;
- (void)renameTrigger:(NSString *)triggerKey toName:(NSString *)newName;
- (NSArray<NSString *> *)nfcTriggerKeys;
- (void)saveConfig;
- (void)stopBackgroundNFC;

// Command Helpers
- (NSString *)nameForCommand:(NSString *)cmd truncate:(BOOL)shouldTruncate;
- (NSString *)iconForCommand:(NSString *)cmd;

// Backup/Restore
- (NSData *)exportConfigAsJSON;
- (BOOL)importConfigFromJSON:(NSData *)jsonData error:(NSError **)error;

extern NSString *const RCConfigChangedNotification;

@end
