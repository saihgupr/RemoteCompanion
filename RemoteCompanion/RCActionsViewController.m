#import "RCActionsViewController.h"
#import "RCConfigManager.h"
#import "RCActionPickerViewController.h"
#import "RCShortcutPickerViewController.h"
#import "RCTextInputViewController.h"

@interface RCActionsViewController ()
@property (nonatomic, strong) NSString *triggerKey;
@property (nonatomic, strong) NSMutableArray<NSString *> *actions;
@end

@implementation RCActionsViewController

- (NSString *)displayNameForCommand:(NSString *)cmd {
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
        @"rotate lock": @"Rotate Lock",
        @"rotate unlock": @"Rotate Unlock",
        @"wifi on": @"WiFi On",
        @"wifi off": @"WiFi Off",
        @"bluetooth on": @"Bluetooth On",
        @"bluetooth off": @"Bluetooth Off",
        @"haptic": @"Haptic Feedback",
        @"screenshot": @"Screenshot",
        @"lock": @"Lock Device",
        @"dnd on": @"DND On",
        @"dnd off": @"DND Off",
        @"lpm on": @"LPM On",
        @"lpm off": @"LPM Off",
        @"anc on": @"ANC On",
        @"anc off": @"ANC Off",
        @"anc transparency": @"Transparency Mode",
        @"airplay disconnect": @"Disconnect AirPlay",
        @"flashlight toggle": @"Flashlight Toggle",
        @"rotate status": @"Rotate Lock Status",
        @"lock toggle": @"Lock Toggle",
        @"lock status": @"Lock Status",
        @"low power on": @"Low Power Mode On",
        @"low power off": @"Low Power Mode Off",
        @"low power mode on": @"Low Power Mode On",
        @"low power mode off": @"Low Power Mode Off",
        @"airplane on": @"Airplane Mode On",
        @"airplane off": @"Airplane Mode Off",
        @"airplane toggle": @"Airplane Mode Toggle",
        @"rotate toggle": @"Rotate Toggle",
        @"rotation toggle": @"Rotate Toggle",
        @"orientation toggle": @"Rotate Toggle",
        @"dnd toggle": @"DND Toggle",
        @"lpm toggle": @"LPM Toggle",
        @"low power toggle": @"Low Power Mode Toggle",
        @"low power mode toggle": @"Low Power Mode Toggle",
        @"mute toggle": @"Mute Toggle"
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
        } else {
            result = cmd;
        }
    }
    
    // Truncate if too long
    if (result.length > 25) {
        result = [[result substringToIndex:22] stringByAppendingString:@"..."];
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
    if ([cmd hasPrefix:@"Lua "]) return @"scroll.fill";
    if ([cmd hasPrefix:@"lua_eval "]) return @"scroll.fill";
    if ([cmd hasPrefix:@"lua "]) return @"scroll.fill";
    if ([cmd hasPrefix:@"spotify "]) return @"music.note";
    
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
        @"rotate lock": @"lock.rotation",
        @"rotate unlock": @"lock.rotation.open",
        @"wifi on": @"wifi",
        @"wifi off": @"wifi.slash",
        @"bluetooth on": @"bolt.horizontal.fill",
        @"bluetooth off": @"bolt.horizontal",
        @"airplane on": @"airplane",
        @"airplane off": @"airplane",
        @"airplane toggle": @"airplane",
        @"haptic": @"hand.tap.fill",
        @"screenshot": @"camera.fill",
        @"lock": @"lock.fill",
        @"dnd on": @"moon.fill",
        @"dnd off": @"moon",
        @"lpm on": @"battery.25",
        @"lpm off": @"battery.100",
        @"low power on": @"battery.25",
        @"low power off": @"battery.100",
        @"low power mode on": @"battery.25",
        @"low power mode off": @"battery.100",
        @"lock status": @"lock.circle",
        @"lock toggle": @"lock.circle",
        @"anc on": @"ear.badge.checkmark",
        @"anc off": @"ear",
        @"anc transparency": @"waveform.circle.fill",
        @"airplay disconnect": @"airplayaudio.badge.exclamationmark",
        @"flashlight toggle": @"flashlight.on.fill",
        @"rotate toggle": @"lock.rotation",
        @"rotation toggle": @"lock.rotation",
        @"orientation toggle": @"lock.rotation",
        @"dnd toggle": @"moon.circle.fill",
        @"lpm toggle": @"battery.25",
        @"low power toggle": @"battery.25",
        @"low power mode toggle": @"battery.25",
        @"mute toggle": @"speaker.slash.fill"
    };
    return icons[cmd] ?: @"circle.fill";
}

- (instancetype)initWithTriggerKey:(NSString *)triggerKey {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _triggerKey = triggerKey;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // Elegant grey tint
    self.navigationController.navigationBar.tintColor = [UIColor systemGrayColor];
    
    self.title = [[RCConfigManager sharedManager] displayNameForTrigger:_triggerKey];
    
    // Add action button
    UIBarButtonItem *addButton = [[UIBarButtonItem alloc] 
        initWithBarButtonSystemItem:UIBarButtonSystemItemAdd 
        target:self 
        action:@selector(addAction)];
    self.navigationItem.rightBarButtonItem = addButton;

    // Add tap gesture to title if it's an NFC trigger
    if ([_triggerKey hasPrefix:@"nfc_"]) {
        UITapGestureRecognizer *titleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(renameTrigger)];
        
        // Create a custom title view to accept interactions
        UILabel *titleLabel = [[UILabel alloc] init];
        titleLabel.text = self.title;
        titleLabel.font = [UIFont boldSystemFontOfSize:17];
        titleLabel.userInteractionEnabled = YES;
        [titleLabel addGestureRecognizer:titleTap];
        
        self.navigationItem.titleView = titleLabel;
    }
    
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    
    // Load actions
    _actions = [[[RCConfigManager sharedManager] actionsForTrigger:_triggerKey] mutableCopy];
    
    // Enable editing for reorder
    self.tableView.editing = YES;
    self.tableView.allowsSelectionDuringEditing = YES;
    
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"ActionCell"];
    self.tableView.rowHeight = 50;
}

- (void)renameTrigger {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Rename Tag" 
                                                                   message:@"Enter a new name for this NFC tag:" 
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = @"My Tag";
        textField.text = self.title;
        textField.autocapitalizationType = UITextAutocapitalizationTypeWords;
    }];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        NSString *newName = alert.textFields.firstObject.text;
        if (newName.length > 0) {
            [[RCConfigManager sharedManager] renameTrigger:self.triggerKey toName:newName];
            self.title = newName;
            
            // Update custom title view text
            if ([self.navigationItem.titleView isKindOfClass:[UILabel class]]) {
                ((UILabel *)self.navigationItem.titleView).text = newName;
                [self.navigationItem.titleView sizeToFit];
            }
        }
    }]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)addAction {
    RCActionPickerViewController *picker = [[RCActionPickerViewController alloc] init];
    picker.onActionSelected = ^(NSString *action) {
        if ([action isEqualToString:@"__SHORTCUT_PICKER__"]) {
            // Present Shortcut Picker
            RCShortcutPickerViewController *vc = [[RCShortcutPickerViewController alloc] init];
            vc.onShortcutSelected = ^(NSString *shortcutName) {
                [self.actions addObject:[NSString stringWithFormat:@"shortcut:%@", shortcutName]];
                [self saveActions];
                [self.tableView reloadData];
                // Dismiss picker
                 [self dismissViewControllerAnimated:YES completion:nil];
            };
            UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
            
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self presentViewController:nav animated:YES completion:nil];
            });
            
        } else if ([action isEqualToString:@"__CUSTOM__"]) {
            // Show custom text input for command
            RCTextInputViewController *inputVC = [[RCTextInputViewController alloc] init];
            inputVC.promptTitle = @"Custom Command";
            inputVC.promptMessage = @"Enter terminal command (e.g. curl ...)";
            inputVC.onComplete = ^(NSString *text) {
                if (text.length > 0) {
                    [self.actions addObject:[NSString stringWithFormat:@"exec %@", text]];
                    [self saveActions];
                    [self.tableView reloadData];
                }
            };
            
            UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:inputVC];
            
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self presentViewController:nav animated:YES completion:nil];
            });
            
        } else if ([action isEqualToString:@"__BT_CONNECT__"] || [action isEqualToString:@"__BT_DISCONNECT__"] || [action isEqualToString:@"__AIRPLAY_CONNECT__"]) {
            
            NSString *title = @"Device Name";
            NSString *prefix = @"";
            
            if ([action isEqualToString:@"__BT_CONNECT__"]) {
                title = @"Connect to Bluetooth";
                prefix = @"bt connect ";
            } else if ([action isEqualToString:@"__BT_DISCONNECT__"]) {
                title = @"Disconnect Bluetooth";
                prefix = @"bluetooth disconnect ";
            } else if ([action isEqualToString:@"__AIRPLAY_CONNECT__"]) {
                title = @"Connect AirPlay";
                prefix = @"airplay connect ";
            }

            UIAlertController *alert = [UIAlertController alertControllerWithTitle:title 
                message:@"Enter exact device name" 
                preferredStyle:UIAlertControllerStyleAlert];
                
            [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
                textField.placeholder = @"My Device";
            }];
            
            [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
            [alert addAction:[UIAlertAction actionWithTitle:@"Add" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull alertAction) {
                NSString *input = alert.textFields.firstObject.text;
                if (input.length > 0) {
                    [self.actions addObject:[NSString stringWithFormat:@"%@%@", prefix, input]];
                    [self saveActions];
                    [self.tableView reloadData];
                }
            }]];
            
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self presentViewController:alert animated:YES completion:nil];
            });

        } else if ([action isEqualToString:@"__DELAY__"]) {
            // Show alert for delay
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Add Delay" 
                message:@"Enter delay in seconds" 
                preferredStyle:UIAlertControllerStyleAlert];
                
            [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
                textField.placeholder = @"1.0";
                textField.keyboardType = UIKeyboardTypeDecimalPad;
            }];
            
            [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
            [alert addAction:[UIAlertAction actionWithTitle:@"Add" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull alertAction) {
                NSString *input = alert.textFields.firstObject.text;
                if (input.length > 0) {
                    [self.actions addObject:[NSString stringWithFormat:@"delay %@", input]];
                    [self saveActions];
                    [self.tableView reloadData];
                }
            }]];
            
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self presentViewController:alert animated:YES completion:nil];
            });
        } else if ([action isEqualToString:@"__LUA_SCRIPT__"]) {
            RCTextInputViewController *inputVC = [[RCTextInputViewController alloc] init];
            inputVC.promptTitle = @"Lua Script";
            inputVC.promptMessage = @"Enter Lua code to execute";
            inputVC.initialText = @"";
            inputVC.onComplete = ^(NSString *text) {
                if (text.length > 0) {
                    [self.actions addObject:[NSString stringWithFormat:@"Lua %@", text]];
                    [self saveActions];
                    [self.tableView reloadData];
                }
            };
            
            UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:inputVC];
            
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self presentViewController:nav animated:YES completion:nil];
            });
        } else {
            [self.actions addObject:action];
            [self saveActions];
            [self.tableView reloadData];
        }
    };
    
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:picker];
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)saveActions {
    [[RCConfigManager sharedManager] setActions:_actions forTrigger:_triggerKey];
}

#pragma mark - Table View Data Source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSString *currentAction = self.actions[indexPath.row];
    
    if ([currentAction hasPrefix:@"exec "]) {
        // Edit Custom Command
        NSString *currentCommand = [currentAction substringFromIndex:5];
        
        RCTextInputViewController *inputVC = [[RCTextInputViewController alloc] init];
        inputVC.promptTitle = @"Edit Command";
        inputVC.promptMessage = @"Update your terminal command";
        inputVC.initialText = currentCommand;
        inputVC.onComplete = ^(NSString *text) {
            if (text.length > 0) {
                self.actions[indexPath.row] = [NSString stringWithFormat:@"exec %@", text];
                [self saveActions];
                [self.tableView reloadData];
            }
        };
        
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:inputVC];
        [self presentViewController:nav animated:YES completion:nil];
    } else if ([currentAction hasPrefix:@"Lua "] || [currentAction hasPrefix:@"lua_eval "] || [currentAction hasPrefix:@"lua "]) {
        // Edit Lua Script (Direct or File)
        BOOL isDirect = [currentAction hasPrefix:@"Lua "] || [currentAction hasPrefix:@"lua_eval "];
        int prefixLength = 0;
        if ([currentAction hasPrefix:@"Lua "]) prefixLength = 4;
        else if ([currentAction hasPrefix:@"lua_eval "]) prefixLength = 9;
        else prefixLength = 4;

        NSString *currentCode = [currentAction substringFromIndex:prefixLength];
        
        RCTextInputViewController *inputVC = [[RCTextInputViewController alloc] init];
        inputVC.promptTitle = @"Edit Lua Script";
        inputVC.promptMessage = isDirect ? @"Update your Lua code" : @"Update script path (convert to direct code if desired)";
        inputVC.initialText = currentCode;
        inputVC.onComplete = ^(NSString *text) {
            if (text.length > 0) {
                // We always save as Lua (direct) when editing
                self.actions[indexPath.row] = [NSString stringWithFormat:@"Lua %@", text];
                [self saveActions];
                [self.tableView reloadData];
            }
        };
        
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:inputVC];
        [self presentViewController:nav animated:YES completion:nil];
    } else if ([currentAction hasPrefix:@"delay "]) {
        // Edit Delay
        NSString *currentDelay = [currentAction substringFromIndex:6];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Edit Delay" 
            message:@"Update delay in seconds" 
            preferredStyle:UIAlertControllerStyleAlert];
            
        [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
            textField.text = currentDelay;
            textField.placeholder = @"1.0";
            textField.keyboardType = UIKeyboardTypeDecimalPad;
        }];
        
        [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Update" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            NSString *input = alert.textFields.firstObject.text;
            if (input.length > 0) {
                self.actions[indexPath.row] = [NSString stringWithFormat:@"delay %@", input];
                [self saveActions];
                [self.tableView reloadData];
            }
        }]];
        
        [self presentViewController:alert animated:YES completion:nil];
    }
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return _actions.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return _actions.count > 0 ? @"Action Sequence" : nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (_actions.count == 0) {
        return @"Tap + to add actions. They will run in sequence when the trigger fires.";
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ActionCell" forIndexPath:indexPath];
    
    NSString *action = _actions[indexPath.row];
    cell.textLabel.text = [self displayNameForCommand:action];
    cell.textLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightMedium];
    cell.textLabel.textColor = [UIColor labelColor];
    
    cell.imageView.image = [UIImage systemImageNamed:[self iconForCommand:action]];
    cell.imageView.tintColor = [UIColor secondaryLabelColor];
    
    cell.showsReorderControl = YES;
    
    return cell;
}

// Reordering
- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)sourceIndexPath toIndexPath:(NSIndexPath *)destinationIndexPath {
    NSString *action = _actions[sourceIndexPath.row];
    [_actions removeObjectAtIndex:sourceIndexPath.row];
    [_actions insertObject:action atIndex:destinationIndexPath.row];
    [self saveActions];
}

// Deletion
- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    return UITableViewCellEditingStyleDelete;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        [_actions removeObjectAtIndex:indexPath.row];
        [self saveActions];
        [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
    }
}

@end
