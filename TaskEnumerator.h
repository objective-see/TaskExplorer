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
#import "3rdParty/OrderedDictionary.h"

#import <syslog.h>
#import <signal.h>
#import <unistd.h>
#import <libproc.h>
#import <sys/proc_info.h>
#import <Foundation/Foundation.h>

@interface TaskEnumerator : NSObject
{
    
}

/* PROPERTIES */

//all tasks objects
@property(nonatomic, retain)OrderedDictionary* tasks;

//all task binaries (main executables)
@property(nonatomic, retain)NSMutableDictionary* executables;

//all dylibs
@property(nonatomic, retain)NSMutableDictionary* dylibs;

//flagged items
@property(nonatomic, retain)NSMutableArray* flaggedItems;

//queue
// ->contains binaries that should be processed
@property (nonatomic, retain)Queue* binaryQueue;

//state
// ->enum'ing tasks, dylibs, file, etc...
@property NSUInteger state;

/* METHODS */

//enumerate all tasks
// ->call back into app delegate to update task (top) table
-(void)enumerateTasks:(NSNumber*)pid;

//get list of all pids
-(OrderedDictionary*)getAllTasks;

//insert tasks into appropriate parent
// ->ensures order of parent's (by pid), is preserved
-(void)generateAncestries:(OrderedDictionary*)newTasks;

//remove a task
// ->contain extra logic to remove children, etc
-(void)removeTask:(Task*)task;

//given a task
// ->get list of all child pids
-(void)getAllChildren:(Task*)parent children:(NSMutableArray*)children;

//get all tasks a dylib/file is loaded into
-(NSMutableArray*)loadedIn:(id)item;

//get all task pids for a given binary
-(NSMutableArray*)tasksForBinary:(Binary*)binary;

//ensure that the list of flagged items is correctly updated
// when a dead task or any of its dylibs were flagged...
-(void)updateFlaggedItems:(Task*)deadTask;


@end
