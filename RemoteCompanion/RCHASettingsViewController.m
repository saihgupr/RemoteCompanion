#import "RCHASettingsViewController.h"
#import "RCConfigManager.h"
#import "RCUITweaker.h"

@interface RCHASettingsSessionDelegate : NSObject <NSURLSessionDelegate>
+ (instancetype)sharedDelegate;
@end

@implementation RCHASettingsSessionDelegate
+ (instancetype)sharedDelegate {
    static RCHASettingsSessionDelegate *del = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        del = [[RCHASettingsSessionDelegate alloc] init];
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

@interface RCHASettingsViewController ()
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISwitch *masterSwitch;
@end

@implementation RCHASettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.title = @"Home Assistant";
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
    return [RCConfigManager sharedManager].haEnabled ? 3 : 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 1 && [RCConfigManager sharedManager].haEnabled) {
        return @"Connection Details";
    }
    return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) {
        return @"Enable Home Assistant integration to trigger entity toggles, call services, and run scenes from triggers.";
    }
    if (section == 1 && [RCConfigManager sharedManager].haEnabled) {
        return @"Specify your local or remote Home Assistant instance URL and a Long-Lived Access Token created in your HA profile.";
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    
    UITableViewCellStyle style = UITableViewCellStyleDefault;
    if (indexPath.section == 1) {
        if (indexPath.row == 0 || indexPath.row == 1) {
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
        cell.textLabel.text = @"Enable Home Assistant";
        _masterSwitch = [[UISwitch alloc] init];
        _masterSwitch.on = cm.haEnabled;
        [_masterSwitch addTarget:self action:@selector(haToggleChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = _masterSwitch;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Server URL";
            cell.detailTextLabel.text = cm.haUrl.length ? cm.haUrl : @"Not Configured";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"Access Token";
            cell.detailTextLabel.text = cm.haToken.length ? @"••••••••" : @"Not Configured";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else if (indexPath.row == 2) {
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
            [self editHAUrl];
        } else if (indexPath.row == 1) {
            [self editHAToken];
        } else if (indexPath.row == 2) {
            [self testHAConnection];
        }
    }
}

#pragma mark - Actions & Configuration Dialogs

- (void)haToggleChanged:(UISwitch *)sender {
    [RCConfigManager sharedManager].haEnabled = sender.on;
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
    
    NSURLSessionConfiguration *sessionConfig = [NSURLSessionConfiguration defaultSessionConfiguration];
    sessionConfig.timeoutIntervalForRequest = 6.0;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:sessionConfig delegate:[RCHASettingsSessionDelegate sharedDelegate] delegateQueue:nil];
    
    [[session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *res, NSError *err) {
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

@end
