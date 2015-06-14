//
//  TaskEnumerator.h
//  
//
//  Created by Patrick Wardle on 5/2/15.
//
//

#import "Queue.h"
#import "3rdParty/OrderedDictionary.h"

#import <Foundation/Foundation.h>


@interface TaskEnumerator : NSObject
{
    
}

/* PROPERTIES */

//flag indicating first scan is complete
//@property BOOL firstScanComplete;

//all tasks objects
@property(nonatomic, retain)OrderedDictionary* tasks;

//all task binaries (main executables)
@property(nonatomic, retain)NSMutableDictionary* executables;

//all (opened) files
@property(nonatomic, retain)NSMutableDictionary* files;

//all dylibs
@property(nonatomic, retain)NSMutableDictionary* dylibs;

//remote XPC interface
//TODO: weak OK?
@property (nonatomic, retain) NSXPCConnection* xpcConnection;

//queue object
// ->contains watch items that should be processed
@property (nonatomic, retain) Queue* binaryQueue;



/* METHODS */

//enumerate all tasks
// ->call back into app delegate to update task (top) table
-(void)enumerateTasks;

//get list of all pids
-(OrderedDictionary*)getAllTasks;

//insert tasks into appropriate parent
// ->ensures order of parent's (by pid), is preserved
-(void)generateAncestries:(OrderedDictionary*)newTasks;

//determine if dylibs should be (re)enumerated
// ->generally yes, unless the first enumeration (of all tasks) is not complete
-(BOOL)shouldEnumDylibs;


@end
