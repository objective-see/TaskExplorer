//
//  Extension.m
//  TaskExplorer (app)
//
//  Created by Patrick Wardle on 9/12/26.
//  Copyright (c) 2026 Objective-See. All rights reserved.
//
//  note: (de)activates the (endpoint security) system extension

#import "Consts.h"
#import "Extension.h"
#import "Utilities.h"

/* GLOBALS */

//log handle
extern os_log_t logHandle;

@implementation Extension

@synthesize replyBlock;
@synthesize needsApproval;

//submit request to toggle system extension
-(void)toggleExtension:(NSUInteger)action reply:(replyBlockType)reply
{
    //request
    OSSystemExtensionRequest* request = nil;

    //dbg msg
    os_log_debug(logHandle, "toggling extension (action: %lu)", (unsigned long)action);

    //save reply
    self.replyBlock = reply;

    //activation request
    if(ACTION_ACTIVATE == action)
    {
        //dbg msg
        os_log_debug(logHandle, "creating activation request");

        //init request
        request = [OSSystemExtensionRequest activationRequestForExtension:EXT_BUNDLE_ID queue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0)];
    }
    //deactivation request
    else
    {
        //dbg msg
        os_log_debug(logHandle, "creating deactivation request");

        //init request
        request = [OSSystemExtensionRequest deactivationRequestForExtension:EXT_BUNDLE_ID queue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0)];
    }

    //sanity check
    if(nil == request)
    {
        //err msg
        os_log_error(logHandle, "ERROR: failed to create request for extension");

        //call reply
        self.replyBlock([NSError errorWithDomain:@BUNDLE_ID code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Failed to create system extension request"}]);

        //bail
        goto bail;
    }

    //set delegate
    request.delegate = self;

    //dbg msg
    os_log_debug(logHandle, "submitting request");

    //submit request
    [OSSystemExtensionManager.sharedManager submitRequest:request];

bail:

    return;
}

//check if extension is running
-(BOOL)isExtensionRunning
{
    return (0 != [findProcesses(EXT_BUNDLE_ID) count]);
}

//deactivate extension (synchronously)
// ->macOS prompts the user for admin credentials (GUI app only; refused for root/cli processes with error 13),
//   and the NEXT activation needs the user's approval in System Settings again (verified 2026-09-13)
//   note: blocks (up to 'timeout' seconds), so call from a background thread
-(BOOL)deactivate:(NSTimeInterval)timeout
{
    //flag
    __block BOOL deactivated = NO;

    //semaphore
    dispatch_semaphore_t semaphore = nil;

    //init semaphore
    semaphore = dispatch_semaphore_create(0);

    //dbg msg
    os_log_debug(logHandle, "deactivating extension...");

    //submit deactivation request
    [self toggleExtension:ACTION_DEACTIVATE reply:^(NSError* error) {

        //error?
        if(nil != error)
        {
            //err msg
            os_log_error(logHandle, "ERROR: failed to deactivate extension: %{public}@", error);
        }
        //deactivated
        else
        {
            //dbg msg
            os_log_debug(logHandle, "deactivated extension");

            //set flag
            deactivated = YES;
        }

        //signal
        dispatch_semaphore_signal(semaphore);
    }];

    //wait
    // ->w/ timeout, so we never hang on exit
    if(0 != dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC))))
    {
        //err msg
        os_log_error(logHandle, "ERROR: timed out waiting for extension to deactivate");
    }

    return deactivated;
}

#pragma mark -
#pragma mark OSSystemExtensionRequest delegate methods

//replace delegate method
// always replaces, so return 'OSSystemExtensionReplacementActionReplace'
-(OSSystemExtensionReplacementAction)request:(nonnull OSSystemExtensionRequest *)request actionForReplacingExtension:(nonnull OSSystemExtensionProperties *)existing withExtension:(nonnull OSSystemExtensionProperties *)ext
{
    //dbg msg
    os_log_debug(logHandle, "method '%s' invoked with %{public}@, %{public}@ -> %{public}@", __PRETTY_FUNCTION__, request.identifier, existing.bundleShortVersion, ext.bundleShortVersion);

    return OSSystemExtensionReplacementActionReplace;
}

//error delegate method
-(void)request:(nonnull OSSystemExtensionRequest *)request didFailWithError:(nonnull NSError *)error
{
    //err msg
    os_log_error(logHandle, "ERROR: method '%s' invoked with %{public}@, %{public}@", __PRETTY_FUNCTION__, request, error);

    //invoke reply
    self.replyBlock(error);

    return;
}

//finish delegate method
-(void)request:(nonnull OSSystemExtensionRequest *)request didFinishWithResult:(OSSystemExtensionRequestResult)result
{
    //error
    NSError* error = nil;

    //dbg msg
    os_log_debug(logHandle, "method '%s' invoked with %{public}@, %ld", __PRETTY_FUNCTION__, request, (long)result);

    //request will complete after reboot?
    if(OSSystemExtensionRequestWillCompleteAfterReboot == result)
    {
        //log msg
        os_log(logHandle, "system extension request will complete after reboot");

        //set error
        error = [NSError errorWithDomain:@BUNDLE_ID
                                    code:result
                                userInfo:@{
                                    NSLocalizedDescriptionKey: @"System extension request will complete after reboot",
                                    NSLocalizedFailureReasonErrorKey: @"The system extension is not active until after the next restart",
        }];
    }
    //issue/error?
    else if(OSSystemExtensionRequestCompleted != result)
    {
        //err msg
        os_log_error(logHandle, "ERROR: result %ld is an unexpected result for system extension request", (long)result);

        //set error
        error = [NSError errorWithDomain:@BUNDLE_ID
                                    code:result
                                userInfo:@{
                                    NSLocalizedDescriptionKey: [NSString stringWithFormat:@"System extension request failed with result: %ld", (long)result],
                                    NSLocalizedFailureReasonErrorKey: @"Unexpected result from system extension request",
        }];
    }

    //reply
    self.replyBlock(error);

    return;
}

//user approval delegate
// set flag, so UI can tell user to approve
-(void)requestNeedsUserApproval:(nonnull OSSystemExtensionRequest *)request
{
    //dbg msg
    os_log_debug(logHandle, "method '%s' invoked with %{public}@", __PRETTY_FUNCTION__, request);

    //set flag
    self.needsApproval = YES;

    return;
}

@end
