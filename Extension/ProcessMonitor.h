//
//  file: ProcessMonitor.h
//  project: TaskExplorer (extension)
//  description: (endpoint security) process/dylib monitor (header)
//
//  created by Patrick Wardle
//  copyright (c) 2026 Objective-See. All rights reserved.
//

#ifndef ProcessMonitor_h
#define ProcessMonitor_h

#import <Foundation/Foundation.h>
#import <EndpointSecurity/EndpointSecurity.h>

/* TYPEDEFS */

//callback block
// type: ES event type, event: process/dylib dictionary
typedef void (^ProcessCallbackBlock)(NSUInteger type, NSDictionary* _Nonnull event);

@interface ProcessMonitor : NSObject

/* PROPERTIES */

//endpoint client
@property es_client_t* _Nullable client;

//callback
//note: atomic: read by the ES handler (its own thread) while 'stop' clears it
@property(atomic, copy)ProcessCallbackBlock _Nullable callback;

/* METHODS */

//start monitoring
// subscribes to ES exec, exit, and mmap (notify) events
-(BOOL)start:(ProcessCallbackBlock _Nonnull)callback;

//stop monitoring
-(BOOL)stop;

//check if we're permitted to create an ES client
// ->i.e. extension has full disk access (TCC)
-(BOOL)isPermitted;

//convert an ES string token to a string
NSString* _Nullable convertStringToken(es_string_token_t* _Nullable stringToken);

@end

#endif /* ProcessMonitor_h */
