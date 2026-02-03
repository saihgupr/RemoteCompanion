#import "RCTriggersViewController.h"
#import "RCConfigManager.h"
#import "RCActionsViewController.h"
#import "RCSettingsViewController.h"
#import "RCNFCTriggerViewController.h"
#import <notify.h>

#define kSimulateNotificationPrefix "com.pizzaman.rc.simulate."

@interface RCTriggersViewController ()
@property (nonatomic, strong) NSArray<NSArray<NSString *> *> *sections;
@property (nonatomic, strong) NSArray<NSString *> *sectionTitles;
@end

@implementation RCTriggersViewController

// Helper to get short friendly names for command strings
- (NSString *)nameForCommand:(NSString *)cmd truncate:(BOOL)shouldTruncate {
    return [[RCConfigManager sharedManager] nameForCommand:cmd truncate:shouldTruncate];
}

- (NSString *)iconNameForTrigger:(NSString *)triggerKey {
    if ([triggerKey containsString:@"volume"]) return @"speaker.wave.2.fill";
    if ([triggerKey containsString:@"power"]) return @"power";
    if ([triggerKey containsString:@"statusbar"]) return @"hand.draw"; // Status bar / screen gestures
    if ([triggerKey containsString:@"home"]) return @"circle.circle"; // Home button
    if ([triggerKey containsString:@"ringer"]) return @"bell.fill";
    if ([triggerKey containsString:@"edge"]) return @"iphone.homebutton.radiowaves.left.and.right"; // Edge gestures
    if ([triggerKey containsString:@"touchid"]) return @"touchid";
    if ([triggerKey hasPrefix:@"nfc_"]) return @"wave.3.right.circle.fill";
    return @"hand.tap"; // Default
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.navigationController.navigationBar.tintColor = [UIColor labelColor];
    
    // Enable Large Titles
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    self.title = @"RemoteCompanion";
    
    // Use default appearance for translucent blur
    // We do NOT set standardAppearance/scrollEdgeAppearance to opaque here anymore
    
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    
    UIBarButtonItem *settingsItem = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"gear"]
        style:UIBarButtonItemStylePlain
        target:self
        action:@selector(openSettings)];

    UIBarButtonItem *addItem = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"plus"]
        style:UIBarButtonItemStylePlain
        target:self
        action:@selector(addNewItem)];

    self.navigationItem.rightBarButtonItems = @[addItem, settingsItem];
    
    self.tableView.rowHeight = 64;
    self.tableView.rowHeight = 64;
    self.tableView.sectionHeaderTopPadding = 15; // increased padding
    self.tableView.contentInset = UIEdgeInsetsMake(0, 0, 0, 0); // Reset inset since we have large titles handling spacing better now
    
    self.tableView.tableHeaderView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, 0.1)];
    self.tableView.tableHeaderView.clipsToBounds = YES;

    // Edit button will be shown/hidden based on favorites

    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] 
        initWithTarget:self action:@selector(handleLongPress:)];
    longPress.minimumPressDuration = 0.5;
    [self.tableView addGestureRecognizer:longPress];
    
    self.navigationController.toolbarHidden = YES;
    
    // Listen for config changes
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(handleConfigChanged:) 
                                                 name:RCConfigChangedNotification 
                                               object:nil];
                                               
    [self setupFooterView];
}

- (void)setupFooterView {
    UIView *footerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 60)];
    
    // App Title Label
    UILabel *appTitleLabel = [[UILabel alloc] init];
    appTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    appTitleLabel.textAlignment = NSTextAlignmentCenter;
    appTitleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    appTitleLabel.textColor = [UIColor secondaryLabelColor]; // Match opacity of Volume Buttons header
    appTitleLabel.text = @"RemoteCompanion";
    
    // Version Label
    UILabel *versionLabel = [[UILabel alloc] init];
    versionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    versionLabel.textAlignment = NSTextAlignmentCenter;
    versionLabel.font = [UIFont systemFontOfSize:13];
    versionLabel.textColor = [UIColor secondaryLabelColor];
    
    NSDictionary *infoDict = [[NSBundle mainBundle] infoDictionary];
    NSString *version = [infoDict objectForKey:@"CFBundleShortVersionString"];
    versionLabel.text = [NSString stringWithFormat:@"v%@", version];
    
    [footerView addSubview:appTitleLabel];
    [footerView addSubview:versionLabel];
    
    // Add Tap Gesture to Footer Labels
    appTitleLabel.userInteractionEnabled = YES;
    versionLabel.userInteractionEnabled = YES;
    
    UITapGestureRecognizer *titleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(openGitHub)];
    [appTitleLabel addGestureRecognizer:titleTap];
    
    UITapGestureRecognizer *versionTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(openGitHub)];
    [versionLabel addGestureRecognizer:versionTap];
    
    [NSLayoutConstraint activateConstraints:@[
        // Stack Title on top of Version
        [appTitleLabel.centerXAnchor constraintEqualToAnchor:footerView.centerXAnchor],
        [appTitleLabel.topAnchor constraintEqualToAnchor:footerView.topAnchor constant:10],
        [appTitleLabel.heightAnchor constraintEqualToConstant:20],
        
        [versionLabel.centerXAnchor constraintEqualToAnchor:footerView.centerXAnchor],
        [versionLabel.topAnchor constraintEqualToAnchor:appTitleLabel.bottomAnchor constant:0],
        [versionLabel.heightAnchor constraintEqualToConstant:16]
    ]];
    
    self.tableView.tableFooterView = footerView;
}
- (void)handleConfigChanged:(NSNotification *)note {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self reloadTableData];
    });
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadTableData];
}

- (void)reloadTableData {
    NSMutableArray *sections = [NSMutableArray array];
    NSMutableArray *titles = [NSMutableArray array];

    RCConfigManager *config = [RCConfigManager sharedManager];

    // Helper to filter out favorited triggers
    NSArray* (^filterFavorites)(NSArray*) = ^NSArray*(NSArray *keys) {
        return [keys filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *key, NSDictionary *bindings) {
            return ![config isTriggerFavorite:key];
        }]];
    };

    // Get ordered favorites from config
    NSArray *allFavorites = [config orderedFavorites];

    // Add Favorites section at top if there are any
    if (allFavorites.count > 0) {
        [sections addObject:[allFavorites mutableCopy]];
        [titles addObject:@"Favorites"];
    }

    // Standard Sections (filtered to exclude favorites)
    [sections addObject:filterFavorites(@[@"volume_up_hold", @"volume_down_hold", @"volume_both_press"])];
    [titles addObject:@"Volume Buttons"];

    [sections addObject:filterFavorites(@[@"power_double_tap", @"power_triple_click", @"power_quadruple_click", @"power_volume_up", @"power_volume_down", @"power_long_press"])];
    [titles addObject:@"Power Button"];

    [sections addObject:filterFavorites(@[@"trigger_statusbar_left_hold", @"trigger_statusbar_center_hold", @"trigger_statusbar_right_hold", @"trigger_statusbar_swipe_left", @"trigger_statusbar_swipe_right"])];
    [titles addObject:@"Screen Gestures"];

    [sections addObject:filterFavorites(@[@"trigger_edge_left_swipe_up", @"trigger_edge_left_swipe_down", @"trigger_edge_right_swipe_up", @"trigger_edge_right_swipe_down"])];
    [titles addObject:@"Edge Gestures"];

    [sections addObject:filterFavorites(@[@"trigger_home_double_click", @"trigger_home_triple_click", @"trigger_home_quadruple_click", @"touchid_tap", @"touchid_hold"])];
    [titles addObject:@"Home Button"];

    [sections addObject:filterFavorites(@[@"trigger_ringer_mute", @"trigger_ringer_unmute", @"trigger_ringer_toggle"])];
    [titles addObject:@"Ringer Switch"];

    // NFC Section (filtered to exclude favorites)
    NSMutableArray *nfcKeys = [[[RCConfigManager sharedManager] nfcTriggerKeys] mutableCopy];
    NSArray *filteredNFC = filterFavorites(nfcKeys);
    NSMutableArray *nfcWithAdd = [filteredNFC mutableCopy];
    [nfcWithAdd addObject:@"__ADD_NEW_NFC__"];

    [sections addObject:nfcWithAdd];
    [titles addObject:@"NFC Tags"];

    self.sections = sections;
    self.sectionTitles = titles;

    // Show Edit button only when there are favorites
    if (allFavorites.count > 0) {
        self.navigationItem.leftBarButtonItem = self.editButtonItem;
    } else {
        self.navigationItem.leftBarButtonItem = nil;
    }

    [self.tableView reloadData];
}


- (void)setEditing:(BOOL)editing animated:(BOOL)animated {
    [super setEditing:editing animated:animated];
    UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [haptic impactOccurred];
}

- (void)openSettings {
    RCSettingsViewController *settingsVC = [[RCSettingsViewController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:settingsVC];
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)addNewItem {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"New Trigger"
        message:@"Select a trigger type to expand your RemoteCompanion setup."
        preferredStyle:UIAlertControllerStyleActionSheet];
        
    [alert addAction:[UIAlertAction actionWithTitle:@"NFC Tag" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self startNFCScan];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    
    if (alert.popoverPresentationController) {
        alert.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItems.firstObject;
    }
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)startNFCScan {
    RCNFCTriggerViewController *vc = [[RCNFCTriggerViewController alloc] init];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)openGitHub {
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://github.com/saihgupr/RemoteCompanion"] options:@{} completionHandler:nil];
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    
    CGPoint point = [gesture locationInView:self.tableView];
    NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:point];
    
    if (!indexPath) return;
    
    NSString *triggerKey = _sections[indexPath.section][indexPath.row];
    if ([triggerKey isEqualToString:@"__ADD_NEW_NFC__"]) return;
    
    RCConfigManager *config = [RCConfigManager sharedManager];
    NSArray *actions = [config actionsForTrigger:triggerKey];
    
    if (actions.count == 0) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"No Actions"
            message:@"No actions configured for this trigger. Tap to add actions first."
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    
    UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [haptic impactOccurred];
    
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
    [cell setHighlighted:YES animated:YES];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [cell setHighlighted:NO animated:YES];
    });
    
    NSString *notificationName = [NSString stringWithFormat:@"%s%@", kSimulateNotificationPrefix, triggerKey];
    notify_post([notificationName UTF8String]);
}

#pragma mark - Table View Data Source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return _sections.count;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    UIView *headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, 40)];
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(20, 15, tableView.bounds.size.width - 40, 20)];
    label.text = [_sectionTitles[section] uppercaseString];
    label.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];

    // Yellow text for Favorites section
    if ([_sectionTitles[section] isEqualToString:@"Favorites"]) {
        label.textColor = [UIColor systemYellowColor];
    } else {
        label.textColor = [UIColor secondaryLabelColor];
    }

    [headerView addSubview:label];
    return headerView;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return 40.0f;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return _sections[section].count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *triggerKey = _sections[indexPath.section][indexPath.row];
    
    if ([triggerKey isEqualToString:@"__ADD_NEW_NFC__"]) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"AddCell"];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"AddCell"];
        }
        cell.textLabel.text = @"Scan New NFC Tag...";
        cell.textLabel.textColor = [UIColor systemBlueColor];
        cell.imageView.image = [UIImage systemImageNamed:@"plus.circle.fill"];
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.detailTextLabel.text = nil;
        return cell;
    }
    
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"TriggerCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"TriggerCell"];
    }
    
    RCConfigManager *config = [RCConfigManager sharedManager];
    
    cell.textLabel.text = [config displayNameForTrigger:triggerKey];
    cell.textLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightMedium];
    cell.textLabel.textColor = [UIColor labelColor];
    
    // Add Icon with tint based on section or type?
    // Using dark gray tint for a "premium" but subtle look
    UIImage *icon = [UIImage systemImageNamed:[self iconNameForTrigger:triggerKey]];
    cell.imageView.image = icon;
    cell.imageView.tintColor = [UIColor systemGrayColor];

    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    
    // Action names joined by >
    NSArray *actions = [config actionsForTrigger:triggerKey];
    if (actions.count > 0) {
        if (actions.count == 1) {
            cell.detailTextLabel.text = [self nameForCommand:actions.firstObject truncate:NO];
        } else {
            NSMutableArray *shortNames = [NSMutableArray array];
            for (NSString *action in actions) {
                [shortNames addObject:[self nameForCommand:action truncate:YES]];
            }
            cell.detailTextLabel.text = [shortNames componentsJoinedByString:@" > "];
        }
        cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
        // Use Monospace font for commands for better readability of code/IDs
        cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
    } else {
        cell.detailTextLabel.text = @"Not configured";
        cell.detailTextLabel.textColor = [UIColor tertiaryLabelColor];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:13]; // Regular font for placeholder
    }

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    NSString *triggerKey = _sections[indexPath.section][indexPath.row];
    
    if ([triggerKey isEqualToString:@"__ADD_NEW_NFC__"]) {
        [self startNFCScan];
        return;
    }
    
    RCActionsViewController *actionsVC = [[RCActionsViewController alloc] initWithTriggerKey:triggerKey];
    [self.navigationController pushViewController:actionsVC animated:YES];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView leadingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *triggerKey = _sections[indexPath.section][indexPath.row];
    if ([triggerKey isEqualToString:@"__ADD_NEW_NFC__"]) return nil;

    RCConfigManager *config = [RCConfigManager sharedManager];
    BOOL isFavorite = [config isTriggerFavorite:triggerKey];

    UIContextualAction *favoriteAction = [UIContextualAction
        contextualActionWithStyle:UIContextualActionStyleNormal
        title:isFavorite ? @"Unfavorite" : @"Favorite"
        handler:^(UIContextualAction * _Nonnull action, __kindof UIView * _Nonnull sourceView, void (^ _Nonnull completionHandler)(BOOL)) {
            UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
            [haptic impactOccurred];
            [config setTriggerFavorite:!isFavorite forTrigger:triggerKey];
            [self reloadTableData];
            completionHandler(YES);
        }];

    favoriteAction.backgroundColor = isFavorite ? [UIColor systemGrayColor] : [UIColor systemYellowColor];
    favoriteAction.image = [UIImage systemImageNamed:isFavorite ? @"star.slash.fill" : @"star.fill"];

    return [UISwipeActionsConfiguration configurationWithActions:@[favoriteAction]];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *triggerKey = _sections[indexPath.section][indexPath.row];
    // Allow editing for all triggers except the "Add NFC" row
    return ![triggerKey isEqualToString:@"__ADD_NEW_NFC__"];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *triggerKey = _sections[indexPath.section][indexPath.row];

    // Only allow delete for NFC triggers
    if (![triggerKey hasPrefix:@"nfc_"]) {
        return [UISwipeActionsConfiguration configurationWithActions:@[]];
    }

    UIContextualAction *deleteAction = [UIContextualAction
        contextualActionWithStyle:UIContextualActionStyleDestructive
        title:@"Delete"
        handler:^(UIContextualAction * _Nonnull action, __kindof UIView * _Nonnull sourceView, void (^ _Nonnull completionHandler)(BOOL)) {
            [[RCConfigManager sharedManager] removeTrigger:triggerKey];
            [self reloadTableData];
            completionHandler(YES);
        }];

    deleteAction.image = [UIImage systemImageNamed:@"trash.fill"];
    return [UISwipeActionsConfiguration configurationWithActions:@[deleteAction]];
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    return UITableViewCellEditingStyleNone;
}

- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)indexPath {
    return NO;
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    if (_sectionTitles.count > 0 && [_sectionTitles[indexPath.section] isEqualToString:@"Favorites"]) {
        return YES;
    }
    return NO;
}

- (NSIndexPath *)tableView:(UITableView *)tableView targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)sourceIndexPath toProposedIndexPath:(NSIndexPath *)proposedDestinationIndexPath {
    if (sourceIndexPath.section != proposedDestinationIndexPath.section) {
        NSInteger row = (proposedDestinationIndexPath.section < sourceIndexPath.section) ? 0 : [_sections[sourceIndexPath.section] count] - 1;
        return [NSIndexPath indexPathForRow:row inSection:sourceIndexPath.section];
    }
    return proposedDestinationIndexPath;
}

- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)sourceIndexPath toIndexPath:(NSIndexPath *)destinationIndexPath {
    NSMutableArray *favorites = [[RCConfigManager sharedManager] orderedFavorites].mutableCopy;
    NSString *movedItem = favorites[sourceIndexPath.row];
    [favorites removeObjectAtIndex:sourceIndexPath.row];
    [favorites insertObject:movedItem atIndex:destinationIndexPath.row];
    [[RCConfigManager sharedManager] setOrderedFavorites:favorites];

    NSMutableArray *sectionData = [_sections[sourceIndexPath.section] mutableCopy];
    [sectionData removeObjectAtIndex:sourceIndexPath.row];
    [sectionData insertObject:movedItem atIndex:destinationIndexPath.row];

    NSMutableArray *mutableSections = [_sections mutableCopy];
    mutableSections[sourceIndexPath.section] = sectionData;
    _sections = mutableSections;
}

@end
