#import "RCMQTTSettingsViewController.h"
#import "RCConfigManager.h"
#import "RCUITweaker.h"
#import "RCMQTTClient.h"

@interface RCMQTTSettingsViewController ()
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISwitch *masterSwitch;
@end

@implementation RCMQTTSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.title = @"MQTT";
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    self.navigationController.navigationBar.tintColor = [UIColor labelColor];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.rowHeight = 50;
    
    if (@available(iOS 15.0, *)) {
        self.tableView.sectionHeaderTopPadding = 10;
    }
    
    [self.view addSubview:self.tableView];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
    
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(handleTweaksChanged:) 
                                                 name:@"RCConfigTweaksChangedNotification" 
                                               object:nil];
    [self applyTweaks];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)handleTweaksChanged:(NSNotification *)note {
    [self applyTweaks];
}

- (void)applyTweaks {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    CGFloat mainBG = [cm tweakValueForKey:@"mainBackground" defaultVal:0.09];
    UIColor *settingsBG = [cm tweakColorForKey:@"settingsBackground" defaultVal:mainBG];
    self.view.backgroundColor = settingsBG;
    self.tableView.backgroundColor = settingsBG;
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

#pragma mark - Table View Data Source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) {
        return 1;
    }
    return [RCConfigManager sharedManager].mqttEnabled ? 7 : 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 1 && [RCConfigManager sharedManager].mqttEnabled) {
        return @"Broker Details";
    }
    return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) {
        return @"Enable MQTT integration to publish topics and trigger smart home or IoT automations directly.";
    }
    if (section == 1 && [RCConfigManager sharedManager].mqttEnabled) {
        return @"Configure your MQTT broker host, port, and optional credentials. Standard MQTT 3.1.1 protocol is used.";
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    
    UITableViewCellStyle style = UITableViewCellStyleDefault;
    if (indexPath.section == 1 && indexPath.row < 6) {
        style = UITableViewCellStyleValue1;
    }
    
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:style reuseIdentifier:nil];
    cell.backgroundColor = [cm tweakColorForKey:@"blockBackground" defaultVal:0.12];
    
    UIView *selBg = [[UIView alloc] init];
    selBg.backgroundColor = [cm tweakColorForKey:@"selectionHighlight" defaultVal:0.15];
    cell.selectedBackgroundView = selBg;

    cell.layer.borderColor = [cm tweakColorForKey:@"borders" defaultVal:0.14].CGColor;
    cell.layer.borderWidth = 1.0;
    cell.contentView.backgroundColor = [UIColor clearColor];
    cell.layer.masksToBounds = YES;
    cell.textLabel.textColor = [UIColor labelColor];
    if (cell.detailTextLabel) {
        cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    }
    
    if (indexPath.section == 0) {
        cell.textLabel.text = @"Enable MQTT";
        _masterSwitch = [[UISwitch alloc] init];
        _masterSwitch.on = cm.mqttEnabled;
        [_masterSwitch addTarget:self action:@selector(mqttToggleChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = _masterSwitch;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else {
        switch (indexPath.row) {
            case 0:
                cell.textLabel.text = @"Broker Host";
                cell.detailTextLabel.text = cm.mqttHost.length ? cm.mqttHost : @"192.168.1.50";
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                break;
            case 1:
                cell.textLabel.text = @"Port";
                cell.detailTextLabel.text = [NSString stringWithFormat:@"%ld", (long)(cm.mqttPort > 0 ? cm.mqttPort : 1883)];
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                break;
            case 2:
                cell.textLabel.text = @"Client ID";
                cell.detailTextLabel.text = cm.mqttClientId.length ? cm.mqttClientId : @"RemoteCompanion";
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                break;
            case 3:
                cell.textLabel.text = @"Username";
                cell.detailTextLabel.text = cm.mqttUser.length ? cm.mqttUser : @"Optional";
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                break;
            case 4:
                cell.textLabel.text = @"Password";
                cell.detailTextLabel.text = cm.mqttPassword.length ? @"••••••••" : @"Optional";
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                break;
            case 5:
                cell.textLabel.text = @"Topic Prefix";
                cell.detailTextLabel.text = cm.mqttTopicPrefix.length ? cm.mqttTopicPrefix : @"remotecompanion";
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                break;
            case 6:
                cell.textLabel.text = @"Test Connection";
                cell.textLabel.textColor = [UIColor systemGreenColor];
                cell.imageView.image = [UIImage systemImageNamed:@"bolt.fill"];
                cell.imageView.tintColor = [UIColor systemGreenColor];
                break;
        }
    }
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 1) {
        switch (indexPath.row) {
            case 0: [self editHost]; break;
            case 1: [self editPort]; break;
            case 2: [self editClientId]; break;
            case 3: [self editUser]; break;
            case 4: [self editPassword]; break;
            case 5: [self editTopicPrefix]; break;
            case 6: [self testConnection]; break;
        }
    }
}

#pragma mark - Actions & Configuration Dialogs

- (void)mqttToggleChanged:(UISwitch *)sender {
    [RCConfigManager sharedManager].mqttEnabled = sender.on;
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:1] withRowAnimation:UITableViewRowAnimationAutomatic];
}

- (void)editHost {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"MQTT Broker Host" message:@"Enter IP address or hostname of your MQTT broker:" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"192.168.1.50 or broker.local";
        tf.text = cm.mqttHost;
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        cm.mqttHost = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:1] withRowAnimation:UITableViewRowAnimationNone];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)editPort {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"MQTT Port" message:@"Enter the port number of your MQTT broker (default: 1883):" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"1883";
        tf.text = [NSString stringWithFormat:@"%ld", (long)(cm.mqttPort > 0 ? cm.mqttPort : 1883)];
        tf.keyboardType = UIKeyboardTypeNumberPad;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSInteger port = [alert.textFields.firstObject.text integerValue];
        cm.mqttPort = port > 0 ? port : 1883;
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:1] withRowAnimation:UITableViewRowAnimationNone];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)editClientId {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"MQTT Client ID" message:@"Enter unique client identifier for this device:" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"RemoteCompanion";
        tf.text = cm.mqttClientId;
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        cm.mqttClientId = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:1] withRowAnimation:UITableViewRowAnimationNone];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)editUser {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"MQTT Username" message:@"Enter optional broker username:" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"Optional";
        tf.text = cm.mqttUser;
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        cm.mqttUser = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:1] withRowAnimation:UITableViewRowAnimationNone];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)editPassword {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"MQTT Password" message:@"Enter optional broker password:" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"Optional";
        tf.text = cm.mqttPassword;
        tf.secureTextEntry = YES;
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        cm.mqttPassword = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:1] withRowAnimation:UITableViewRowAnimationNone];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)editTopicPrefix {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Default Topic Prefix" message:@"Enter default topic prefix for published events:" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"remotecompanion";
        tf.text = cm.mqttTopicPrefix;
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        cm.mqttTopicPrefix = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:1] withRowAnimation:UITableViewRowAnimationNone];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)testConnection {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    if (!cm.mqttHost.length) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Missing Configuration" message:@"Please configure Broker Host first." preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    
    UIAlertController *loading = [UIAlertController alertControllerWithTitle:@"Testing Connection..." message:@"Connecting to MQTT Broker..." preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:loading animated:YES completion:nil];
    
    NSString *host = cm.mqttHost;
    NSInteger port = cm.mqttPort > 0 ? cm.mqttPort : 1883;
    NSString *user = cm.mqttUser;
    NSString *pass = cm.mqttPassword;
    NSString *clientId = cm.mqttClientId.length ? cm.mqttClientId : @"RemoteCompanion-Test";
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSError *err = nil;
        BOOL success = [RCMQTTClient testConnectionToHost:host port:port user:user pass:pass clientId:clientId error:&err];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [loading dismissViewControllerAnimated:YES completion:^{
                if (success) {
                    UIAlertController *ok = [UIAlertController alertControllerWithTitle:@"Connection Successful" message:[NSString stringWithFormat:@"Connected to MQTT broker (%@:%ld) successfully!", host, (long)port] preferredStyle:UIAlertControllerStyleAlert];
                    [ok addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                    [self presentViewController:ok animated:YES completion:nil];
                } else {
                    UIAlertController *fail = [UIAlertController alertControllerWithTitle:@"Connection Failed" message:err.localizedDescription ?: @"Could not connect to MQTT broker" preferredStyle:UIAlertControllerStyleAlert];
                    [fail addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                    [self presentViewController:fail animated:YES completion:nil];
                }
            }];
        });
    });
}

@end
