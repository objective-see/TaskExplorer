//
//  Extension.h
//  TaskExplorer
//
//  Created by Patrick Wardle on 2/19/15.
//  Copyright (c) 2015 Objective-See. All rights reserved.
//

#import "ItemBase.h"

#import <netdb.h>
#import <arpa/inet.h>
#import <netinet/tcp_fsm.h>
#import <Foundation/Foundation.h>

//socket states
// ->note, index correspondes to numberic value
static const char* socketStates[] =
{
    "closed",
    "listening",
    "syn sent",
    "syn received",
    "established",
    "close/wait",
    "fin wait 1",
    "closing",
    "last act",
    "fin wait 2",
    "time wait",
};

static const char *socketFamilies[] =
{
    "AF_UNSPEC",
    "AF_UNIX",
    "AF_INET",
    "AF_IMPLINK",
    "AF_PUP",
    "AF_CHAOS",
    "AF_NS",
    "AF_ISO",
    "AF_ECMA",
    "AF_DATAKIT",
    "AF_CCITT",
    "AF_SNA",
    "AF_DECnet",
    "AF_DLI",
    "AF_LAT",
    "AF_HYLINK",
    "AF_APPLETALK",
    "AF_ROUTE",
    "AF_LINK",
    "#define",
    "AF_COIP",
    "AF_CNT",
    "pseudo_AF_RTIP",
    "AF_IPX",
    "AF_SIP",
    "pseudo_AF_PIP",
    "pseudo_AF_BLUE",
    "AF_NDRV",
    "AF_ISDN",
    "pseudo_AF_KEY",
    "AF_INET6",
    "AF_NATM",
    "AF_SYSTEM",
    "AF_NETBIOS",
    "AF_PPP",
    "pseudo_AF_HDRCMPLT",
    "AF_RESERVED_36",
};
#define SOCKET_FAMILY_MAX (int)(sizeof(socketFamilies)/sizeof(char *))



@interface Connection : ItemBase
{
    
}

//local ip addr
@property(nonatomic, retain)NSString* localIPAddr;

//local port
@property(nonatomic, retain)NSNumber* localPort;

//remote ip addr
@property(nonatomic, retain)NSString* remoteIPAddr;

//remote port
@property(nonatomic, retain)NSNumber* remotePort;

//remote name (url)
@property(nonatomic, retain)NSString* remoteName;

//socket type
@property(nonatomic, retain)NSString* type;

//socket family
@property(nonatomic, retain)NSString* family;

//socket proto
@property(nonatomic, retain)NSString* proto;

//socket state
@property(nonatomic, retain)NSString* state;

//pretty print of connnection
@property(nonatomic, retain)NSMutableString* endpoints;


/* METHODS */

//set icon
-(void)setConnectionIcon;

//return a string representation of the connection
-(void)setConnectionString;



@end
