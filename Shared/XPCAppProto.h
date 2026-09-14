//
//  file: XPCAppProto.h
//  project: TaskExplorer (shared)
//  description: methods exported by the app (invoked by the extension)
//
//  created by Patrick Wardle
//  copyright (c) 2026 Objective-See. All rights reserved.
//

#ifndef XPCAppProto_h
#define XPCAppProto_h

#import <Foundation/Foundation.h>
#import <sys/types.h>

@protocol XPCAppProtocol

//process started (ES_EVENT_TYPE_NOTIFY_EXEC)
// process dictionary (see KEY_PROCESS_* in Consts.h)
-(void)processStarted:(NSDictionary*)process;

//process exited (ES_EVENT_TYPE_NOTIFY_EXIT)
// process dictionary (pid, exit status)
-(void)processExited:(NSDictionary*)process;

//dylib loaded (ES_EVENT_TYPE_NOTIFY_MMAP)
// event dictionary (pid, dylib path)
-(void)dylibLoaded:(NSDictionary*)event;

//dylibs loaded (batched mmap events; array of the same dictionaries as 'dylibLoaded:')
-(void)dylibsLoaded:(NSArray*)events;

//resync required
// ->extension detected dropped ES events (sequence gap); app should re-enumerate
-(void)resyncRequired;

//network connections (re)enumerated
// array of (all) connection dictionaries
-(void)connectionsUpdated:(NSArray*)connections;

@end

#endif /* XPCAppProto_h */
