//
//  Extension.m
//  TaskExplorer
//
//  Created by Patrick Wardle on 2/19/15.
//  Copyright (c) 2015 Objective-See. All rights reserved.
//

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
    //self = [super initWithParams:params];
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

        //extract/save type
        self.type = params[KEY_SOCKET_TYPE];
        
        //extract/save family
        self.family = params[KEY_SOCKET_FAMILY];
        
        //extract/save proto
        self.proto = params[KEY_SOCKET_PROTO];
        
        //extract/save state
        self.state = params[KEY_SOCKET_STATE];
        
        //set icon
        [self setConnectionIcon];
        
        //resolve DNS names
        if(nil != self.remoteIPAddr)
        {
            //resolve
            [self addressesForHost];
        }
        
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
        //wait related states
        else if( (YES == [self.state isEqualToString:@"close/wait"]) ||
                 (YES == [self.state isEqualToString:@"in wait 1"]) ||
                 (YES == [self.state isEqualToString:@"closing"]) ||
                 (YES == [self.state isEqualToString:@"last act"]) ||
                 (YES == [self.state isEqualToString:@"fin wait 2"]) ||
                 (YES == [self.state isEqualToString:@"time wait"]) )
        {
            //set
            self.icon = [NSImage imageNamed:@"closeWait"];
        }
        
        //closed
        else if(YES == [self.state isEqualToString:@"closed"])
        {
            //set
            self.icon = [NSImage imageNamed:@"closedIcon"];
        }
        
        //by design, other connection states won't have an icon
        // TODO: maybe add other icons?
    }
    
    //set icon for UDP sockets
    // ->can't listen, so just show em as streaming
    else if(YES == [self.type isEqualToString:@"SOCK_DGRAM"])
    {
        //set
        self.icon = [NSImage imageNamed:@"streamIcon"];
    }
    
    return;
}

//resolve a remote IP address to nice DNS name
// ->uses address and port, which are passed to getaddrinfo
//   note: call from bg thread, cuz it can be slow due to DNS resolution(s)
-(void)addressesForHost
{
    //host
    NSHost* host = nil;
    
    //init host
    host = [NSHost hostWithAddress:self.remoteIPAddr];
    
    //extract/save name
    self.remoteName = host.name;
    
    return;
}

//build printable connection string
-(void)setConnectionString
{
    //add local addr/port to endpoint string
    [self.endpoints appendString:[NSString stringWithFormat:@"%@:%d", self.localIPAddr, [self.localPort unsignedShortValue]]];
    
    //for remote connections
    // ->add remote endpoint
    if( (nil != self.remoteIPAddr) &&
        (nil != self.remotePort) )
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

//convert Connection object to a JSON string
-(NSString*)toJSON
{
    //json string
    NSString *json = nil;
    
    //init json
    json = [NSString stringWithFormat:@"\"connection\": \"%@\", \"local IP\": \"%@\", \"local port\": \"%d\", \"remote IP\": \"%@\", \"remote port\": \"%d\", \"type\": \"%@\", \"family\": \"%@\", \"protocol\": \"%@\", \"state\": \"%@\"", self.endpoints, self.localIPAddr, [self.localPort unsignedShortValue], self.remoteIPAddr, [self.remotePort unsignedShortValue], self.type, self.family, self.proto, self.state];
    
    return json;
}

@end
