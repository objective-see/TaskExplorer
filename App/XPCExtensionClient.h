//
//  XPCExtensionClient.h
//  TaskExplorer (app)
//
//  Created by Patrick Wardle on 9/12/26.
//  Copyright (c) 2026 Objective-See. All rights reserved.
//
//  note: talk to the (system) extension via XPC

#ifndef XPCExtensionClient_h
#define XPCExtensionClient_h

#import <Foundation/Foundation.h>

#import "XPCExtensionProto.h"

@interface XPCExtensionClient : NSObject
{

}

/* PROPERTIES */

//xpc connection to extension
@property(atomic, strong, readwrite)NSXPCConnection* extension;

//invoked when the connection is interrupted (extension exited/restarted)
// ->set by the task enumerator, to re-arm monitoring & resync
@property(nonatomic, copy)void (^connectionLostHandler)(void);

/* METHODS */

//wait for the extension to be up & accepting XPC connections
// note: blocks, so call from a background thread
-(BOOL)waitForExtension:(NSUInteger)maxAttempts;

//check if extension has full disk access
// note: synchronous
-(BOOL)extensionHasFullDiskAccess;

//enumerate all (running) processes
// note: synchronous
-(NSArray*)enumerateProcesses;

//enumerate (loaded) dylibs for a process
// note: synchronous
-(NSArray*)enumerateDylibs:(pid_t)pid;

//enumerate (open) files for a process
// note: synchronous
-(NSArray*)enumerateFiles:(pid_t)pid;

//enumerate all dylibs (incl. dyld shared cache) via vmmap (in extension)
-(NSArray*)enumerateAllDylibs:(pid_t)pid;

//enumerate (all) network connections
// note: synchronous
-(NSArray*)enumerateConnections;

//extract binary info (via extension, as root): signing info & mach-o flags
// ->pid: dynamic signing check (then static via path); pid 0: static via path
-(NSDictionary*)extractBinaryInfo:(pid_t)pid auditToken:(NSData*)auditToken path:(NSString*)path;

//hash a file (via extension, as root)
-(NSDictionary*)hashFile:(NSString*)path;

//start monitoring
// note: synchronous
-(BOOL)startMonitoring;

//stop monitoring
// note: synchronous
-(BOOL)stopMonitoring;

@end

#endif /* XPCExtensionClient_h */
