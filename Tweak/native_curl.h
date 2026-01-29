
#import <Foundation/Foundation.h>

static void CurlLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    
    NSLog(@"[RemoteCommand] [NativeCurl] %@", message);
    
    // Write to same log file
    NSString *logMsg = [NSString stringWithFormat:@"%@ [RemoteCommand] [NativeCurl] %@\n", [NSDate date], message];
    NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:@"/tmp/remotecommand.log"];
    if (fileHandle) {
        @try {
            [fileHandle seekToEndOfFile];
            [fileHandle writeData:[logMsg dataUsingEncoding:NSUTF8StringEncoding]];
        } @catch (NSException *e) {}
        [fileHandle closeFile];
    }
}

static NSArray *tokenize_command(NSString *cmd) {
    NSMutableArray *tokens = [NSMutableArray array];
    NSMutableString *currentToken = [NSMutableString string];
    BOOL inDoubleQuote = NO;
    BOOL inSingleQuote = NO;
    BOOL escaped = NO;

    for (NSUInteger i = 0; i < cmd.length; i++) {
        unichar c = [cmd characterAtIndex:i];

        if (escaped) {
             [currentToken appendFormat:@"%C", c];
             escaped = NO;
             continue;
        }

        if (c == '\\') {
            escaped = YES;
            continue;
        }

        if (c == '"' && !inSingleQuote) {
            inDoubleQuote = !inDoubleQuote;
            continue;
        }
        
        if (c == '\'' && !inDoubleQuote) {
            inSingleQuote = !inSingleQuote;
            continue;
        }

        if (c == ' ' && !inDoubleQuote && !inSingleQuote) {
            if (currentToken.length > 0) {
                [tokens addObject:[currentToken copy]];
                [currentToken setString:@""];
            }
        } else {
            [currentToken appendFormat:@"%C", c];
        }
    }
    if (currentToken.length > 0) {
        [tokens addObject:[currentToken copy]];
    }
    return tokens;
}

// Delegate to allow self-signed certs when -k flag is used
@interface InsecureSessionDelegate : NSObject <NSURLSessionDelegate>
@end

@implementation InsecureSessionDelegate
- (void)URLSession:(NSURLSession *)session didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential *))completionHandler {
    if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
        NSURLCredential *credential = [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust];
        completionHandler(NSURLSessionAuthChallengeUseCredential, credential);
    } else {
        completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
    }
}
@end

static void perform_native_curl(NSString *fullCmd) {
    NSArray *tokens = tokenize_command(fullCmd);
    
    NSString *urlStr = nil;
    NSString *method = @"GET";
    NSMutableDictionary *headers = [NSMutableDictionary dictionary];
    NSString *body = nil;
    BOOL insecure = NO;
    NSString *basicAuth = nil;
    
    for (NSUInteger i = 1; i < tokens.count; i++) { // Skip 'curl'
        NSString *token = tokens[i];
        
        if ([token isEqualToString:@"-X"] && i + 1 < tokens.count) {
            method = tokens[++i];
        } else if ([token isEqualToString:@"-H"] && i + 1 < tokens.count) {
            NSString *headerStr = tokens[++i];
            NSArray *parts = [headerStr componentsSeparatedByString:@":"];
            if (parts.count >= 2) {
                NSString *key = [parts[0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                NSString *val = [[parts subarrayWithRange:NSMakeRange(1, parts.count-1)] componentsJoinedByString:@":"];
                val = [val stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                headers[key] = val;
            }
        } else if (([token isEqualToString:@"-d"] || [token isEqualToString:@"--data"]) && i + 1 < tokens.count) {
            body = tokens[++i];
        } else if ([token isEqualToString:@"-k"] || [token isEqualToString:@"--insecure"]) {
            insecure = YES;
        } else if (([token isEqualToString:@"-u"] || [token isEqualToString:@"--user"]) && i + 1 < tokens.count) {
            basicAuth = tokens[++i];
        } else if (![token hasPrefix:@"-"]) {
            urlStr = token;
        }
    }
    
    if (!urlStr) {
        CurlLog(@"[SpringRemote] Native Curl Error: No URL found");
        return;
    }
    
    NSURL *url = [NSURL URLWithString:urlStr];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    [req setHTTPMethod:method];
    
    // Add Basic Auth header if --user was provided
    if (basicAuth) {
        NSData *authData = [basicAuth dataUsingEncoding:NSUTF8StringEncoding];
        NSString *base64Auth = [authData base64EncodedStringWithOptions:0];
        [req setValue:[NSString stringWithFormat:@"Basic %@", base64Auth] forHTTPHeaderField:@"Authorization"];
    }
    
    for (NSString *key in headers) {
        [req setValue:headers[key] forHTTPHeaderField:key];
    }
    if (body) {
        [req setHTTPBody:[body dataUsingEncoding:NSUTF8StringEncoding]];
    }
    
    CurlLog(@"[SpringRemote] Native Curl: %@ %@ (insecure=%d, auth=%@)", method, urlStr, insecure, basicAuth ? @"YES" : @"NO");
    
    // Use custom session with delegate if -k flag was used
    NSURLSession *session;
    if (insecure) {
        static InsecureSessionDelegate *insecureDelegate = nil;
        static NSURLSession *insecureSession = nil;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            insecureDelegate = [[InsecureSessionDelegate alloc] init];
            NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
            insecureSession = [NSURLSession sessionWithConfiguration:config delegate:insecureDelegate delegateQueue:nil];
        });
        session = insecureSession;
    } else {
        session = [NSURLSession sharedSession];
    }
    
    NSURLSessionDataTask *task = [session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            CurlLog(@"[SpringRemote] Native Curl Error: %@", error);
        } else {
            NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)response;
            CurlLog(@"[SpringRemote] Native Curl Success: %ld", (long)httpResp.statusCode);
            if (data) {
                NSString *respStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                CurlLog(@"[SpringRemote] Response: %@", respStr);
            }
        }
    }];
    [task resume];
}
