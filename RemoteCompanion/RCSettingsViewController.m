#import "RCSettingsViewController.h"
#import "RCConfigManager.h"
#import "RCUITweaker.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface RCSettingsViewController () <UIDocumentPickerDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UILabel *versionLabel;
@property (nonatomic, strong) UILabel *appTitleLabel;
@property (nonatomic, strong) UISwitch *masterSwitch;
@property (nonatomic, strong) UISwitch *nfcSwitch;
@property (nonatomic, strong) UISwitch *webUISwitch;
@property (nonatomic, strong) UISwitch *haSwitch;
@property (nonatomic, strong) UISwitch *kmSwitch;
@end

typedef NS_ENUM(NSInteger, RCIntegrationRowType) {
    RCIntegrationRowHAHeader,
    RCIntegrationRowHAUrl,
    RCIntegrationRowHAToken,
    RCIntegrationRowHATest,
    RCIntegrationRowKMHeader,
    RCIntegrationRowKMUrl,
    RCIntegrationRowKMUser,
    RCIntegrationRowKMPassword,
    RCIntegrationRowKMTest
};

@implementation RCSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.title = @"Settings";
    
    // Enable Large Titles
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    self.navigationController.navigationBar.tintColor = [UIColor labelColor];

    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    
    // Close button
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(dismissSettings)];
    
    // Setup Table View
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.rowHeight = 50;
    
    // Improved Section Spacing
    if (@available(iOS 15.0, *)) {
        self.tableView.sectionHeaderTopPadding = 10;
    }
    
    [self.view addSubview:self.tableView];
    
    // Setup App Title Label (Sticky Bottom)
    UILabel *appTitleLabel = [[UILabel alloc] init];
    appTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    appTitleLabel.textAlignment = NSTextAlignmentCenter;
    appTitleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    appTitleLabel.textColor = [UIColor secondaryLabelColor];
    appTitleLabel.text = @"RemoteCompanion";
    [self.view addSubview:appTitleLabel];

    // Setup Version Label (Sticky Bottom)
    UILabel *versionLabel = [[UILabel alloc] init];
    versionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    versionLabel.textAlignment = NSTextAlignmentCenter;
    versionLabel.font = [UIFont systemFontOfSize:13];
    versionLabel.textColor = [UIColor secondaryLabelColor];
    
    NSDictionary *infoDict = [[NSBundle mainBundle] infoDictionary];
    NSString *version = [infoDict objectForKey:@"CFBundleShortVersionString"];
    versionLabel.text = [NSString stringWithFormat:@"v%@", version];
    [self.view addSubview:versionLabel];
    
    // Add Tap Gesture to Footer Labels
    appTitleLabel.userInteractionEnabled = YES;
    versionLabel.userInteractionEnabled = YES;
    
    UITapGestureRecognizer *titleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(openGitHub)];
    [appTitleLabel addGestureRecognizer:titleTap];
    
    UITapGestureRecognizer *versionTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(openGitHub)];
    [versionLabel addGestureRecognizer:versionTap];
    
    // Constraints for Sticky Footer
    [NSLayoutConstraint activateConstraints:@[
        [versionLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [versionLabel.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-10],
        
        [appTitleLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [appTitleLabel.bottomAnchor constraintEqualToAnchor:versionLabel.topAnchor constant:-2]
    ]];
    
    // Constraints
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        // The table view ends above the footer labels
        [self.tableView.bottomAnchor constraintEqualToAnchor:appTitleLabel.topAnchor constant:-10]
    ]];
    
    // Listen for color tweak changes
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(handleTweaksChanged:) 
                                                 name:@"RCConfigTweaksChangedNotification" 
                                               object:nil];
    [self applyTweaks];
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

- (void)dismissSettings {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (NSArray<NSNumber *> *)rowsForIntegrationsSection {
    NSMutableArray *rows = [NSMutableArray array];
    [rows addObject:@(RCIntegrationRowHAHeader)];
    if ([RCConfigManager sharedManager].haEnabled) {
        [rows addObject:@(RCIntegrationRowHAUrl)];
        [rows addObject:@(RCIntegrationRowHAToken)];
        [rows addObject:@(RCIntegrationRowHATest)];
    }
    [rows addObject:@(RCIntegrationRowKMHeader)];
    if ([RCConfigManager sharedManager].kmEnabled) {
        [rows addObject:@(RCIntegrationRowKMUrl)];
        [rows addObject:@(RCIntegrationRowKMUser)];
        [rows addObject:@(RCIntegrationRowKMPassword)];
        [rows addObject:@(RCIntegrationRowKMTest)];
    }
    return rows;
}

#pragma mark - Table View Data Source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 3;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    NSString *title;
    if (section == 0) title = @"General";
    else if (section == 1) title = @"Integrations";
    else title = @"Backup";
    
    UIView *headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, 40)];
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(20, 15, tableView.bounds.size.width - 40, 20)];
    label.text = [title uppercaseString];
    label.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    label.textColor = [UIColor secondaryLabelColor];
    [headerView addSubview:label];
    return headerView;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return 40.0f;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) {
        return nil;
    } else if (section == 1) {
        return @"Configure connections to Home Assistant and Keyboard Maestro Web Server.";
    } else if (section == 2) {
        return @"Export your configuration to share or backup. Import to restore.";
    }
    return nil;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 3; // Master + NFC + WebUI
    if (section == 1) return [self rowsForIntegrationsSection].count;
    return 2; // Export, Import
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    
    UITableViewCellStyle style = UITableViewCellStyleDefault;
    if (indexPath.section == 1) {
        NSInteger rowType = [[self rowsForIntegrationsSection][indexPath.row] integerValue];
        if (rowType == RCIntegrationRowHAUrl || rowType == RCIntegrationRowHAToken ||
            rowType == RCIntegrationRowKMUrl || rowType == RCIntegrationRowKMUser ||
            rowType == RCIntegrationRowKMPassword) {
            style = UITableViewCellStyleValue1;
        }
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
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Enable All Triggers";
            _masterSwitch = [[UISwitch alloc] init];
            _masterSwitch.on = cm.masterEnabled;
            [_masterSwitch addTarget:self action:@selector(masterToggleChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = _masterSwitch;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"NFC Scanning";
            _nfcSwitch = [[UISwitch alloc] init];
            _nfcSwitch.on = cm.nfcEnabled;
            [_nfcSwitch addTarget:self action:@selector(nfcToggleChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = _nfcSwitch;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else if (indexPath.row == 2) {
            cell.textLabel.text = @"Web UI";
            _webUISwitch = [[UISwitch alloc] init];
            _webUISwitch.on = cm.webUIEnabled;
            [_webUISwitch addTarget:self action:@selector(webUIToggleChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = _webUISwitch;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        }
    } else if (indexPath.section == 1) {
        NSInteger rowType = [[self rowsForIntegrationsSection][indexPath.row] integerValue];
        switch (rowType) {
            case RCIntegrationRowHAHeader:
                cell.textLabel.text = @"Home Assistant";
                _haSwitch = [[UISwitch alloc] init];
                _haSwitch.on = cm.haEnabled;
                [_haSwitch addTarget:self action:@selector(haToggleChanged:) forControlEvents:UIControlEventValueChanged];
                cell.accessoryView = _haSwitch;
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
                break;
            case RCIntegrationRowHAUrl:
                cell.textLabel.text = @"Server URL";
                cell.detailTextLabel.text = cm.haUrl.length ? cm.haUrl : @"Not Configured";
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                break;
            case RCIntegrationRowHAToken:
                cell.textLabel.text = @"Access Token";
                cell.detailTextLabel.text = cm.haToken.length ? @"••••••••" : @"Not Configured";
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                break;
            case RCIntegrationRowHATest:
                cell.textLabel.text = @"Test Connection";
                cell.textLabel.textColor = [UIColor systemGreenColor];
                cell.imageView.image = [UIImage systemImageNamed:@"bolt.fill"];
                cell.imageView.tintColor = [UIColor systemGreenColor];
                break;
            case RCIntegrationRowKMHeader:
                cell.textLabel.text = @"Keyboard Maestro";
                _kmSwitch = [[UISwitch alloc] init];
                _kmSwitch.on = cm.kmEnabled;
                [_kmSwitch addTarget:self action:@selector(kmToggleChanged:) forControlEvents:UIControlEventValueChanged];
                cell.accessoryView = _kmSwitch;
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
                break;
            case RCIntegrationRowKMUrl:
                cell.textLabel.text = @"Web Server URL";
                cell.detailTextLabel.text = cm.kmUrl.length ? cm.kmUrl : @"http://192.168.1.50:4490";
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                break;
            case RCIntegrationRowKMUser:
                cell.textLabel.text = @"Username";
                cell.detailTextLabel.text = cm.kmUser.length ? cm.kmUser : @"Optional";
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                break;
            case RCIntegrationRowKMPassword:
                cell.textLabel.text = @"Password";
                cell.detailTextLabel.text = cm.kmPassword.length ? @"••••••••" : @"Optional";
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                break;
            case RCIntegrationRowKMTest:
                cell.textLabel.text = @"Test Connection";
                cell.textLabel.textColor = [UIColor systemGreenColor];
                cell.imageView.image = [UIImage systemImageNamed:@"bolt.fill"];
                cell.imageView.tintColor = [UIColor systemGreenColor];
                break;
        }
    } else {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Export Configuration";
            cell.imageView.image = [UIImage systemImageNamed:@"square.and.arrow.up"];
            cell.imageView.tintColor = [UIColor systemBlueColor];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else {
            cell.textLabel.text = @"Import Configuration";
            cell.imageView.image = [UIImage systemImageNamed:@"square.and.arrow.down"];
            cell.imageView.tintColor = [UIColor systemGreenColor];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
    }
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == 1) {
        NSInteger rowType = [[self rowsForIntegrationsSection][indexPath.row] integerValue];
        switch (rowType) {
            case RCIntegrationRowHAUrl:
                [self editHAUrl];
                break;
            case RCIntegrationRowHAToken:
                [self editHAToken];
                break;
            case RCIntegrationRowHATest:
                [self testHAConnection];
                break;
            case RCIntegrationRowKMUrl:
                [self editKMUrl];
                break;
            case RCIntegrationRowKMUser:
                [self editKMUser];
                break;
            case RCIntegrationRowKMPassword:
                [self editKMPassword];
                break;
            case RCIntegrationRowKMTest:
                [self testKMConnection];
                break;
            default:
                break;
        }
    } else if (indexPath.section == 2) {
        if (indexPath.row == 0) {
            [self exportConfig];
        } else {
            [self importConfig];
        }
    }
}

#pragma mark - Integration Editors

- (void)haToggleChanged:(UISwitch *)sender {
    [RCConfigManager sharedManager].haEnabled = sender.on;
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:1] withRowAnimation:UITableViewRowAnimationAutomatic];
}

- (void)kmToggleChanged:(UISwitch *)sender {
    [RCConfigManager sharedManager].kmEnabled = sender.on;
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:1] withRowAnimation:UITableViewRowAnimationAutomatic];
}

- (void)editHAUrl {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Home Assistant URL" message:@"Enter the full base URL of your Home Assistant instance:" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"http://192.168.1.100:8123";
        tf.text = cm.haUrl;
        tf.keyboardType = UIKeyboardTypeURL;
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        cm.haUrl = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:1] withRowAnimation:UITableViewRowAnimationNone];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)editHAToken {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Long-Lived Access Token" message:@"Paste the access token generated from your Home Assistant profile:" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"eyJhbGciOiJIUzI1Ni...";
        tf.text = cm.haToken;
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        cm.haToken = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:1] withRowAnimation:UITableViewRowAnimationNone];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)testHAConnection {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    if (!cm.haUrl.length || !cm.haToken.length) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Missing Configuration" message:@"Please configure Server URL and Access Token first." preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    
    UIAlertController *loading = [UIAlertController alertControllerWithTitle:@"Testing Connection..." message:@"Connecting to Home Assistant..." preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:loading animated:YES completion:nil];
    
    NSString *base = cm.haUrl;
    if ([base hasSuffix:@"/"]) base = [base substringToIndex:base.length - 1];
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@/api/", base]];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.timeoutInterval = 6.0;
    [req setValue:[NSString stringWithFormat:@"Bearer %@", cm.haToken] forHTTPHeaderField:@"Authorization"];
    
    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *res, NSError *err) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [loading dismissViewControllerAnimated:YES completion:^{
                NSHTTPURLResponse *httpRes = (NSHTTPURLResponse *)res;
                if (!err && httpRes.statusCode == 200) {
                    UIAlertController *ok = [UIAlertController alertControllerWithTitle:@"Connection Successful" message:@"Connected to Home Assistant successfully!" preferredStyle:UIAlertControllerStyleAlert];
                    [ok addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                    [self presentViewController:ok animated:YES completion:nil];
                } else {
                    NSString *msg = err ? err.localizedDescription : [NSString stringWithFormat:@"Server returned HTTP status %ld", (long)httpRes.statusCode];
                    UIAlertController *fail = [UIAlertController alertControllerWithTitle:@"Connection Failed" message:msg preferredStyle:UIAlertControllerStyleAlert];
                    [fail addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                    [self presentViewController:fail animated:YES completion:nil];
                }
            }];
        });
    }] resume];
}

- (void)editKMUrl {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Keyboard Maestro Server URL" message:@"Enter the Web Server URL from Keyboard Maestro Preferences (e.g. http://192.168.1.50:4490):" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"http://192.168.1.50:4490";
        tf.text = cm.kmUrl;
        tf.keyboardType = UIKeyboardTypeURL;
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        cm.kmUrl = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:1] withRowAnimation:UITableViewRowAnimationNone];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)editKMUser {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Keyboard Maestro Username" message:@"Enter the optional username configured in Keyboard Maestro Web Server preferences:" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"Optional";
        tf.text = cm.kmUser;
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        cm.kmUser = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:1] withRowAnimation:UITableViewRowAnimationNone];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)editKMPassword {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Keyboard Maestro Password" message:@"Enter the optional password configured in Keyboard Maestro Web Server preferences:" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"Optional";
        tf.text = cm.kmPassword;
        tf.secureTextEntry = YES;
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        cm.kmPassword = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:1] withRowAnimation:UITableViewRowAnimationNone];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)testKMConnection {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    if (!cm.kmUrl.length) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Missing Configuration" message:@"Please configure Keyboard Maestro Web Server URL first." preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    
    UIAlertController *loading = [UIAlertController alertControllerWithTitle:@"Testing Connection..." message:@"Connecting to Keyboard Maestro Web Server..." preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:loading animated:YES completion:nil];
    
    NSString *base = cm.kmUrl;
    if ([base hasSuffix:@"/"]) base = [base substringToIndex:base.length - 1];
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@/action.html", base]];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.timeoutInterval = 6.0;
    if (cm.kmUser.length || cm.kmPassword.length) {
        NSString *auth = [NSString stringWithFormat:@"%@:%@", cm.kmUser ?: @"", cm.kmPassword ?: @""];
        NSString *b64 = [[auth dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];
        [req setValue:[NSString stringWithFormat:@"Basic %@", b64] forHTTPHeaderField:@"Authorization"];
    }
    
    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *res, NSError *err) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [loading dismissViewControllerAnimated:YES completion:^{
                NSHTTPURLResponse *httpRes = (NSHTTPURLResponse *)res;
                if (!err && (httpRes.statusCode == 200 || httpRes.statusCode == 400 || httpRes.statusCode == 404)) {
                    UIAlertController *ok = [UIAlertController alertControllerWithTitle:@"Connection Successful" message:@"Connected to Keyboard Maestro Web Server successfully!" preferredStyle:UIAlertControllerStyleAlert];
                    [ok addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                    [self presentViewController:ok animated:YES completion:nil];
                } else {
                    NSString *msg = err ? err.localizedDescription : [NSString stringWithFormat:@"Server returned HTTP status %ld", (long)httpRes.statusCode];
                    UIAlertController *fail = [UIAlertController alertControllerWithTitle:@"Connection Failed" message:msg preferredStyle:UIAlertControllerStyleAlert];
                    [fail addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                    [self presentViewController:fail animated:YES completion:nil];
                }
            }];
        });
    }] resume];
}



#pragma mark - Actions

- (void)masterToggleChanged:(UISwitch *)sender {
    [RCConfigManager sharedManager].masterEnabled = sender.on;
}

- (void)nfcToggleChanged:(UISwitch *)sender {
    [RCConfigManager sharedManager].nfcEnabled = sender.on;
}

- (void)webUIToggleChanged:(UISwitch *)sender {
    [RCConfigManager sharedManager].webUIEnabled = sender.on;
}

- (void)exportConfig {
    NSData *jsonData = [[RCConfigManager sharedManager] exportConfigAsJSON];
    if (!jsonData) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Export Failed" message:@"Could not export configuration" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    [df setDateFormat:@"yyyyMMdd_HHmm"];
    NSString *dateStr = [df stringFromDate:[NSDate date]];
    if (!dateStr) dateStr = @"backup";
    
    NSString *filename = [NSString stringWithFormat:@"rc_config_%@.json", dateStr];
    
    // Use system /tmp directly to avoid sandbox confusion for system app
    NSString *exportPath = [@"/tmp" stringByAppendingPathComponent:filename];
    
    NSError *writeError = nil;
    BOOL written = [jsonData writeToFile:exportPath options:NSDataWritingAtomic error:&writeError];
    
    if (!written || writeError) {
        NSLog(@"[RemoteCompanion] Error writing export file: %@", writeError);
        // Show exact path in alert for debugging
        NSString *debugMsg = [NSString stringWithFormat:@"Failed to write to:\n%@\n\nError: %@", exportPath, writeError.localizedDescription];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Export Error" message:debugMsg preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Copy Path" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [UIPasteboard generalPasteboard].string = exportPath;
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    
    NSURL *fileURL = [NSURL fileURLWithPath:exportPath];
    if (!fileURL) {
         NSLog(@"[RemoteCompanion] Error: fileURL is nil");
         return;
    }
    
    // Use share sheet instead of document picker to avoid glitchy loading indicator
    UIActivityViewController *activityVC = [[UIActivityViewController alloc] initWithActivityItems:@[fileURL] applicationActivities:nil];
    activityVC.modalPresentationStyle = UIModalPresentationFormSheet;
    
    // Success callback when user saves the file
    activityVC.completionWithItemsHandler = ^(UIActivityType activityType, BOOL completed, NSArray *returnedItems, NSError *error) {
        if (completed) {
            NSLog(@"[RemoteCompanion] Export successful via: %@", activityType);
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Export Successful" message:@"Configuration file has been saved." preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
        }
    };
    
    [self presentViewController:activityVC animated:YES completion:nil];
}

- (void)importConfig {
    // iOS 14+ supported
    NSArray *types = @[[UTType typeWithIdentifier:@"public.json"], [UTType typeWithIdentifier:@"public.plain-text"]];
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types];
    picker.delegate = self;
    picker.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)openGitHub {
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://github.com/saihgupr/RemoteCompanion"] options:@{} completionHandler:nil];
}

#pragma mark - UIDocumentPickerDelegate (Import only)

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (!url) return;
    
    NSLog(@"[RemoteCompanion] Import selected URL: %@", url);
    
    // Security scoped access is mandatory for 'Opening' mode
    BOOL accessing = [url startAccessingSecurityScopedResource];
    
    NSError *readError = nil;
    NSData *data = [NSData dataWithContentsOfURL:url options:0 error:&readError];
    
    if (accessing) {
        [url stopAccessingSecurityScopedResource];
    }
    
    if (!data) {
        NSLog(@"[RemoteCompanion] Failed to read file: %@", readError);
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Import Failed" message:[NSString stringWithFormat:@"Could not read file: %@", readError.localizedDescription] preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    
    NSError *error = nil;
    BOOL success = [[RCConfigManager sharedManager] importConfigFromJSON:data error:&error];
    
    if (success) {
        _masterSwitch.on = [RCConfigManager sharedManager].masterEnabled;
        _nfcSwitch.on = [RCConfigManager sharedManager].nfcEnabled;
        _webUISwitch.on = [RCConfigManager sharedManager].webUIEnabled;
        [self.tableView reloadData];
        
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Import Successful" message:@"Configuration restored. Return to Triggers to see changes." preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    } else {
        NSLog(@"[RemoteCompanion] Import Parsing Failed: %@", error);
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Import Failed" message:error.localizedDescription ?: @"Invalid configuration file" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    NSLog(@"[RemoteCompanion] Import cancelled by user");
}

@end
