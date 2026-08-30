#import "RCMQTTTriggerViewController.h"
#import "RCConfigManager.h"
#import "RCActionsViewController.h"

@interface RCMQTTTriggerViewController () <UITextFieldDelegate>
@property (nonatomic, strong) NSString *triggerKey;
@property (nonatomic, strong) UITextField *topicField;
@property (nonatomic, strong) UITextField *payloadField;
@property (nonatomic, strong) UITextField *nameField;
@end

@implementation RCMQTTTriggerViewController

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
    self.title = self.triggerKey ? @"Edit MQTT Trigger" : @"New MQTT Trigger";
    
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(applyTweaks) 
                                                 name:@"RCConfigTweaksChangedNotification" 
                                               object:nil];
    [self applyTweaks];
    
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:self.triggerKey ? @"Save" : @"Add" 
                                                                              style:UIBarButtonItemStyleDone 
                                                                             target:self 
                                                                             action:@selector(saveTrigger)];
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
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"MQTT Topic";
    if (section == 1) return @"Payload Match (Optional)";
    if (section == 2) return @"Trigger Name (Optional)";
    return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) {
        return @"Enter the topic to subscribe to. Supports exact topics or wildcards (+ for single level, # for multi-level).";
    }
    if (section == 1) {
        return @"Leave empty to trigger on any message received on this topic, or enter exact text/JSON payload to match.";
    }
    if (section == 2) {
        return @"A friendly name displayed in the triggers list.";
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.backgroundColor = [cm tweakColorForKey:@"blockBackground" defaultVal:0.12];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    
    NSDictionary *data = self.triggerKey ? [cm triggerDataForKey:self.triggerKey] : nil;
    
    UITextField *tf = [[UITextField alloc] initWithFrame:CGRectMake(16, 0, cell.contentView.bounds.size.width - 32, 44)];
    tf.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    tf.textColor = [UIColor labelColor];
    tf.autocorrectionType = UITextAutocorrectionTypeNo;
    tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
    tf.delegate = self;
    
    if (indexPath.section == 0) {
        tf.placeholder = @"e.g. remotecompanion/cmd/ring";
        if (data) {
            tf.text = data[@"topic"] ?: @"";
        } else if (cm.mqttTopicPrefix.length > 0) {
            tf.text = [NSString stringWithFormat:@"%@/alerts/phone", cm.mqttTopicPrefix];
        } else {
            tf.text = @"remotecompanion/alerts/phone";
        }
        self.topicField = tf;
    } else if (indexPath.section == 1) {
        tf.placeholder = @"Leave empty for any payload, or e.g. ON";
        if (data) {
            tf.text = data[@"matchPayload"] ?: @"";
        }
        self.payloadField = tf;
    } else if (indexPath.section == 2) {
        tf.placeholder = @"e.g. Inbound Alert";
        if (data) {
            tf.text = data[@"name"] ?: @"";
        }
        self.nameField = tf;
    }
    
    [cell.contentView addSubview:tf];
    return cell;
}

- (void)saveTrigger {
    NSString *topic = [self.topicField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *payload = [self.payloadField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *name = [self.nameField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    
    if (!topic.length) {
        UIAlertController *err = [UIAlertController alertControllerWithTitle:@"Missing Topic" 
                                                                     message:@"Please enter an MQTT topic to subscribe to." 
                                                              preferredStyle:UIAlertControllerStyleAlert];
        [err addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:err animated:YES completion:nil];
        return;
    }
    
    NSString *friendlyName = name.length > 0 ? name : (payload.length > 0 ? [NSString stringWithFormat:@"MQTT: %@ (%@)", topic, payload] : [NSString stringWithFormat:@"MQTT: %@", topic]);
    
    RCConfigManager *cm = [RCConfigManager sharedManager];
    NSString *triggerKey = self.triggerKey;
    
    if (triggerKey) {
        NSMutableDictionary *mutableData = [[cm triggerDataForKey:triggerKey] mutableCopy] ?: [NSMutableDictionary dictionary];
        mutableData[@"name"] = friendlyName;
        mutableData[@"topic"] = topic;
        if (payload.length > 0) {
            mutableData[@"matchPayload"] = payload;
        } else {
            [mutableData removeObjectForKey:@"matchPayload"];
        }
        [cm updateTrigger:triggerKey withData:mutableData];
        [self.navigationController popViewControllerAnimated:YES];
    } else {
        triggerKey = [NSString stringWithFormat:@"mqtt_sub_%ld", (long)[[NSDate date] timeIntervalSince1970]];
        NSMutableDictionary *triggerData = [@{
            @"name": friendlyName,
            @"topic": topic,
            @"enabled": @YES,
            @"actions": @[]
        } mutableCopy];
        if (payload.length > 0) {
            triggerData[@"matchPayload"] = payload;
        }
        [cm updateTrigger:triggerKey withData:triggerData];
        
        RCActionsViewController *vc = [[RCActionsViewController alloc] initWithTriggerKey:triggerKey];
        NSMutableArray *vcs = [self.navigationController.viewControllers mutableCopy];
        [vcs removeLastObject]; // Remove self
        [vcs addObject:vc];
        [self.navigationController setViewControllers:vcs animated:YES];
    }
}

@end
