#import "RCSettingsViewController.h"
#import "RCConfigManager.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface RCSettingsViewController () <UIDocumentPickerDelegate>
@property (nonatomic, strong) UISwitch *masterSwitch;
@property (nonatomic, assign) BOOL isExporting;
@end

@implementation RCSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.title = @"Settings";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    
    // Close button
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(dismissSettings)];
    
    self.tableView.rowHeight = 50;
}

- (void)dismissSettings {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Table View Data Source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"General";
    return @"Backup";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) {
        return @"When disabled, no triggers will fire.";
    } else if (section == 1) {
        return @"Export your configuration to share or backup. Import to restore.";
    }
    return nil;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 1; // Master toggle
    return 2; // Export, Import
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    
    if (indexPath.section == 0) {
        cell.textLabel.text = @"Enable All Triggers";
        _masterSwitch = [[UISwitch alloc] init];
        _masterSwitch.on = [RCConfigManager sharedManager].masterEnabled;
        [_masterSwitch addTarget:self action:@selector(masterToggleChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = _masterSwitch;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
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
        if (indexPath.row == 0) {
            [self exportConfig];
        } else {
            [self importConfig];
        }
    }
}

#pragma mark - Actions

- (void)masterToggleChanged:(UISwitch *)sender {
    [RCConfigManager sharedManager].masterEnabled = sender.on;
}

- (void)exportConfig {
    self.isExporting = YES;
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
    
    @try {
        // Use UIDocumentPicker for reliable "Save to Files"
        UIDocumentPickerViewController *documentPicker = [[UIDocumentPickerViewController alloc] initForExportingURLs:@[fileURL] asCopy:YES];
        documentPicker.delegate = self;
        documentPicker.modalPresentationStyle = UIModalPresentationFormSheet;
        [self presentViewController:documentPicker animated:YES completion:nil];
    } @catch (NSException *exception) {
        NSLog(@"[RemoteCompanion] EXCEPTION in export: %@, %@", exception.name, exception.reason);
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Export Crash Prevented" message:[NSString stringWithFormat:@"%@: %@", exception.name, exception.reason] preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}

- (void)importConfig {
    self.isExporting = NO;
    // iOS 14+ supported
    NSArray *types = @[[UTType typeWithIdentifier:@"public.json"], [UTType typeWithIdentifier:@"public.plain-text"]];
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types];
    picker.delegate = self;
    picker.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:picker animated:YES completion:nil];
}

#pragma mark - UIDocumentPickerDelegate

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (!url) return;

    if (self.isExporting) {
        NSLog(@"[RemoteCompanion] Export finished successfully to: %@", url);
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Export Successful" message:@"Configuration file has been saved." preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    
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
