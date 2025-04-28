//
//  main.m
//  remoteTaskService
//
//  Created by Patrick Wardle on 5/27/15.
//  Copyright (c) 2015 Objective-See, LLC. All rights reserved.
//

#import "../Utilities.h"
#import "serviceInterface.h"
#import "remoteTaskService.h"


#import <syslog.h>
#import <libproc.h>
#import <sys/proc_info.h>
#import <Foundation/Foundation.h>

//interface for 'extension' to NSXPCConnection
// ->allows us to access the 'private' auditToken iVar
@interface ExtendedNSXPCConnection : NSXPCConnection
{
    //private iVar
    audit_token_t auditToken;
}
//private iVar
@property audit_token_t auditToken;

@end

//implementation for 'extension' to NSXPCConnection
// ->allows us to access the 'private' auditToken iVar
@implementation ExtendedNSXPCConnection

//private iVar
@synthesize auditToken;

@end

//function def
OSStatus SecTaskValidateForRequirement(SecTaskRef task, CFStringRef requirement);

//signing auth
#define SIGNING_AUTH @"Developer ID Application: Objective-See, LLC (VBG97UB4TA)"

//skeleton interface
@interface ServiceDelegate : NSObject <NSXPCListenerDelegate>
@end

@implementation ServiceDelegate

//automatically invoked
//->allows NSXPCListener to configure/accept/resume a new incoming NSXPCConnection
//  note: we only allow binaries signed by Objective-See to talk to this!
-(BOOL)listener:(NSXPCListener *)listener shouldAcceptNewConnection:(NSXPCConnection *)newConnection
{
    //flag
    BOOL shouldAccept = NO;
    
    //task ref
    SecTaskRef taskRef = 0;

    //signing req string
    NSString *requirementString = nil;
    
    //init signing req string
    requirementString = [NSString stringWithFormat:@"anchor trusted and certificate leaf [subject.CN] = \"%@\"", SIGNING_AUTH];

    //step 1: create task ref
    // ->uses NSXPCConnection's (private) 'auditToken' iVar
    taskRef = SecTaskCreateWithAuditToken(NULL, ((ExtendedNSXPCConnection*)newConnection).auditToken);
    if(NULL == taskRef)
    {
        //bail
        goto bail;
    }
    
    //step 2: validate
    // ->check that client is signed with Objective-See's dev cert
    if(0 != SecTaskValidateForRequirement(taskRef, (__bridge CFStringRef)(requirementString)))
    {
        //bail
        goto bail;
    }
    
    //set the interface that the exported object implements
    newConnection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(remoteTaskProto)];
    
    //set object exported by connection
    newConnection.exportedObject = [remoteTaskService new];
    
    //resume
    [newConnection resume];
    
    //happy
    shouldAccept = YES;

//bail
bail:
    
    //release task ref object
    if(NULL != taskRef)
    {
        //release
        CFRelease(taskRef);
        
        //unset
        taskRef = NULL;
    }
    
    return shouldAccept;
}

@end

//main entrypoint
// ->install exception handlers & setup/kickoff listener
int main(int argc, const char *argv[])
{
    //ret var
    int status = -1;
    
    //service delegate
    ServiceDelegate* delegate = nil;
    
    //listener
    NSXPCListener* listener = nil;
        
    //make really r00t
    // ->needed for exec'ing vmmap, etc
    if(0 != setuid(0))
    {
        //err msg
        syslog(LOG_ERR, "OBJECTIVE-SEE TASKEXPLORER ERROR: setuid() failed with: %d\n", errno);
        
        //bail
        goto bail;
    }
    
    //create the delegate for the service.
    delegate = [ServiceDelegate new];
    
    //set up the one NSXPCListener for this service
    // ->handles incoming connections
    listener = [NSXPCListener serviceListener];
    
    //set delegate
    listener.delegate = delegate;
    
    //resuming the listener starts this service
    // ->method does not return
    [listener resume];
    
    //happy
    status = 0;
    
//bail
bail:
    
    return status;
}
