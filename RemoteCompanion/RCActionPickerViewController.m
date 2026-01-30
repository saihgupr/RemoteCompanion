#import "RCActionPickerViewController.h"

@interface RCActionPickerViewController () <UISearchResultsUpdating>
@property (nonatomic, strong) NSArray<NSString *> *sectionTitles;
@property (nonatomic, strong) NSArray<NSArray<NSDictionary *> *> *sections;
@property (nonatomic, strong) NSArray<NSDictionary *> *filteredActions;
@property (nonatomic, strong) UISearchController *searchController;
@end

@implementation RCActionPickerViewController

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // Elegant grey tint
    self.navigationController.navigationBar.tintColor = [UIColor systemGrayColor];
    
    self.title = @"Select Action";
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    
    // Reduce gap above first section (below search bar)
    self.tableView.tableHeaderView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, CGFLOAT_MIN)];
    if (@available(iOS 15.0, *)) {
        self.tableView.sectionHeaderTopPadding = 0;
    }
    
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
        target:self
        action:@selector(cancel)];
    
    // Setup Search
    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"Search Actions";
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;
    
    // Categories and actions
    // Each action: @{ @"name": display name, @"command": rc command }
    _sectionTitles = @[@"Media", @"Device Controls", @"Connectivity", @"System", @"Audio"];
    
    _sections = @[
        // Media
        @[
            @{ @"name": @"Play", @"command": @"play", @"icon": @"play.fill" },
            @{ @"name": @"Pause", @"command": @"pause", @"icon": @"pause.fill" },
            @{ @"name": @"Volume Down", @"command": @"volume down", @"icon": @"speaker.wave.1.fill" },
            @{ @"name": @"Set Volume...", @"command": @"__SET_VOLUME__", @"icon": @"speaker.wave.3.fill" },
            @{ @"name": @"Set Brightness...", @"command": @"__SET_BRIGHTNESS__", @"icon": @"sun.max.fill" },
            @{ @"name": @"Next Track", @"command": @"next", @"icon": @"forward.fill" },
            @{ @"name": @"Previous Track", @"command": @"prev", @"icon": @"backward.fill" },
            @{ @"name": @"Play/Pause Toggle", @"command": @"playpause", @"icon": @"playpause.fill" },
            @{ @"name": @"Volume Up", @"command": @"volume up", @"icon": @"speaker.wave.3.fill" },
            @{ @"name": @"Volume Down", @"command": @"volume down", @"icon": @"speaker.wave.1.fill" }
        ],
        // Device Controls
        @[
            @{ @"name": @"Flashlight Toggle", @"command": @"flashlight toggle", @"icon": @"flashlight.on.fill" },
            @{ @"name": @"Flashlight On", @"command": @"flashlight on", @"icon": @"flashlight.on.fill" },
            @{ @"name": @"Flashlight Off", @"command": @"flashlight off", @"icon": @"flashlight.off.fill" },
            @{ @"name": @"Rotate Lock", @"command": @"rotate lock", @"icon": @"lock.rotation" },
            @{ @"name": @"Rotate Unlock", @"command": @"rotate unlock", @"icon": @"lock.rotation.open" },
            @{ @"name": @"Rotate Toggle", @"command": @"rotate toggle", @"icon": @"lock.rotation" }
        ],
        // Connectivity
        @[
            @{ @"name": @"WiFi On", @"command": @"wifi on", @"icon": @"wifi" },
            @{ @"name": @"WiFi Off", @"command": @"wifi off", @"icon": @"wifi.slash" },
            @{ @"name": @"WiFi Toggle", @"command": @"wifi toggle", @"icon": @"wifi" },
            @{ @"name": @"Bluetooth On", @"command": @"bluetooth on", @"icon": @"bolt.horizontal.fill" },
            @{ @"name": @"Bluetooth Off", @"command": @"bluetooth off", @"icon": @"bolt.horizontal" },
            @{ @"name": @"Bluetooth Toggle", @"command": @"bluetooth toggle", @"icon": @"bolt.horizontal.fill" },
            @{ @"name": @"Airplane Mode On", @"command": @"airplane on", @"icon": @"airplane" },
            @{ @"name": @"Airplane Mode Off", @"command": @"airplane off", @"icon": @"airplane" },
            @{ @"name": @"Airplane Mode Toggle", @"command": @"airplane toggle", @"icon": @"airplane" },
            @{ @"name": @"Connect Bluetooth...", @"command": @"__BT_CONNECT__", @"icon": @"link" },
            @{ @"name": @"Disconnect Bluetooth...", @"command": @"__BT_DISCONNECT__", @"icon": @"xmark.circle" },
            @{ @"name": @"Connect AirPlay...", @"command": @"__AIRPLAY_CONNECT__", @"icon": @"airplayaudio" },
            @{ @"name": @"Disconnect AirPlay", @"command": @"airplay disconnect", @"icon": @"airplayaudio.badge.exclamationmark" }
        ],
        // System
        @[
            @{ @"name": @"Haptic Feedback", @"command": @"haptic", @"icon": @"hand.tap.fill" },
            @{ @"name": @"Screenshot", @"command": @"screenshot", @"icon": @"camera.fill" },
            @{ @"name": @"Run Shortcut...", @"command": @"__SHORTCUT_PICKER__", @"icon": @"command" },
            @{ @"name": @"Open App...", @"command": @"__OPEN_APP__", @"icon": @"square.grid.2x2.fill" },
            @{ @"name": @"Lock Device", @"command": @"lock", @"icon": @"lock.fill" },
            @{ @"name": @"Do Not Disturb On", @"command": @"dnd on", @"icon": @"moon.fill" },
            @{ @"name": @"Do Not Disturb Off", @"command": @"dnd off", @"icon": @"moon" },
            @{ @"name": @"Do Not Disturb Toggle", @"command": @"dnd toggle", @"icon": @"moon.circle.fill" },
            @{ @"name": @"Respring Device", @"command": @"respring", @"icon": @"memories" },
            @{ @"name": @"Lock Status", @"command": @"lock status", @"icon": @"lock.circle" },
            @{ @"name": @"Low Power Mode On", @"command": @"low power on", @"icon": @"battery.25" },
            @{ @"name": @"Low Power Mode Off", @"command": @"low power off", @"icon": @"battery.100" },
            @{ @"name": @"Low Power Mode Toggle", @"command": @"low power toggle", @"icon": @"battery.25" },
            @{ @"name": @"Custom Lua Script...", @"command": @"__LUA_SCRIPT__", @"icon": @"scroll.fill" },
            @{ @"name": @"Delay", @"command": @"__DELAY__", @"icon": @"timer" },
            @{ @"name": @"Custom Command...", @"command": @"__CUSTOM__", @"icon": @"terminal.fill" }
        ],
        // Audio (ANC)
        @[
            @{ @"name": @"ANC On", @"command": @"anc on", @"icon": @"ear.badge.checkmark" },
            @{ @"name": @"ANC Off", @"command": @"anc off", @"icon": @"ear" },
            @{ @"name": @"Transparency Mode", @"command": @"anc transparency", @"icon": @"waveform.circle.fill" }
        ]
    ];
    
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"ActionCell"];
    self.tableView.rowHeight = 48;
}

- (void)cancel {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Table View Data Source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    if (self.searchController.isActive && self.searchController.searchBar.text.length > 0) {
        return 1;
    }
    return _sections.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (self.searchController.isActive && self.searchController.searchBar.text.length > 0) {
        return @"Search Results";
    }
    return _sectionTitles[section];
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return 30.0f;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (self.searchController.isActive && self.searchController.searchBar.text.length > 0) {
        return self.filteredActions.count;
    }
    return _sections[section].count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ActionCell" forIndexPath:indexPath];
    
    NSDictionary *action;
    if (self.searchController.isActive && self.searchController.searchBar.text.length > 0) {
        action = self.filteredActions[indexPath.row];
    } else {
        action = _sections[indexPath.section][indexPath.row];
    }
    cell.textLabel.text = action[@"name"];
    cell.textLabel.font = [UIFont systemFontOfSize:17];
    
    if (action[@"icon"]) {
        cell.imageView.image = [UIImage systemImageNamed:action[@"icon"]];
        cell.imageView.tintColor = [UIColor secondaryLabelColor];
    }
    
    cell.accessoryType = UITableViewCellAccessoryNone;
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    NSDictionary *action;
    if (self.searchController.isActive && self.searchController.searchBar.text.length > 0) {
        action = self.filteredActions[indexPath.row];
    } else {
        action = _sections[indexPath.section][indexPath.row];
    }
    NSString *command = action[@"command"];
    


    if ([command isEqualToString:@"__SET_VOLUME__"] || [command isEqualToString:@"__SET_BRIGHTNESS__"]) {
        [self handleValueInputForCommand:command];
        return; // Don't dismiss yet
    }
    
    // Existing special handlers

    
    if (self.onActionSelected) {
        self.onActionSelected(command);
    }
    
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)handleValueInputForCommand:(NSString *)commandPlaceholder {
    NSString *title = [commandPlaceholder isEqualToString:@"__SET_VOLUME__"] ? @"Set Volume" : @"Set Brightness";
    NSString *prefix = [commandPlaceholder isEqualToString:@"__SET_VOLUME__"] ? @"set-vol" : @"brightness";
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title 
                                                                   message:@"Enter a value (0-100)" 
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.keyboardType = UIKeyboardTypeNumberPad;
        textField.placeholder = @"50";
        textField.textAlignment = NSTextAlignmentCenter;
    }];
    
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"Set" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        UITextField *textField = alert.textFields.firstObject;
        NSString *value = textField.text;
        // Basic validation
        int val = [value intValue];
        if (val < 0) val = 0;
        if (val > 100) val = 100;
        
        NSString *finalCommand = [NSString stringWithFormat:@"%@ %d", prefix, val];
        
        if (self.onActionSelected) {
            self.onActionSelected(finalCommand);
        }
        [self dismissViewControllerAnimated:YES completion:nil];
    }];
    
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
        [self.tableView deselectRowAtIndexPath:[self.tableView indexPathForSelectedRow] animated:YES];
    }];
    
    [alert addAction:cancelAction];
    [alert addAction:okAction];
    
    [self presentViewController:alert animated:YES completion:nil];
}



#pragma mark - Search

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSString *text = searchController.searchBar.text;
    if (text.length == 0) {
        self.filteredActions = @[];
    } else {
        NSMutableArray *allActions = [NSMutableArray array];
        for (NSArray *section in self.sections) {
            [allActions addObjectsFromArray:section];
        }
        
        NSPredicate *pred = [NSPredicate predicateWithFormat:@"name CONTAINS[cd] %@ OR command CONTAINS[cd] %@", text, text];
        self.filteredActions = [allActions filteredArrayUsingPredicate:pred];
    }
    [self.tableView reloadData];
}

@end
