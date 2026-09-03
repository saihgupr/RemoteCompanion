#import <UIKit/UIKit.h>

@interface RCKMMacroPickerViewController : UITableViewController
@property (nonatomic, copy) void (^onMacroSelected)(NSString *command);
@end
