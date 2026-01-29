#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface RCShortcutPickerViewController : UITableViewController

@property (nonatomic, copy) void (^onShortcutSelected)(NSString *shortcutName);

@end

NS_ASSUME_NONNULL_END
