//
//  file: main.m
//  project: TaskExplorer (extension)
//  description: main entry point for (endpoint security) system extension
//
//  created by Patrick Wardle
//  copyright (c) 2026 Objective-See. All rights reserved.
//

//FOR LOGGING:
// % log stream --level debug --predicate="subsystem='com.objective-see.taskexplorer'"

#import "main.h"

#import <os/log.h>
#import <Foundation/Foundation.h>

/* GLOBALS */

//log handle
os_log_t logHandle = nil;

//main
// init globals & XPC listener, then wait for (app) clients
int main(int argc, char *argv[])
{
    //pool
    @autoreleasepool {

    //init log
    logHandle = os_log_create(BUNDLE_ID, "extension");

    //dbg msg
    os_log_debug(logHandle, "started: %{public}@ (pid: %d / uid: %d)", NSProcessInfo.processInfo.arguments.firstObject, getpid(), getuid());

    //alloc/init enumerator
    enumerator = [[Enumerator alloc] init];

    //alloc/init (ES) process monitor
    // note: doesn't start until client asks
    processMonitor = [[ProcessMonitor alloc] init];

    //alloc/init network monitor
    // note: doesn't start until client asks
    networkMonitor = [[NetworkMonitor alloc] init];

    //alloc/init XPC comms object
    xpcListener = [[XPCListener alloc] init];

    //dbg msg
    os_log_debug(logHandle, "created client XPC listener");

    }//pool

    //run forever
    dispatch_main();

    return 0;
}
