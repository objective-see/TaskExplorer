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
#import "Connection.h"

#import <syslog.h>
#import <signal.h>
#import <unistd.h>


@implementation TaskEnumerator

//@synthesize files;
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
//   TODO: existing tasks w/ nil vtInfo, call [vtObject addItem:binary] ?
-(void)enumerateTasks
{
    //(new) task item
    Task* newTask = nil;
    
    //dead tasks
    NSArray *deadTasks = nil;

    //new tasks
    OrderedDictionary* newTasks = nil;
    
    //thread priority
    double threadPriority = 0;

    //determine if network is connected
    // ->sets 'isConnected' flag
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
    
    //now generate signing info/encryption check/packer check
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
        // ->do this before macho parsing!
        [newTask.binary generatedSigningInfo];
        
        //parse
        if(YES == [newTask.binary parse])
        {
            //save encrypted flag
            newTask.binary.isEncrypted = [newTask.binary.parser.binaryInfo[KEY_IS_ENCRYPTED] boolValue];
            
            //save packed flag
            newTask.binary.isPacked = [newTask.binary.parser.binaryInfo[KEY_IS_PACKED] boolValue];
        }
        
        //reload task (row) in table
        [((AppDelegate*)[[NSApplication sharedApplication] delegate]) reloadRow:newTask];
    
        //reload bottom pane
        // ->this will only reload if new task is the currently selected one, etc
        [((AppDelegate*)[[NSApplication sharedApplication] delegate]) reloadBottomPane:newTask itemView:CURRENT_VIEW];

    }//signing info for all new tasks

    /*
      begin enumeration of dylibs/files/network connections
      ->this is for global search, as otherwise, each is re-gen'd per task on each bottom-pane click
    */
    
    //get current thread priority
    threadPriority = [NSThread threadPriority];
    
    //reduce thread priorty
    [NSThread setThreadPriority:0.0f];
    
    //begin dylib enumeration
    for(NSNumber* key in newTasks)
    {
        //get task
        newTask = newTasks[key];
        
        //enumerate
        [newTask enumerateDylibs:self.dylibs];
        
        //nap
        // ->helps with UI
        [NSThread sleepForTimeInterval:0.1f];
    }
    
    //begin file enumeration
    // ->for search view
    for(NSNumber* key in newTasks)
    {
        //get task
        newTask = newTasks[key];
        
        //enumerate
        [newTask enumerateFiles];
        
        //nap
        // ->helps with UI
        [NSThread sleepForTimeInterval:0.1f];
    }
    
    //begin network enumeration
    // ->for search view
    for(NSNumber* key in newTasks)
    {
        //get task
        newTask = newTasks[key];
        
        //enumerate
        [newTask enumerateNetworking];
        
        //nap
        // ->helps with UI
        [NSThread sleepForTimeInterval:0.1f];
    }
    
    //reset thread priority
    [NSThread setThreadPriority:threadPriority];
    
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
        //syslog(LOG_ERR, "OBJECTIVE-SEE ERROR: proc_listpids() failed with %d", status);
        
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
    
    //interate over all tasks
    // ->insert task into parent's *ordered* child array
    for(NSNumber* key in newTasks.allKeys)
    {
        //get task
        task = newTasks[key];
        
        //ignore tasks that have died
        if(YES != isAlive([task.pid intValue]))
        {
            //skip
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
// ->contains extra logic to remove children, flagged items, etc
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
    
    //ensure that flagged item list is accurate
    // ->the dead task or its dylibs might have been flagged
    [self updateFlaggedItems:deadTask];
    
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
    
    //sync to remove from all tasks
    @synchronized(self.tasks)
    {
        //remove dead task task
        [self.tasks removeObjectForKey:deadTask.pid];
    }
    
    //sync to remove from all executables
    @synchronized(((AppDelegate*)[[NSApplication sharedApplication] delegate]).taskEnumerator.executables)
    {
        //remove dead executables
        [((AppDelegate*)[[NSApplication sharedApplication] delegate]).taskEnumerator.executables removeObjectForKey:deadTask.binary.path];
    }
    
    //get parent
    parent = [self.tasks objectForKey:deadTask.ppid];
    
    //remove task from parent's list of children
    [parent.children removeObject:deadTask.pid];
    
    return;
}

//ensure that the list of flagged items is correctly updated
// when a dead task or any of its dylibs were flagged...
-(void)updateFlaggedItems:(Task*)deadTask
{
    //task
    Task* task = nil;
    
    //number of task instances
    NSUInteger taskInstances = 0;
    
    //tasks that host flagged dylib
    NSMutableArray* taskHosts = nil;
    
    //remove any dylibs that are flagged and loaded (only!) in dead task
    for(Binary* dylib in deadTask.dylibs)
    {
        //skip dylibs that aren't flagged
        if(YES != [((AppDelegate*)[[NSApplication sharedApplication] delegate]).flaggedItems containsObject:dylib])
        {
            //skip
            continue;
        }
        
        //get all tasks that host the flagged dylib
        taskHosts = [self loadedIn:dylib];
        
        //skip dylibs that are hosted in more than one task
        // or aren't hosted in dead task
        if( (1 != taskHosts.count) ||
            (taskHosts.firstObject != deadTask.binary) )
        {
            //skip
            continue;
        }
        
        //dylib is flagged and only hosted in dead task
        // ->remove it from flaggedItems
        @synchronized(((AppDelegate*)[[NSApplication sharedApplication] delegate]).flaggedItems)
        {
            //remove
            [((AppDelegate*)[[NSApplication sharedApplication] delegate]).flaggedItems removeObject:dylib];
        }
    }
    
    //also remove task if its flagged and only instance
    if(YES == [((AppDelegate*)[[NSApplication sharedApplication] delegate]).flaggedItems containsObject:deadTask.binary])
    {
        //get number of task instances
        // ->might be more (flagged) instances that are still alive
        for(NSNumber* taskPid in self.tasks)
        {
            //extract task
            task = self.tasks[taskPid];
            
            //check for task has dylib
            if(task.binary == deadTask.binary)
            {
                //inc
                taskInstances++;
            }
        }
        
        //remove if only instance
        if(1 == taskInstances)
        {
            //sync and remove
            @synchronized(((AppDelegate*)[[NSApplication sharedApplication] delegate]).flaggedItems)
            {
                //remove
                [((AppDelegate*)[[NSApplication sharedApplication] delegate]).flaggedItems removeObject:deadTask.binary];
            }
        }
    }
    
    //when there are no flagged items
    // ->(re)set flagged icon to black
    if(0 == ((AppDelegate*)[[NSApplication sharedApplication] delegate]).flaggedItems.count)
    {
        //set main image
        [((AppDelegate*)[[NSApplication sharedApplication] delegate]).flaggedButton setImage:[NSImage imageNamed:@"flagged"]];
        
        //set alternate image
        [((AppDelegate*)[[NSApplication sharedApplication] delegate]).flaggedButton setAlternateImage:[NSImage imageNamed:@"flaggedBG"]];
    }

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

//get all task pids for a given binary
-(NSMutableArray*)tasksForBinary:(Binary*)binary
{
    //array of tasks
    NSMutableArray* matchingTasks = nil;
    
    //task
    Task* task = nil;
    
    //tasks
    matchingTasks = [NSMutableArray array];
    
    //sync
    @synchronized(self.tasks)
    {
        //reload each row w/ new VT info
        for(NSNumber* taskPid in self.tasks)
        {
            //extract task
            task = self.tasks[taskPid];
            
            //check for task has dylib
            if(task.binary == binary)
            {
                //save
                [matchingTasks addObject:task];
            }
        }
        
    }//sync
    
    return matchingTasks;
}


//get all tasks a dylib/file is loaded into
-(NSMutableArray*)loadedIn:(id)item
{
    //array of tasks
    NSMutableArray* hostTasks = nil;
    
    //task
    Task* task = nil;
    
    //dylib flag
    BOOL isDylib = NO;
    
    //file flag
    BOOL isFile = NO;
    
    //connection flag
    BOOL isConnection = NO;
    
    //tasks
    hostTasks = [NSMutableArray array];
    
    //check if item is dylib
    if(YES == [item isKindOfClass:[Binary class]])
    {
        //dylib
        isDylib = YES;
    }
    
    //check if item is file
    else if(YES == [item isKindOfClass:[File class]])
    {
        //file
        isFile = YES;
    }
    
    //check if item is connection
    else if(YES == [item isKindOfClass:[Connection class]])
    {
        //file
        isConnection = YES;
    }
    
    //sanity check
    if( (YES != isDylib) &&
        (YES != isFile) &&
        (YES != isConnection) )
    {
        //bail
        goto bail;
    }
    
    //sync
    @synchronized(self.tasks)
    {
        //iterate over all tasks
        for(NSNumber* taskPid in self.tasks)
        {
            //extract task
            task = self.tasks[taskPid];
            
            //dylib check
            if(YES == isDylib)
            {
                //sync
                @synchronized(task.dylibs)
                {
                    //check if dylib is loaded in task
                    for(Binary* taskDylib in task.dylibs)
                    {
                        //check for task has dylib
                        if(taskDylib == (Binary*)item)
                        {
                            //save
                            [hostTasks addObject:task];
                            
                            //can bail, since match was found
                            break;
                        }
                    }
                    
                }//sync
                
            }//dylibs
            
            //file check
            else if(YES == isFile)
            {
                //sync
                @synchronized(task.files)
                {
                    //check if file is loaded in task
                    for(File* taskFile in task.files)
                    {
                        //check for task has file
                        if(taskFile == (File*)item)
                        {
                            //save
                            [hostTasks addObject:task];
                            
                            //can bail, since match was found
                            break;
                        }
                    }
                }//sync
                
            }//files
            
            //connection check
            else if(YES == isConnection)
            {
                //sync
                @synchronized(task.connections)
                {
                    //check if connection is 'in' task
                    for(Connection* taskConnection in task.connections)
                    {
                        //check for task has connection
                        // note: ->check via endpoints, as that a good representation of connection(?)
                        if(YES == [taskConnection.endpoints isEqualToString: ((Connection*)item).endpoints])
                        {
                            //save
                            [hostTasks addObject:task];
                            
                            //can bail, since match was found
                            break;
                        }
                    }
                }//sync
            
            }//connections
    
        }//all tasks
        
    }//sync
    
//bail
bail:
    
    return hostTasks;
}


@end
