//
//  XPCExtensionClient.m
//  TaskExplorer (app)
//
//  Created by Patrick Wardle on 9/12/26.
//  Copyright (c) 2026 Objective-See. All rights reserved.
//
//  note: talk to the (system) extension via XPC

#import "Consts.h"
#import "XPCApp.h"
#import "Utilities.h"
#import "XPCAppProto.h"
#import "XPCExtensionClient.h"

#import <os/log.h>

/* GLOBALS */

//log handle
extern os_log_t logHandle;

@implementation XPCExtensionClient

@synthesize extension;

//init
// create XPC connection & set remote obj interface
-(id)init
{
    //super
    self = [super init];
    if(nil != self)
    {
        //create connection
        //sync (w/ 'reconnect')
        @synchronized(self)
        {
            //create
            [self createConnection];
        }
    }

    return self;
}

//create (or re-create) the XPC connection to the extension
-(void)createConnection
{
    //connection
    // ->built & resumed locally, then published; other threads only ever see a fully configured connection
    //   (publishing early let a concurrent caller use it w/o a remote interface -> 'unrecognized selector', or resume it twice -> xpc api misuse)
    NSXPCConnection* connection = nil;

    //alloc/init
    connection = [[NSXPCConnection alloc] initWithMachServiceName:EXT_MACH_SERVICE options:0];

    //set remote object interface
    connection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(XPCExtensionProtocol)];

    //set exported interface/object
    // ->extension invokes these (process/dylib/connection events)
    connection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(XPCAppProtocol)];
    connection.exportedObject = [[XPCApp alloc] init];

    //set invalidation handler
    [connection setInvalidationHandler:^{

        //dbg msg
        os_log_debug(logHandle, "XPC 'invalidationHandler' method invoked");
    }];

    //set interruption handler
    [connection setInterruptionHandler:^{

        //dbg msg
        os_log_debug(logHandle, "XPC 'interruptionHandler' method invoked (extension exited/restarted?)");

        //notify
        // ->e.g. task enumerator re-arms monitoring & resyncs
        if(nil != self.connectionLostHandler)
        {
            //invoke
            self.connectionLostHandler();
        }
    }];

    //resume
    [connection resume];

    //publish
    self.extension = connection;

    return;
}

//(re)connect to the extension
// note: an NSXPCConnection that fails at lookup (e.g. the extension wasn't up yet) is *permanently*
//       invalidated & will never reconnect on its own ...so throw it away and build a new one
-(void)reconnect
{
    //old connection
    NSXPCConnection* old = nil;

    //dbg msg
    os_log_debug(logHandle, "(re)creating XPC connection to extension");

    //sync
    // ->many threads make XPC calls; swap in the new connection atomically, then invalidate the old one
    @synchronized(self)
    {
        //grab old
        old = self.extension;

        //create new (replaces 'extension')
        [self createConnection];
    }

    //invalidate old
    [old invalidate];

    return;
}

//handle XPC error
// logs, then rebuilds the (now dead) connection
-(void)handleXPCError:(NSError*)proxyError method:(const char*)method
{
    //err msg
    os_log_error(logHandle, "ERROR: failed to execute extension XPC method '%s' (error: %{public}@)", method, proxyError);

    //connection level error?
    // ->(re)create the connection; other errors (e.g. decoding) don't warrant it
    if( (YES == [proxyError.domain isEqualToString:NSCocoaErrorDomain]) &&
        ( (NSXPCConnectionInterrupted == proxyError.code) ||
          (NSXPCConnectionInvalid == proxyError.code) ) )
    {
        //reconnect
        [self reconnect];
    }

    return;
}

//wait for the extension to be up & accepting XPC connections
-(BOOL)waitForExtension:(NSUInteger)maxAttempts
{
    //flag
    __block BOOL ready = NO;

    //dbg msg
    os_log_debug(logHandle, "waiting for extension to be ready...");

    //try until the extension replies (or we give up)
    for(NSUInteger attempt = 0; attempt < maxAttempts; attempt++)
    {
        //check in
        [[self.extension synchronousRemoteObjectProxyWithErrorHandler:^(NSError * proxyError)
        {
            //dbg msg
            os_log_debug(logHandle, "check in failed (attempt: %lu), will reconnect/retry", (unsigned long)attempt);

            //reconnect
            // rebuilds the (now dead) connection for the next attempt
            [self reconnect];

        }] checkIn:^(BOOL checkedIn)
        {
            //save
            ready = checkedIn;
        }];

        //ready? done
        if(YES == ready) break;

        //nap, then retry (w/ the rebuilt connection)
        [NSThread sleepForTimeInterval:0.25f];
    }

    //dbg msg
    os_log_debug(logHandle, "extension ready? %d", ready);

    return ready;
}

//check if extension has full disk access
// note: synchronous, will block until extension responds
-(BOOL)extensionHasFullDiskAccess
{
    //flag
    __block BOOL hasFDA = NO;

    //make XPC request
    [[self.extension synchronousRemoteObjectProxyWithErrorHandler:^(NSError * proxyError)
    {
        //handle error
        [self handleXPCError:proxyError method:__PRETTY_FUNCTION__];

    }] hasFullDiskAccess:^(BOOL extensionHasFDA)
    {
        //save
        hasFDA = extensionHasFDA;
    }];

    return hasFDA;
}

//enumerate all (running) processes
// note: synchronous, will block until extension responds
-(NSArray*)enumerateProcesses
{
    //processes
    __block NSArray* processes = nil;

    //dbg msg
    os_log_debug(logHandle, "invoking extension XPC method, '%s'", __PRETTY_FUNCTION__);

    //make XPC request
    [[self.extension synchronousRemoteObjectProxyWithErrorHandler:^(NSError * proxyError)
    {
        //handle error
        [self handleXPCError:proxyError method:__PRETTY_FUNCTION__];

    }] enumerateProcesses:^(NSArray* extensionProcesses)
    {
        //save
        processes = extensionProcesses;
    }];

    return processes;
}

//enumerate (loaded) dylibs for a process
// note: synchronous, will block until extension responds
-(NSArray*)enumerateDylibs:(pid_t)pid
{
    //dylibs
    __block NSArray* dylibs = nil;

    //make XPC request
    [[self.extension synchronousRemoteObjectProxyWithErrorHandler:^(NSError * proxyError)
    {
        //handle error
        [self handleXPCError:proxyError method:__PRETTY_FUNCTION__];

    }] enumerateDylibs:pid reply:^(NSArray* extensionDylibs)
    {
        //save
        dylibs = extensionDylibs;
    }];

    return dylibs;
}

//enumerate (open) files for a process
// note: synchronous, will block until extension responds
-(NSArray*)enumerateFiles:(pid_t)pid
{
    //files
    __block NSArray* files = nil;

    //make XPC request
    [[self.extension synchronousRemoteObjectProxyWithErrorHandler:^(NSError * proxyError)
    {
        //handle error
        [self handleXPCError:proxyError method:__PRETTY_FUNCTION__];

    }] enumerateFiles:pid reply:^(NSArray* extensionFiles)
    {
        //save
        files = extensionFiles;
    }];

    return files;
}

//enumerate (all) network connections
// note: synchronous, will block until extension responds
-(NSArray*)enumerateConnections
{
    //connections
    __block NSArray* connections = nil;

    //semaphore
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    //make XPC request
    // ->async w/ a timeout, as the reply depends on NetworkStatistics' completion (which shouldn't, but could, never come)
    [[self.extension remoteObjectProxyWithErrorHandler:^(NSError * proxyError)
    {
        //handle error
        [self handleXPCError:proxyError method:__PRETTY_FUNCTION__];

        //signal
        dispatch_semaphore_signal(semaphore);

    }] enumerateConnections:^(NSArray* extensionConnections)
    {
        //save
        connections = extensionConnections;

        //signal
        dispatch_semaphore_signal(semaphore);
    }];

    //wait (w/ timeout)
    if(0 != dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(15 * NSEC_PER_SEC))))
    {
        //err msg
        os_log_error(logHandle, "ERROR: timed out waiting for extension to enumerate connections");
    }

    return connections;
}

//start monitoring
// note: synchronous, will block until extension responds
-(BOOL)startMonitoring
{
    //flag
    __block BOOL started = NO;

    //dbg msg
    os_log_debug(logHandle, "invoking extension XPC method, '%s'", __PRETTY_FUNCTION__);

    //make XPC request
    [[self.extension synchronousRemoteObjectProxyWithErrorHandler:^(NSError * proxyError)
    {
        //handle error
        [self handleXPCError:proxyError method:__PRETTY_FUNCTION__];

    }] startMonitoring:^(BOOL extensionStarted)
    {
        //save
        started = extensionStarted;
    }];

    return started;
}

//stop monitoring
// note: synchronous, will block until extension responds
-(BOOL)stopMonitoring
{
    //flag
    __block BOOL stopped = NO;

    //dbg msg
    os_log_debug(logHandle, "invoking extension XPC method, '%s'", __PRETTY_FUNCTION__);

    //semaphore
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    //make XPC request (async, w/ a timeout)
    // ->called on quit; a wedged extension must not keep the app from terminating
    [[self.extension remoteObjectProxyWithErrorHandler:^(NSError * proxyError)
    {
        //handle error
        [self handleXPCError:proxyError method:__PRETTY_FUNCTION__];

        //signal
        dispatch_semaphore_signal(semaphore);

    }] stopMonitoring:^(BOOL extensionStopped)
    {
        //save
        stopped = extensionStopped;

        //signal
        dispatch_semaphore_signal(semaphore);
    }];

    //wait (max 5s)
    if(0 != dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC))))
    {
        //err msg
        os_log_error(logHandle, "ERROR: extension did not respond to 'stopMonitoring' within 5s");
    }

    return stopped;
}



//enumerate all dylibs (incl. dyld shared cache) via vmmap (in extension)
-(NSArray*)enumerateAllDylibs:(pid_t)pid
{
    //dylibs
    __block NSArray* dylibs = nil;

    //make XPC request
    [[self.extension synchronousRemoteObjectProxyWithErrorHandler:^(NSError * proxyError)
    {
        //handle error
        [self handleXPCError:proxyError method:__PRETTY_FUNCTION__];

    }] enumerateAllDylibs:pid reply:^(NSArray* extensionDylibs)
    {
        //save
        dylibs = extensionDylibs;
    }];

    return dylibs;
}

//extract binary info (via extension, as root)
-(NSDictionary*)extractBinaryInfo:(pid_t)pid auditToken:(NSData*)auditToken path:(NSString*)path
{
    //binary info
    __block NSDictionary* binaryInfo = nil;

    //make XPC request
    [[self.extension synchronousRemoteObjectProxyWithErrorHandler:^(NSError * proxyError)
    {
        //handle error
        [self handleXPCError:proxyError method:__PRETTY_FUNCTION__];

    }] extractBinaryInfo:pid auditToken:auditToken path:path reply:^(NSDictionary* extensionBinaryInfo)
    {
        //save
        binaryInfo = extensionBinaryInfo;
    }];

    return binaryInfo;
}

//hash a file (via extension, as root)
-(NSDictionary*)hashFile:(NSString*)path
{
    //hashes
    __block NSDictionary* hashes = nil;

    //make XPC request
    [[self.extension synchronousRemoteObjectProxyWithErrorHandler:^(NSError * proxyError)
    {
        //handle error
        [self handleXPCError:proxyError method:__PRETTY_FUNCTION__];

    }] hashFile:path reply:^(NSDictionary* fileHashes)
    {
        //save
        hashes = fileHashes;
    }];

    return hashes;
}

@end
