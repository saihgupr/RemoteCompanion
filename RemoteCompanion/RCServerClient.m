#import "RCServerClient.h"
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>

@implementation RCServerClient

+ (instancetype)sharedClient {
    static RCServerClient *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[RCServerClient alloc] init];
    });
    return sharedInstance;
}

- (void)executeCommand:(NSString *)command completion:(void (^)(NSString * _Nullable, NSError * _Nullable))completion {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        int sockfd = -1;
        int port = 12340;
        BOOL connected = NO;
        
        // Try ports 12340-12344
        for (int i = 0; i < 5; i++) {
            port = 12340 + i;
            sockfd = socket(AF_INET, SOCK_STREAM, 0);
            if (sockfd < 0) continue;
            
            struct sockaddr_in serv_addr;
            memset(&serv_addr, 0, sizeof(serv_addr));
            serv_addr.sin_family = AF_INET;
            serv_addr.sin_port = htons(port);
            inet_pton(AF_INET, "127.0.0.1", &serv_addr.sin_addr);
            
            struct timeval tv;
            tv.tv_sec = 0;
            tv.tv_usec = 500000; // 500ms timeout for connect
            setsockopt(sockfd, SOL_SOCKET, SO_RCVTIMEO, (const char*)&tv, sizeof tv);
            setsockopt(sockfd, SOL_SOCKET, SO_SNDTIMEO, (const char*)&tv, sizeof tv);
            
            if (connect(sockfd, (struct sockaddr *)&serv_addr, sizeof(serv_addr)) == 0) {
                connected = YES;
                break;
            }
            close(sockfd);
        }
        
        if (!connected) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, [NSError errorWithDomain:@"RCServerClientError" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Could not connect to SpringRemote tweak (checked ports 12340-12344)"}]);
            });
            return;
        }
        
        // Send command
        const char *cmd = [command UTF8String];
        if (write(sockfd, cmd, strlen(cmd)) < 0) {
            close(sockfd);
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, [NSError errorWithDomain:@"RCServerClientError" code:2 userInfo:@{NSLocalizedDescriptionKey: @"Failed to send command"}]);
            });
            return;
        }
        
        // Read response
        NSMutableData *receivedData = [NSMutableData data];
        char buffer[1024];
        ssize_t n;
        
        // Increase timeout for reading data (5 seconds)
        struct timeval tv;
        tv.tv_sec = 5;
        tv.tv_usec = 0;
        setsockopt(sockfd, SOL_SOCKET, SO_RCVTIMEO, (const char*)&tv, sizeof tv);
        
        while ((n = read(sockfd, buffer, sizeof(buffer) - 1)) > 0) {
            [receivedData appendBytes:buffer length:n];
        }
        
        close(sockfd);
        
        NSString *output = [[NSString alloc] initWithData:receivedData encoding:NSUTF8StringEncoding];
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(output, nil);
        });
    });
}

@end
