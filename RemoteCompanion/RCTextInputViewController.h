#import <UIKit/UIKit.h>

@interface RCTextInputViewController : UIViewController

@property (nonatomic, copy) NSString *promptTitle;
@property (nonatomic, copy) NSString *promptMessage;
@property (nonatomic, copy) NSString *placeholderText;
@property (nonatomic, copy) NSString *initialText;
@property (nonatomic, copy) void (^onComplete)(NSString *text);

@end
