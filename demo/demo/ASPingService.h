//
//  ASPingService.h
//  demo
//
//  Created by 孙泉 on 2019/9/16.
//  Copyright © 2019 puzzle. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

typedef void(^ASHostBlock)(NSData *hostaddr);
typedef void(^ASPingBlock)(BOOL result, CGFloat delay);

@interface ASPingService : NSObject

+ (void)ping:(NSString *)host handler:(ASPingBlock)handler;

+ (void)ping:(NSString *)host resolution:(ASHostBlock)resolution handler:(ASPingBlock)handler;

@end
