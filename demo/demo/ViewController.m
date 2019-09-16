//
//  ViewController.m
//  demo
//
//  Created by 孙泉 on 2019/9/2.
//  Copyright © 2019 puzzle. All rights reserved.
//

#import "ViewController.h"
#import "ASHostResolver.h"
#import "ASICMPSocket.h"
#import "ASPingService.h"

@interface ViewController ()

{
    ASHostResolver *resolver;
    NSData *hostaddr;
    ASICMPSocket *socket;
}

@property (weak, nonatomic) IBOutlet UITextField *hostTextField;
@property (weak, nonatomic) IBOutlet UILabel *ipLabel;
@property (weak, nonatomic) IBOutlet UILabel *delayLabel;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    NSTimer *t = [NSTimer timerWithTimeInterval:3 repeats:YES block:^(NSTimer * _Nonnull timer) {
        [self ping:nil];
    }];
    [NSRunLoop.currentRunLoop addTimer:t forMode:NSRunLoopCommonModes];
}

- (IBAction)revolseHost:(id)sender
{
    resolver = ASHostResolver.hostResolver;
    [resolver resolveHost:self.hostTextField.text handler:^(NSData *hostaddr) {
        if (hostaddr) {
            self->hostaddr = hostaddr;
            self.ipLabel.text = self->resolver.hostip;
        }
        else {
            self.ipLabel.text = @"Error";
        }
    }];
}

- (IBAction)conncet:(id)sender {
    socket = ASICMPSocket.icmpSocket;
    [socket connect:hostaddr];
}

- (IBAction)send:(id)sender {
    NSData *packet = socket.icmpPacket;
    [socket send:packet handler:^(BOOL result, CGFloat delay) {
        if (result) {
            self.delayLabel.text = [NSString stringWithFormat:@"%.3f ms", delay];
        }
        else {
            self.delayLabel.text = @"error";
        }
    }];
}

- (IBAction)ping:(id)sender {
    [socket stop];
    
    [ASPingService ping:self.hostTextField.text resolution:^(NSData *hostaddr) {
        if (hostaddr) {
            self.ipLabel.text = [ASHostResolver hostip:hostaddr];
        }
        else {
            self.ipLabel.text = @"error";
        }
    } handler:^(BOOL result, CGFloat delay) {
        if (result) {
            self.delayLabel.text = [NSString stringWithFormat:@"%.3f ms", delay];
        }
        else {
            self.delayLabel.text = @"error";
        }
    }];
}

@end
