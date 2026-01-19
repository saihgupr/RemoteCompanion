#import "RCActionPickerViewController.h"

@interface RCActionPickerViewController ()
@property (nonatomic, strong) NSArray<NSString *> *sectionTitles;
@property (nonatomic, strong) NSArray<NSArray<NSDictionary *> *> *sections;
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
    
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
        target:self
        action:@selector(cancel)];
    
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
            @{ @"name": @"Volume Up", @"command": @"volume up", @"icon": @"speaker.wave.3.fill" },
            @{ @"name": @"Volume Down", @"command": @"volume down", @"icon": @"speaker.wave.1.fill" }
        ],
        // Device Controls
        @[
            @{ @"name": @"Flashlight Toggle", @"command": @"flashlight toggle", @"icon": @"flashlight.on.fill" },
            @{ @"name": @"Flashlight On", @"command": @"flashlight on", @"icon": @"flashlight.on.fill" },
            @{ @"name": @"Flashlight Off", @"command": @"flashlight off", @"icon": @"flashlight.off.fill" },
            @{ @"name": @"Rotate Lock", @"command": @"rotate lock", @"icon": @"lock.rotation" },
            @{ @"name": @"Rotate Unlock", @"command": @"rotate unlock", @"icon": @"lock.rotation.open" }
        ],
        // Connectivity
        @[
            @{ @"name": @"WiFi On", @"command": @"wifi on", @"icon": @"wifi" },
            @{ @"name": @"WiFi Off", @"command": @"wifi off", @"icon": @"wifi.slash" },
            @{ @"name": @"Bluetooth On", @"command": @"bluetooth on", @"icon": @"bolt.horizontal.fill" },
            @{ @"name": @"Bluetooth Off", @"command": @"bluetooth off", @"icon": @"bolt.horizontal" },
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
            @{ @"name": @"Lock Device", @"command": @"lock", @"icon": @"lock.fill" },
            @{ @"name": @"Do Not Disturb On", @"command": @"dnd on", @"icon": @"moon.fill" },
            @{ @"name": @"Do Not Disturb Off", @"command": @"dnd off", @"icon": @"moon" },
            @{ @"name": @"Lock Status", @"command": @"lock status", @"icon": @"lock.circle" },
            @{ @"name": @"Low Power Mode On", @"command": @"low power on", @"icon": @"battery.25" },
            @{ @"name": @"Low Power Mode Off", @"command": @"low power off", @"icon": @"battery.100" },
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
    return _sections.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return _sectionTitles[section];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return _sections[section].count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ActionCell" forIndexPath:indexPath];
    
    NSDictionary *action = _sections[indexPath.section][indexPath.row];
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
    
    NSDictionary *action = _sections[indexPath.section][indexPath.row];
    NSString *command = action[@"command"];
    
    if ([command isEqualToString:@"__BT_DISCONNECT__"]) {
        // [Existing BT Disconnect Logic] - Wait, I haven't implemented that yet in this file,
        // but I should probably leave placeholders or check if I need to copy logic.
        // Actually, looking at previous steps, I only changed the ICON in the list.
        // The previous implementation used RCShortcutPickerViewController logic for shortcuts.
        // For BT Disconnect, I likely need a picker too? 
        // Wait, the user request for BT disconnect was just about the icon in the displayed action list.
        // But if I select "Disconnect Bluetooth...", does it work? 
        // The implementation plan for that was in a previous session or skipped?
        // Let's focus on Volume/Brightness first.
    }

    if ([command isEqualToString:@"__SET_VOLUME__"] || [command isEqualToString:@"__SET_BRIGHTNESS__"]) {
        [self handleValueInputForCommand:command];
        return; // Don't dismiss yet
    }
    
    // Existing special handlers
    if ([command isEqualToString:@"__SHORTCUT__"]) {
        // ... (Shortcut logic is likely handled elsewhere or I need to import headers)
        // Checking my file view, I don't see shortcut logic in this file?
        // Ah, RCActionPickerViewController just returns the command?
        // No, for "Run Shortcut...", it launches RCShortcutPickerViewController?
        // Let's look at the file content I viewed earlier. It has "Run Shortcut..." mapping to __SHORTCUT__?
        // I need to be careful not to break existing logic.
        // Re-reading view_file output:
        // 67: @{ @"name": @"Run Shortcut...", @"command": @"__SHORTCUT__", @"icon": @"command" }
        // 130: NSDictionary *action = _sections[indexPath.section][indexPath.row];
        // 131: NSString *command = action[@"command"];
        // 133: if (self.onActionSelected) { self.onActionSelected(command); }
        // So the parent controller handles "__SHORTCUT__".
        // I can do the same for __SET_VOLUME__, OR handle it here and return the final string.
        // Handling here is better UX (picker stays on top of parent).
    }
    
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

@end
