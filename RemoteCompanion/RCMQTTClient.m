#import "RCMQTTClient.h"
#include <sys/socket.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>

@implementation RCMQTTClient

static void appendRemainingLength(NSMutableData *data, NSUInteger length) {
    do {
        uint8_t d = length % 128;
        length /= 128;
        if (length > 0) {
            d |= 128;
        }
        [data appendBytes:&d length:1];
    } while (length > 0);
}

static void appendUTF8String(NSMutableData *data, NSString *str) {
    if (!str) str = @"";
    NSData *strData = [str dataUsingEncoding:NSUTF8StringEncoding];
    uint16_t len = htons((uint16_t)strData.length);
    [data appendBytes:&len length:2];
    if (strData.length > 0) {
        [data appendData:strData];
    }
}

static int createConnectedSocket(NSString *host, NSInteger port, double timeoutSeconds, NSError **error) {
    if (!host.length) {
        if (error) *error = [NSError errorWithDomain:@"RCMQTTErrorDomain" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Host is empty"}];
        return -1;
    }
    
    char portStr[16];
    snprintf(portStr, sizeof(portStr), "%ld", (long)(port > 0 ? port : 1883));
    
    struct addrinfo hints;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    hints.ai_protocol = IPPROTO_TCP;
    
    struct addrinfo *res = NULL;
    int gai_err = getaddrinfo([host UTF8String], portStr, &hints, &res);
    if (gai_err != 0 || !res) {
        if (error) {
            *error = [NSError errorWithDomain:@"RCMQTTErrorDomain" code:-2 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Could not resolve host '%@': %s", host, gai_strerror(gai_err)]}];
        }
        return -1;
    }
    
    int sockfd = -1;
    for (struct addrinfo *rp = res; rp != NULL; rp = rp->ai_next) {
        sockfd = socket(rp->ai_family, rp->ai_socktype, rp->ai_protocol);
        if (sockfd == -1) continue;
        
        // Set non-blocking for timeout connection
        int flags = fcntl(sockfd, F_GETFL, 0);
        fcntl(sockfd, F_SETFL, flags | O_NONBLOCK);
        
        int conn = connect(sockfd, rp->ai_addr, rp->ai_addrlen);
        if (conn == 0) {
            // Connected immediately
            fcntl(sockfd, F_SETFL, flags);
            break;
        }
        
        if (errno == EINPROGRESS) {
            fd_set fdset;
            FD_ZERO(&fdset);
            FD_SET(sockfd, &fdset);
            
            struct timeval tv;
            tv.tv_sec = (time_t)timeoutSeconds;
            tv.tv_usec = (suseconds_t)((timeoutSeconds - tv.tv_sec) * 1000000.0);
            
            if (select(sockfd + 1, NULL, &fdset, NULL, &tv) == 1) {
                int so_error = 0;
                socklen_t len = sizeof(so_error);
                getsockopt(sockfd, SOL_SOCKET, SO_ERROR, &so_error, &len);
                if (so_error == 0) {
                    // Success
                    fcntl(sockfd, F_SETFL, flags);
                    break;
                }
            }
        }
        
        close(sockfd);
        sockfd = -1;
    }
    
    freeaddrinfo(res);
    
    if (sockfd == -1) {
        if (error) {
            *error = [NSError errorWithDomain:@"RCMQTTErrorDomain" code:-3 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Could not connect to %@:%ld (timeout or connection refused)", host, (long)port]}];
        }
        return -1;
    }
    
    // Set socket receive timeout
    struct timeval rtv;
    rtv.tv_sec = (time_t)timeoutSeconds;
    rtv.tv_usec = 0;
    setsockopt(sockfd, SOL_SOCKET, SO_RCVTIMEO, (const char *)&rtv, sizeof(rtv));
    setsockopt(sockfd, SOL_SOCKET, SO_SNDTIMEO, (const char *)&rtv, sizeof(rtv));
    
    return sockfd;
}

static NSData *buildConnectPacket(NSString *clientId, NSString *user, NSString *pass) {
    NSMutableData *varHeaderAndPayload = [NSMutableData data];
    
    // Protocol Name: 0x00 0x04 "MQTT"
    uint16_t protoNameLen = htons(4);
    [varHeaderAndPayload appendBytes:&protoNameLen length:2];
    [varHeaderAndPayload appendBytes:"MQTT" length:4];
    
    // Protocol Level: 4 (MQTT 3.1.1)
    uint8_t protoLevel = 4;
    [varHeaderAndPayload appendBytes:&protoLevel length:1];
    
    // Connect Flags: Clean Session (0x02)
    uint8_t flags = 0x02;
    if (user.length > 0) flags |= 0x80;
    if (pass.length > 0) flags |= 0x40;
    [varHeaderAndPayload appendBytes:&flags length:1];
    
    // Keepalive: 60s (0x00 0x3C)
    uint16_t keepAlive = htons(60);
    [varHeaderAndPayload appendBytes:&keepAlive length:2];
    
    // Payload: Client ID
    appendUTF8String(varHeaderAndPayload, clientId.length > 0 ? clientId : @"RemoteCompanion");
    
    // Payload: Username
    if (user.length > 0) {
        appendUTF8String(varHeaderAndPayload, user);
    }
    
    // Payload: Password
    if (pass.length > 0) {
        appendUTF8String(varHeaderAndPayload, pass);
    }
    
    NSMutableData *packet = [NSMutableData data];
    uint8_t connectType = 0x10; // CONNECT
    [packet appendBytes:&connectType length:1];
    appendRemainingLength(packet, varHeaderAndPayload.length);
    [packet appendData:varHeaderAndPayload];
    
    return packet;
}

static BOOL readConnack(int sockfd, NSError **error) {
    uint8_t header[2];
    ssize_t n = recv(sockfd, header, 2, 0);
    if (n < 2 || header[0] != 0x20 || header[1] < 2) {
        if (error) {
            *error = [NSError errorWithDomain:@"RCMQTTErrorDomain" code:-4 userInfo:@{NSLocalizedDescriptionKey: @"Invalid CONNACK response from broker"}];
        }
        return NO;
    }
    
    uint8_t body[2];
    n = recv(sockfd, body, 2, 0);
    if (n < 2) {
        if (error) {
            *error = [NSError errorWithDomain:@"RCMQTTErrorDomain" code:-5 userInfo:@{NSLocalizedDescriptionKey: @"Failed to read CONNACK return code"}];
        }
        return NO;
    }
    
    uint8_t returnCode = body[1];
    if (returnCode == 0) {
        return YES;
    }
    
    NSString *reason = @"Connection rejected";
    switch (returnCode) {
        case 1: reason = @"Unacceptable protocol version"; break;
        case 2: reason = @"Identifier rejected"; break;
        case 3: reason = @"Server unavailable"; break;
        case 4: reason = @"Bad username or password"; break;
        case 5: reason = @"Not authorized"; break;
        default: reason = [NSString stringWithFormat:@"MQTT Error Code %d", returnCode]; break;
    }
    
    if (error) {
        *error = [NSError errorWithDomain:@"RCMQTTErrorDomain" code:returnCode userInfo:@{NSLocalizedDescriptionKey: reason}];
    }
    return NO;
}

static NSData *buildPublishPacket(NSString *topic, NSString *payload, NSInteger qos, BOOL retain) {
    NSMutableData *varHeaderAndPayload = [NSMutableData data];
    
    // Topic
    appendUTF8String(varHeaderAndPayload, topic);
    
    // Packet ID for QoS 1
    if (qos > 0) {
        uint16_t pktId = htons(1);
        [varHeaderAndPayload appendBytes:&pktId length:2];
    }
    
    // Payload
    if (payload.length > 0) {
        NSData *pData = [payload dataUsingEncoding:NSUTF8StringEncoding];
        if (pData) [varHeaderAndPayload appendData:pData];
    }
    
    NSMutableData *packet = [NSMutableData data];
    uint8_t pubType = 0x30; // PUBLISH (QoS 0)
    if (qos == 1) pubType |= 0x02;
    if (retain) pubType |= 0x01;
    
    [packet appendBytes:&pubType length:1];
    appendRemainingLength(packet, varHeaderAndPayload.length);
    [packet appendData:varHeaderAndPayload];
    
    return packet;
}

+ (BOOL)testConnectionToHost:(NSString *)host
                        port:(NSInteger)port
                        user:(NSString *)user
                        pass:(NSString *)pass
                    clientId:(NSString *)clientId
                       error:(NSError **)error {
    int sockfd = createConnectedSocket(host, port, 5.0, error);
    if (sockfd < 0) return NO;
    
    NSData *connPacket = buildConnectPacket(clientId, user, pass);
    ssize_t sent = send(sockfd, connPacket.bytes, connPacket.length, 0);
    if (sent < (ssize_t)connPacket.length) {
        close(sockfd);
        if (error) *error = [NSError errorWithDomain:@"RCMQTTErrorDomain" code:-6 userInfo:@{NSLocalizedDescriptionKey: @"Failed to send CONNECT packet"}];
        return NO;
    }
    
    BOOL success = readConnack(sockfd, error);
    
    // Disconnect gracefully
    uint8_t disconnectPacket[] = { 0xE0, 0x00 };
    send(sockfd, disconnectPacket, sizeof(disconnectPacket), 0);
    close(sockfd);
    
    return success;
}

+ (BOOL)publishTopic:(NSString *)topic
             payload:(NSString *)payload
                host:(NSString *)host
                port:(NSInteger)port
                user:(NSString *)user
                pass:(NSString *)pass
            clientId:(NSString *)clientId
                 qos:(NSInteger)qos
              retain:(BOOL)retain
               error:(NSError **)error {
    if (!topic.length) {
        if (error) *error = [NSError errorWithDomain:@"RCMQTTErrorDomain" code:-7 userInfo:@{NSLocalizedDescriptionKey: @"MQTT Topic cannot be empty"}];
        return NO;
    }
    
    int sockfd = createConnectedSocket(host, port, 5.0, error);
    if (sockfd < 0) return NO;
    
    NSData *connPacket = buildConnectPacket(clientId, user, pass);
    ssize_t sent = send(sockfd, connPacket.bytes, connPacket.length, 0);
    if (sent < (ssize_t)connPacket.length) {
        close(sockfd);
        if (error) *error = [NSError errorWithDomain:@"RCMQTTErrorDomain" code:-6 userInfo:@{NSLocalizedDescriptionKey: @"Failed to send CONNECT packet"}];
        return NO;
    }
    
    if (!readConnack(sockfd, error)) {
        close(sockfd);
        return NO;
    }
    
    NSData *pubPacket = buildPublishPacket(topic, payload, qos, retain);
    sent = send(sockfd, pubPacket.bytes, pubPacket.length, 0);
    
    BOOL pubSuccess = (sent == (ssize_t)pubPacket.length);
    if (!pubSuccess && error) {
        *error = [NSError errorWithDomain:@"RCMQTTErrorDomain" code:-8 userInfo:@{NSLocalizedDescriptionKey: @"Failed to send PUBLISH packet"}];
    }
    
    // If QoS 1, read PUBACK
    if (pubSuccess && qos == 1) {
        uint8_t puback[4];
        recv(sockfd, puback, sizeof(puback), 0);
    }
    
    // Disconnect gracefully
    uint8_t disconnectPacket[] = { 0xE0, 0x00 };
    send(sockfd, disconnectPacket, sizeof(disconnectPacket), 0);
    close(sockfd);
    
    return pubSuccess;
}

@end
