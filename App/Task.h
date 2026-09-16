//
//  Task.h
//  TaskExplorer
//
//  Created by Patrick Wardle on 5/2/15.
//  Copyright (c) 2015 Objective-See, LLC. All rights reserved.
//

#import "Binary.h"
#import "File.h"
#import "Connection.h"
#import <Foundation/Foundation.h>

NS_SWIFT_NAME(TETask)
@interface Task : NSObject
{

}

/* PROPERTIES */

//pid
@property(nonatomic, retain)NSNumber* pid;

//main binary
@property(nonatomic, retain)Binary* binary;

//process args
@property(nonatomic, retain)NSMutableArray* arguments;

//loaded dylibs
@property(nonatomic, retain)NSMutableArray* dylibs;

//open files
@property(nonatomic, retain)NSMutableArray* files;

//connections
@property(nonatomic, retain)NSMutableArray* connections;

//uid
@property uid_t uid;

//parent's pid
//note: atomic: rewritten on the event queue (re-parenting) while read on main
@property(atomic, retain)NSNumber* ppid;

//responsible pid
@property(nonatomic, retain)NSNumber* rpid;

//children
@property(nonatomic, retain)NSMutableArray* children;

//start time
@property(nonatomic, retain)NSDate* startTime;

//audit token
@property(nonatomic, retain)NSData* auditToken;

//include dyld shared cache dylibs (on demand, via vmmap)
// ->set when the user asks for them for this task; the global index pref covers all tasks
@property BOOL includeCacheDylibs;

//dyld shared cache dylibs were enumerated (via vmmap)
@property BOOL cacheDylibsEnumerated;

//discovered at
// ->when this task object was created (snapshot or live event); used by the snapshot diff
@property(nonatomic, retain)NSDate* discoveredAt;

//(raw) info from extension
// includes ES info (cs flags, signing/team id, platform binary, cdhash) for live processes
@property(nonatomic, retain)NSDictionary* info;

/* (KVC) QUERY PROPERTIES */
// ->readonly, computed; used by #keyword predicates & the assistant tools
//   note: unknown keys (e.g. 'isApple', 'signer') are forwarded to the task's binary

//name (of binary)
@property(nonatomic, readonly)NSString* name;

//path (of binary)
@property(nonatomic, readonly)NSString* path;

//has network connections?
@property(nonatomic, readonly)BOOL hasConnections;

//has listening socket(s)?
@property(nonatomic, readonly)BOOL isListening;

//platform binary (per ES)
@property(nonatomic, readonly)BOOL isPlatformBinary;

//endpoint security client (per ES / csops)
// ->its shared cache dylibs are never enumerated (vmmap would suspend it; a suspended ES client gets killed)
@property(nonatomic, readonly)BOOL isESClient;

//team id (from ES, or signing info)
@property(nonatomic, readonly)NSString* teamID;

//dylibs whose team id differs from the task's
// ->ignores apple/dyld-cache dylibs
@property(nonatomic, readonly)NSArray* mismatchedDylibs;

//has mismatched dylibs?
@property(nonatomic, readonly)BOOL hasMismatchedDylibs;

/* METHODS */

//init w/ process info (dictionary) from extension
// note: icons are dynamically determined only when process is shown in alert
-(id)initWithInfo:(NSDictionary*)processInfo;

//generate signing info (for main binary)
// dynamic (via audit token/pid), falling back to static
-(void)generateSigningInfo;

//enumerate all dylibs (via extension)
// ->new ones are added to 'existingDylibs' (global) dictionary
-(void)enumerateDylibs:(NSMutableDictionary*)allDylibs;

//enumerate all dylibs, optionally incl. those from the dyld shared cache (via vmmap, in the extension)
-(void)enumerateDylibs:(NSMutableDictionary*)allDylibs includeCache:(BOOL)includeCache;

//add a (single) dylib
// ->e.g. from a (live) mmap event
-(Binary*)addDylib:(NSString*)dylibPath allDylibs:(NSMutableDictionary*)allDylibs;

//enumerate all open files (via extension)
-(void)enumerateFiles;

//set network connections
// ->from array of connection dictionaries (from extension)
-(void)setConnectionsFromInfo:(NSArray*)connectionInfos;

//remove self as host from all items (dylibs, files, connections)
// ->invoked when task exits
-(void)unhostAll;

//convert self to JSON string
-(NSString*)toJSON:(BOOL)detailed;

//(thread-safe) snapshots of dylibs/files/connections
-(NSArray<Binary*>*)dylibsSnapshot;

//number of dylibs (cheap; no copy)
-(NSUInteger)dylibCount;
-(NSArray<File*>*)filesSnapshot;
-(NSArray<Connection*>*)connectionsSnapshot;

//children (copy, under the tasks lock)
-(NSArray*)childrenSnapshot;

@end
