//
//  ASHostResolver.h
//  demo
//
//  Created by 孙泉 on 2019/9/16.
//  Copyright © 2019 puzzle. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef void(^ASHostRevolveBlock)(NSData *hostaddr);

@interface ASHostResolver : NSObject

+ (ASHostResolver *)hostResolver;

- (void)resolveHost:(NSString *)host handler:(ASHostRevolveBlock)handler;

// The address family for `hostAddress`, or `AF_UNSPEC` if that's nil.
@property (nonatomic, assign) sa_family_t hostaddrFamily;

@property (nonatomic, strong) NSString *hostip;

+ (NSString *)hostip:(NSData *)hostaddr;


@end
