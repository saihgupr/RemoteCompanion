#import <Foundation/Foundation.h>

@interface RCMQTTClient : NSObject

+ (BOOL)testConnectionToHost:(NSString *)host
                        port:(NSInteger)port
                        user:(NSString *)user
                        pass:(NSString *)pass
                    clientId:(NSString *)clientId
                       error:(NSError **)error;

+ (BOOL)publishTopic:(NSString *)topic
             payload:(NSString *)payload
                host:(NSString *)host
                port:(NSInteger)port
                user:(NSString *)user
                pass:(NSString *)pass
            clientId:(NSString *)clientId
                 qos:(NSInteger)qos
              retain:(BOOL)retain
               error:(NSError **)error;

@end
