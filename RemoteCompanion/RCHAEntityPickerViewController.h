#import <UIKit/UIKit.h>

@interface RCHAEntityPickerViewController : UITableViewController
@property (nonatomic, copy) void (^onEntitySelected)(NSString *command);
@end
