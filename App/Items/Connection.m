//
//  Connection.m
//  TaskExplorer
//
//  Created by Patrick Wardle on 2/19/15.
//  Copyright (c) 2015 Objective-See. All rights reserved.
//
//  note: connection dictionaries (from extension) come from the NetworkStatistics framework
//        so provider ('TCP'/'UDP') and (tcp) state are strings

#import "Consts.h"
#import "Connection.h"
#import "AppDelegate.h"

@implementation Connection

@synthesize endpoints;
@synthesize remoteName;

//init method
-(id)initWithParams:(NSDictionary*)params
{
    //super
    self = [super init];
    if(nil != self)
    {
        //alloc string for connection
        endpoints = [NSMutableString string];

        //extract/save local addr
        self.localIPAddr = params[KEY_LOCAL_ADDR];

        //extract/save local port
        self.localPort = params[KEY_LOCAL_PORT];

        //extract/save remote addr
        self.remoteIPAddr = params[KEY_REMOTE_ADDR];

        //extract/save remote port
        self.remotePort = params[KEY_REMOTE_PORT];

        //extract/save proto
        // ->'TCP' or 'UDP'
        self.proto = [self provider2String:params[KEY_PROVIDER]];

        //extract/save type
        // ->derived from proto
        self.type = [self provider2Type:params[KEY_PROVIDER]];

        //extract/save family
        self.family = [self socketFamily2String:params[KEY_SOCKET_FAMILY]];

        //extract/save state
        // ->nil, unless TCP
        self.state = [self socketState2String:params[KEY_SOCKET_STATE]];

        //extract/save interface
        self.interface = params[KEY_INTERFACE];

        //extract/save bytes up
        self.bytesUp = [params[KEY_BYTES_UP] unsignedLongLongValue];

        //extract/save bytes down
        self.bytesDown = [params[KEY_BYTES_DOWN] unsignedLongLongValue];

        //name
        self.name = self.proto;

        //set icon
        [self setConnectionIcon];

        //build/set connection string
        [self setConnectionString];
    }

    return self;
}

//set icon
// ->based on state
-(void)setConnectionIcon
{
    //set icon for TCP sockets
    if(nil != self.state)
    {
        //listening
        if(YES == [self.state isEqualToString:@"listening"])
        {
            //set
            self.icon = [NSImage imageNamed:@"listeningIcon"];
        }
        //connected
        else if(YES == [self.state isEqualToString:@"established"])
        {
            //set
            self.icon = [NSImage imageNamed:@"connectedIcon"];
        }
        //closed
        else if(YES == [self.state isEqualToString:@"closed"])
        {
            //set
            self.icon = [NSImage imageNamed:@"closedIcon"];
        }
        //everything else
        // ->wait related states, etc
        else
        {
            //set
            self.icon = [NSImage imageNamed:@"closeWait"];
        }
    }

    //set icon for UDP sockets
    // ->can't listen, so just show 'em as streaming
    else
    {
        //set
        self.icon = [NSImage imageNamed:@"streamIcon"];
    }

    return;
}

//convert provider (TCP/UDP) into (lowercase) proto string
-(NSString*)provider2String:(NSString*)provider
{
    //proto
    NSString* proto = nil;

    //convert
    proto = [provider lowercaseString];

    //default
    if(0 == proto.length)
    {
        //set
        proto = @"unknown";
    }

    return proto;
}

//convert provider (TCP/UDP) into socket type string
-(NSString*)provider2Type:(NSString*)provider
{
    //socket type
    NSString* socketType = nil;

    //tcp
    if(NSOrderedSame == [provider caseInsensitiveCompare:@"TCP"])
    {
        //stream
        socketType = @"SOCK_STREAM";
    }
    //udp
    else if(NSOrderedSame == [provider caseInsensitiveCompare:@"UDP"])
    {
        //dgram
        socketType = @"SOCK_DGRAM";
    }
    //unknown
    else
    {
        //unknown
        socketType = @"unknown";
    }

    return socketType;
}

//convert a socket family into string
-(NSString*)socketFamily2String:(NSNumber*)family
{
    //socket family
    NSString* socketFamily = nil;

    //convert
    switch(family.intValue)
    {
        //ipv4
        case AF_INET:
            socketFamily = @"AF_INET";
            break;

        //ipv6
        case AF_INET6:
            socketFamily = @"AF_INET6";
            break;

        //unknown
        default:
            socketFamily = [NSString stringWithFormat:@"unknown (%d)", family.intValue];
            break;
    }

    return socketFamily;
}

//convert a (tcp) socket state into (normalized) string
// ->nstat gives us strings such as 'Established', 'Listen', 'CloseWait', etc
-(NSString*)socketState2String:(NSString*)state
{
    //socket state
    NSString* socketState = nil;

    //no state
    // ->e.g. udp
    if(0 == state.length)
    {
        //bail
        goto bail;
    }

    //listening
    if(NSOrderedSame == [state caseInsensitiveCompare:@"Listen"])
    {
        //set
        socketState = @"listening";
    }
    //established
    else if(NSOrderedSame == [state caseInsensitiveCompare:@"Established"])
    {
        //set
        socketState = @"established";
    }
    //closed
    else if(NSOrderedSame == [state caseInsensitiveCompare:@"Closed"])
    {
        //set
        socketState = @"closed";
    }
    //everything else
    // ->just lowercase
    else
    {
        //set
        socketState = [state lowercaseString];
    }

bail:

    return socketState;
}

//build printable connection string
-(void)setConnectionString
{
    //add local addr/port to endpoint string
    [self.endpoints appendString:[NSString stringWithFormat:@"%@:%d", self.localIPAddr, [self.localPort unsignedShortValue]]];

    //for remote connections
    // ->add remote endpoint
    if( (nil != self.remoteIPAddr) &&
        (nil != self.remotePort) &&
        (0 != [self.remotePort unsignedShortValue]) )
    {
        //add remote IP:port
        [self.endpoints appendString:[NSString stringWithFormat:@" -> %@:%d", self.remoteIPAddr, [self.remotePort unsignedShortValue]]];

        //add DNS name
        if(nil != self.remoteName)
        {
            //add
            [self.endpoints appendString:[NSString stringWithFormat:@" (%@)", self.remoteName]];
        }
    }

    return;
}

//override method
// ->hash
-(NSUInteger)hash
{
    return [self.endpoints hash] ^ [self.proto hash];
}

//override method
// ->equality check
-(BOOL)isEqual:(id)object
{
    //flag
    BOOL objEqual = NO;

    //check self
    if(self == object)
    {
        //match
        objEqual = YES;

        //bail
        goto bail;
    }

    //check for type
    if(YES != [object isKindOfClass:[Connection class]])
    {
        //no match
        objEqual = NO;

        //bail
        goto bail;
    }

    //do check
    // ->endpoints, proto, and state
    if( (YES == [((Connection*)object).endpoints isEqualToString:self.endpoints]) &&
        (YES == [((Connection*)object).proto isEqualToString:self.proto]) &&
        ( (((Connection*)object).state == self.state) || (YES == [((Connection*)object).state isEqualToString:self.state]) ) )
    {
        //happy
        objEqual = YES;

        //bail
        goto bail;
    }

//bail
bail:

    return objEqual;
}

//convert object to JSON string
-(NSString*)toJSON
{
    //json string
    NSString *json = nil;

    //state
    NSString* connectionState = nil;

    //interface
    NSString* connectionInterface = nil;

    //default state
    connectionState = (nil != self.state) ? self.state : @"n/a";

    //default interface
    connectionInterface = (nil != self.interface) ? self.interface : @"";

    //init json
    json = [NSString stringWithFormat:@"\"protocol\": \"%@\", \"family\": \"%@\", \"interface\": \"%@\", \"local address\": \"%@\", \"local port\": \"%d\", \"remote address\": \"%@\", \"remote port\": \"%d\", \"state\": \"%@\", \"bytes up\": \"%llu\", \"bytes down\": \"%llu\"", jsonEscape(self.proto), jsonEscape(self.family), jsonEscape(connectionInterface), jsonEscape(self.localIPAddr), [self.localPort unsignedShortValue], jsonEscape(self.remoteIPAddr), [self.remotePort unsignedShortValue], jsonEscape(connectionState), self.bytesUp, self.bytesDown];

    return json;
}

@end
