//
//  ASHostResolver.m
//  demo
//
//  Created by 孙泉 on 2019/9/16.
//  Copyright © 2019 puzzle. All rights reserved.
//

#import "ASHostResolver.h"
#include <sys/socket.h>
#import <arpa/inet.h>
#include <errno.h>

@interface ASHostResolver ()

@property (nonatomic, strong) NSString *host;

// A host object for name-to-address resolution
@property (nonatomic, strong) CFHostRef hostRef __attribute__ ((NSObject));

// The address being pinged. The contents of the NSData is a (struct sockaddr) of some form.  The value is nil while the object is stopped and remains nil on start until
@property (nonatomic, strong) NSData *hostaddr;

@property (nonatomic, copy) ASHostRevolveBlock handler;

@end

@implementation ASHostResolver

+ (ASHostResolver *)hostResolver
{
    return ASHostResolver.new;
}

- (void)dealloc
{
    self.hostRef = NULL;
}

#pragma mark - 域名解析

- (void)resolveHost:(NSString *)host handler:(ASHostRevolveBlock)handler
{
    self.hostRef = NULL;
    self.hostaddr = nil;
    
    self.host = host;
    self.handler = handler;
    
    if (!self.host) {
        [self resolveHostFinished];
        return;
    }
    
    self.hostRef = (CFHostRef)CFAutorelease(CFHostCreateWithName(NULL, (__bridge CFStringRef)(self.host)));
    
    CFHostClientContext context = {0, (__bridge void *)(self), NULL, NULL, NULL};
    CFHostSetClient(self.hostRef, ResolveHostCallback, &context);
    CFHostScheduleWithRunLoop(self.hostRef, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
    
    // 设置域名解析超时检查
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!self.hostaddr) {
            CFHostCancelInfoResolution(self.hostRef, kCFHostAddresses);
            [self resolveHostFinished];
        }
    });
    
    CFStreamError streamError;
    Boolean success = CFHostStartInfoResolution(self.hostRef, kCFHostAddresses, &streamError);
    
    if (success) {
        return;
    }
    
    NSLog(@"CFHostStartInfoResolution failed");
    [self resolveHostFinished];
}

static void ResolveHostCallback(CFHostRef hostRef, CFHostInfoType infoType, const CFStreamError *error, void *info)
{
    // 这个方法当域名解析完成时被CFHost调用, 单纯只是转发
    ASHostResolver *obj = (__bridge ASHostResolver *)info;
    
    if (![obj isKindOfClass:ASHostResolver.class]) {
        return;
    }
    
    if (error != NULL && error->domain != 0) {
        [obj resolveHostFinished];
        return;
    }
    
    Boolean resolved = false;
    NSArray *addresses = (__bridge NSArray *)CFHostGetAddressing(obj.hostRef, &resolved);
    
    // We're done resolving, so shut that down.
    [obj stopResolvingHost];
    
    if (!resolved || !addresses || !addresses.count) {
        [obj resolveHostFinished];
        return;
    }
    
    NSData *address = addresses.firstObject;
    if (address.length < sizeof(struct sockaddr)) {
        [obj resolveHostFinished];
        return;
    }
    
    obj.hostaddr = address;
    
    // If all is OK, start the send and receive infrastructure, otherwise stop.
    [obj resolveHostFinished];
}

- (sa_family_t)hostaddrFamily
{
    sa_family_t result = AF_UNSPEC;
    if (self.hostaddr && self.hostaddr.length >= sizeof(struct sockaddr)) {
        result = ((const struct sockaddr *)self.hostaddr.bytes)->sa_family;
    }
    return result;
}

+ (NSString *)hostip:(NSData *)hostaddr
{
    ASHostResolver *resolver = ASHostResolver.hostResolver;
    resolver.hostaddr = hostaddr;
    return resolver.hostip;
}

- (NSString *)hostip
{
    NSString *ip = nil;
    if (self.hostaddrFamily == AF_INET) {
        struct sockaddr_in *sockaddr = (struct sockaddr_in *)self.hostaddr.bytes;
        char sockip[16];
        strcpy(sockip, inet_ntoa(sockaddr->sin_addr));
        ip = [NSString stringWithCString:sockip encoding:NSUTF8StringEncoding];
    }
    else if (self.hostaddrFamily == AF_INET6) {
        struct sockaddr_in6 *sockaddr = (struct sockaddr_in6 *)self.hostaddr.bytes;
        ip = [NSString stringWithFormat:@"%04x:%04x:%04x:%04x:%04x:%04x:%04x:%04x",
              sockaddr->sin6_addr.__u6_addr.__u6_addr16[0],
              sockaddr->sin6_addr.__u6_addr.__u6_addr16[1],
              sockaddr->sin6_addr.__u6_addr.__u6_addr16[2],
              sockaddr->sin6_addr.__u6_addr.__u6_addr16[3],
              sockaddr->sin6_addr.__u6_addr.__u6_addr16[4],
              sockaddr->sin6_addr.__u6_addr.__u6_addr16[5],
              sockaddr->sin6_addr.__u6_addr.__u6_addr16[6],
              sockaddr->sin6_addr.__u6_addr.__u6_addr16[7]];
    }
    
    return ip;
}

- (void)resolveHostFinished
{
    if (self.handler) {
        self.handler(self.hostaddr);
    }
    self.handler = nil;
}

- (void)stopResolvingHost
{
    // Shut down the CFHost.
    if (self.hostRef == NULL) {
        return;
    }
    
    CFHostSetClient(self.hostRef, NULL, NULL);
    CFHostUnscheduleFromRunLoop(self.hostRef, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
    self.hostRef = NULL;
}

@end
