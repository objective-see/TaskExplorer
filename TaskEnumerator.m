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

#import <syslog.h>
#import <signal.h>
#import <unistd.h>


@implementation TaskEnumerator


@synthesize files;
@synthesize tasks;
@synthesize dylibs;
@synthesize binaryQueue;
@synthesize executables;


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
        
        //init binary processing queue
        binaryQueue = [[Queue alloc] init];

    }
    
    return self;
}


//enumerate all tasks
// ->calls back into app delegate to update task (top) table when pau
//   TODO: call every x # of seconds?
//   TODO: existsing tasks w/ nil vtInfo, call [vtObject addItem:binary] ?
-(void)enumerateTasks
{
    //(new) task item
    Task* newTask = nil;
    
    //dead tasks
    NSArray *deadTasks = nil;

    //new tasks
    OrderedDictionary* newTasks = nil;
    
    //set connected flag
    ((AppDelegate*)[[NSApplication sharedApplication] delegate]).isConnected = isNetworkConnected();

    //get all tasks
    // ->pids and binary obj with just path/name
    newTasks = [self getAllTasks];
    
    //build ancestries
    // ->do here, and use 'new tasks' since there might be new parents too
    [self generateAncestries:newTasks];
    
    //get all tasks that are pau
    deadTasks = [self.tasks.allKeys filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"NOT SELF IN %@", newTasks.allKeys]];
    
    //remove any old tasks that have exited/died
    // ->invoke custom method to handle kids too...
    for(NSNumber* key in deadTasks)
    {
        //remove
        [self removeTask:self.tasks[key]];
    }
    
    //add all tasks that are really new to 'tasks' iVar
    // ->ensures existing task and their info are reused
    for(NSNumber* key in newTasks.allKeys)
    {
        //get task
        newTask = newTasks[key];
        
        //handle and non-new (i.e. existing) tasks
        // ->first, update the existing task's children (as it may contain a new child)
        //   then delete the task from the 'newTasks' array - since its not new :)
        if(nil != self.tasks[newTask.pid])
        {
            //update children
            ((Task*)self.tasks[newTask.pid]).children = newTask.children;
            
            //not new
            // ->so remove
            [newTasks removeObjectForKey:key];
            
            //next
            continue;
        }
        
        //sync
        @synchronized(self.tasks)
        {
        
        //add new task
        [self.tasks setObject:newTask forKey:newTask.pid];
            
        }//sync
        
    }//add new tasks
    
    //sort tasks
    // ->ensures that signing info etc w/ be generated for (top) visible tasks
    [((AppDelegate*)[[NSApplication sharedApplication] delegate]) sortTasksForView:newTasks];
    
    //reload task table
    [((AppDelegate*)[[NSApplication sharedApplication] delegate]) reloadTaskTable];
    
    //call on main thread
    dispatch_sync(dispatch_get_main_queue(), ^{
        
        //reload bottom pane
        [((AppDelegate*)[[NSApplication sharedApplication] delegate]) selectBottomPaneContent:nil];
    });
    
    //now generate signing info
    // ->for (new) tasks
    for(NSNumber* key in newTasks)
    {
        //get task
        newTask = newTasks[key];
        
        //don't need to regerate signing info if its already there
        // ->e.g. task is just another instance of the same binary
        if(nil != newTask.binary.signingInfo)
        {
            //skip
            continue;
        }
        
        //generate signing info
        [newTask.binary generatedSigningInfo];
        
        //reload task (row) in table
        [((AppDelegate*)[[NSApplication sharedApplication] delegate]) reloadRow:newTask];
    
        //reload bottom pane
        // ->this will only reload if new task is the currently selected one, etc
        [((AppDelegate*)[[NSApplication sharedApplication] delegate]) reloadBottomPane:newTask itemView:CURRENT_VIEW];

    }//signing info for all new tasks
    
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
        syslog(LOG_ERR, "OBJECTIVE-SEE ERROR: proc_listpids() failed with %d", status);
        
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
        
        //ignore tasks that have died
        if(YES != isAlive([task.pid intValue]))
        {
            //next
            continue;
        }
        
        //get parent
        parent = newTasks[task.ppid];
        
        //when parent is nil or dead
        // ->default to launchd (pid 0x1)
        if( (nil == parent) ||
            (YES != isAlive([task.pid intValue])) )
        {
            //default
            parent = self.tasks[@1];
        }
        
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
// ->contains extra logic to remove children, etc
-(void)removeTask:(Task*)deadTask
{
    //parent
    Task* parent = nil;
    
    //child
    Task* child = nil;
    
    //launchd
    // ->will host orphaned kids
    Task* launchdTask = nil;
    
    //children
    NSMutableArray* children = nil;
    
    //alloc array for children
    children = [NSMutableArray array];
    
    //get launchd's task
    // ->its 'pid' is 0x1
    launchdTask = self.tasks[@1];

    //get all children
    [self getAllChildren:deadTask children:children];
    
    //these are now orphans :/
    // ->add under launchd
    for(NSNumber* childPid in children)
    {
        //get child task
        child = self.tasks[childPid];
        
        //update child's parent
        if(nil != child)
        {
            //update parent
            child.ppid = @0;
            
            //force adoption
            [launchdTask.children addObject:childPid];
        }
    }
    
    //remove dead task task
    [self.tasks removeObjectForKey:deadTask.pid];
    
    //get parent
    parent = [self.tasks objectForKey:deadTask.ppid];
    
    //remove task from parent's list of children
    [parent.children removeObject:deadTask.pid];
    
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
