#import "RCConfigManager.h"
#import <notify.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>

// Use absolute path that both TrollStore app and tweak can access
#define kConfigPath @"/var/mobile/Documents/rc_triggers.plist"
#define kConfigChangedNotification "com.pizzaman.rc.configchanged"

NSString *const RCConfigChangedNotification = @"RCConfigChangedNotification";

@interface RCConfigManager ()
@property (nonatomic, strong) NSMutableDictionary *config;
@end

@implementation RCConfigManager

+ (instancetype)sharedManager {
    static RCConfigManager *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[RCConfigManager alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [self loadConfig];
    }
    return self;
}

- (void)loadConfig {
    NSDictionary *saved = nil;
    
    // 1. Try shared path first (persists across reinstalls)
    saved = [NSDictionary dictionaryWithContentsOfFile:kConfigPath];
    if (saved) {
        NSLog(@"[RCConfigManager] Loaded from shared path: %@", kConfigPath);
    } else {
        // 2. Try app Documents (container)
        NSString *appDocsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        NSString *appConfigPath = [appDocsPath stringByAppendingPathComponent:@"rc_triggers.plist"];
        saved = [NSDictionary dictionaryWithContentsOfFile:appConfigPath];
        if (saved) {
            NSLog(@"[RCConfigManager] Loaded from app Documents: %@", appConfigPath);
        }
    }
    
    if (saved) {
        _config = [saved mutableCopy];
        
        // Ensure triggers dict exists and is mutable
        if (!_config[@"triggers"]) {
            _config[@"triggers"] = [NSMutableDictionary dictionary];
        } else if (![_config[@"triggers"] isKindOfClass:[NSMutableDictionary class]]) {
            _config[@"triggers"] = [_config[@"triggers"] mutableCopy];
        }
        
        // Auto-add any missing triggers (for upgrades)
        NSMutableDictionary *triggers = _config[@"triggers"];
        NSArray *allKeys = @[@"volume_up_hold", @"volume_down_hold", @"power_double_tap", @"power_long_press", 
                             @"trigger_statusbar_left_hold", @"trigger_statusbar_center_hold", @"trigger_statusbar_right_hold", 
                             @"trigger_statusbar_swipe_left", @"trigger_statusbar_swipe_right", @"trigger_home_double_tap",
                             @"trigger_edge_left_swipe_up", @"trigger_edge_left_swipe_down", 
                             @"trigger_edge_right_swipe_up", @"trigger_edge_right_swipe_down"];
        
        BOOL needsSave = NO;
        for (NSString *key in allKeys) {
            if (!triggers[key]) {
                triggers[key] = [@{ @"enabled": @NO, @"actions": @[] } mutableCopy];
                NSLog(@"[RCConfigManager] Added missing trigger: %@", key);
                needsSave = YES;
            }
        }
        
        if (needsSave) {
            [self saveConfig];
        }
    } else {
        // Default config with all triggers
        NSLog(@"[RCConfigManager] Using default config");
        _config = [@{
            @"masterEnabled": @YES,
            @"triggers": [@{
                @"volume_up_hold": [@{ @"enabled": @NO, @"actions": @[] } mutableCopy],
                @"volume_down_hold": [@{ @"enabled": @NO, @"actions": @[] } mutableCopy],
                @"power_double_tap": [@{ @"enabled": @NO, @"actions": @[] } mutableCopy],
                @"power_long_press": [@{ @"enabled": @NO, @"actions": @[] } mutableCopy],
                @"trigger_statusbar_left_hold": [@{ @"enabled": @NO, @"actions": @[] } mutableCopy],
                @"trigger_statusbar_center_hold": [@{ @"enabled": @NO, @"actions": @[] } mutableCopy],
                @"trigger_statusbar_right_hold": [@{ @"enabled": @NO, @"actions": @[] } mutableCopy],
                @"trigger_statusbar_swipe_left": [@{ @"enabled": @NO, @"actions": @[] } mutableCopy],
                @"trigger_statusbar_swipe_right": [@{ @"enabled": @NO, @"actions": @[] } mutableCopy],
                @"trigger_home_double_tap": [@{ @"enabled": @NO, @"actions": @[] } mutableCopy],
                @"trigger_edge_left_swipe_up": [@{ @"enabled": @NO, @"actions": @[] } mutableCopy],
                @"trigger_edge_left_swipe_down": [@{ @"enabled": @NO, @"actions": @[] } mutableCopy],
                @"trigger_edge_right_swipe_up": [@{ @"enabled": @NO, @"actions": @[] } mutableCopy],
                @"trigger_edge_right_swipe_down": [@{ @"enabled": @NO, @"actions": @[] } mutableCopy]
            } mutableCopy]
        } mutableCopy];
    }
}

- (BOOL)masterEnabled {
    return [_config[@"masterEnabled"] boolValue];
}

- (void)setMasterEnabled:(BOOL)masterEnabled {
    _config[@"masterEnabled"] = @(masterEnabled);
    [self saveConfig];
}

- (void)updateTrigger:(NSString *)triggerKey withData:(NSDictionary *)data {
    NSMutableDictionary *triggers = _config[@"triggers"];
    triggers[triggerKey] = [data mutableCopy];
    [self saveConfig];
}

- (void)removeTrigger:(NSString *)triggerKey {
    NSMutableDictionary *triggers = _config[@"triggers"];
    if (triggers[triggerKey]) {
        [triggers removeObjectForKey:triggerKey];
    }
}

- (void)renameTrigger:(NSString *)triggerKey toName:(NSString *)newName {
    NSMutableDictionary *triggers = _config[@"triggers"];
    if (triggers[triggerKey]) {
        NSMutableDictionary *triggerData = [triggers[triggerKey] mutableCopy];
        triggerData[@"name"] = newName;
        triggers[triggerKey] = triggerData;
        
        NSLog(@"[RCConfigManager] Renamed trigger %@ to '%@'", triggerKey, newName);
        [self saveConfig];
    }
}

- (NSArray<NSString *> *)nfcTriggerKeys {
    NSMutableArray *keys = [NSMutableArray array];
    for (NSString *key in _config[@"triggers"]) {
        if ([key hasPrefix:@"nfc_"]) {
            [keys addObject:key];
        }
    }
    return keys;
}

- (NSArray<NSString *> *)allTriggerKeys {
    return @[@"volume_up_hold", @"volume_down_hold", @"power_double_tap", @"power_long_press", @"trigger_statusbar_left_hold", @"trigger_statusbar_center_hold", @"trigger_statusbar_right_hold", @"trigger_statusbar_swipe_left", @"trigger_statusbar_swipe_right", @"trigger_home_double_tap", @"trigger_edge_left_swipe_up", @"trigger_edge_left_swipe_down", @"trigger_edge_right_swipe_up", @"trigger_edge_right_swipe_down"];
}

- (NSString *)displayNameForTrigger:(NSString *)triggerKey {
    NSDictionary *names = @{
        @"volume_up_hold": @"Volume Up Hold",
        @"volume_down_hold": @"Volume Down Hold",
        @"power_double_tap": @"Power Double-Tap",
        @"power_long_press": @"Power Long Press",
        @"trigger_statusbar_left_hold": @"Status Bar Left Hold",
        @"trigger_statusbar_center_hold": @"Status Bar Center Hold",
        @"trigger_statusbar_right_hold": @"Status Bar Right Hold",
        @"trigger_statusbar_swipe_left": @"Status Bar Swipe Left",
        @"trigger_statusbar_swipe_right": @"Status Bar Swipe Right",
        @"trigger_home_double_tap": @"Home Button (Double Tap)",
        @"trigger_edge_left_swipe_up": @"Left Edge Swipe Up",
        @"trigger_edge_left_swipe_down": @"Left Edge Swipe Down",
        @"trigger_edge_right_swipe_up": @"Right Edge Swipe Up",
        @"trigger_edge_right_swipe_down": @"Right Edge Swipe Down"
    };
    
    if ([triggerKey hasPrefix:@"nfc_"]) {
        // Return custom name or default
        NSString *customName = _config[@"triggers"][triggerKey][@"name"];
        return customName ?: [NSString stringWithFormat:@"NFC Tag %@", [triggerKey substringFromIndex:4]];
    }
    
    return names[triggerKey] ?: triggerKey;
}

- (NSMutableDictionary *)triggerDict:(NSString *)triggerKey {
    NSMutableDictionary *triggers = _config[@"triggers"];
    if (!triggers) {
        triggers = [NSMutableDictionary dictionary];
        _config[@"triggers"] = triggers;
    }
    NSMutableDictionary *trigger = triggers[triggerKey];
    if (!trigger) {
        trigger = [@{ @"enabled": @NO, @"actions": @[] } mutableCopy];
        triggers[triggerKey] = trigger;
    }
    return trigger;
}

- (BOOL)isTriggerEnabled:(NSString *)triggerKey {
    return [[self triggerDict:triggerKey][@"enabled"] boolValue];
}

- (void)setTriggerEnabled:(BOOL)enabled forTrigger:(NSString *)triggerKey {
    [self triggerDict:triggerKey][@"enabled"] = @(enabled);
    [self saveConfig];
}

- (NSArray<NSString *> *)actionsForTrigger:(NSString *)triggerKey {
    return [self triggerDict:triggerKey][@"actions"] ?: @[];
}

- (void)setActions:(NSArray<NSString *> *)actions forTrigger:(NSString *)triggerKey {
    NSMutableDictionary *trigger = [self triggerDict:triggerKey];
    trigger[@"actions"] = [actions mutableCopy];
    
    // Auto-enable trigger if it has actions, auto-disable if empty
    trigger[@"enabled"] = @(actions.count > 0);
    
    [self saveConfig];
}

- (void)saveConfig {
    // Serialize config to plist data
    NSError *error = nil;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:_config 
                                                              format:NSPropertyListXMLFormat_v1_0 
                                                             options:0 
                                                               error:&error];
    if (error) {
        NSLog(@"[RCConfigManager] ERROR serializing config: %@", error);
        return;
    }
    
    // 1. Save to app's own Documents folder (container - this always works)
    NSString *appDocsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *appConfigPath = [appDocsPath stringByAppendingPathComponent:@"rc_triggers.plist"];
    [data writeToFile:appConfigPath atomically:YES];
    NSLog(@"[RCConfigManager] Saved to app Documents: %@", appConfigPath);
    
    // 2. Also save to shared path using POSIX (bypasses sandbox)
    const char *sharedPath = [kConfigPath UTF8String];
    int fd = open(sharedPath, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd >= 0) {
        write(fd, [data bytes], [data length]);
        close(fd);
        NSLog(@"[RCConfigManager] Saved to shared path: %@", kConfigPath);
    } else {
        NSLog(@"[RCConfigManager] Could not open shared path (errno=%d): %@", errno, kConfigPath);
    }
    
    // Notify tweak of config change
    notify_post(kConfigChangedNotification);
    
    // Notify App UI
    [[NSNotificationCenter defaultCenter] postNotificationName:RCConfigChangedNotification object:nil];
    
    NSLog(@"[RCConfigManager] Notifications posted");
}

#pragma mark - Backup/Restore

- (NSData *)exportConfigAsJSON {
    NSError *error = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:_config
                                                       options:NSJSONWritingPrettyPrinted
                                                         error:&error];
    if (error) {
        NSLog(@"[RCConfigManager] Export error: %@", error);
        return nil;
    }
    return jsonData;
}

- (BOOL)importConfigFromJSON:(NSData *)jsonData error:(NSError **)error {
    id parsed = [NSJSONSerialization JSONObjectWithData:jsonData options:NSJSONReadingMutableContainers error:error];
    if (!parsed || ![parsed isKindOfClass:[NSDictionary class]]) {
        return NO;
    }
    
    NSMutableDictionary *importedConfig = (NSMutableDictionary *)parsed;
    
    // Robust Merge Logic
    // 1. Master Switch (if present)
    if (importedConfig[@"masterEnabled"]) {
        _config[@"masterEnabled"] = importedConfig[@"masterEnabled"];
    }
    // If missing in import, keep current local setting.
    
    // 2. Triggers (Merge)
    NSDictionary *importedTriggers = importedConfig[@"triggers"];
    if (importedTriggers && [importedTriggers isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *currentTriggers = _config[@"triggers"];
        if (!currentTriggers) {
            currentTriggers = [NSMutableDictionary dictionary];
            _config[@"triggers"] = currentTriggers;
        }
        
        [importedTriggers enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
            // Overwrite or add
            currentTriggers[key] = [obj mutableCopy];
        }];
    }
    
    [self saveConfig];
    NSLog(@"[RCConfigManager] Config merged successfully. Master: %@, Triggers Updated: %lu", 
          _config[@"masterEnabled"], (unsigned long)importedTriggers.count);
    return YES;
}

@end
