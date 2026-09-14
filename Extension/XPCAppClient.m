//
//  file: XPCAppClient.m
//  project: TaskExplorer (extension)
//  description: talk to the app, via XPC
//
//  created by Patrick Wardle
//  copyright (c) 2026 Objective-See. All rights reserved.
//

#import "Consts.h"
#import "XPCListener.h"
#import "XPCAppClient.h"

#import <os/log.h>

/* GLOBALS */

//log handle
extern os_log_t logHandle;

//xpc listener
extern XPCListener* xpcListener;

@implementation XPCAppClient

//shared instance
+(instancetype)sharedInstance
{
    //once
    static dispatch_once_t once = 0;

    //instance
    static XPCAppClient* instance = nil;

    //init
    dispatch_once(&once, ^{

        //alloc/init
        instance = [[XPCAppClient alloc] init];
    });

    return instance;
}

//is (app) client connected?
-(BOOL)isConnected
{
    return (nil != xpcListener.client);
}

//get remote (app) proxy
// note: nil if no client is connected
-(id<XPCAppProtocol>)remoteApp
{
    //proxy
    id<XPCAppProtocol> proxy = nil;

    //client
    NSXPCConnection* client = xpcListener.client;

    //no client?
    if(nil == client)
    {
        //bail
        goto bail;
    }

    //sync
    @synchronized(self)
    {
        //(re)create proxy?
        // ->cached per connection, so each event doesn't allocate a new proxy object
        if( (nil == self.proxy) ||
            (self.proxyConnection != client) )
        {
            //create
            self.proxy = [client remoteObjectProxyWithErrorHandler:^(NSError * _Nonnull error) {

                //dbg msg (per event, so not an error-level log)
                os_log_debug(logHandle, "failed to deliver event to app (error: %{public}@)", error);
            }];

            //save
            self.proxyConnection = client;
        }

        //grab
        proxy = self.proxy;
    }

bail:

    return proxy;
}

//process started
-(void)processStarted:(NSDictionary*)process
{
    //deliver
    [[self remoteApp] processStarted:process];

    return;
}

//process exited
-(void)processExited:(NSDictionary*)process
{
    //deliver
    [[self remoteApp] processExited:process];

    return;
}

//dylib loaded
-(void)dylibLoaded:(NSDictionary*)event
{
    //deliver
    [[self remoteApp] dylibLoaded:event];

    return;
}

//network connections (re)enumerated
//dylibs loaded (batched)
-(void)dylibsLoaded:(NSArray*)events
{
    //forward
    [[self remoteApp] dylibsLoaded:events];

    return;
}

//resync required
-(void)resyncRequired
{
    //forward
    [[self remoteApp] resyncRequired];

    return;
}

-(void)connectionsUpdated:(NSArray*)connections
{
    //deliver
    [[self remoteApp] connectionsUpdated:connections];

    return;
}

//drop the cached proxy
// ->otherwise it keeps the (dead) connection alive until the next client connects
-(void)clearProxy
{
    //sync
    @synchronized(self)
    {
        //clear
        self.proxy = nil;
        self.proxyConnection = nil;
    }

    return;
}

@end
