#import "RCNotificationTriggerViewController.h"
#import "RCConfigManager.h"
#import "RCActionsViewController.h"
#import "RCAppPickerViewController.h"

@interface RCNotificationTriggerViewController () <UITextFieldDelegate>
@property (nonatomic, strong) UITextField *textMatchField;
@property (nonatomic, copy) NSString *selectedBundleId;
@property (nonatomic, copy) NSString *selectedAppName;
@property (nonatomic, strong) NSString *triggerKey;
@end

@implementation RCNotificationTriggerViewController

- (instancetype)initWithTriggerKey:(NSString *)triggerKey {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _triggerKey = triggerKey;
    }
    return self;
}

- (instancetype)init {
    return [self initWithTriggerKey:nil];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.triggerKey ? @"Edit Notification" : @"New Notification";

    self.selectedAppName = @"Any App"; // Default
    self.selectedBundleId = @"";

    if (self.triggerKey) {
        RCConfigManager *cm = [RCConfigManager sharedManager];
        NSArray *notifTriggers = [cm notificationTriggers];
        for (NSDictionary *entry in notifTriggers) {
            if ([entry[@"triggerKey"] isEqualToString:self.triggerKey]) {
                self.selectedBundleId = entry[@"bundleId"] ?: @"";
                if (self.selectedBundleId.length > 0) {
                    self.selectedAppName = [cm nameForBundleId:self.selectedBundleId] ?: self.selectedBundleId;
                }
                
                if (!self.textMatchField) {
                    self.textMatchField = [[UITextField alloc] init];
                }
                self.textMatchField.text = entry[@"textMatch"] ?: @"";
                break;
            }
        }
    }
    
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(applyTweaks) 
                                                 name:@"RCConfigTweaksChangedNotification" 
                                               object:nil];
    
    [self applyTweaks];
    
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:self.triggerKey ? @"Save" : @"Add" style:UIBarButtonItemStyleDone target:self action:@selector(saveTrigger)];
}

- (void)applyTweaks {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    UIColor *bg = [cm tweakColorForKey:@"mainBackground" defaultVal:0.09];
    self.view.backgroundColor = bg;
    self.navigationController.navigationBar.backgroundColor = bg;
    self.tableView.backgroundColor = bg;
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

#pragma mark - Table View Data Source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"Target App";
    if (section == 1) return @"Text Match (Optional)";
    return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) return @"Choose which app's notifications to listen for, or leave as 'Any App' to match all incoming notifications.";
    if (section == 1) return @"Matches text in the title, subtitle, or body (case-insensitive).";
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell;
    
    if (indexPath.section == 0) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"AppCell"];
        cell.textLabel.text = @"App";
        cell.detailTextLabel.text = self.selectedAppName;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"TextCell"];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        
        if (!self.textMatchField) {
            UITextField *field = [[UITextField alloc] initWithFrame:CGRectMake(20, 0, tableView.bounds.size.width - 40, 44)];
            field.delegate = self;
            field.autocorrectionType = UITextAutocorrectionTypeNo;
            field.autocapitalizationType = UITextAutocapitalizationTypeNone;
            field.clearButtonMode = UITextFieldViewModeWhileEditing;
            field.placeholder = @"Keyword to match";
            self.textMatchField = field;
        }
        
        // Ensure field fits appropriately
        self.textMatchField.frame = CGRectMake(16, 0, cell.contentView.bounds.size.width - 32, 44);
        self.textMatchField.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        
        if (!self.textMatchField.superview) {
            [cell.contentView addSubview:self.textMatchField];
        }
    }
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    if (indexPath.section == 0) {
        RCAppPickerViewController *picker = [[RCAppPickerViewController alloc] init];
        
        // Add "Any App" as a custom selection option?
        // Since the user can't clear a selection easily if RCAppPickerViewController only lists apps,
        // we might want a way to reset to "Any App". Let's handle it by adding a custom app row or just 
        // using the standard behavior of the app picker. RCAppPickerViewController doesn't support "Any App".
        // Let's add an option inside RCAppPickerViewController or handle it gracefully.
        // Actually, we can add a way to clear it in a separate button, or just pass a completion block.
        
        __weak typeof(self) weakSelf = self;
        picker.onAppSelected = ^(NSString *name, NSString *bundleId) {
            weakSelf.selectedAppName = name;
            weakSelf.selectedBundleId = bundleId;
            [weakSelf.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:0 inSection:0]] withRowAnimation:UITableViewRowAnimationAutomatic];
        };
        
        [self.navigationController pushViewController:picker animated:YES];
    }
}

// Add a context menu or trailing swipe to easy clear "Any App"?
// Let's add a trailing swipe action to clear the selected app back to "Any App"
- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        UIContextualAction *clearAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"Clear" handler:^(UIContextualAction *action, UIView *sourceView, void (^completionHandler)(BOOL)) {
            self.selectedAppName = @"Any App";
            self.selectedBundleId = @"";
            [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
            completionHandler(YES);
        }];
        clearAction.backgroundColor = [UIColor systemGrayColor];
        
        return [UISwipeActionsConfiguration configurationWithActions:@[clearAction]];
    }
    return nil;
}

- (void)saveTrigger {
    NSString *bundleId = [self.selectedBundleId stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *textMatch = [self.textMatchField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    
    NSString *name;
    if (bundleId.length > 0) {
        if (textMatch.length > 0) {
            name = [NSString stringWithFormat:@"Notification from %@ containing '%@'", self.selectedAppName, textMatch];
        } else {
            name = [NSString stringWithFormat:@"Any Notification from %@", self.selectedAppName];
        }
    } else {
        if (textMatch.length > 0) {
            name = [NSString stringWithFormat:@"Any Notification containing '%@'", textMatch];
        } else {
            name = @"Any Notification";
        }
    }
    
    
    RCConfigManager *config = [RCConfigManager sharedManager];
    NSString *triggerKey = self.triggerKey;
    
    if (!triggerKey) {
        NSString *uniqueId = [[NSUUID UUID].UUIDString substringToIndex:8];
        triggerKey = [NSString stringWithFormat:@"notif_%@", uniqueId];
    }
    
    NSDictionary *notificationEntry = @{
        @"triggerKey": triggerKey,
        @"bundleId": bundleId ?: @"",
        @"textMatch": textMatch ?: @"",
        @"enabled": @YES,
        @"name": name
    };
    
    NSMutableArray *notifTriggers = [[config notificationTriggers] mutableCopy];
    // Remove existing if editing
    for (NSInteger i = 0; i < notifTriggers.count; i++) {
        if ([notifTriggers[i][@"triggerKey"] isEqualToString:triggerKey]) {
            [notifTriggers removeObjectAtIndex:i];
            break;
        }
    }
    [notifTriggers addObject:notificationEntry];
    [config setNotificationTriggers:notifTriggers];
    
    if (self.triggerKey) {
        // Update existing trigger data
        NSDictionary *existingData = [config triggerDataForKey:triggerKey];
        NSMutableDictionary *mutableData = existingData ? [existingData mutableCopy] : [NSMutableDictionary dictionary];
        mutableData[@"name"] = name;
        if (!existingData) {
            mutableData[@"enabled"] = @YES;
            mutableData[@"actions"] = @[];
        }
        [config updateTrigger:triggerKey withData:mutableData];
        
        [self.navigationController popViewControllerAnimated:YES];
    } else {
        // Create new
        NSDictionary *triggerData = @{
            @"name": name,
            @"enabled": @YES,
            @"actions": @[]
        };
        [config updateTrigger:triggerKey withData:triggerData];
        
        // Redirect to action picker
        RCActionsViewController *vc = [[RCActionsViewController alloc] initWithTriggerKey:triggerKey];
        NSMutableArray *vcs = [self.navigationController.viewControllers mutableCopy];
        [vcs removeLastObject]; // Remove self
        [vcs addObject:vc];
        [self.navigationController setViewControllers:vcs animated:YES];
    }
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

@end
