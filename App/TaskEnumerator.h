//
//  TaskEnumerator.h
//
//
//  Created by Patrick Wardle on 5/2/15.
//
//

#import "Task.h"
#import "Queue.h"
#import "Consts.h"
#import "Signing.h"
#import "Utilities.h"
#import "Connection.h"
#import "XPCExtensionClient.h"
#import "3rdParty/OrderedDictionary.h"

#import <signal.h>
#import <unistd.h>
#import <libproc.h>
#import <sys/proc_info.h>
#import <Foundation/Foundation.h>

@interface TaskEnumerator : NSObject
{

}

/* PROPERTIES */

//xpc client
// ->talks to (system) extension
@property(nonatomic, retain)XPCExtensionClient* xpcClient;

//enumerator thread
@property(nonatomic, retain)NSThread* enumerator;

//queue for per-exec dylib/file enumeration (bounded concurrency)
@property(nonatomic, retain)NSOperationQueue* enumerationQueue;

//(serial) queue for events
// ->from extension (process start/exit, dylib load, connections)
@property(nonatomic, retain)dispatch_queue_t eventQueue;

//queue for user-driven (per selection / tab) item refreshes
// ->separate from the event queue, so a click never waits behind a burst of live events
@property(nonatomic, retain)dispatch_queue_t refreshQueue;

//slots for concurrent shared cache (vmmap) enumerations
@property(nonatomic, retain)dispatch_semaphore_t cacheSlots;

//all tasks objects
@property(nonatomic, retain)OrderedDictionary* tasks;

//all task binaries (main executables)
@property(nonatomic, retain)NSMutableDictionary* executables;

//all dylibs
// ->key: path, value: (shared) Binary; each tracks its host pids
@property(nonatomic, retain)NSMutableDictionary* dylibs;

//all (open) files
// ->key: path, value: (shared) File; each tracks its host pids
@property(nonatomic, retain)NSMutableDictionary* files;

//all network connections
// ->(most recent) list, each tracks its host pid
@property(nonatomic, retain)NSArray* connections;

//flagged items
@property(nonatomic, retain)NSMutableArray* flaggedItems;

//queue
// ->contains binaries that should be processed
@property (nonatomic, retain)Queue* binaryQueue;

//state
// ->enum'ing tasks, dylibs, file, etc...
@property NSUInteger state;

//flag
// ->(live) monitoring started?
@property BOOL isMonitoring;

//shared cache index (via vmmap) progress
// ->'cacheIndexing' while a pass runs; done/total for the status bar
@property BOOL cacheIndexing;
@property BOOL cacheIndexComplete;
@property NSUInteger cacheIndexDone;
@property NSUInteger cacheIndexTotal;

/* METHODS */

//init
// ->w/ xpc client
-(id)initWithClient:(XPCExtensionClient*)client;

//enumerate all tasks
// ->call back into app delegate to update task (top) table
-(void)enumerateTasks:(NSNumber*)pid;

//get list of all pids
-(OrderedDictionary*)getAllTasks;

//insert tasks into appropriate parent
// ->ensures order of parent's (by pid), is preserved
-(void)generateAncestries:(OrderedDictionary*)newTasks;

//insert a (single) task into its parent
-(void)generateAncestry:(Task*)task;

//remove a task
// ->contain extra logic to remove children, etc
-(void)removeTask:(Task*)task;


//get all tasks a dylib/file is loaded into
-(NSMutableArray*)loadedIn:(id)item;

/* QUERY API */
// ->(thread-safe) snapshots & predicate queries over the model
//   note: keys for predicates are the (KVC) properties of Task/Binary/File/Connection
//         e.g. tasks: "hasConnections == YES", dylibs: "isApple == NO AND hostCount > 1"

//all tasks (snapshot)
-(NSArray*)allTasks;

//all dylibs (snapshot)
-(NSArray*)allDylibs;

//all (open) files (snapshot)
-(NSArray*)allFiles;

//all network connections (snapshot)
-(NSArray*)allConnections;

//flagged (VirusTotal) items (snapshot)
-(NSArray*)flaggedItemsSnapshot;

//is task (still) the current one for its pid? (guards against pid reuse)
-(BOOL)isCurrent:(Task*)task;

//tasks matching predicate
-(NSArray*)tasksMatching:(NSPredicate*)predicate;

//dylibs matching predicate
-(NSArray*)dylibsMatching:(NSPredicate*)predicate;

//files matching predicate
-(NSArray*)filesMatching:(NSPredicate*)predicate;

//connections matching predicate
-(NSArray*)connectionsMatching:(NSPredicate*)predicate;

//get all task pids for a given binary
-(NSMutableArray*)tasksForBinary:(Binary*)binary;

//ensure that the list of flagged items is correctly updated
// when a dead task or any of its dylibs were flagged...
-(void)updateFlaggedItems:(Task*)deadTask;

//(re)enumerate a single task's items (dylibs, files, or connections)
// ->runs in the background; results are posted via the usual 'items changed' notification
//   invoked by the UI when the user selects a process / switches tabs, so the bottom pane is always fresh
-(void)refreshItems:(Task*)task view:(NSUInteger)view;

//enumerate a task's shared cache dylibs (vmmap) in the background
-(void)enumerateCacheDylibsInBackground:(Task*)task;

//start (live) monitoring
// ->via extension: ES exec/exit/mmap + network (timer)
-(void)startMonitoring;

//index dyld shared cache dylibs for all tasks (via vmmap, a few at a time, in the background)
// ->no-op if a pass is already running; skips tasks already done
-(void)indexCacheDylibs;

//stop (live) monitoring
-(void)stopMonitoring;

/* EVENTS (from extension) */

//process started
-(void)processStarted:(NSDictionary*)processInfo;

//process exited
-(void)processExited:(NSDictionary*)processInfo;

//dylib loaded
-(void)dylibLoaded:(NSDictionary*)event;

//network connections (re)enumerated
-(void)connectionsUpdated:(NSArray*)connections;

@end
