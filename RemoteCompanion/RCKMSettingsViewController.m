#import "RCKMSettingsViewController.h"
#import "RCConfigManager.h"
#import "RCUITweaker.h"

@interface RCKMSettingsSessionDelegate : NSObject <NSURLSessionDelegate>
+ (instancetype)sharedDelegate;
@end

@implementation RCKMSettingsSessionDelegate
+ (instancetype)sharedDelegate {
    static RCKMSettingsSessionDelegate *del = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        del = [[RCKMSettingsSessionDelegate alloc] init];
    });
    return del;
}

- (void)URLSession:(NSURLSession *)session didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential))completionHandler {
    if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
        completionHandler(NSURLSessionAuthChallengeUseCredential, [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust]);
    } else {
        completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
    }
}
@end

@interface RCKMSettingsViewController ()
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISwitch *masterSwitch;
@end

@implementation RCKMSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.title = @"Keyboard Maestro";
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
    return [RCConfigManager sharedManager].kmEnabled ? 4 : 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 1 && [RCConfigManager sharedManager].kmEnabled) {
        return @"Web Server Details";
    }
    return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) {
        return @"Enable Keyboard Maestro integration to trigger macros on your Mac over Wi-Fi or LAN.";
    }
    if (section == 1 && [RCConfigManager sharedManager].kmEnabled) {
        return @"Configure the URL and authentication credentials specified in Keyboard Maestro Preferences > Web Server.";
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    
    UITableViewCellStyle style = UITableViewCellStyleDefault;
    if (indexPath.section == 1) {
        if (indexPath.row == 0 || indexPath.row == 1 || indexPath.row == 2) {
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
        cell.textLabel.text = @"Enable Keyboard Maestro";
        _masterSwitch = [[UISwitch alloc] init];
        _masterSwitch.on = cm.kmEnabled;
        [_masterSwitch addTarget:self action:@selector(kmToggleChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = _masterSwitch;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Web Server URL";
            cell.detailTextLabel.text = cm.kmUrl.length ? cm.kmUrl : @"http://192.168.1.50:4490";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"Username";
            cell.detailTextLabel.text = cm.kmUser.length ? cm.kmUser : @"Optional";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else if (indexPath.row == 2) {
            cell.textLabel.text = @"Password";
            cell.detailTextLabel.text = cm.kmPassword.length ? @"••••••••" : @"Optional";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else if (indexPath.row == 3) {
            cell.textLabel.text = @"Test Connection";
            cell.textLabel.textColor = [UIColor systemGreenColor];
            cell.imageView.image = [UIImage systemImageNamed:@"bolt.fill"];
            cell.imageView.tintColor = [UIColor systemGreenColor];
        }
    }
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 1) {
        if (indexPath.row == 0) {
            [self editKMUrl];
        } else if (indexPath.row == 1) {
            [self editKMUser];
        } else if (indexPath.row == 2) {
            [self editKMPassword];
        } else if (indexPath.row == 3) {
            [self testKMConnection];
        }
    }
}

#pragma mark - Actions & Configuration Dialogs

- (void)kmToggleChanged:(UISwitch *)sender {
    [RCConfigManager sharedManager].kmEnabled = sender.on;
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:1] withRowAnimation:UITableViewRowAnimationAutomatic];
}

- (void)editKMUrl {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Keyboard Maestro Server URL" message:@"Enter the Web Server URL from Keyboard Maestro Preferences (e.g. http://192.168.1.50:4490 or https://192.168.1.30:4491):" preferredStyle:UIAlertControllerStyleAlert];
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
    
    NSString *endpointStr;
    if ([base containsString:@"/action.html"] || [base containsString:@"/authenticatedaction.html"]) {
        endpointStr = base;
    } else {
        NSString *path = (cm.kmUser.length || cm.kmPassword.length) ? @"/authenticatedaction.html" : @"/action.html";
        endpointStr = [NSString stringWithFormat:@"%@%@", base, path];
    }
    
    NSURL *url = [NSURL URLWithString:endpointStr];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.timeoutInterval = 6.0;
    if (cm.kmUser.length || cm.kmPassword.length) {
        NSString *auth = [NSString stringWithFormat:@"%@:%@", cm.kmUser ?: @"", cm.kmPassword ?: @""];
        NSString *b64 = [[auth dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];
        [req setValue:[NSString stringWithFormat:@"Basic %@", b64] forHTTPHeaderField:@"Authorization"];
    }
    
    NSURLSessionConfiguration *sessionConfig = [NSURLSessionConfiguration defaultSessionConfiguration];
    sessionConfig.timeoutIntervalForRequest = 6.0;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:sessionConfig delegate:[RCKMSettingsSessionDelegate sharedDelegate] delegateQueue:nil];
    
    [[session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *res, NSError *err) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [loading dismissViewControllerAnimated:YES completion:^{
                NSHTTPURLResponse *httpRes = (NSHTTPURLResponse *)res;
                if (!err && ((httpRes.statusCode >= 200 && httpRes.statusCode < 400) || httpRes.statusCode == 404)) {
                    UIAlertController *ok = [UIAlertController alertControllerWithTitle:@"Connection Successful" message:@"Connected to Keyboard Maestro Web Server successfully!" preferredStyle:UIAlertControllerStyleAlert];
                    [ok addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                    [self presentViewController:ok animated:YES completion:nil];
                } else {
                    NSString *msg = err ? err.localizedDescription : (httpRes.statusCode == 401 ? @"HTTP 401: Unauthorized (Check Username / Password)" : [NSString stringWithFormat:@"Server returned HTTP status %ld", (long)httpRes.statusCode]);
                    UIAlertController *fail = [UIAlertController alertControllerWithTitle:@"Connection Failed" message:msg preferredStyle:UIAlertControllerStyleAlert];
                    [fail addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                    [self presentViewController:fail animated:YES completion:nil];
                }
            }];
        });
    }] resume];
}

@end
