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
                             @"power_triple_click", @"power_quadruple_click", 
                             @"trigger_statusbar_left_hold", @"trigger_statusbar_center_hold", @"trigger_statusbar_right_hold", 
                             @"trigger_statusbar_swipe_left", @"trigger_statusbar_swipe_right",
                             @"trigger_home_triple_click", @"trigger_home_quadruple_click", @"trigger_home_double_click",
                             @"trigger_edge_left_swipe_up", @"trigger_edge_left_swipe_down", 
                             @"trigger_edge_right_swipe_up", @"trigger_edge_right_swipe_down",
                             @"trigger_edge_left_swipe_up", @"trigger_edge_left_swipe_down", 
                             @"trigger_edge_right_swipe_up", @"trigger_edge_right_swipe_down",
                             @"volume_both_press", @"touchid_tap",
                             @"power_volume_up", @"power_volume_down",
                             @"trigger_ringer_mute", @"trigger_ringer_unmute", @"trigger_ringer_toggle"];
        
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
        
        // Auto-add tcpEnabled if missing
        if (_config[@"tcpEnabled"] == nil) {
            _config[@"tcpEnabled"] = @NO;
            [self saveConfig];
        }
        
        // Auto-add nfcEnabled if missing
        if (_config[@"nfcEnabled"] == nil) {
            _config[@"nfcEnabled"] = @YES;
            [self saveConfig];
        }
    } else {
        // Default config with all triggers
        NSLog(@"[RCConfigManager] Using default config");
        _config = [@{
            @"masterEnabled": @YES,
            @"tcpEnabled": @NO,
            @"nfcEnabled": @YES,
            @"triggers": [@{
                @"volume_up_hold": [@{ @"enabled": @NO, @"actions": @[] } mutableCopy],
                @"volume_down_hold": [@{ @"enabled": @NO, @"actions": @[] } mutableCopy],
                @"power_double_tap": [@{ @"enabled": @NO, @"actions": @[] } mutableCopy],
                @"power_long_press": [@{ @"enabled": @NO, @"actions": @[] } mutableCopy],
                @"power_triple_click": [@{ @"enabled": @NO, @"actions": @[] } mutableCopy],
                @"power_quadruple_click": [@{ @"enabled": @NO, @"actions": @[] } mutableCopy],
                @"trigger_statusbar_left_hold": [@{ @"enabled": @NO, @"actions": @[] } mutableCopy],
                @"trigger_statusbar_center_hold": [@{ @"enabled": @NO, @"actions": @[] } mutableCopy],
                @"trigger_statusbar_right_hold": [@{ @"enabled": @NO, @"actions": @[] } mutableCopy],
                @"trigger_statusbar_swipe_left": [@{ @"enabled": @NO, @"actions": @[] } mutableCopy],
                @"trigger_statusbar_swipe_right": [@{ @"enabled": @NO, @"actions": @[] } mutableCopy],
                @"trigger_home_triple_click": [@{ @"enabled": @NO, @"actions": @[] } mutableCopy],
                @"trigger_home_quadruple_click": [@{ @"enabled": @NO, @"actions": @[] } mutableCopy],
                @"trigger_home_double_click": [@{ @"enabled": @NO, @"actions": @[] } mutableCopy],
                @"touchid_hold": [@{ @"enabled": @NO, @"actions": @[] } mutableCopy],
                @"touchid_tap": [@{ @"enabled": @NO, @"actions": @[] } mutableCopy],
                @"trigger_edge_left_swipe_up": [@{ @"enabled": @NO, @"actions": @[] } mutableCopy],
                @"trigger_edge_left_swipe_down": [@{ @"enabled": @NO, @"actions": @[] } mutableCopy],
                @"trigger_edge_right_swipe_up": [@{ @"enabled": @NO, @"actions": @[] } mutableCopy],
                @"trigger_edge_right_swipe_down": [@{ @"enabled": @NO, @"actions": @[] } mutableCopy],
                @"volume_both_press": [@{ @"enabled": @NO, @"actions": @[] } mutableCopy],
                @"power_volume_up": [@{ @"enabled": @NO, @"actions": @[] } mutableCopy],
                @"power_volume_down": [@{ @"enabled": @NO, @"actions": @[] } mutableCopy],
                @"trigger_ringer_mute": [@{ @"enabled": @NO, @"actions": @[] } mutableCopy],
                @"trigger_ringer_unmute": [@{ @"enabled": @NO, @"actions": @[] } mutableCopy],
                @"trigger_ringer_toggle": [@{ @"enabled": @NO, @"actions": @[] } mutableCopy]
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

- (BOOL)tcpEnabled {
    // Default to YES for backward compatibility with existing configs
    if (!_config[@"tcpEnabled"]) {
        return YES;
    }
    return [_config[@"tcpEnabled"] boolValue];
}

- (void)setTcpEnabled:(BOOL)tcpEnabled {
    _config[@"tcpEnabled"] = @(tcpEnabled);
    [self saveConfig];
}

- (BOOL)nfcEnabled {
    // Default to YES if missing
    if (!_config[@"nfcEnabled"]) {
        return YES;
    }
    return [_config[@"nfcEnabled"] boolValue];
}

- (void)setNfcEnabled:(BOOL)nfcEnabled {
    _config[@"nfcEnabled"] = @(nfcEnabled);
    if (!nfcEnabled) {
        [self stopBackgroundNFC];
    }
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
    return @[@"volume_up_hold", @"volume_down_hold", @"volume_both_press", @"power_double_tap", @"power_long_press", @"power_triple_click", @"power_quadruple_click", @"trigger_statusbar_left_hold", @"trigger_statusbar_center_hold", @"trigger_statusbar_right_hold", @"trigger_statusbar_swipe_left", @"trigger_statusbar_swipe_right", @"trigger_home_triple_click", @"trigger_home_quadruple_click", @"trigger_edge_left_swipe_up", @"trigger_edge_left_swipe_down", @"trigger_edge_right_swipe_up", @"trigger_edge_right_swipe_down"];
}

- (NSString *)displayNameForTrigger:(NSString *)triggerKey {
    NSDictionary *names = @{
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
        @"trigger_home_triple_click": @"Home Button (Triple Click)",
        @"trigger_home_quadruple_click": @"Home Button (Quadruple Click)",
        @"trigger_home_double_click": @"Home Button (Double Click)",
        @"touchid_hold": @"Touch ID Hold (Rest Finger)",
        @"touchid_tap": @"Touch ID Single Tap",
        @"trigger_edge_left_swipe_up": @"Left Edge Swipe Up",
        @"trigger_edge_left_swipe_down": @"Left Edge Swipe Down",
        @"trigger_edge_right_swipe_up": @"Right Edge Swipe Up",
        @"trigger_edge_right_swipe_down": @"Right Edge Swipe Down",
        @"trigger_ringer_mute": @"Ringer Muted (Silent Mode On)",
        @"trigger_ringer_unmute": @"Ringer Unmuted (Silent Mode Off)",
        @"trigger_ringer_toggle": @"Ringer Toggled (Any Change)"
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

- (void)stopBackgroundNFC {
    NSLog(@"[RCConfigManager] Signaling to stop background NFC scanning");
    notify_post("com.pizzaman.rc.stop_nfc");
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
    
    if (importedConfig[@"nfcEnabled"]) {
        _config[@"nfcEnabled"] = importedConfig[@"nfcEnabled"];
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

#pragma mark - Command Helpers

- (NSString *)nameForCommand:(NSString *)cmd truncate:(BOOL)shouldTruncate {
    NSDictionary *names = @{
        @"play": @"Play",
        @"pause": @"Pause",
        @"playpause": @"Play/Pause",
        @"next": @"Next Track",
        @"prev": @"Previous Track",
        @"volume up": @"Volume Up",
        @"volume down": @"Volume Down",
        @"flashlight": @"Flashlight Toggle",
        @"flashlight on": @"Flashlight On",
        @"flashlight off": @"Flashlight Off",
        @"flashlight toggle": @"Flashlight Toggle",
        @"rotate lock": @"Rotate Lock",
        @"rotate unlock": @"Rotate Unlock",
        @"rotate toggle": @"Rotate Toggle",
        @"wifi on": @"WiFi On",
        @"wifi off": @"WiFi Off",
        @"wifi toggle": @"WiFi Toggle",
        @"bluetooth on": @"Bluetooth On",
        @"bluetooth off": @"Bluetooth Off",
        @"bluetooth toggle": @"Bluetooth Toggle",
        @"bt toggle": @"Bluetooth Toggle",
        @"haptic": @"Haptic Feedback",
        @"screenshot": @"Screenshot",
        @"lock": @"Lock Device",
        @"lock toggle": @"Lock Toggle",
        @"lock status": @"Lock Status",
        @"dnd on": @"DND On",
        @"dnd off": @"DND Off",
        @"dnd toggle": @"DND Toggle",
        @"respring": @"Respring",
        @"lpm on": @"LPM On",
        @"lpm off": @"LPM Off",
        @"lpm toggle": @"LPM Toggle",
        @"anc on": @"ANC On",
        @"anc off": @"ANC Off",
        @"anc transparency": @"Transparency Mode",
        @"airplay disconnect": @"Disconnect AirPlay",
        @"airplane on": @"Airplane On",
        @"airplane off": @"Airplane Off",
        @"airplane toggle": @"Airplane Toggle",
        @"low power on": @"LPM On",
        @"low power off": @"LPM Off",
        @"low power mode on": @"LPM On",
        @"low power mode off": @"LPM Off",
        @"low power toggle": @"LPM Toggle",
        @"low power mode toggle": @"LPM Toggle",
        @"mute toggle": @"Mute Toggle",
        @"siri": @"Activate Siri"
    };
    
    NSString *result = names[cmd];
    
    if (!result) {
        if ([cmd hasPrefix:@"exec "]) {
            result = [cmd substringFromIndex:5];
        } else if ([cmd hasPrefix:@"delay "]) {
            result = [NSString stringWithFormat:@"Delay %@s", [cmd substringFromIndex:6]];
        } else if ([cmd hasPrefix:@"bt connect "]) {
            result = [NSString stringWithFormat:@"Connect BT: %@", [cmd substringFromIndex:11]];
        } else if ([cmd hasPrefix:@"bluetooth connect "]) {
            result = [NSString stringWithFormat:@"Connect BT: %@", [cmd substringFromIndex:18]];
        } else if ([cmd hasPrefix:@"bt disconnect "]) {
            result = [NSString stringWithFormat:@"Disconnect BT: %@", [cmd substringFromIndex:14]];
        } else if ([cmd hasPrefix:@"bluetooth disconnect "]) {
            result = [NSString stringWithFormat:@"Disconnect BT: %@", [cmd substringFromIndex:21]];
        } else if ([cmd hasPrefix:@"airplay connect "]) {
            result = [NSString stringWithFormat:@"Connect AirPlay: %@", [cmd substringFromIndex:16]];
        } else if ([cmd hasPrefix:@"set-vol "]) {
            result = [NSString stringWithFormat:@"Set Vol: %@", [cmd substringFromIndex:8]];
        } else if ([cmd hasPrefix:@"brightness "]) {
            result = [NSString stringWithFormat:@"Set Brightness: %@", [cmd substringFromIndex:11]];
        } else if ([cmd hasPrefix:@"shortcut:"]) {
            result = [NSString stringWithFormat:@"Shortcut: %@", [cmd substringFromIndex:9]];
        } else if ([cmd hasPrefix:@"Lua "]) {
            result = [NSString stringWithFormat:@"Lua: %@", [cmd substringFromIndex:4]];
        } else if ([cmd hasPrefix:@"lua_eval "]) {
            result = [NSString stringWithFormat:@"Lua: %@", [cmd substringFromIndex:9]];
        } else if ([cmd hasPrefix:@"lua "]) {
            result = [[cmd substringFromIndex:4] lastPathComponent];
        } else if ([cmd hasPrefix:@"spotify "]) {
            result = @"Spotify";
        } else if ([cmd hasPrefix:@"uiopen "]) {
            NSString *bundleId = [cmd substringFromIndex:7];
            Class LSProxy = NSClassFromString(@"LSApplicationProxy");
            if (LSProxy) {
                id app = [LSProxy performSelector:@selector(applicationProxyForIdentifier:) withObject:bundleId];
                if (app) {
                    NSString *appName = [app performSelector:@selector(localizedName)];
                    if (appName) {
                        result = [NSString stringWithFormat:@"Open %@", appName];
                    } else {
                       result = [NSString stringWithFormat:@"Open %@", bundleId];
                    }
                } else {
                    result = [NSString stringWithFormat:@"Open %@", bundleId];
                }
            } else {
                result = [NSString stringWithFormat:@"Open %@", bundleId];
            }
        } else {
            result = cmd;
        }
    }
    
    // Final truncation to keep the detail labels from overflowing
    // Use middle truncation: "Start...End"
    if (shouldTruncate && result.length > 25) {
        NSInteger keep = 10; 
        NSString *prefix = [result substringToIndex:keep];
        NSString *suffix = [result substringFromIndex:result.length - keep];
        result = [NSString stringWithFormat:@"%@...%@", prefix, suffix];
    }
    
    return result;
}

- (NSString *)iconForCommand:(NSString *)cmd {
    if ([cmd hasPrefix:@"exec "]) return @"terminal.fill";
    if ([cmd hasPrefix:@"delay "]) return @"timer";
    if ([cmd hasPrefix:@"bt connect "] || [cmd hasPrefix:@"bluetooth connect "]) return @"link";
    if ([cmd hasPrefix:@"bt disconnect "] || [cmd hasPrefix:@"bluetooth disconnect "]) return @"xmark.circle";
    if ([cmd hasPrefix:@"airplay connect "]) return @"airplayaudio";
    if ([cmd hasPrefix:@"shortcut:"]) return @"command";
    if ([cmd hasPrefix:@"set-vol "]) return @"speaker.wave.3.fill";
    if ([cmd hasPrefix:@"brightness "]) return @"sun.max.fill";
    if ([cmd hasPrefix:@"Lua "] || [cmd hasPrefix:@"lua_eval "] || [cmd hasPrefix:@"lua "]) return @"scroll.fill";
    if ([cmd hasPrefix:@"spotify "]) return @"music.note";
    if ([cmd hasPrefix:@"uiopen "]) return [NSString stringWithFormat:@"USER_APP:%@", [cmd substringFromIndex:7]];
    
    NSDictionary *icons = @{
        @"play": @"play.fill",
        @"pause": @"pause.fill",
        @"playpause": @"playpause.fill",
        @"next": @"forward.fill",
        @"prev": @"backward.fill",
        @"volume up": @"speaker.wave.3.fill",
        @"volume down": @"speaker.wave.1.fill",
        @"flashlight": @"flashlight.on.fill",
        @"flashlight on": @"flashlight.on.fill",
        @"flashlight off": @"flashlight.off.fill",
        @"flashlight toggle": @"flashlight.on.fill",
        @"rotate lock": @"lock.rotation",
        @"rotate unlock": @"lock.rotation.open",
        @"rotate toggle": @"lock.rotation",
        @"wifi on": @"wifi",
        @"wifi off": @"wifi.slash",
        @"wifi toggle": @"wifi",
        @"bluetooth on": @"bolt.horizontal.fill",
        @"bluetooth off": @"bolt.horizontal",
        @"bluetooth toggle": @"bolt.horizontal.fill",
        @"bt toggle": @"bolt.horizontal.fill",
        @"airplane on": @"airplane",
        @"airplane off": @"airplane",
        @"airplane toggle": @"airplane",
        @"haptic": @"hand.tap.fill",
        @"screenshot": @"camera.fill",
        @"lock": @"lock.fill",
        @"lock toggle": @"lock.circle",
        @"lock status": @"lock.circle",
        @"dnd on": @"moon.fill",
        @"dnd off": @"moon",
        @"dnd toggle": @"moon.circle.fill",
        @"respring": @"memories",
        @"lpm on": @"battery.25",
        @"lpm off": @"battery.100",
        @"lpm toggle": @"battery.25",
        @"low power on": @"battery.25",
        @"low power off": @"battery.100",
        @"low power toggle": @"battery.25",
        @"low power mode on": @"battery.25",
        @"low power mode off": @"battery.100",
        @"low power mode toggle": @"battery.25",
        @"anc on": @"ear.badge.checkmark",
        @"anc off": @"ear",
        @"anc transparency": @"waveform.circle.fill",
        @"airplay disconnect": @"airplayaudio.badge.exclamationmark",
        @"mute toggle": @"speaker.slash.fill",
        @"siri": @"mic.circle.fill"
    };
    
    return icons[cmd] ?: @"circle.fill";
}

@end
