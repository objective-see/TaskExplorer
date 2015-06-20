//
//  TaskEnumerator.m
//  
//
//  Created by Patrick Wardle on 5/2/15.
//
//

#import <libproc.h>
#import <sys/proc_info.h>

#import "Task.h"
#import "Consts.h"
#import "AppDelegate.h"
#import "Utilities.h"
#import "TaskEnumerator.h"
#import "serviceInterface.h"
#include <signal.h>
#include <unistd.h>




@implementation TaskEnumerator


@synthesize files;
@synthesize tasks;
@synthesize dylibs;
@synthesize binaryQueue;
@synthesize executables;
@synthesize xpcConnection;

//@synthesize firstScanComplete;

//init
-(id)init
{
    //init super
    self = [super init];
    if(nil != self)
    {
        //init tasks dictionary
        tasks = [[OrderedDictionary alloc] init];
        
        //alloc executables dictionary
        executables = [NSMutableDictionary dictionary];
        
        //alloc dylibs dictionary
        dylibs = [NSMutableDictionary dictionary];
        
        //alloc XPC connection
        xpcConnection = [[NSXPCConnection alloc] initWithServiceName:@"com.objective-see.remoteTaskService"];
        
        //set remote object interface
        self.xpcConnection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(remoteTaskProto)];
        
        //set classes
        // ->arrays & strings are what is ok to vend
        [self.xpcConnection.remoteObjectInterface
         setClasses: [NSSet setWithObjects: [NSMutableArray class], [NSMutableDictionary class], [NSString class], nil]
         forSelector: @selector(enumerateDylibs:withReply:)
         argumentIndex: 0  // the first parameter
         ofReply: YES // in the method itself.
         ];
        
        //set classes
        // ->arrays & strings are what is ok to vend
        [self.xpcConnection.remoteObjectInterface
         setClasses: [NSSet setWithObjects: [NSMutableArray class], [NSMutableDictionary class], [NSString class], nil]
         forSelector: @selector(enumerateFiles:withReply:)
         argumentIndex: 0  // the first parameter
         ofReply: YES // in the method itself.
         ];
        
        //set classes
        // ->arrays & strings are what is ok to vend
        [self.xpcConnection.remoteObjectInterface
         setClasses: [NSSet setWithObjects: [NSMutableArray class], [NSMutableDictionary class], [NSString class], [NSNumber class], nil]
         forSelector: @selector(enumerateNetwork:withReply:)
         argumentIndex: 0  // the first parameter
         ofReply: YES // in the method itself.
         ];

        //resume
        [self.xpcConnection resume];
        
        //init binary processing queue
        binaryQueue = [[Queue alloc] init];
    }
    
    return self;
}


//enumerate all tasks
// ->call back into app delegate to update task (top) table
//   call every x # of seconds~

-(void)enumerateTasks
{
    //(new) task item
    Task* newTask = nil;

    //new tasks
    OrderedDictionary* newTasks = nil;
    
    //get all tasks
    // ->pids and binary obj with just path/name
    newTasks = [self getAllTasks];
    
    //build ancestries
    [self generateAncestries:newTasks];
    
    //add all tasks that are really new to 'tasks' iVar
    // ->ensures existing task and their info are reused
    for(NSNumber* key in newTasks.allKeys)
    {
        //get task
        newTask = newTasks[key];
        
        //remove any non-new (i.e. existing) tasks
        if(nil != self.tasks[newTask.pid])
        {
            //not new
            // ->remove
            [newTasks removeObjectForKey:key];
            
            //next
            continue;
        }
        
        //add new task
        [self.tasks setObject:newTask forKey:newTask.pid];
        
    }//add new tasks
    
    //sort tasks
    // ->ensures that signing info etc w/ be generated for (top) visible tasks
    [((AppDelegate*)[[NSApplication sharedApplication] delegate]) sortTasksForView:newTasks];
    
    //reload task table
    [((AppDelegate*)[[NSApplication sharedApplication] delegate]) reloadTaskTable];
    
    //now generate signing info
    // ->for (new) tasks & their dylibs
    for(NSNumber* key in newTasks)
    {
        //get task
        newTask = newTasks[key];
        
        //generate signing info
        [newTask.binary generatedSigningInfo];
        
        //reload task (row) in table
        [((AppDelegate*)[[NSApplication sharedApplication] delegate]) reloadRow:newTask item:newTask.binary pane:PANE_TOP];
    
        //reload bottom pane
        // ->this will only reload if new task is the currently selected one, etc
        [((AppDelegate*)[[NSApplication sharedApplication] delegate]) reloadBottomPane:newTask itemView:CURRENT_VIEW];

    }//signing info for all tasks and dylibs
    
    return;
}

//get list of all pids
-(OrderedDictionary*)getAllTasks
{
    //tasks
    // ->pid/name
    OrderedDictionary* allTasks = nil;
    
    //task
    Task* task = nil;
    
    //alloc/init list
    allTasks = [[OrderedDictionary alloc] init];
    
    //# of procs
    int numberOfProcesses = 0;
    
    //array of pids
    pid_t* pids = NULL;
    
    //buffer for process path
    char pathBuffer[PROC_PIDPATHINFO_MAXSIZE] = {0};
    
    //status
    int status = -1;
    
    //process ID
    NSNumber* processID = nil;
    
    //process name
    NSString* processName = nil;
    
    //get # of procs
    numberOfProcesses = proc_listpids(PROC_ALL_PIDS, 0, NULL, 0);
    
    //alloc buffer for pids
    pids = calloc(numberOfProcesses, sizeof(pid_t));
    
    //get list of pids
    status = proc_listpids(PROC_ALL_PIDS, 0, pids, numberOfProcesses * sizeof(pid_t));
    if(status < 0)
    {
        //err
        NSLog(@"OBJECTIVE-SEE ERROR: proc_listpids() failed with %d", status);
        
        //bail
        goto bail;
    }
    
    //iterate over all pids
    // ->get name for each
    for(int i = 0; i < numberOfProcesses; ++i)
    {
        //skip blank pids
        if(0 == pids[i])
        {
            //skip
            continue;
        }
        
        //reset buffer
        bzero(pathBuffer, PROC_PIDPATHINFO_MAXSIZE);
        
        //init process ID
        processID = [NSNumber numberWithInt:pids[i]];
        
        //get path
        status = proc_pidpath(pids[i], pathBuffer, sizeof(pathBuffer));
        
        //sanity check
        // ->this generally just fails if process has exited....
        if( (status < 0) ||
            (0 == strlen(pathBuffer)) )
        {
            //skip
            continue;
        }
            
        //init process name
        processName = [NSString stringWithUTF8String:pathBuffer];
        
        //init task
        // ->pass in pid and name
        task = [[Task alloc] initWithPID:processID andPath:processName];
        
        //add task to list
        // ->order by pid for now
        [allTasks setObject:task forKey:processID];
    }
    
    //always add kernel's task
    // ->hardcoded pid (0) and path to kernel
    task = [[Task alloc] initWithPID:@0 andPath:path2Kernel()];
    
    //add kernel task
    [allTasks setObject:task forKey:@0];
    
//bail
bail:
    
    //free buffer
    if(NULL != pids)
    {
        //free
        free(pids);
    }
    
    //dbg msg
    //NSLog(@"OBJECTIVE-SEE INFO: done scanning running processes");
    
    return allTasks;
}

//insert tasks into appropriate parent
// ->ensures order of parent's (by pid), is preserved
//TODO: what about parentless procs!? (e.g. malware?)
-(void)generateAncestries:(OrderedDictionary*)newTasks
{
    //task
    Task* task = nil;
    
    //parent
    Task* parent = nil;
    
    //comparator
    NSComparator comparator = nil;
    
    //index
    // ->where task should be inserted into parent's child array
    NSUInteger childIndex = 0;
    
    //init comparator
    // ->sort pids
    comparator = ^(id obj1, id obj2)
    {
        if (obj1 < obj2)
            return NSOrderedAscending;
        
        if (obj1 > obj2)
            return NSOrderedDescending;
        
        return NSOrderedSame;
    };
    
    //interate over all task
    // ->insert task into parent's *ordered* child array
    for(NSNumber* key in newTasks.allKeys)
    {
        //get task
        task = newTasks[key];
        
        //get parent
        parent = newTasks[task.ppid];
        
        //ignore tasks that are their own parent
        // ->i.e. kernel_task
        if(YES == [task.pid isEqualToNumber:task.ppid])
        {
            //skip
            continue;
        }

        //get index where child should be inserted
        childIndex = [parent.children indexOfObject:task.pid
                      inSortedRange:(NSRange){0, [parent.children count]}
                      options:NSBinarySearchingInsertionIndex usingComparator:comparator];
        
        //insert child
        [parent.children insertObject:task.pid atIndex:childIndex];
        
    }
    
    return;
}

//remove a task
// ->contain extra logic to remove children, etc
-(void)removeTask:(Task*)task
{
    //parent
    Task* parent = nil;
    
    //children
    NSMutableArray* children = nil;
    
    //alloc array for children
    children = [NSMutableArray array];

    //get all children
    [self getAllChildren:task children:children];
    
    //remove all child tasks
    for(NSNumber* childPid in children)
    {
        //remove
        [self.tasks removeObjectForKey:childPid];
    }
    
    //remove task
    [self.tasks removeObjectForKey:task.pid];
    
    //get parent
    parent = [self.tasks objectForKey:task.ppid];
    
    //remove task from parent's list of children
    [parent.children removeObject:task.pid];
    
    return;
    
}

//given a task
// ->get list of all child pids
-(void)getAllChildren:(Task*)parent children:(NSMutableArray*)children
{
    //child task
    Task* childTask = nil;
    
    //add parent's children
    [children addObjectsFromArray:parent.children];
    
    for(NSNumber* childPid in parent.children)
    {
        //get child task
        childTask = self.tasks[childPid];
        
        if(0 != [childTask.children count])
        {
            //recurse
            [self getAllChildren:childTask children:children];
        }
    }
    
    return;
}


@end
