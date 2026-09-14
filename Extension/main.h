//
//  file: main.h
//  project: TaskExplorer (extension)
//  description: main (header)
//
//  created by Patrick Wardle
//  copyright (c) 2026 Objective-See. All rights reserved.
//

#ifndef main_h
#define main_h

#import "Consts.h"
#import "Utilities.h"
#import "Enumerator.h"
#import "XPCListener.h"
#import "ProcessMonitor.h"
#import "NetworkMonitor.h"

/* GLOBALS */

//XPC listener obj
XPCListener* xpcListener = nil;

//enumerator obj
Enumerator* enumerator = nil;

//(ES) process monitor obj
ProcessMonitor* processMonitor = nil;

//network monitor obj
NetworkMonitor* networkMonitor = nil;

#endif /* main_h */
