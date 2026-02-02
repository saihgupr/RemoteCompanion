#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RCServerClient : NSObject

+ (instancetype)sharedClient;

- (void)executeCommand:(NSString *)command completion:(void (^)(NSString * _Nullable output, NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
