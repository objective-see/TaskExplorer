//
//  ModelNotify.m
//  TaskExplorer (app)
//
//  Created by Patrick Wardle on 9/12/26.
//  Copyright (c) 2026 Objective-See. All rights reserved.
//
//  note: the (objective-c) model notifies the (swift) UI of changes via these notifications
//        ...all are posted on the main queue

#import "Consts.h"
#import "ModelNotify.h"

/* GLOBALS */

//cmdline flag
extern BOOL cmdlineMode;

//notification names
NSNotificationName const TETasksChangedNotification = @"com.objective-see.taskexplorer.tasksChanged";
NSNotificationName const TETaskChangedNotification = @"com.objective-see.taskexplorer.taskChanged";
NSNotificationName const TEItemsChangedNotification = @"com.objective-see.taskexplorer.itemsChanged";
NSNotificationName const TEBinaryChangedNotification = @"com.objective-see.taskexplorer.binaryChanged";
NSNotificationName const TEStatusChangedNotification = @"com.objective-see.taskexplorer.statusChanged";
NSNotificationName const TEEnumerationStateChangedNotification = @"com.objective-see.taskexplorer.enumerationStateChanged";

//post (on main queue)
// note: skipped in cmdline mode (no UI)
static void post(NSNotificationName name, id object, NSDictionary* userInfo)
{
    //cmdline mode?
    if(YES == cmdlineMode)
    {
        //bail
        return;
    }

    //post on main queue
    dispatch_async(dispatch_get_main_queue(), ^{

        //post
        [[NSNotificationCenter defaultCenter] postNotificationName:name object:object userInfo:userInfo];
    });

    return;
}

//tasks changed
void notifyTasksChanged(void)
{
    post(TETasksChangedNotification, nil, nil);
}

//task changed
void notifyTaskChanged(Task* task)
{
    post(TETaskChangedNotification, task, nil);
}

//task's items changed
void notifyItemsChanged(Task* task, NSUInteger view)
{
    post(TEItemsChangedNotification, task, @{@"view":@(view)});
}

//binary changed
void notifyBinaryChanged(Binary* binary)
{
    post(TEBinaryChangedNotification, binary, nil);
}

//status changed
void notifyStatus(NSString* status)
{
    post(TEStatusChangedNotification, status, nil);
}

//enumeration state changed
void notifyEnumerationState(void)
{
    post(TEEnumerationStateChangedNotification, nil, nil);
}
