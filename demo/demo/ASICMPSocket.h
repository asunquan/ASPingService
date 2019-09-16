//
//  ASICMPSocket.h
//  demo
//
//  Created by 孙泉 on 2019/9/16.
//  Copyright © 2019 puzzle. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

typedef void(^ASDelayBlock)(BOOL result, CGFloat delay);

@interface ASICMPSocket : NSObject

+ (ASICMPSocket *)icmpSocket;

- (BOOL)connect:(NSData *)hostaddr;

- (NSData *)icmpPacket;

- (void)send:(NSData *)packet handler:(ASDelayBlock)handler;

- (void)stop;

@end
