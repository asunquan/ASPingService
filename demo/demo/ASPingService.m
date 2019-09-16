//
//  ASPingService.m
//  demo
//
//  Created by 孙泉 on 2019/9/16.
//  Copyright © 2019 puzzle. All rights reserved.
//

#import "ASPingService.h"
#import "ASHostResolver.h"
#import "ASICMPSocket.h"

@interface ASPingService ()

@property (nonatomic, strong) ASHostResolver *resolver;
@property (nonatomic, strong) NSData *hostaddr;
@property (nonatomic, strong) ASICMPSocket *socket;

@end

@implementation ASPingService

#pragma mark - 生命周期

static ASPingService *instance = nil;

+ (instancetype)allocWithZone:(struct _NSZone *)zone
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [super allocWithZone:zone];
    });
    return instance;
}

#pragma mark - ping

+ (void)ping:(NSString *)host handler:(ASPingBlock)handler
{
    [self ping:host resolution:nil handler:handler];
}

+ (void)ping:(NSString *)host resolution:(ASHostBlock)resolution handler:(ASPingBlock)handler
{
    instance = self.new;
    instance.resolver = nil;
    instance.socket = nil;
    
    [instance.resolver resolveHost:host handler:^(NSData *hostaddr) {
        if (resolution) {
            resolution(hostaddr);
        }
        
        if (hostaddr) {
            BOOL connection = [instance.socket connect:hostaddr];
            
            if (connection) {
                [instance.socket send:instance.socket.icmpPacket handler:^(BOOL result, CGFloat delay) {
                    if (handler) {
                        handler(result, delay);
                    }
                    [instance.socket stop];
                }];
            }
            else if (handler) {
                handler(NO, 9999);
            }
        }
    }];
}

- (ASHostResolver *)resolver
{
    if (!_resolver) {
        _resolver = ASHostResolver.hostResolver;
    }
    return _resolver;
}

- (ASICMPSocket *)socket
{
    if (!_socket) {
        _socket = ASICMPSocket.icmpSocket;
    }
    return _socket;
}

@end
