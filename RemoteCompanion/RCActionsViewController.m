#import "RCActionsViewController.h"
#import "RCConfigManager.h"
#import "RCActionPickerViewController.h"
#import "RCShortcutPickerViewController.h"
#import "RCAppPickerViewController.h"
#import "RCTextInputViewController.h"
#import "RCServerClient.h"
#import "RCScheduledTriggerViewController.h"
#import "RCNotificationTriggerViewController.h"
#import "RCWiFiTriggerViewController.h"
#import "RCBluetoothTriggerViewController.h"
#import "RCNFCTriggerViewController.h"

@interface UIImage (Private)
+ (UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)bundleIdentifier format:(int)format scale:(CGFloat)scale;
@end

@interface RCActionsViewController () <UITableViewDragDelegate, UITableViewDropDelegate>
@property (nonatomic, strong) NSString *triggerKey;
@property (nonatomic, strong) NSMutableArray *actions;
@end

@implementation RCActionsViewController

static id g_actionClipboard = nil;

- (NSString *)displayNameForCommand:(id)cmd {
    return [[RCConfigManager sharedManager] nameForCommand:cmd truncate:YES];
}

- (NSAttributedString *)attributedDisplayNameForCommand:(NSString *)cmd {
    if (![cmd isKindOfClass:[NSString class]]) return nil;
    NSString *lower = [cmd lowercaseString];
    NSString *baseText = nil;
    NSString *paramText = nil;
    
    UIColor *accentColor = [UIColor systemBlueColor];
    
    if ([lower hasPrefix:@"set-vol "]) {
        baseText = @"Set Volume ";
        paramText = [NSString stringWithFormat:@"%@%%", [cmd substringFromIndex:8]];
    } else if ([lower hasPrefix:@"brightness "]) {
        baseText = @"Set Brightness ";
        paramText = [NSString stringWithFormat:@"%@%%", [cmd substringFromIndex:11]];
    } else if ([lower hasPrefix:@"flashlight "] || [lower hasPrefix:@"flash "]) {
        NSString *val = [cmd substringFromIndex:[lower hasPrefix:@"flashlight "] ? 11 : 6];
        // Only if it's a number (flashlight intensity)
        NSScanner *scanner = [NSScanner scannerWithString:val];
        BOOL isNumeric = [scanner scanFloat:NULL] && [scanner isAtEnd];
        if (isNumeric) {
            baseText = @"Flashlight ";
            paramText = [NSString stringWithFormat:@"%@%%", val];
        }
    } else if ([lower hasPrefix:@"delay "]) {
        baseText = @"Wait ";
        paramText = [NSString stringWithFormat:@"%@s", [cmd substringFromIndex:6]];
    } else if ([lower hasPrefix:@"shortcut:"]) {
        baseText = @"Shortcut: ";
        paramText = [cmd substringFromIndex:9];
    } else if ([lower hasPrefix:@"uiopen "]) {
        baseText = @"Open ";
        NSString *bundleId = [cmd substringFromIndex:7];
        NSString *appName = bundleId;
        Class proxyClass = NSClassFromString(@"LSApplicationProxy");
        if (proxyClass) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            id proxy = [proxyClass performSelector:@selector(applicationProxyForIdentifier:) withObject:bundleId];
            if (proxy) {
                NSString *name = [proxy performSelector:@selector(localizedName)];
                if (name.length > 0) {
                    appName = name;
                }
            }
#pragma clang diagnostic pop
        }
        paramText = appName;
    } else if ([lower hasPrefix:@"airplay connect "]) {
        baseText = @"AirPlay Connect ";
        paramText = [cmd substringFromIndex:16];
    } else if ([lower hasPrefix:@"bt connect "] || [lower hasPrefix:@"bluetooth connect "]) {
        baseText = @"Connect ";
        paramText = [cmd substringFromIndex:[lower hasPrefix:@"bt connect "] ? 11 : 18];
    } else if ([lower hasPrefix:@"bt disconnect "] || [lower hasPrefix:@"bluetooth disconnect "]) {
        baseText = @"Disconnect ";
        paramText = [cmd substringFromIndex:[lower hasPrefix:@"bt disconnect "] ? 14 : 21];
    }
    
    if (baseText && paramText) {
        NSString *fullText = [NSString stringWithFormat:@"%@%@", baseText, paramText];
        NSMutableAttributedString *attrStr = [[NSMutableAttributedString alloc] initWithString:fullText];
        NSRange baseRange = NSMakeRange(0, baseText.length);
        NSRange paramRange = NSMakeRange(baseText.length, paramText.length);
        
        [attrStr addAttribute:NSFontAttributeName value:[UIFont systemFontOfSize:17 weight:UIFontWeightMedium] range:NSMakeRange(0, fullText.length)];
        [attrStr addAttribute:NSForegroundColorAttributeName value:[UIColor labelColor] range:baseRange];
        [attrStr addAttribute:NSForegroundColorAttributeName value:accentColor range:paramRange];
        return attrStr;
    }
    
    return nil;
}

- (NSString *)iconForCommand:(id)cmd {
    return [[RCConfigManager sharedManager] iconForCommand:cmd];
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
    self.navigationController.navigationBar.tintColor = [UIColor labelColor];
    
    self.title = [[RCConfigManager sharedManager] displayNameForTrigger:_triggerKey];
    
    // Plus Button to add action directly
    UIBarButtonItem *plusButton = [[UIBarButtonItem alloc] 
        initWithImage:[UIImage systemImageNamed:@"plus"] 
        style:UIBarButtonItemStylePlain 
        target:self 
        action:@selector(addAction)];
    
    // More options menu (Import, Export)
    NSMutableArray *menuActions = [NSMutableArray array];
    [menuActions addObject:[UIAction actionWithTitle:@"Import Actions" 
                                               image:[UIImage systemImageNamed:@"square.and.arrow.down"] 
                                          identifier:nil 
                                             handler:^(__kindof UIAction * _Nonnull action) {
        [self importActions];
    }]];
    [menuActions addObject:[UIAction actionWithTitle:@"Export Actions" 
                                               image:[UIImage systemImageNamed:@"square.and.arrow.up"] 
                                          identifier:nil 
                                             handler:^(__kindof UIAction * _Nonnull action) {
        [self exportActions];
    }]];
    
    UIMenu *shareMenu = [UIMenu menuWithTitle:@"" children:menuActions];
    UIBarButtonItem *moreButton = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"ellipsis.circle"] menu:shareMenu];
    
    NSMutableArray *rightItems = [NSMutableArray arrayWithArray:@[moreButton, plusButton]];
    
    // Only show Settings Button if the trigger is configurable
    BOOL isConfigurable = [_triggerKey hasPrefix:@"sched_"] ||
                          [_triggerKey hasPrefix:@"notif_"] ||
                          [_triggerKey hasPrefix:@"wifi_"] ||
                          [_triggerKey hasPrefix:@"bt_"] ||
                          [_triggerKey hasPrefix:@"app_launch_"];
    
    if (isConfigurable) {
        UIBarButtonItem *settingsButton = [[UIBarButtonItem alloc] 
            initWithImage:[UIImage systemImageNamed:@"slider.horizontal.3"] 
            style:UIBarButtonItemStylePlain 
            target:self 
            action:@selector(editTriggerSettings)];
        [rightItems addObject:settingsButton];
    }
    
    self.navigationItem.rightBarButtonItems = rightItems;

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

    UILongPressGestureRecognizer *lpgr = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    lpgr.minimumPressDuration = 0.5;
    [self.tableView addGestureRecognizer:lpgr];
    
    // Enable Large Titles
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    
    // Listen for color tweak changes
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(handleTweaksChanged:) 
                                                  name:@"RCConfigTweaksChangedNotification" 
                                               object:nil];
    // Listen for config changes
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(handleConfigChanged:) 
                                                  name:RCConfigChangedNotification 
                                               object:nil];
    [self applyTweaks];
    
    // Load actions
    _actions = [[[RCConfigManager sharedManager] actionsForTrigger:_triggerKey] mutableCopy];
    
    // Non-editing mode to allow swipe actions
    self.tableView.editing = NO;
    self.tableView.allowsSelectionDuringEditing = YES;
    self.tableView.dragInteractionEnabled = YES;
    self.tableView.dragDelegate = self;
    self.tableView.dropDelegate = self;
    
    // Deletion is handled via swipe actions (trailingSwipeActionsConfigurationForRowAtIndexPath)
    
    // rightBarButtonItems set above

    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"ActionCell"];
    self.tableView.rowHeight = 70; // Fixed height as in V2.1.2
}

- (void)handleTweaksChanged:(NSNotification *)note {
    [self applyTweaks];
}

- (void)handleConfigChanged:(NSNotification *)note {
    dispatch_async(dispatch_get_main_queue(), ^{
        _actions = [[[RCConfigManager sharedManager] actionsForTrigger:_triggerKey] mutableCopy];
        [self.tableView reloadData];
    });
}

- (void)applyTweaks {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    self.view.backgroundColor = [cm tweakColorForKey:@"mainBackground" defaultVal:0.09];
    self.navigationController.navigationBar.backgroundColor = [cm tweakColorForKey:@"navBar" defaultVal:0.09];
    self.tableView.separatorColor = [cm tweakColorForKey:@"separators" defaultVal:0.30];
    [self.tableView reloadData];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if (@available(iOS 13.0, *)) {
        if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
            [self applyTweaks];
        }
    }
}

- (void)editTriggerSettings {
    UIViewController *vc = nil;
    
    if ([_triggerKey hasPrefix:@"sched_"]) {
        vc = [[RCScheduledTriggerViewController alloc] initWithTriggerKey:_triggerKey];
    } else if ([_triggerKey hasPrefix:@"notif_"]) {
        vc = [[RCNotificationTriggerViewController alloc] initWithTriggerKey:_triggerKey];
    } else if ([_triggerKey hasPrefix:@"wifi_"]) {
        vc = [[RCWiFiTriggerViewController alloc] initWithTriggerKey:_triggerKey];
    } else if ([_triggerKey hasPrefix:@"bt_"]) {
        vc = [[RCBluetoothTriggerViewController alloc] initWithTriggerKey:_triggerKey];
    } else if ([_triggerKey hasPrefix:@"app_launch_"]) {
        RCAppPickerViewController *appVC = [[RCAppPickerViewController alloc] init];
        appVC.onAppSelected = ^(NSString *appName, NSString *bundleId) {
            NSString *newKey = [NSString stringWithFormat:@"app_launch_%@", bundleId];
            NSString *friendlyName = [NSString stringWithFormat:@"Launch %@", appName];
            
            RCConfigManager *config = [RCConfigManager sharedManager];
            if (![self.triggerKey isEqualToString:newKey]) {
                // Migrate
                NSDictionary *oldData = [config triggerDataForKey:self.triggerKey];
                NSArray *actions = oldData[@"actions"] ?: @[];
                
                NSDictionary *newData = @{
                    @"name": friendlyName,
                    @"enabled": @YES,
                    @"actions": actions
                };
                [config updateTrigger:newKey withData:newData];
                [config removeTrigger:self.triggerKey];
                
                // Update our own key for the current view if needed, 
                // but we are popping/reloading so it's better to just go back.
            } else {
                NSMutableDictionary *mutableData = [[config triggerDataForKey:newKey] mutableCopy];
                mutableData[@"name"] = friendlyName;
                [config updateTrigger:newKey withData:mutableData];
            }
            [self.navigationController popViewControllerAnimated:YES];
        };
        vc = appVC;
    } else if ([_triggerKey hasPrefix:@"nfc_"]) {
        [self renameTrigger];
        return;
    }
    
    if (vc) {
        [self.navigationController pushViewController:vc animated:YES];
    }
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

- (void)showHUDToast:(NSString *)title subtitle:(NSString *)subtitle icon:(NSString *)iconName {
    NSString *safeTitle = [title stringByReplacingOccurrencesOfString:@"\"" withString:@"'"];
    NSString *safeSubtitle = [subtitle stringByReplacingOccurrencesOfString:@"\"" withString:@"'"];
    NSString *safeIcon = [iconName stringByReplacingOccurrencesOfString:@"\"" withString:@"'"];

    NSString *cmd = [NSString stringWithFormat:@"toast \"%@\" \"%@\" \"%@\"", 
                     safeTitle ?: @"", 
                     safeSubtitle ?: @"", 
                     safeIcon ?: @""];
                     
    [[RCServerClient sharedClient] executeCommand:cmd completion:^(NSString * _Nullable output, NSError * _Nullable error) {
        if (error) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                           message:subtitle
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [self presentViewController:alert animated:YES completion:nil];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [alert dismissViewControllerAnimated:YES completion:nil];
            });
        }
    }];
}

- (void)exportActions {
    if (_actions.count == 0) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"No Actions"
                                                                       message:@"There are no actions in this sequence to export."
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    
    NSError *error = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:_actions options:NSJSONWritingPrettyPrinted error:&error];
    if (error || !jsonData) {
        NSLog(@"Failed to serialize actions for export: %@", error);
        return;
    }
    
    NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    [UIPasteboard generalPasteboard].string = jsonString;
    
    [self showHUDToast:@"Copied to Clipboard" subtitle:nil icon:@"doc.on.doc"];
}

- (void)importActions {
    __weak typeof(self) weakSelf = self;
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Import Actions"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"Paste action code here…";
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
        textField.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
    }];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Import" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        NSString *text = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (!strongSelf || text.length == 0) return;
        
        NSArray *newCommands = nil;
        if ([text hasPrefix:@"["] && [text hasSuffix:@"]"]) {
            NSError *jsonErr = nil;
            id parsed = [NSJSONSerialization JSONObjectWithData:[text dataUsingEncoding:NSUTF8StringEncoding] options:0 error:&jsonErr];
            if (!jsonErr && [parsed isKindOfClass:[NSArray class]]) newCommands = parsed;
        }
        if (!newCommands) {
            NSMutableArray *lines = [NSMutableArray array];
            for (NSString *rawLine in [text componentsSeparatedByString:@"\n"]) {
                NSString *line = [rawLine stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                if (line.length > 0) [lines addObject:line];
            }
            if (lines.count > 0) newCommands = lines;
        }
        NSMutableArray *validCmds = [NSMutableArray array];
        for (id cmd in newCommands) {
            if ([cmd isKindOfClass:[NSString class]]) {
                NSString *clean = [cmd stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                if (clean.length > 0) [validCmds addObject:clean];
            } else if ([cmd isKindOfClass:[NSDictionary class]]) {
                [validCmds addObject:cmd];
            }
        }
        if (validCmds.count > 0) {
            [strongSelf.actions addObjectsFromArray:validCmds];
            [strongSelf saveActions];
            [strongSelf.tableView reloadData];
            [strongSelf showHUDToast:@"Import Successful"
                           subtitle:[NSString stringWithFormat:@"Loaded %lu action(s).", (unsigned long)validCmds.count]
                               icon:@"square.and.arrow.down"];
        } else {
            [strongSelf showHUDToast:@"Import Failed" subtitle:@"No valid actions found." icon:@"exclamationmark.triangle"];
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
            inputVC.promptTitle = @"Terminal Command";
            inputVC.promptMessage = @"Enter terminal command";
            inputVC.showRootToggle = YES;
            inputVC.initialText = @"";
            
            __weak typeof(inputVC) weakInputVC = inputVC;
            inputVC.onComplete = ^(NSString *text) {
                if (text.length > 0) {
                    NSString *prefix = weakInputVC.isRootToggled ? @"root" : @"exec";
                    [self.actions addObject:[NSString stringWithFormat:@"%@ %@", prefix, text]];
                    [self saveActions];
                    [self.tableView reloadData];
                }
            };
            
            UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:inputVC];
            
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self presentViewController:nav animated:YES completion:nil];
            });

        } else if ([action isEqualToString:@"__CUSTOM_ROOT__"]) {
            // Re-use terminal command but fixed as root
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Root Command" 
                message:@"Enter terminal command (runs as root)" 
                preferredStyle:UIAlertControllerStyleAlert];
                
            [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
                textField.placeholder = @"ldrestart";
                textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
                textField.autocorrectionType = UITextAutocorrectionTypeNo;
            }];
            
            [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
            [alert addAction:[UIAlertAction actionWithTitle:@"Add" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull alertAction) {
                NSString *input = alert.textFields.firstObject.text;
                if (input.length > 0) {
                    [self.actions addObject:[NSString stringWithFormat:@"root %@", input]];
                    [self saveActions];
                    [self.tableView reloadData];
                }
            }]];
            
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self presentViewController:alert animated:YES completion:nil];
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
        } else if ([action isEqualToString:@"__OPEN_APP__"]) {
            RCAppPickerViewController *appPicker = [[RCAppPickerViewController alloc] init];
            appPicker.onAppSelected = ^(NSString *name, NSString *bundleId) {
                // Save as "uiopen <bundleId>"
                [self.actions addObject:[NSString stringWithFormat:@"uiopen %@", bundleId]];
                [self saveActions];
                [self.tableView reloadData];
            };
            
            UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:appPicker];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self presentViewController:nav animated:YES completion:nil];
            });
        } else if ([action isEqualToString:@"__IF_CONDITION__"]) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self presentIfConditionPickerForIndex:NSNotFound];
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

- (NSString *)actionTypeForItem:(id)item {
    if (![item isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    return [[((NSDictionary *)item)[@"type"] description] lowercaseString];
}

- (BOOL)isIfActionItem:(id)item {
    return [[self actionTypeForItem:item] isEqualToString:@"if"];
}

- (BOOL)isElseActionItem:(id)item {
    return [[self actionTypeForItem:item] isEqualToString:@"else"];
}

- (BOOL)isElseIfActionItem:(id)item {
    return [[self actionTypeForItem:item] isEqualToString:@"else_if"];
}

- (BOOL)isEndIfActionItem:(id)item {
    NSString *type = [self actionTypeForItem:item];
    return [type isEqualToString:@"end_if"] || [type isEqualToString:@"end"];
}

- (NSInteger)matchingElseIndexForIfAtIndex:(NSInteger)startIndex {
    if (startIndex < 0 || startIndex >= (NSInteger)self.actions.count) {
        return NSNotFound;
    }
    if (![self isIfActionItem:self.actions[startIndex]]) {
        return NSNotFound;
    }
    
    NSInteger depth = 0;
    for (NSInteger idx = startIndex; idx < (NSInteger)self.actions.count; idx++) {
        id item = self.actions[idx];
        if ([self isIfActionItem:item]) {
            depth++;
        } else if ([self isEndIfActionItem:item]) {
            depth--;
            if (depth == 0) return NSNotFound;
        } else if ([self isElseActionItem:item]) {
            if (depth == 1) return idx;
        }
    }
    return NSNotFound;
}

- (NSInteger)matchingEndIndexForIfAtIndex:(NSInteger)startIndex {
    if (startIndex < 0 || startIndex >= (NSInteger)self.actions.count) {
        return NSNotFound;
    }
    if (![self isIfActionItem:self.actions[startIndex]]) {
        return NSNotFound;
    }
    
    NSInteger depth = 0;
    for (NSInteger idx = startIndex; idx < (NSInteger)self.actions.count; idx++) {
        id item = self.actions[idx];
        if ([self isIfActionItem:item]) {
            depth++;
        } else if ([self isEndIfActionItem:item]) {
            depth--;
            if (depth == 0) {
                return idx;
            }
        }
    }
    return NSNotFound;
}

- (NSInteger)matchingIfIndexForEndAtIndex:(NSInteger)endIndex {
    if (endIndex < 0 || endIndex >= (NSInteger)self.actions.count) {
        return NSNotFound;
    }
    if (![self isEndIfActionItem:self.actions[endIndex]]) {
        return NSNotFound;
    }
    
    NSInteger depth = 0;
    for (NSInteger idx = endIndex; idx >= 0; idx--) {
        id item = self.actions[idx];
        if ([self isEndIfActionItem:item]) {
            depth++;
        } else if ([self isIfActionItem:item]) {
            depth--;
            if (depth == 0) {
                return idx;
            }
        }
    }
    return NSNotFound;
}

- (NSRange)ifBlockRangeForIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.actions.count) {
        return NSMakeRange(NSNotFound, 0);
    }
    
    id item = self.actions[index];
    if ([self isIfActionItem:item]) {
        NSInteger endIndex = [self matchingEndIndexForIfAtIndex:index];
        if (endIndex != NSNotFound) {
            return NSMakeRange(index, endIndex - index + 1);
        }
    } else if ([self isEndIfActionItem:item]) {
        NSInteger startIndex = [self matchingIfIndexForEndAtIndex:index];
        if (startIndex != NSNotFound) {
            return NSMakeRange(startIndex, index - startIndex + 1);
        }
    }
    
    return NSMakeRange(index, 1);
}

- (NSInteger)indentationLevelForRow:(NSInteger)row {
    NSInteger depth = 0;
    for (NSInteger idx = 0; idx < row; idx++) {
        id item = self.actions[idx];
        if ([self isIfActionItem:item]) {
            depth++;
        } else if ([self isEndIfActionItem:item]) {
            depth = MAX(depth - 1, 0);
        }
    }
    
    id current = self.actions[row];
    if ([self isEndIfActionItem:current] || [self isElseActionItem:current] || [self isElseIfActionItem:current]) {
        return MAX(depth - 1, 0);
    }
    return depth;
}

- (NSArray<NSDictionary *> *)ifConditionDefinitions {
    return @[
        @{
            @"key": @"lock",
            @"title": @"Lock Status",
            @"values": @[
                @{ @"value": @"LOCKED", @"title": @"Locked" },
                @{ @"value": @"UNLOCKED", @"title": @"Unlocked" }
            ]
        },
        @{
            @"key": @"player",
            @"title": @"Player Status",
            @"values": @[
                @{ @"value": @"PLAYING", @"title": @"Playing" },
                @{ @"value": @"PAUSED", @"title": @"Paused" },
                @{ @"value": @"STOPPED", @"title": @"Stopped" }
            ]
        },
        @{
            @"key": @"wifi",
            @"title": @"Wi-Fi",
            @"values": @[
                @{ @"value": @"ON", @"title": @"On" },
                @{ @"value": @"OFF", @"title": @"Off" }
            ]
        },
        @{
            @"key": @"bluetooth",
            @"title": @"Bluetooth",
            @"values": @[
                @{ @"value": @"ON", @"title": @"On" },
                @{ @"value": @"OFF", @"title": @"Off" }
            ]
        },
        @{
            @"key": @"airplane",
            @"title": @"Airplane Mode",
            @"values": @[
                @{ @"value": @"ON", @"title": @"On" },
                @{ @"value": @"OFF", @"title": @"Off" }
            ]
        },
        @{
            @"key": @"silent_vibration",
            @"title": @"Silent Vibration",
            @"values": @[
                @{ @"value": @"ON", @"title": @"On" },
                @{ @"value": @"OFF", @"title": @"Off" }
            ]
        },
        @{
            @"key": @"ring_vibration",
            @"title": @"Ring Vibration",
            @"values": @[
                @{ @"value": @"ON", @"title": @"On" },
                @{ @"value": @"OFF", @"title": @"Off" }
            ]
        },
        @{
            @"key": @"orientation",
            @"title": @"Orientation",
            @"values": @[
                @{ @"value": @"PORTRAIT", @"title": @"Portrait" },
                @{ @"value": @"LANDSCAPE", @"title": @"Landscape" }
            ]
        },
        @{
            @"key": @"front_app",
            @"title": @"Front Application"
        }
    ];
}

- (void)configurePopoverSourceForAlert:(UIAlertController *)alert {
    if (alert.popoverPresentationController) {
        alert.popoverPresentationController.sourceView = self.view;
        alert.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
    }
}

- (NSDictionary *)buildIfActionWithCondition:(NSDictionary *)condition expectedValue:(NSDictionary *)expectedValue {
    return @{
        @"type": @"if",
        @"conditionKey": condition[@"key"] ?: @"",
        @"conditionTitle": condition[@"title"] ?: @"Condition",
        @"expectedValue": expectedValue[@"value"] ?: @"",
        @"expectedTitle": expectedValue[@"title"] ?: @"Value"
    };
}

- (void)presentIfValuePickerForCondition:(NSDictionary *)condition existingIndex:(NSInteger)existingIndex insertIndex:(NSInteger)insertIndex type:(NSString *)type {
    NSString *actionType = type ?: @"if";
    
    if ([condition[@"key"] isEqualToString:@"front_app"]) {
        RCAppPickerViewController *appPicker = [[RCAppPickerViewController alloc] init];
        __weak typeof(self) weakSelf = self;
        appPicker.onAppSelected = ^(NSString *name, NSString *bundleId) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            
            NSDictionary *ifAction = @{
                @"type": actionType,
                @"conditionKey": @"front_app",
                @"conditionTitle": @"Front Application",
                @"expectedValue": bundleId,
                @"expectedTitle": name
            };
            
            if (existingIndex != NSNotFound && existingIndex >= 0 && existingIndex < (NSInteger)strongSelf.actions.count) {
                strongSelf.actions[existingIndex] = ifAction;
            } else if (insertIndex != NSNotFound && insertIndex >= 0 && insertIndex <= (NSInteger)strongSelf.actions.count) {
                [strongSelf.actions insertObject:ifAction atIndex:insertIndex];
            } else {
                [strongSelf.actions addObject:ifAction];
                [strongSelf.actions addObject:@{ @"type": @"end_if" }];
            }
            [strongSelf saveActions];
            [strongSelf.tableView reloadData];
        };
        [self.navigationController pushViewController:appPicker animated:YES];
        return;
    }

    NSArray *values = condition[@"values"] ?: @[];
    NSString *title = [NSString stringWithFormat:@"%@ is...", condition[@"title"] ?: @"Condition"];
    UIAlertController *picker = [UIAlertController alertControllerWithTitle:title
                                                                     message:nil
                                                              preferredStyle:UIAlertControllerStyleActionSheet];
    
    __weak typeof(self) weakSelf = self;
    for (NSDictionary *value in values) {
        [picker addAction:[UIAlertAction actionWithTitle:value[@"title"]
                                                  style:UIAlertActionStyleDefault
                                                handler:^(__unused UIAlertAction * _Nonnull action) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            
            NSDictionary *ifAction = @{
                @"type": actionType,
                @"conditionKey": condition[@"key"] ?: @"",
                @"conditionTitle": condition[@"title"] ?: @"Condition",
                @"expectedValue": value[@"value"] ?: @"",
                @"expectedTitle": value[@"title"] ?: @"Value"
            };
            if (existingIndex != NSNotFound && existingIndex >= 0 && existingIndex < (NSInteger)strongSelf.actions.count) {
                strongSelf.actions[existingIndex] = ifAction;
            } else if (insertIndex != NSNotFound && insertIndex >= 0 && insertIndex <= (NSInteger)strongSelf.actions.count) {
                [strongSelf.actions insertObject:ifAction atIndex:insertIndex];
            } else {
                [strongSelf.actions addObject:ifAction];
                [strongSelf.actions addObject:@{ @"type": @"end_if" }];
            }
            [strongSelf saveActions];
            [strongSelf.tableView reloadData];
        }]];
    }
    
    [picker addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self configurePopoverSourceForAlert:picker];
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)presentIfConditionPickerForIndex:(NSInteger)existingIndex insertIndex:(NSInteger)insertIndex type:(NSString *)type {
    NSString *title = [type isEqualToString:@"else_if"] ? @"Else If Condition" : @"If Condition";
    UIAlertController *picker = [UIAlertController alertControllerWithTitle:title
                                                                     message:@"Choose a status to evaluate"
                                                              preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    
    for (NSDictionary *condition in [self ifConditionDefinitions]) {
        [picker addAction:[UIAlertAction actionWithTitle:condition[@"title"]
                                                  style:UIAlertActionStyleDefault
                                                handler:^(__unused UIAlertAction * _Nonnull action) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            [strongSelf presentIfValuePickerForCondition:condition existingIndex:existingIndex insertIndex:insertIndex type:type];
        }]];
    }
    
    [picker addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self configurePopoverSourceForAlert:picker];
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)presentIfConditionPickerForIndex:(NSInteger)index {
    NSString *type = @"if";
    if (index != NSNotFound && index >= 0 && index < (NSInteger)self.actions.count) {
        id actionItem = self.actions[index];
        if ([self isElseIfActionItem:actionItem]) {
            type = @"else_if";
        }
    }
    [self presentIfConditionPickerForIndex:index insertIndex:NSNotFound type:type];
}

- (void)presentIfValuePickerForCondition:(NSDictionary *)condition existingIndex:(NSInteger)index {
    [self presentIfValuePickerForCondition:condition existingIndex:index insertIndex:NSNotFound type:@"if"];
}

- (NSInteger)elseIfInsertionIndexForBlockIndex:(NSInteger)index {
    id item = self.actions[index];
    NSInteger ifIndex = NSNotFound;
    if ([self isIfActionItem:item]) {
        ifIndex = index;
    } else if ([self isElseIfActionItem:item] || [self isElseActionItem:item]) {
        NSInteger depth = 0;
        for (NSInteger idx = index; idx >= 0; idx--) {
            id checkItem = self.actions[idx];
            if ([self isEndIfActionItem:checkItem]) {
                depth++;
            } else if ([self isIfActionItem:checkItem]) {
                depth--;
                if (depth < 0) {
                    ifIndex = idx;
                    break;
                }
            }
        }
    } else if ([self isEndIfActionItem:item]) {
        ifIndex = [self matchingIfIndexForEndAtIndex:index];
    }
    
    if (ifIndex == NSNotFound) return NSNotFound;
    
    NSInteger depth = 0;
    for (NSInteger idx = ifIndex; idx < (NSInteger)self.actions.count; idx++) {
        id checkItem = self.actions[idx];
        if ([self isIfActionItem:checkItem]) {
            depth++;
        } else if ([self isEndIfActionItem:checkItem]) {
            depth--;
            if (depth == 0) {
                return idx;
            }
        } else if ([self isElseActionItem:checkItem]) {
            if (depth == 1) {
                return idx;
            }
        }
    }
    return NSNotFound;
}

- (NSInteger)moveActionFromIndex:(NSInteger)sourceIndex toFinalIndex:(NSInteger)finalIndex {
    if (sourceIndex < 0 || sourceIndex >= (NSInteger)self.actions.count) {
        return NSNotFound;
    }
    
    NSRange rangeToMove = [self ifBlockRangeForIndex:sourceIndex];
    if (rangeToMove.location == NSNotFound || rangeToMove.length == 0) {
        return NSNotFound;
    }
    
    NSInteger maxFinalIndex = (NSInteger)self.actions.count - (NSInteger)rangeToMove.length;
    finalIndex = MAX(0, MIN(finalIndex, maxFinalIndex));
    if (finalIndex == (NSInteger)rangeToMove.location) {
        return rangeToMove.location;
    }
    
    NSArray *itemsToMove = [self.actions subarrayWithRange:rangeToMove];
    [self.actions removeObjectsInRange:rangeToMove];

    finalIndex = MAX(0, MIN(finalIndex, (NSInteger)self.actions.count));
    NSIndexSet *indexes = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(finalIndex, itemsToMove.count)];
    [self.actions insertObjects:itemsToMove atIndexes:indexes];
    
    [self saveActions];
    [self.tableView reloadData];
    return finalIndex;
}

- (NSInteger)finalIndexFromDropDestinationIndex:(NSInteger)destinationIndex sourceIndex:(NSInteger)sourceIndex {
    NSRange sourceRange = [self ifBlockRangeForIndex:sourceIndex];
    if (sourceRange.location == NSNotFound || sourceRange.length == 0) {
        return destinationIndex;
    }
    if (destinationIndex > (NSInteger)sourceRange.location) {
        destinationIndex -= sourceRange.length;
    }
    return destinationIndex;
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    
    CGPoint touchPoint = [gesture locationInView:self.tableView];
    NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:touchPoint];
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:indexPath ? @"Action Options" : @"Actions"
                                                                   message:nil 
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    if (indexPath) {
        id item = self.actions[indexPath.row];
        
        // Copy option
        [alert addAction:[UIAlertAction actionWithTitle:@"Copy" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            g_actionClipboard = [item copy];
        }]];
        
        // Paste Above/Below options
        if (g_actionClipboard) {
            [alert addAction:[UIAlertAction actionWithTitle:@"Paste Above" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
                [self.actions insertObject:[g_actionClipboard copy] atIndex:indexPath.row];
                [self saveActions];
                [self.tableView reloadData];
            }]];
            [alert addAction:[UIAlertAction actionWithTitle:@"Paste Below" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
                [self.actions insertObject:[g_actionClipboard copy] atIndex:indexPath.row + 1];
                [self saveActions];
                [self.tableView reloadData];
            }]];
        }

        // If-specific options
        if ([self isIfActionItem:item] || [self isElseIfActionItem:item] || [self isElseActionItem:item] || [self isEndIfActionItem:item]) {
            NSInteger insertionIndex = [self elseIfInsertionIndexForBlockIndex:indexPath.row];
            if (insertionIndex != NSNotFound) {
                [alert addAction:[UIAlertAction actionWithTitle:@"Add Else If" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
                    [self presentIfConditionPickerForIndex:NSNotFound insertIndex:insertionIndex type:@"else_if"];
                }]];
            }
            
            NSInteger ifIndex = NSNotFound;
            if ([self isIfActionItem:item]) {
                ifIndex = indexPath.row;
            } else {
                NSInteger depth = 0;
                for (NSInteger idx = indexPath.row; idx >= 0; idx--) {
                    id checkItem = self.actions[idx];
                    if ([self isEndIfActionItem:checkItem]) {
                        depth++;
                    } else if ([self isIfActionItem:checkItem]) {
                        depth--;
                        if (depth < 0) {
                            ifIndex = idx;
                            break;
                        }
                    }
                }
            }
            
            if (ifIndex != NSNotFound) {
                NSInteger elseIndex = [self matchingElseIndexForIfAtIndex:ifIndex];
                BOOL hasElse = (elseIndex != NSNotFound);
                
                if (hasElse) {
                    if ([self isElseActionItem:item] || [self isIfActionItem:item]) {
                        [alert addAction:[UIAlertAction actionWithTitle:@"Remove Else" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
                            [self.actions removeObjectAtIndex:elseIndex];
                            [self saveActions];
                            [self.tableView reloadData];
                        }]];
                    }
                } else {
                    [alert addAction:[UIAlertAction actionWithTitle:@"Add Else" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
                        NSInteger endIndex = [self matchingEndIndexForIfAtIndex:ifIndex];
                        if (endIndex != NSNotFound) {
                            [self.actions insertObject:@{ @"type": @"else" } atIndex:endIndex];
                            [self saveActions];
                            [self.tableView reloadData];
                        }
                    }]];
                }
            }
            
            if ([self isIfActionItem:item] || [self isElseIfActionItem:item]) {
                [alert addAction:[UIAlertAction actionWithTitle:@"Edit Condition" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
                    [self presentIfConditionPickerForIndex:indexPath.row];
                }]];
            }
            
            if ([self isElseIfActionItem:item]) {
                [alert addAction:[UIAlertAction actionWithTitle:@"Delete Else If" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
                    [self.actions removeObjectAtIndex:indexPath.row];
                    [self saveActions];
                    [self.tableView reloadData];
                }]];
            }
        }
    } else {
        // Long press on empty space
        if (g_actionClipboard) {
            [alert addAction:[UIAlertAction actionWithTitle:@"Paste" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
                [self.actions addObject:[g_actionClipboard copy]];
                [self saveActions];
                [self.tableView reloadData];
            }]];
        } else {
            return; // Nothing to do on empty space if clipboard is empty
        }
    }
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self configurePopoverSourceForAlert:alert];
    [self presentViewController:alert animated:YES completion:nil];
}

- (NSInteger)adjustedDestinationIndexForDropCoordinator:(id<UITableViewDropCoordinator>)coordinator
                                   destinationIndexPath:(NSIndexPath *)destinationIndexPath
                                             sourceItem:(id)sourceItem {
    NSInteger destinationIndex = destinationIndexPath ? destinationIndexPath.row : self.actions.count;
    if (!destinationIndexPath ||
        destinationIndex < 0 ||
        destinationIndex >= (NSInteger)self.actions.count) {
        return destinationIndex;
    }
    
    BOOL sourceIsControlRow = [self isIfActionItem:sourceItem] || [self isEndIfActionItem:sourceItem];
    if (sourceIsControlRow) {
        return destinationIndex;
    }
    
    id destinationItem = self.actions[destinationIndex];
    BOOL destinationIsIf = [self isIfActionItem:destinationItem];
    BOOL destinationIsEndIf = [self isEndIfActionItem:destinationItem];
    if (!destinationIsIf && !destinationIsEndIf) {
        return destinationIndex;
    }
    
    CGPoint dropPoint = [coordinator.session locationInView:self.tableView];
    CGRect destinationRect = [self.tableView rectForRowAtIndexPath:destinationIndexPath];
    BOOL lowerHalfDrop = dropPoint.y >= CGRectGetMidY(destinationRect);
    
    if (destinationIsIf) {
        // Lower-half drop on "If" row means "place inside block", upper-half means before it.
        return lowerHalfDrop ? destinationIndex + 1 : destinationIndex;
    }
    
    // Lower-half drop on "End If" row means "place outside block", upper-half means inside.
    return lowerHalfDrop ? destinationIndex + 1 : destinationIndex;
}

#pragma mark - Table View Data Source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    id actionData = self.actions[indexPath.row];
    
    if ([actionData isKindOfClass:[NSDictionary class]]) {
        if ([self isIfActionItem:actionData] || [self isElseIfActionItem:actionData]) {
            [self presentIfConditionPickerForIndex:indexPath.row];
        }
        return;
    }
    
    NSString *currentAction = (NSString *)actionData;
    NSDictionary *toggleInfo = [[RCConfigManager sharedManager] toggleInfoForCommand:currentAction];
    
    if (toggleInfo) {
        UIAlertController *picker = [UIAlertController alertControllerWithTitle:toggleInfo[@"name"]
                                                                         message:@"Select desired state"
                                                                  preferredStyle:UIAlertControllerStyleActionSheet];
        
        NSArray *suffixes = toggleInfo[@"suffixes"];
        NSArray *displaySuffixes = toggleInfo[@"displaySuffixes"];
        NSString *matchedPrefix = toggleInfo[@"matchedPrefix"];
        NSArray *prefixes = toggleInfo[@"prefixes"];
        NSString *canonicalPrefix = (matchedPrefix.length > 0) ? matchedPrefix : (prefixes.firstObject ?: @"");
        
        __weak typeof(self) weakSelf = self;
        for (NSUInteger idx = 0; idx < suffixes.count; idx++) {
            NSString *suffix = suffixes[idx];
            NSString *displaySuffix = displaySuffixes[idx];
            
            [picker addAction:[UIAlertAction actionWithTitle:displaySuffix
                                                      style:UIAlertActionStyleDefault
                                                    handler:^(__unused UIAlertAction * _Nonnull action) {
                __strong typeof(weakSelf) strongSelf = weakSelf;
                if (!strongSelf) return;
                
                NSString *newCommand = [NSString stringWithFormat:@"%@%@", canonicalPrefix, suffix];
                if (matchedPrefix.length == 0 && [toggleInfo[@"key"] isEqualToString:@"audiomix"] && [suffix isEqualToString:@"toggle"]) {
                    newCommand = @"audiomix";
                }
                
                strongSelf.actions[indexPath.row] = newCommand;
                [strongSelf saveActions];
                [strongSelf.tableView reloadData];
            }]];
        }
        
        [picker addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        
        picker.popoverPresentationController.sourceView = self.view;
        UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
        if (cell) {
            picker.popoverPresentationController.sourceRect = cell.bounds;
            picker.popoverPresentationController.sourceView = cell;
        } else {
            picker.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2, 1, 1);
        }
        
        [self presentViewController:picker animated:YES completion:nil];
        return;
    }
    
    if ([currentAction hasPrefix:@"exec "] || [currentAction hasPrefix:@"root "]) {
        // Edit Terminal Command
        BOOL isRoot = [currentAction hasPrefix:@"root "];
        NSString *currentCommand = [currentAction substringFromIndex:5];
        
        RCTextInputViewController *inputVC = [[RCTextInputViewController alloc] init];
        inputVC.promptTitle = @"Edit Command";
        inputVC.promptMessage = @"Update your terminal command";
        inputVC.initialText = currentCommand;
        inputVC.showRootToggle = YES;
        inputVC.isRootToggled = isRoot;
        
        __weak typeof(inputVC) weakInputVC = inputVC;
        inputVC.onComplete = ^(NSString *text) {
            if (text.length > 0) {
                NSString *prefix = weakInputVC.isRootToggled ? @"root" : @"exec";
                self.actions[indexPath.row] = [NSString stringWithFormat:@"%@ %@", prefix, text];
                [self saveActions];
                [self.tableView reloadData];
            }
        };
        
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:inputVC];
        [self presentViewController:nav animated:YES completion:nil];
    } else if ([currentAction hasPrefix:@"set-vol "] || [currentAction hasPrefix:@"brightness "]) {
        // Edit Volume/Brightness
        BOOL isVolume = [currentAction hasPrefix:@"set-vol "];
        NSString *title = isVolume ? @"Edit Volume" : @"Edit Brightness";
        NSString *prefix = isVolume ? @"set-vol " : @"brightness ";
        NSString *currentValue = [currentAction substringFromIndex:prefix.length];
        
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:title 
                                                                       message:@"Enter a value (0-100)" 
                                                                preferredStyle:UIAlertControllerStyleAlert];
        
        [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
            textField.keyboardType = UIKeyboardTypeNumberPad;
            textField.text = currentValue;
            textField.textAlignment = NSTextAlignmentCenter;
        }];
        
        [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Update" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            UITextField *textField = alert.textFields.firstObject;
            int val = [textField.text intValue];
            if (val < 0) val = 0;
            if (val > 100) val = 100;
            
            self.actions[indexPath.row] = [NSString stringWithFormat:@"%@%d", prefix, val];
            [self saveActions];
            [self.tableView reloadData];
        }]];
        
        [self presentViewController:alert animated:YES completion:nil];
    } else if ([currentAction hasPrefix:@"Lua "] || [currentAction hasPrefix:@"lua_eval "] || [currentAction hasPrefix:@"lua "]) {
        // Edit Lua Script
        int prefixLength = [currentAction hasPrefix:@"lua_eval "] ? 9 : 4;
        NSString *currentCode = [currentAction substringFromIndex:prefixLength];
        
        RCTextInputViewController *inputVC = [[RCTextInputViewController alloc] init];
        inputVC.promptTitle = @"Edit Lua Script";
        inputVC.promptMessage = @"Update your Lua code";
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
    } else if ([currentAction hasPrefix:@"shortcut:"]) {
        // Edit Shortcut
        RCShortcutPickerViewController *shortcutPicker = [[RCShortcutPickerViewController alloc] init];
        shortcutPicker.onShortcutSelected = ^(NSString *name) {
            self.actions[indexPath.row] = [NSString stringWithFormat:@"shortcut:%@", name];
            [self saveActions];
            [self.tableView reloadData];
        };
        
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:shortcutPicker];
        [self presentViewController:nav animated:YES completion:nil];
    } else if ([currentAction hasPrefix:@"uiopen "]) {
        // Edit App
        RCAppPickerViewController *appPicker = [[RCAppPickerViewController alloc] init];
        appPicker.onAppSelected = ^(NSString *name, NSString *bundleId) {
            self.actions[indexPath.row] = [NSString stringWithFormat:@"uiopen %@", bundleId];
            [self saveActions];
            [self.tableView reloadData];
        };
        
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:appPicker];
        [self presentViewController:nav animated:YES completion:nil];
    } else if ([currentAction hasPrefix:@"airplay connect "] || [currentAction hasPrefix:@"airplay-connect "]) {
        [self editAirPlayConnectAtIndex:indexPath.row];
    } else if ([currentAction hasPrefix:@"bt connect "] || [currentAction hasPrefix:@"bluetooth connect "] || [currentAction hasPrefix:@"bt-connect "]) {
        [self editBluetoothConnectAtIndex:indexPath.row isDisconnect:NO];
    } else if ([currentAction hasPrefix:@"bt disconnect "] || [currentAction hasPrefix:@"bluetooth disconnect "] || [currentAction hasPrefix:@"bt-disconnect "]) {
        [self editBluetoothConnectAtIndex:indexPath.row isDisconnect:YES];
    } else {
        // Generic edit for other commands - show alert with current command
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Edit Action"
            message:@"Modify the command"
            preferredStyle:UIAlertControllerStyleAlert];

        [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
            textField.text = currentAction;
            textField.autocorrectionType = UITextAutocorrectionTypeNo;
            textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        }];

        [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            NSString *input = alert.textFields.firstObject.text;
            if (input.length > 0) {
                self.actions[indexPath.row] = input;
                [self saveActions];
                [self.tableView reloadData];
            }
        }]];

        [self presentViewController:alert animated:YES completion:nil];
    }
}

- (void)editAirPlayConnectAtIndex:(NSInteger)index {
    UIAlertController *loading = [UIAlertController alertControllerWithTitle:@"Scanning for devices..." 
                                                                     message:@"Please wait" 
                                                              preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:loading animated:YES completion:nil];
    
    [[RCServerClient sharedClient] executeCommand:@"airplay list" completion:^(NSString * _Nullable output, NSError * _Nullable error) {
        [loading dismissViewControllerAnimated:YES completion:^{
            if (error) {
                UIAlertController *errAlert = [UIAlertController alertControllerWithTitle:@"Error" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
                [errAlert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
                [self presentViewController:errAlert animated:YES completion:nil];
                return;
            }
            
            NSArray *lines = [output componentsSeparatedByString:@"\n"];
            NSMutableArray *devices = [NSMutableArray array];
            for (NSString *line in lines) {
                NSString *clean = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                if (clean.length == 0 || [clean isEqualToString:@"No AirPlay devices found."] || [clean hasPrefix:@"Error:"]) continue;
                if (clean.length < 5) continue;
                NSString *workingLine = clean;
                if ([workingLine hasPrefix:@"* "] || [workingLine hasPrefix:@"  "]) workingLine = [workingLine substringFromIndex:2];
                NSRange openBracket = [workingLine rangeOfString:@" [" options:NSBackwardsSearch];
                NSRange closeBracket = [workingLine rangeOfString:@"]" options:NSBackwardsSearch];
                if (openBracket.location != NSNotFound && closeBracket.location != NSNotFound && closeBracket.location > openBracket.location) {
                    NSString *name = [[workingLine substringToIndex:openBracket.location] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                    NSString *uid = [[workingLine substringWithRange:NSMakeRange(openBracket.location + 2, closeBracket.location - openBracket.location - 2)] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                    [devices addObject:@{ @"uid": uid, @"name": name }];
                }
            }
            
            if (devices.count == 0) {
                UIAlertController *empty = [UIAlertController alertControllerWithTitle:@"No Devices Found" message:@"Ensure AirPlay devices are reachable." preferredStyle:UIAlertControllerStyleAlert];
                [empty addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
                [self presentViewController:empty animated:YES completion:nil];
                return;
            }
            
            UIAlertController *picker = [UIAlertController alertControllerWithTitle:@"Update AirPlay Device" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
            for (NSDictionary *device in devices) {
                [picker addAction:[UIAlertAction actionWithTitle:device[@"name"] style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                    self.actions[index] = [NSString stringWithFormat:@"airplay connect %@ # %@", device[@"uid"], device[@"name"]];
                    [self saveActions];
                    [self.tableView reloadData];
                }]];
            }
            [picker addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
            picker.popoverPresentationController.sourceView = self.view;
            [self presentViewController:picker animated:YES completion:nil];
        }];
    }];
}

- (void)editBluetoothConnectAtIndex:(NSInteger)index isDisconnect:(BOOL)isDisconnect {
    NSString *promptTitle = isDisconnect ? @"Update Bluetooth Disconnect" : @"Update Bluetooth Connection";
    
    UIAlertController *loading = [UIAlertController alertControllerWithTitle:@"Fetching paired devices..." 
                                                                     message:@"Please wait" 
                                                              preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:loading animated:YES completion:nil];
    
    [[RCServerClient sharedClient] executeCommand:@"bluetooth list" completion:^(NSString * _Nullable output, NSError * _Nullable error) {
        [loading dismissViewControllerAnimated:YES completion:^{
            if (error || !output) {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error" message:error.localizedDescription ?: @"Failed to fetch devices" preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
                [self presentViewController:alert animated:YES completion:nil];
                return;
            }
            
            NSArray *lines = [output componentsSeparatedByString:@"\n"];
            NSMutableArray *devices = [NSMutableArray array];
            for (NSString *line in lines) {
                NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                if (trimmed.length > 0) [devices addObject:trimmed];
            }
            
            if (devices.count == 0) {
                UIAlertController *empty = [UIAlertController alertControllerWithTitle:@"No Devices Found" message:@"Ensure Bluetooth devices are paired." preferredStyle:UIAlertControllerStyleAlert];
                [empty addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
                [self presentViewController:empty animated:YES completion:nil];
                return;
            }
            
            UIAlertController *picker = [UIAlertController alertControllerWithTitle:promptTitle message:nil preferredStyle:UIAlertControllerStyleActionSheet];
            for (NSString *deviceName in devices) {
                [picker addAction:[UIAlertAction actionWithTitle:deviceName style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                    NSString *prefix = isDisconnect ? @"bt disconnect" : @"bt connect";
                    self.actions[index] = [NSString stringWithFormat:@"%@ %@", prefix, deviceName];
                    [self saveActions];
                    [self.tableView reloadData];
                }]];
            }
            [picker addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
            picker.popoverPresentationController.sourceView = self.view;
            [self presentViewController:picker animated:YES completion:nil];
        }];
    }];
}

- (UIBezierPath *)fillPathForRect:(CGRect)rect
                            first:(BOOL)isFirst
                             last:(BOOL)isLast
                           single:(BOOL)isSingle
                     cornerRadius:(CGFloat)cornerRadius {
    if (isSingle) {
        return [UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:cornerRadius];
    }
    if (isFirst) {
        return [UIBezierPath bezierPathWithRoundedRect:rect
                                     byRoundingCorners:(UIRectCornerTopLeft | UIRectCornerTopRight)
                                           cornerRadii:CGSizeMake(cornerRadius, cornerRadius)];
    }
    if (isLast) {
        return [UIBezierPath bezierPathWithRoundedRect:rect
                                     byRoundingCorners:(UIRectCornerBottomLeft | UIRectCornerBottomRight)
                                           cornerRadii:CGSizeMake(cornerRadius, cornerRadius)];
    }
    return [UIBezierPath bezierPathWithRect:rect];
}

- (void)applySectionCardStyleToCell:(UITableViewCell *)cell atIndexPath:(NSIndexPath *)indexPath {
    RCConfigManager *config = [RCConfigManager sharedManager];
    UIColor *fillColor = [config tweakColorForKey:@"blockBackground" defaultVal:0.12];
    UIColor *selectedFillColor = [config tweakColorForKey:@"selectionHighlight" defaultVal:0.15];
    UIColor *borderColor = [config tweakColorForKey:@"borders" defaultVal:0.14];
    
    NSInteger rowCount = [self.tableView numberOfRowsInSection:indexPath.section];
    if (rowCount < 1) {
        return;
    }
    
    BOOL isSingle = (rowCount == 1);
    BOOL isFirst = (indexPath.row == 0);
    BOOL isLast = (indexPath.row == rowCount - 1);
    
    CGFloat lineWidth = 1.0;
    CGFloat cornerRadius = 12.0;
    CGRect fillRect = CGRectInset(cell.bounds, 0.0, 0.0);
    CGRect borderRect = CGRectInset(fillRect, lineWidth * 0.5, lineWidth * 0.5);
    if (CGRectGetWidth(fillRect) <= 0 || CGRectGetHeight(fillRect) <= 0) {
        return;
    }
    if (CGRectGetWidth(borderRect) <= 0 || CGRectGetHeight(borderRect) <= 0) {
        return;
    }
    
    UIBezierPath *fillPath = [self fillPathForRect:fillRect
                                             first:isFirst
                                              last:isLast
                                            single:isSingle
                                      cornerRadius:cornerRadius];
    
    UIBezierPath *borderPath = [self fillPathForRect:borderRect
                                             first:isFirst
                                              last:isLast
                                            single:isSingle
                                      cornerRadius:cornerRadius];
    
    UIView *normalBackgroundView = [[UIView alloc] initWithFrame:cell.bounds];
    normalBackgroundView.backgroundColor = [UIColor clearColor];
    
    CAShapeLayer *normalFillLayer = [CAShapeLayer layer];
    normalFillLayer.frame = normalBackgroundView.bounds;
    normalFillLayer.path = fillPath.CGPath;
    normalFillLayer.fillColor = fillColor.CGColor;
    [normalBackgroundView.layer addSublayer:normalFillLayer];
    
    CAShapeLayer *normalBorderLayer = [CAShapeLayer layer];
    normalBorderLayer.frame = normalBackgroundView.bounds;
    normalBorderLayer.path = borderPath.CGPath;
    normalBorderLayer.fillColor = [UIColor clearColor].CGColor;
    normalBorderLayer.strokeColor = borderColor.CGColor;
    normalBorderLayer.lineWidth = lineWidth;
    
    if (!isSingle) {
        CGRect maskRect = normalBorderLayer.bounds;
        if (isFirst) {
            maskRect.size.height = MAX(0.0, maskRect.size.height - lineWidth);
        } else if (isLast) {
            maskRect.origin.y = lineWidth;
            maskRect.size.height = MAX(0.0, maskRect.size.height - lineWidth);
        } else {
            maskRect.origin.y = lineWidth;
            maskRect.size.height = MAX(0.0, maskRect.size.height - (2.0 * lineWidth));
        }
        CAShapeLayer *maskLayer = [CAShapeLayer layer];
        maskLayer.path = [UIBezierPath bezierPathWithRect:maskRect].CGPath;
        normalBorderLayer.mask = maskLayer;
    }
    [normalBackgroundView.layer addSublayer:normalBorderLayer];
    
    UIView *selectedBackgroundView = [[UIView alloc] initWithFrame:cell.bounds];
    selectedBackgroundView.backgroundColor = [UIColor clearColor];
    
    CAShapeLayer *selectedFillLayer = [CAShapeLayer layer];
    selectedFillLayer.frame = selectedBackgroundView.bounds;
    selectedFillLayer.path = fillPath.CGPath;
    selectedFillLayer.fillColor = selectedFillColor.CGColor;
    [selectedBackgroundView.layer addSublayer:selectedFillLayer];
    
    CAShapeLayer *selectedBorderLayer = [CAShapeLayer layer];
    selectedBorderLayer.frame = selectedBackgroundView.bounds;
    selectedBorderLayer.path = borderPath.CGPath;
    selectedBorderLayer.fillColor = [UIColor clearColor].CGColor;
    selectedBorderLayer.strokeColor = borderColor.CGColor;
    selectedBorderLayer.lineWidth = lineWidth;
    if (!isSingle) {
        CGRect maskRect = selectedBorderLayer.bounds;
        if (isFirst) {
            maskRect.size.height = MAX(0.0, maskRect.size.height - lineWidth);
        } else if (isLast) {
            maskRect.origin.y = lineWidth;
            maskRect.size.height = MAX(0.0, maskRect.size.height - lineWidth);
        } else {
            maskRect.origin.y = lineWidth;
            maskRect.size.height = MAX(0.0, maskRect.size.height - (2.0 * lineWidth));
        }
        CAShapeLayer *maskLayer = [CAShapeLayer layer];
        maskLayer.path = [UIBezierPath bezierPathWithRect:maskRect].CGPath;
        selectedBorderLayer.mask = maskLayer;
    }
    [selectedBackgroundView.layer addSublayer:selectedBorderLayer];
    
    cell.backgroundColor = [UIColor clearColor];
    cell.contentView.backgroundColor = [UIColor clearColor];
    cell.backgroundView = normalBackgroundView;
    cell.selectedBackgroundView = selectedBackgroundView;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return _actions.count;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    if (_actions.count == 0) return nil;
    
    UIView *headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, 40)];
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(20, 15, tableView.bounds.size.width - 40, 20)];
    label.text = @"ACTION SEQUENCE";
    label.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    label.textColor = [UIColor secondaryLabelColor];
    [headerView addSubview:label];
    return headerView;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return _actions.count > 0 ? 40.0f : 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (_actions.count == 0) {
        return @"Tap + to add actions. They will run in sequence when the trigger fires.";
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    // Use Subtitle style
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ActionCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"ActionCell"];
    }
    
    // Action card styling applied via applySectionCardStyleToCell: below
    id actionItem = _actions[indexPath.row];
    NSString *cleanName = [self displayNameForCommand:actionItem];
    NSString *subtitle = nil;
    NSInteger indentationLevel = [self indentationLevelForRow:indexPath.row];

    cell.indentationWidth = 18.0f;
    cell.indentationLevel = indentationLevel;

    if ([actionItem isKindOfClass:[NSDictionary class]]) {
        cell.textLabel.text = cleanName;
        cell.textLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightMedium];
        BOOL isControl = [self isEndIfActionItem:actionItem] || [self isElseActionItem:actionItem];
        cell.textLabel.textColor = isControl ? [UIColor secondaryLabelColor] : [UIColor labelColor];
        cell.detailTextLabel.text = nil;
        
        cell.imageView.image = [UIImage systemImageNamed:[self iconForCommand:actionItem]];
        cell.imageView.tintColor = isControl ? [UIColor tertiaryLabelColor] : [UIColor systemGrayColor];
        
        UIImageView *handleView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"line.3.horizontal"]];
        handleView.tintColor = [UIColor systemGray3Color];
        cell.accessoryView = handleView;
        [self applySectionCardStyleToCell:cell atIndexPath:indexPath];
        return cell;
    }

    NSString *action = (NSString *)actionItem;
    NSDictionary *toggleInfo = [[RCConfigManager sharedManager] toggleInfoForCommand:action];

    // Logic to separate "Type" from "Value"
    if (toggleInfo) {
        NSString *baseName = toggleInfo[@"name"];
        NSString *suffix = toggleInfo[@"currentDisplaySuffix"];
        NSString *fullText = [NSString stringWithFormat:@"%@ %@", baseName, suffix];
        NSMutableAttributedString *attrStr = [[NSMutableAttributedString alloc] initWithString:fullText];
        
        NSRange baseRange = NSMakeRange(0, baseName.length + 1); // includes the space
        NSRange suffixRange = [fullText rangeOfString:suffix options:NSBackwardsSearch];
        
        UIColor *accentColor = [UIColor systemBlueColor];
        
        [attrStr addAttribute:NSFontAttributeName value:[UIFont systemFontOfSize:17 weight:UIFontWeightMedium] range:NSMakeRange(0, fullText.length)];
        [attrStr addAttribute:NSForegroundColorAttributeName value:[UIColor labelColor] range:baseRange];
        if (suffixRange.location != NSNotFound) {
            [attrStr addAttribute:NSForegroundColorAttributeName value:accentColor range:suffixRange];
        }
        cell.textLabel.attributedText = attrStr;
        subtitle = nil;
    } else {
        cell.textLabel.attributedText = nil; // Clear any attributed text
        
        NSAttributedString *paramAttrStr = [self attributedDisplayNameForCommand:action];
        if (paramAttrStr) {
            cell.textLabel.attributedText = paramAttrStr;
            subtitle = nil;
        } else {
            if ([action hasPrefix:@"exec "]) {
                cell.textLabel.text = [action substringFromIndex:5];
                subtitle = @"Terminal Command";
            } else if ([action hasPrefix:@"root "]) {
                cell.textLabel.text = [action substringFromIndex:5];
                subtitle = @"Root Command";
            } else if ([action hasPrefix:@"Lua "] || [action hasPrefix:@"lua "]) {
                cell.textLabel.text = [action hasPrefix:@"Lua "] ? [action substringFromIndex:4] : [action substringFromIndex:4];
                subtitle = @"Lua Script";
            } else if ([action hasPrefix:@"delay "]) {
                cell.textLabel.text = [NSString stringWithFormat:@"Wait %@s", [action substringFromIndex:6]];
                subtitle = [NSString stringWithFormat:@"%@ seconds", [action substringFromIndex:6]];
            } else if ([action hasPrefix:@"shortcut:"]) {
                cell.textLabel.text = cleanName;
                subtitle = @"Siri Shortcut";
            } else if ([action hasPrefix:@"uiopen "]) {
                cell.textLabel.text = cleanName;
                subtitle = @"Application";
            } else if ([action hasPrefix:@"airplay connect "]) {
                cell.textLabel.text = cleanName;
                subtitle = @"AirPlay Device";
            } else if ([action hasPrefix:@"bt connect "] || [action hasPrefix:@"bluetooth connect "]) {
                cell.textLabel.text = cleanName;
                subtitle = @"Bluetooth Device";
            } else if ([action hasPrefix:@"bt disconnect "] || [action hasPrefix:@"bluetooth disconnect "]) {
                cell.textLabel.text = cleanName;
                subtitle = nil;
            } else if ([action hasPrefix:@"airplay disconnect"]) {
                cell.textLabel.text = cleanName;
                subtitle = nil;
            } else if ([action isEqualToString:@"ldrestart"] || [action isEqualToString:@"userspace-reboot"] || [action isEqualToString:@"uicache"] || [action isEqualToString:@"player status"]) {
                cell.textLabel.text = cleanName;
                subtitle = nil;
            } else {
                cell.textLabel.text = cleanName;
                subtitle = nil;
            }
        }
    }

    if (cell.textLabel.attributedText == nil) {
        cell.textLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightMedium];
        cell.textLabel.textColor = [UIColor labelColor];
    }

    if (subtitle) {
        cell.detailTextLabel.text = subtitle;
        cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];

        // Use monospace for code-like things
        if ([action hasPrefix:@"exec "] || [action hasPrefix:@"root "] || [action hasPrefix:@"Lua "] || [action hasPrefix:@"lua "]) {
            cell.textLabel.font = [UIFont monospacedSystemFontOfSize:15 weight:UIFontWeightRegular];
            cell.textLabel.numberOfLines = 1;
            cell.textLabel.lineBreakMode = NSLineBreakByTruncatingTail;
            
            cell.detailTextLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
            cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
        } else {
             cell.detailTextLabel.font = [UIFont systemFontOfSize:15];
             cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
        }
    } else {
        cell.detailTextLabel.text = nil;
    }

    NSString *iconName = [self iconForCommand:action];
    if ([iconName hasPrefix:@"USER_APP:"]) {
        NSString *bundleId = [iconName substringFromIndex:9];
        cell.imageView.image = [UIImage _applicationIconImageForBundleIdentifier:bundleId format:0 scale:[UIScreen mainScreen].scale];
        cell.imageView.tintColor = nil;
    } else {
        cell.imageView.image = [UIImage systemImageNamed:iconName];
        cell.imageView.tintColor = [UIColor systemGrayColor];
    }

    // Custom reorder handle (since editing = NO)
    UIImageView *handleView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"line.3.horizontal"]];
    handleView.tintColor = [UIColor systemGray3Color];
    cell.accessoryView = handleView;
    [self applySectionCardStyleToCell:cell atIndexPath:indexPath];
    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    [self applySectionCardStyleToCell:cell atIndexPath:indexPath];
}

#pragma mark - UITableViewDragDelegate

- (NSArray<UIDragItem *> *)tableView:(UITableView *)tableView itemsForBeginningDragSession:(id<UIDragSession>)session atIndexPath:(NSIndexPath *)indexPath {
    id action = self.actions[indexPath.row];
    NSItemProvider *itemProvider = [[NSItemProvider alloc] initWithObject:@"rc-action"];
    UIDragItem *dragItem = [[UIDragItem alloc] initWithItemProvider:itemProvider];
    dragItem.localObject = action;
    return @[dragItem];
}

#pragma mark - UITableViewDropDelegate

- (UITableViewDropProposal *)tableView:(UITableView *)tableView dropSessionDidUpdate:(id<UIDropSession>)session withDestinationIndexPath:(NSIndexPath *)destinationIndexPath {
    if (tableView.hasActiveDrag) {
        return [[UITableViewDropProposal alloc] initWithDropOperation:UIDropOperationMove intent:UITableViewDropIntentInsertAtDestinationIndexPath];
    }
    return [[UITableViewDropProposal alloc] initWithDropOperation:UIDropOperationForbidden];
}

- (void)tableView:(UITableView *)tableView performDropWithCoordinator:(id<UITableViewDropCoordinator>)coordinator {
    NSIndexPath *destinationIndexPath = coordinator.destinationIndexPath;
    
    for (id<UITableViewDropItem> item in coordinator.items) {
        if (!item.sourceIndexPath) continue;
        
        NSInteger sourceIndex = item.sourceIndexPath.row;
        id sourceItem = (sourceIndex >= 0 && sourceIndex < (NSInteger)self.actions.count) ? self.actions[sourceIndex] : nil;
        NSInteger destinationIndex = [self adjustedDestinationIndexForDropCoordinator:coordinator
                                                                 destinationIndexPath:destinationIndexPath
                                                                           sourceItem:sourceItem];
        NSInteger finalIndex = [self finalIndexFromDropDestinationIndex:destinationIndex sourceIndex:sourceIndex];
        NSInteger insertedIndex = [self moveActionFromIndex:sourceIndex toFinalIndex:finalIndex];
        
        if (self.actions.count > 0) {
            NSInteger safeInserted = (insertedIndex == NSNotFound) ? sourceIndex : insertedIndex;
            NSInteger finalRow = MIN(MAX(safeInserted, 0), (NSInteger)self.actions.count - 1);
            [coordinator dropItem:item.dragItem toRowAtIndexPath:[NSIndexPath indexPathForRow:finalRow inSection:0]];
        }
        break;
    }
}

// Swipe Actions
- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSRange rangeToDelete = [self ifBlockRangeForIndex:indexPath.row];
    BOOL isBlockDelete = rangeToDelete.length > 1;
    
    UIContextualAction *deleteAction = [UIContextualAction
        contextualActionWithStyle:UIContextualActionStyleDestructive
        title:isBlockDelete ? @"Delete Block" : @"Delete"
        handler:^(UIContextualAction * _Nonnull action, __kindof UIView * _Nonnull sourceView, void (^ _Nonnull completionHandler)(BOOL)) {
            if (rangeToDelete.location != NSNotFound && rangeToDelete.length > 0 && NSMaxRange(rangeToDelete) <= self.actions.count) {
                [self.actions removeObjectsInRange:rangeToDelete];
            } else if (indexPath.row < self.actions.count) {
                [self.actions removeObjectAtIndex:indexPath.row];
            }
            [self saveActions];
            [tableView reloadData];
            completionHandler(YES);
        }];

    deleteAction.image = [UIImage systemImageNamed:@"trash.fill"];
    return [UISwipeActionsConfiguration configurationWithActions:@[deleteAction]];
}

// Reordering (legacy but kept for logic reference, though drag/drop is primary now)
- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)sourceIndexPath toIndexPath:(NSIndexPath *)destinationIndexPath {
    [self moveActionFromIndex:sourceIndexPath.row toFinalIndex:destinationIndexPath.row];
}

// Deletion (legacy - leading/trailing swipe actions are preferred now)
- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    return UITableViewCellEditingStyleNone; // Prevent standard delete indicator
}

- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)indexPath {
    return NO;
}


@end
