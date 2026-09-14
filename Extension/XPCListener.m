//
//  file: XPCListener.m
//  project: TaskExplorer (extension)
//  description: XPC listener for connections from the app
//
//  created by Patrick Wardle
//  copyright (c) 2026 Objective-See. All rights reserved.
//

#import "Consts.h"
#import "Utilities.h"
#import "XPCListener.h"
#import "XPCAppClient.h"
#import "XPCExtension.h"
#import "XPCAppProto.h"
#import "ProcessMonitor.h"
#import "NetworkMonitor.h"
#import "XPCExtensionProto.h"

#import <os/log.h>
#import <bsm/libbsm.h>

/* GLOBALS */

//log handle
extern os_log_t logHandle;

//(ES) process monitor
extern ProcessMonitor* processMonitor;

//network monitor
extern NetworkMonitor* networkMonitor;

//interface for 'extension' to NSXPCConnection
// allows us to access the 'private' auditToken iVar
@interface ExtendedNSXPCConnection : NSXPCConnection
{
    //private iVar
    audit_token_t auditToken;
}
//private iVar
@property audit_token_t auditToken;

@end

//implementation for 'extension' to NSXPCConnection
// allows us to access the 'private' auditToken iVar
@implementation ExtendedNSXPCConnection

//private iVar
@synthesize auditToken;

@end

@implementation XPCListener

@synthesize client;
@synthesize listener;

//init
// create XPC listener
-(id)init
{
    //code signing requirement
    NSString* requirement = nil;

    //init super
    self = [super init];
    if(nil != self)
    {
        //init listener
        listener = [[NSXPCListener alloc] initWithMachServiceName:EXT_MACH_SERVICE];

        //macOS 13+
        // set code signing requirement for clients via 'setConnectionCodeSigningRequirement'
        if(@available(macOS 13.0, *)) {

            //init requirement
            requirement = [NSString stringWithFormat:@"anchor apple generic and identifier \"%@\" and certificate leaf [subject.OU] = \"%@\"", APP_ID, TEAM_ID];

            //set requirement
            [self.listener setConnectionCodeSigningRequirement:requirement];

            //dbg msg
            os_log_debug(logHandle, "set XPC requirement %{public}@", requirement);
        }

        //dbg msg
        os_log_debug(logHandle, "created mach service %{public}@", EXT_MACH_SERVICE);

        //set delegate
        self.listener.delegate = self;

        //ready to accept connections
        [self.listener resume];
    }

    return self;
}

#pragma mark -
#pragma mark NSXPCConnection method overrides

//automatically invoked
// allows NSXPCListener to configure/accept/resume a new incoming NSXPCConnection
// shoutout to writeup: https://blog.obdev.at/what-we-have-learned-from-a-vulnerability
-(BOOL)listener:(NSXPCListener *)listener shouldAcceptNewConnection:(NSXPCConnection *)newConnection
{
    //(weak) connection, for the invalidation handler
    __weak NSXPCConnection* weakConnection = nil;

    //flag
    BOOL shouldAccept = NO;

    //status
    OSStatus status = !errSecSuccess;

    //audit token
    audit_token_t auditToken = {0};

    //task ref
    SecTaskRef taskRef = 0;

    //code ref
    SecCodeRef codeRef = NULL;

    //code signing info
    CFDictionaryRef csInfo = NULL;

    //cs flags
    uint32_t csFlags = 0;

    //signing req string (main app)
    NSString* requirement = nil;

    //extract audit token
    auditToken = ((ExtendedNSXPCConnection*)newConnection).auditToken;

    //dbg msg
    os_log_debug(logHandle, "received request to connect to XPC interface from: (%d)%{public}@", audit_token_to_pid(auditToken), getProcessPath(audit_token_to_pid(auditToken)));

    //obtain dynamic code ref
    status = SecCodeCopyGuestWithAttributes(NULL, (__bridge CFDictionaryRef _Nullable)(@{(__bridge NSString *)kSecGuestAttributeAudit : [NSData dataWithBytes:&auditToken length:sizeof(audit_token_t)]}), kSecCSDefaultFlags, &codeRef);
    if(errSecSuccess != status)
    {
        //err msg
        os_log_error(logHandle, "ERROR: 'SecCodeCopyGuestWithAttributes' failed with': %#x", status);

        //bail
        goto bail;
    }

    //validate code
    status = SecCodeCheckValidity(codeRef, kSecCSDefaultFlags, NULL);
    if(errSecSuccess != status)
    {
        //err msg
        os_log_error(logHandle, "ERROR: 'SecCodeCheckValidity' failed with': %#x", status);

        //bail
        goto bail;
    }

    //get code signing info
    status = SecCodeCopySigningInformation(codeRef, kSecCSDynamicInformation, &csInfo);
    if(errSecSuccess != status)
    {
        //err msg
        os_log_error(logHandle, "ERROR: 'SecCodeCopySigningInformation' failed with': %#x", status);

        //bail
        goto bail;
    }

    //extract flags
    csFlags = [((__bridge NSDictionary *)csInfo)[(__bridge NSString *)kSecCodeInfoStatus] unsignedIntValue];

    //dbg msg
    os_log_debug(logHandle, "client code signing flags: %#x", csFlags);

    //gotta have hardened runtime
    if( !(CS_VALID & csFlags) ||
        !(CS_RUNTIME & csFlags) )
    {
        //err msg
        os_log_error(logHandle, "ERROR: invalid code signing flags: %#x", csFlags);

        //bail
        goto bail;
    }

    //dbg msg
    os_log_debug(logHandle, "client code signing flags, ok (includes 'CS_RUNTIME')");

    //init signing req
    requirement = [NSString stringWithFormat:@"anchor apple generic and identifier \"%@\" and certificate leaf [subject.OU] = \"%@\"", APP_ID, TEAM_ID];

    //step 1: create task ref
    // uses NSXPCConnection's (private) 'auditToken' iVar
    taskRef = SecTaskCreateWithAuditToken(NULL, ((ExtendedNSXPCConnection*)newConnection).auditToken);
    if(NULL == taskRef)
    {
        //bail
        goto bail;
    }

    //step 2: validate
    // check that client is signed with Objective-See's cert and it's TaskExplorer
    if(errSecSuccess != (status = SecTaskValidateForRequirement(taskRef, (__bridge CFStringRef)(requirement))))
    {
        //err msg
        os_log_error(logHandle, "ERROR: failed with validate client (error: %#x/%d)", status, status);

        //bail
        goto bail;
    }

#ifndef DEBUG
    //step 3: (release) reject debuggable clients
    // ->a development-signed copy passes the requirement above, but carries 'get-task-allow': lldb could drive us via it
    {
        CFTypeRef debuggable = SecTaskCopyValueForEntitlement(taskRef, CFSTR("com.apple.security.get-task-allow"), NULL);
        BOOL isDebuggable = ( (NULL != debuggable) && (CFBooleanGetTypeID() == CFGetTypeID(debuggable)) && CFBooleanGetValue(debuggable) );
        if(NULL != debuggable) CFRelease(debuggable);
        if(YES == isDebuggable)
        {
            //err msg
            os_log_error(logHandle, "ERROR: client is debuggable ('get-task-allow'); rejecting");

            //bail
            goto bail;
        }
    }
#endif

    //dbg msg
    os_log_debug(logHandle, "client code signing information, ok");

    //set the interface that the exported object implements
    newConnection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(XPCExtensionProtocol)];

    //set object exported by connection
    newConnection.exportedObject = [[XPCExtension alloc] init];

    //set type of remote object
    // app will set this object (used to deliver events)
    newConnection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol: @protocol(XPCAppProtocol)];

    //set interruption handler
    [newConnection setInterruptionHandler:^{

        //dbg msg
        os_log_debug(logHandle, "XPC 'interruptionHandler' method invoked");

    }];

    //set invalidation handler
    //set invalidation handler
    // ->stops monitoring, but only if this connection is (still) the client; the app may have reconnected already
    weakConnection = newConnection;
    {
    [newConnection setInvalidationHandler:^{

        //dbg msg
        os_log_debug(logHandle, "XPC 'invalidationHandler' method invoked ...client is gone");

        //superseded by a newer client?
        if( (nil != self.client) &&
            (self.client != weakConnection) )
        {
            //dbg msg
            os_log_debug(logHandle, "...a newer client is connected, so leaving monitoring running");

            //bail
            return;
        }

        //unset
        self.client = nil;

        //drop the cached proxy (it retains this connection)
        [[XPCAppClient sharedInstance] clearProxy];

        //stop (ES) monitoring
        [processMonitor stop];

        //stop network monitoring
        [networkMonitor stop];

    }];
    }

    //save
    self.client = newConnection;

    //resume
    [newConnection resume];

    //dbg msg
    os_log_debug(logHandle, "allowing XPC connection from client (pid: %d)", audit_token_to_pid(auditToken));

    //happy
    shouldAccept = YES;

bail:

    //release task ref object
    if(NULL != taskRef)
    {
        //release
        CFRelease(taskRef);
        taskRef = NULL;
    }

    //free cs info
    if(NULL != csInfo)
    {
        //free
        CFRelease(csInfo);
        csInfo = NULL;
    }

    //free code ref
    if(NULL != codeRef)
    {
        //free
        CFRelease(codeRef);
        codeRef = NULL;
    }

    return shouldAccept;
}

@end
