#import <UIKit/UIKit.h>
#import <UserNotifications/UserNotifications.h>

@interface RCAppDelegate : UIResponder <UIApplicationDelegate, UNUserNotificationCenterDelegate>
@property (nonatomic, strong) UIWindow *window;
@end
