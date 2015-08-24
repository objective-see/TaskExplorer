//
//  main.m
//  remoteTaskService
//
//  Created by Patrick Wardle on 5/27/15.
//  Copyright (c) 2015 Objective-See, LLC. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "remoteTaskService.h"
#import "serviceInterface.h"

#import <libproc.h>
#import <sys/proc_info.h>
#import <syslog.h>

//TODO: CHANGE B4 RELEASE!!
//-> for testing: @"Mac Developer: patrick wardle (5SKKU32KLJ)"
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
    
    //status
    int status = -1;
    
    //buffer for process path
    char pathBuffer[PROC_PIDPATHINFO_MAXSIZE] = {0};
    
    //code
    SecStaticCodeRef staticCode = NULL;
    
    //signing reqs
    SecRequirementRef requirementRef = NULL;
    
    //signing req string
    NSString *requirementString = nil;
    
    //init signing req string
    // ->check for Ojective-See's dev cert
    requirementString = [NSString stringWithFormat:@"anchor trusted and certificate leaf [subject.CN] = \"%@\"", SIGNING_AUTH];
    
    //get path
    status = proc_pidpath(newConnection.processIdentifier, pathBuffer, sizeof(pathBuffer));
    
    //sanity check
    // ->this generally just fails if process has exited....
    if( (status < 0) ||
        (0 == strlen(pathBuffer)) )
    {
        //bail
        goto bail;
    }
    
    //create static code
    if(0 != SecStaticCodeCreateWithPath((__bridge CFURLRef)([NSURL fileURLWithPath:[NSString stringWithUTF8String:pathBuffer]]), kSecCSDefaultFlags, &staticCode))
    {
        //bail
        goto bail;
    }
    
    //create req string w/ 'anchor apple'
    // (3rd party: 'anchor apple generic')
    if(0 != SecRequirementCreateWithString((__bridge CFStringRef)requirementString, kSecCSDefaultFlags, &requirementRef))
    {
        //bail
        goto bail;
    }
    
    //check if file is signed by apple
    // ->i.e. it conforms to req string
    if(0 != SecStaticCodeCheckValidity(staticCode, kSecCSDefaultFlags, requirementRef))
    {
        //err msg
        syslog(LOG_ERR, "OBJECTIVE-SEE ERROR: SecStaticCodeCheckValidity() failed on %s", pathBuffer);
        
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
    
    return shouldAccept;
}

@end

int main(int argc, const char *argv[])
{
    // Create the delegate for the service.
    ServiceDelegate *delegate = [ServiceDelegate new];
    
    // Set up the one NSXPCListener for this service. It will handle all incoming connections.
    NSXPCListener *listener = [NSXPCListener serviceListener];
    listener.delegate = delegate;
    
    // Resuming the serviceListener starts this service. This method does not return.
    [listener resume];
    return 0;
}
