//
//  file: XPCAppClient.h
//  project: TaskExplorer (extension)
//  description: talk to the app, via XPC (header)
//
//  created by Patrick Wardle
//  copyright (c) 2026 Objective-See. All rights reserved.
//

#ifndef XPCAppClient_h
#define XPCAppClient_h

#import <Foundation/Foundation.h>

#import "XPCAppProto.h"

@interface XPCAppClient : NSObject <XPCAppProtocol>

/* METHODS */

//shared instance
+(instancetype)sharedInstance;

//is (app) client connected?
-(BOOL)isConnected;

//cached (remote) proxy, and the connection it belongs to
@property(nonatomic, retain)id<XPCAppProtocol> proxy;
@property(nonatomic, weak)NSXPCConnection* proxyConnection;

//drop the cached proxy (e.g. its connection was invalidated)
-(void)clearProxy;

//dylibs loaded (batched)
-(void)dylibsLoaded:(NSArray*)events;

//resync required
-(void)resyncRequired;

@end

#endif /* XPCAppClient_h */
