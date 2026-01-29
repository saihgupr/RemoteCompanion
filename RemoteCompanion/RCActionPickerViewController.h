#import <UIKit/UIKit.h>

@interface RCActionPickerViewController : UITableViewController

@property (nonatomic, copy) void (^onActionSelected)(NSString *action);

@end
