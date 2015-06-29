//
//  Extension.m
//  KnockKnock
//
//  Created by Patrick Wardle on 2/19/15.
//  Copyright (c) 2015 Objective-See. All rights reserved.
//

#import "Consts.h"
#import "Connection.h"
#import "AppDelegate.h"

@implementation Connection

@synthesize endpoints;

//init method
-(id)initWithParams:(NSDictionary*)params
{
    //super
    //self = [super initWithParams:params];
    //TODO: think about this - Connection doesn't share any baseItem stuffz
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
        if(YES == [self.state isEqualToString:SOCKET_LISTENING])
        {
            //set
            self.icon = [NSImage imageNamed:@"listeningIcon"];
        }
        //connected
        else if(YES == [self.state isEqualToString:SOCKET_ESTABLISHED])
        {
            //set
            self.icon = [NSImage imageNamed:@"connectedIcon"];
        }
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

//build nice string
-(void)setConnectionString
{
    //add local addr/port to endpoint string
    [self.endpoints appendString:[NSString stringWithFormat:@"%@:%d", self.localIPAddr, [self.localPort unsignedShortValue]]];
    
    //for remote connections
    // ->add remote endpoint
    if( (nil != self.remoteIPAddr) &&
        (nil != self.remotePort) )
    {
        //add remote endpoint
        [self.endpoints appendString:[NSString stringWithFormat:@" -> %@:%d", self.remoteIPAddr, [self.remotePort unsignedShortValue]]];
    }
    
    return;

}

/*

//convert object to JSON string
-(NSString*)toJSON
{
    //json string
    NSString *json = nil;
    
    //init json
    json = [NSString stringWithFormat:@"\"name\": \"%@\", \"path\": \"%@\", \"identifier\": \"%@\", \"details\": \"%@\", \"browser\": \"%@\"", self.name, self.path, self.identifier, self.details, self.browser];
    
    return json;
}
*/

@end
