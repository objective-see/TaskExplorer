//
//  XPCApp.m
//  TaskExplorer (app)
//
//  Created by Patrick Wardle on 9/12/26.
//  Copyright (c) 2026 Objective-See. All rights reserved.
//
//  note: methods invoked by the extension (event delivery)
//        ...just hands events off to the task enumerator

#import "Consts.h"
#import "XPCApp.h"
#import "AppDelegate.h"
#import "TaskEnumerator.h"

#import <os/log.h>

/* GLOBALS */

//log handle
extern os_log_t logHandle;

//task enumerator
extern TaskEnumerator* taskEnumerator;

@implementation XPCApp

//process started (ES_EVENT_TYPE_NOTIFY_EXEC)
-(void)processStarted:(NSDictionary*)process
{
    //dbg msg
    os_log_debug(logHandle, "XPC event: process started (pid: %{public}@, path: %{public}@)", process[KEY_PROCESS_ID], process[KEY_PROCESS_PATH]);

    //hand off
    [taskEnumerator processStarted:process];

    return;
}

//process exited (ES_EVENT_TYPE_NOTIFY_EXIT)
-(void)processExited:(NSDictionary*)process
{
    //dbg msg
    os_log_debug(logHandle, "XPC event: process exited (pid: %{public}@)", process[KEY_PROCESS_ID]);

    //hand off
    [taskEnumerator processExited:process];

    return;
}

//dylib loaded (ES_EVENT_TYPE_NOTIFY_MMAP)
-(void)dylibLoaded:(NSDictionary*)event
{
    //hand off
    [taskEnumerator dylibLoaded:event];

    return;
}

//network connections (re)enumerated
//dylibs loaded (batched mmap events)
-(void)dylibsLoaded:(NSArray*)events
{
    //dbg msg
    os_log_debug(logHandle, "XPC event: dylibs loaded (%lu)", (unsigned long)events.count);

    //process each
    for(NSDictionary* event in events)
    {
        //forward
        [taskEnumerator dylibLoaded:event];
    }

    return;
}

//resync required
// ->extension detected dropped ES events; re-enumerate everything
-(void)resyncRequired
{
    //dbg msg
    os_log_debug(logHandle, "XPC event: resync required (extension detected dropped events)");

    //refresh (on main)
    dispatch_async(dispatch_get_main_queue(), ^{

        //refresh
        [(AppDelegate*)NSApp.delegate refreshTasks:nil];
    });

    return;
}

-(void)connectionsUpdated:(NSArray*)connections
{
    //dbg msg
    os_log_debug(logHandle, "XPC event: connections updated (%lu)", (unsigned long)connections.count);

    //hand off
    [taskEnumerator connectionsUpdated:connections];

    return;
}

@end
