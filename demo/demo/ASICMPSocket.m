//
//  ASICMPSocket.m
//  demo
//
//  Created by 孙泉 on 2019/9/16.
//  Copyright © 2019 puzzle. All rights reserved.
//

#import "ASICMPSocket.h"
#include <AssertMacros.h>           // for __Check_Compile_Time
#include <sys/socket.h>
#import <arpa/inet.h>

#pragma mark - ASICMPPacket

// Describes the on-the-wire header format for an ICMP ping. This defines the header structure of ping packets on the wire.  Both IPv4 and IPv6 use the same basic structure. This is declared in the header because clients of SimplePing might want to use it parse received ping packets.
struct ASICMPPacket {
    uint8_t type;
    uint8_t code;
    uint16_t checksum;
    uint16_t identifier;
    uint16_t sequence;
    char data[56];
};
typedef struct ASICMPPacket ASICMPPacket;
__Check_Compile_Time(sizeof(ASICMPPacket) == 64);
__Check_Compile_Time(offsetof(ASICMPPacket, type) == 0);
__Check_Compile_Time(offsetof(ASICMPPacket, code) == 1);
__Check_Compile_Time(offsetof(ASICMPPacket, checksum) == 2);
__Check_Compile_Time(offsetof(ASICMPPacket, identifier) == 4);
__Check_Compile_Time(offsetof(ASICMPPacket, sequence) == 6);

#pragma mark - ASIPv4Header

// Describes the on-the-wire header format for an IPv4 packet. This defines the header structure of IPv4 packets on the wire. We need this in order to skip this header in the IPv4 case, where the kernel passes it to us for no obvious reason.
struct ASIPv4Header {
    uint8_t versionAndHeaderLength;
    uint8_t differentiatedServices;
    uint16_t totalLength;
    uint16_t identification;
    uint16_t flagsAndFragmentOffset;
    uint8_t timeToLive;
    uint8_t protocol;
    uint16_t headerChecksum;
    uint8_t sourceAddress[4];
    uint8_t destinationAddress[4];
    // options...
    // data...
};
typedef struct ASIPv4Header ASIPv4Header;
__Check_Compile_Time(sizeof(ASIPv4Header) == 20);
__Check_Compile_Time(offsetof(ASIPv4Header, versionAndHeaderLength) == 0);
__Check_Compile_Time(offsetof(ASIPv4Header, differentiatedServices) == 1);
__Check_Compile_Time(offsetof(ASIPv4Header, totalLength) == 2);
__Check_Compile_Time(offsetof(ASIPv4Header, identification) == 4);
__Check_Compile_Time(offsetof(ASIPv4Header, flagsAndFragmentOffset) == 6);
__Check_Compile_Time(offsetof(ASIPv4Header, timeToLive) == 8);
__Check_Compile_Time(offsetof(ASIPv4Header, protocol) == 9);
__Check_Compile_Time(offsetof(ASIPv4Header, headerChecksum) == 10);
__Check_Compile_Time(offsetof(ASIPv4Header, sourceAddress) == 12);
__Check_Compile_Time(offsetof(ASIPv4Header, destinationAddress) == 16);

#pragma mark - ASICMPPacketType

typedef NS_ENUM(NSUInteger, ASICMPPacketType) {
    ASICMPPacketTypev4Send = 8, ///< The ICMP `type` for a IPv4 ping send; in this case `code` is always 0.
    ASICMPPacketTypev4Recv = 0, ///< The ICMP `type` for a IPv4 ping recv; in this case `code` is always 0.
    ASICMPPacketTypev6Send = 128, ///< The ICMP `type` for a IPv6 ping send; in this case `code` is always 0.
    ASICMPPacketTypev6Recv = 129 ///< The ICMP `type` for a ping IPv6 recv; in this case `code` is always 0.
};

static const size_t kMaxPacketSize = 65535;

@interface ASICMPSocket ()

// The identifier used by pings by this object. When you create an instance of this object it generates a random identifier that it uses to identify its own pings.
@property (nonatomic, assign) uint16_t identifier;

// The next sequence number to be used by this object. This value starts at zero and increments each time you send a ping (safely wrapping back to zero if necessary). The sequence number is included in the ping, allowing you to match up requests and responses, and thus calculate ping times and so on.
@property (nonatomic, assign) uint16_t sequence;

// if next sequence has wrapped from 65535 to 0.
@property (nonatomic, assign) BOOL hasWrapped;

// The address being pinged. The contents of the NSData is a (struct sockaddr) of some form.  The value is nil while the object is stopped and remains nil on start until
@property (nonatomic, strong) NSData *hostaddr;

// The address family for `hostAddress`, or `AF_UNSPEC` if that's nil.
@property (nonatomic, assign) sa_family_t hostaddrFamily;

// A socket object for ICMP send and receive
@property (nonatomic, strong) CFSocketRef socketRef __attribute__ ((NSObject));

@property (nonatomic, assign) NSTimeInterval sendTimestamp;

@property (nonatomic, assign) NSTimeInterval recvTimestamp;

@property (nonatomic, copy) ASDelayBlock handler;

@end

@implementation ASICMPSocket

- (instancetype)init
{
    self = [super init];
    if (self) {
        self.identifier = (uint16_t)arc4random();
    }
    return self;
}

+ (ASICMPSocket *)icmpSocket
{
    return ASICMPSocket.new;
}

- (sa_family_t)hostaddrFamily
{
    sa_family_t result = AF_UNSPEC;
    if (self.hostaddr && self.hostaddr.length >= sizeof(struct sockaddr)) {
        result = ((const struct sockaddr *)self.hostaddr.bytes)->sa_family;
    }
    return result;
}

#pragma mark - connect

- (BOOL)connect:(NSData *)hostaddr
{
    self.hostaddr = hostaddr;
    
    if (!self.hostaddr) {
        NSLog(@"Connect hostaddr can't be nil");
        return NO;
    }
    
    // Open the socket.
    int error = 0;
    int sock = -1;
    
    if (self.hostaddrFamily == AF_INET) {
        sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP);
        error = sock < 0 ? errno : error;
    }
    else if (self.hostaddrFamily == AF_INET6) {
        sock = socket(AF_INET6, SOCK_DGRAM, IPPROTO_ICMPV6);
        error = sock < 0 ? errno : error;
    }
    else {
        error = EPROTONOSUPPORT;
    }
    
    if (error != 0) {
        NSLog(@"Connect socket failed");
        return NO;
    }
    
    struct timeval timeout;
    timeout.tv_sec = 1;
    timeout.tv_usec = 0;
    setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    
    // Wrap it in a CFSocket and schedule it on the runloop.
    CFSocketContext context = {0, (__bridge void *)(self), NULL, NULL, NULL};
    self.socketRef = (CFSocketRef)CFAutorelease(CFSocketCreateWithNative(NULL, sock, kCFSocketReadCallBack, SocketRecvHandler, &context));
    
    CFRunLoopSourceRef sourceRef = CFSocketCreateRunLoopSource(NULL, self.socketRef, 0);
    CFRunLoopAddSource(CFRunLoopGetCurrent(), sourceRef, kCFRunLoopDefaultMode);
    CFRelease(sourceRef);
    
    return YES;
}

- (NSData *)icmpPacket
{
    if (self.hostaddrFamily != AF_INET && self.hostaddrFamily != AF_INET6) {
        return nil;
    }
    
    // Construct the ping packet.
    // Our dummy payload is sized so that the resulting ICMP packet, including the ICMPHeader, is
    // 64-bytes, which makes it easier to recognise our packets on the wire.
    
    ASICMPPacket *icmpPtr;
    NSMutableData *packet = [NSMutableData dataWithLength:sizeof(*icmpPtr)];
    
    icmpPtr = packet.mutableBytes;
    icmpPtr->type = (self.hostaddrFamily == AF_INET) ? ASICMPPacketTypev4Send : ASICMPPacketTypev6Send;
    icmpPtr->code = 0;
    icmpPtr->checksum = 0;
    icmpPtr->identifier = OSSwapHostToBigInt16(self.identifier);
    icmpPtr->sequence = OSSwapHostToBigInt16(self.sequence);
    memset(icmpPtr->data, 65, 56);
    
    if (self.hostaddrFamily == AF_INET) {
        // The IP checksum routine returns a 16-bit number that's already in correct byte order
        // (due to wacky 1's complement maths), so we just put it into the packet as a 16-bit unit.
        icmpPtr->checksum = [self in_cksum:packet.bytes size:packet.length];
    }
    
    return packet;
}

- (void)send:(NSData *)packet handler:(ASDelayBlock)handler
{
    self.handler = handler;
    
    if (self.socketRef == NULL || !CFSocketIsValid(self.socketRef)) {
        NSLog(@"Socket haven't connected yet");
        [self sendPacketFailed];
        return;
    }
    
    self.sendTimestamp = NSDate.date.timeIntervalSince1970;
    
    ssize_t bytesSent = sendto(CFSocketGetNative(self.socketRef), packet.bytes, packet.length, 0, self.hostaddr.bytes, (socklen_t)self.hostaddr.length);
    
    // Handle the results of the send.
    if (bytesSent > 0 && (NSUInteger)bytesSent == packet.length) {
        // Complete success.  Tell the client.
    }
    else {
        // Some sort of failure.  Tell the client.
        NSLog(@"Socket send ICMP Packet failed");
        [self sendPacketFailed];
        return;
    }
    
    self.sequence += 1;
    if (self.sequence == 0) {
        self.hasWrapped = YES;
    }
}

static void SocketRecvHandler(CFSocketRef socketRef, CFSocketCallBackType type, CFDataRef address, const void *data, void *info)
{
    // This C routine is called by CFSocket when there's data waiting on our ICMP socket.  It just redirects the call to Objective-C code.
    ASICMPSocket *obj = (__bridge ASICMPSocket *)info;
    
    // 65535 is the maximum IP packet size, which seems like a reasonable bound
    // here (plus it's what <x-man-page://8/ping> uses).
    void *buffer = malloc(kMaxPacketSize);
    
    // Actually read the data.  We use recvfrom(), and thus get back the source address,
    // but we don't actually do anything with it.  It would be trivial to pass it to
    // the delegate but we don't need it in this example.
    struct sockaddr_storage addr;
    socklen_t addrlen = sizeof(addr);
    ssize_t bytesRecv = recvfrom(CFSocketGetNative(obj.socketRef), buffer, kMaxPacketSize, 0, (struct sockaddr *)&addr, &addrlen);
    
    obj.recvTimestamp = NSDate.date.timeIntervalSince1970;
    
    if (bytesRecv <= 0) {
        NSLog(@"Socket recv 0 bytes");
        [obj sendPacketFailed];
        free(buffer);
        return;
    }
    
    NSMutableData *packet = [NSMutableData dataWithBytes:buffer length:(NSUInteger)bytesRecv];
    
    // We got some data, pass it up to our client.
    uint16_t seq;
    
    if ([obj validateRecvPacket:packet sequence:&seq]) {
        // 验证成功
        NSTimeInterval duration = obj.recvTimestamp - obj.sendTimestamp;
        if (obj.handler) {
            obj.handler(YES, duration * 1000);
        }
    }
    else {
        // 失败
        NSLog(@"ICMP recv invalid");
        [obj sendPacketFailed];
    }
    
    free(buffer);
    
    // Note that we don't loop back trying to read more data.  Rather, we just
    // let CFSocket call us again.
}

- (BOOL)validateRecvPacket:(NSMutableData *)packet sequence:(uint16_t *)seq
{
    BOOL result = NO;
    if (self.hostaddrFamily == AF_INET) {
        result = [self validateIPv4RecvPacket:packet sequence:seq];
    }
    else if (self.hostaddrFamily == AF_INET6) {
        result = [self validateIPv6RecvPacket:packet sequence:seq];
    }
    return result;
}

- (BOOL)validateIPv4RecvPacket:(NSMutableData *)packet sequence:(uint16_t *)sequence
{
    BOOL result = NO;
    ASICMPPacket *icmpPtr;
    uint16_t recvChecksum;
    uint16_t calcChecksum;
    
    NSUInteger icmpHeaderOffset = [self offsetInICMPv4Packet:packet];
    
    if (icmpHeaderOffset != NSNotFound) {
        icmpPtr = (struct ASICMPPacket *)(((uint8_t *) packet.mutableBytes) + icmpHeaderOffset);
        
        recvChecksum = icmpPtr->checksum;
        icmpPtr->checksum = 0;
        calcChecksum = [self in_cksum:icmpPtr size:packet.length - icmpHeaderOffset];
        icmpPtr->checksum  = recvChecksum;
        
        if (recvChecksum == calcChecksum) {
            if ((icmpPtr->type == ASICMPPacketTypev4Recv) && (icmpPtr->code == 0)) {
                if (OSSwapBigToHostInt16(icmpPtr->identifier) == self.identifier) {
                    uint16_t seq = OSSwapBigToHostInt16(icmpPtr->sequence);
                    if ([self validateSequence:seq]) {
                        // Remove the IPv4 header off the front of the data we received, leaving us with
                        // just the ICMP header and the ping payload.
                        [packet replaceBytesInRange:NSMakeRange(0, icmpHeaderOffset) withBytes:NULL length:0];
                        
                        *sequence = seq;
                        result = YES;
                    }
                }
            }
        }
    }
    
    return result;
}

- (NSUInteger)offsetInICMPv4Packet:(NSData *)packet
{
    // Returns the offset of the ICMPv4Header within an IP packet.
    NSUInteger result = NSNotFound;
    const struct ASIPv4Header *ipPtr;
    
    if (packet.length >= (sizeof(ASIPv4Header) + sizeof(ASICMPPacket))) {
        ipPtr = (const ASIPv4Header *)packet.bytes;
        if (((ipPtr->versionAndHeaderLength & 0xF0) == 0x40) &&            // IPv4
            (ipPtr->protocol == IPPROTO_ICMP)) {
            size_t ipHeaderLength = (ipPtr->versionAndHeaderLength & 0x0F) * sizeof(uint32_t);
            if (packet.length >= (ipHeaderLength + sizeof(ASICMPPacket))) {
                result = ipHeaderLength;
            }
        }
    }
    return result;
}

- (BOOL)validateSequence:(uint16_t)seq
{
    if (self.hasWrapped) {
        // If the sequence numbers have wrapped that we can't reliably check
        // whether this is a sequence number we sent.  Rather, we check to see
        // whether the sequence number is within the last 120 sequence numbers
        // we sent.  Note that the uint16_t subtraction here does the right
        // thing regardless of the wrapping.
        //
        // Why 120?  Well, if we send one ping per second, 120 is 2 minutes, which
        // is the standard "max time a packet can bounce around the Internet" value.
        return ((uint16_t)(self.sequence - seq)) < (uint16_t) 120;
    }
    else {
        return seq < self.sequence;
    }
}

- (BOOL)validateIPv6RecvPacket:(NSMutableData *)packet sequence:(uint16_t *)sequence
{
    BOOL result = NO;
    const ASICMPPacket *icmpPtr;
    
    if (packet.length >= sizeof(*icmpPtr)) {
        icmpPtr = packet.bytes;
        
        // In the IPv6 case we don't check the checksum because that's hard (we need to
        // cook up an IPv6 pseudo header and we don't have the ingredients) and unnecessary
        // (the kernel has already done this check).
        if ((icmpPtr->type == ASICMPPacketTypev6Recv) && (icmpPtr->code == 0)) {
            if (OSSwapBigToHostInt16(icmpPtr->identifier) == self.identifier) {
                uint16_t seq = OSSwapBigToHostInt16(icmpPtr->sequence);
                if ([self validateSequence:seq]) {
                    *sequence = seq;
                    result = YES;
                }
            }
        }
    }
    return result;
}

#pragma mark -

- (void)sendPacketFailed
{
    if (self.handler) {
        self.handler(NO, 9999);
    }
}

- (void)stop
{
    if (self.socketRef != NULL) {
        CFSocketInvalidate(self.socketRef);
    }
}

#pragma mark - checksum

// Calculates an IP checksum. This is the standard BSD checksum code, modified to use modern types.
- (uint16_t)in_cksum:(const void *)buffer size:(size_t)size
{
    size_t bytesLeft = size;
    int32_t sum = 0;
    const uint16_t *cursor = buffer;
    union {
        uint16_t us;
        uint8_t uc[2];
    } last;
    uint16_t result;
    
    // Our algorithm is simple, using a 32 bit accumulator (sum), we add sequential 16 bit words to it, and at the end, fold back all the carry bits from the top 16 bits into the lower 16 bits.
    while (bytesLeft > 1) {
        sum += *cursor;
        cursor += 1;
        bytesLeft -= 2;
    }
    
    /* mop up an odd byte, if necessary */
    if (bytesLeft == 1) {
        last.uc[0] = *(const uint8_t *)cursor;
        last.uc[1] = 0;
        sum += last.us;
    }
    
    /* add back carry outs from top 16 bits to low 16 bits */
    sum = (sum >> 16) + (sum & 0xffff); /* add hi 16 to low 16 */
    sum += (sum >> 16); /* add carry */
    result = (uint16_t)~sum; /* truncate to 16 bits */
    
    return result;
}

@end
