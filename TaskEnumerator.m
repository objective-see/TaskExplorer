//
//  TaskEnumerator.m
//  
//
//  Created by Patrick Wardle on 5/2/15.
//
//

#import "AppDelegate.h"
#import "TaskEnumerator.h"

@implementation TaskEnumerator

@synthesize state;
@synthesize tasks;
@synthesize dylibs;
@synthesize enumerator;
@synthesize binaryQueue;
@synthesize executables;
@synthesize flaggedItems;

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
        
        //alloc flagged items
        flaggedItems = [NSMutableArray array];
        
        //init binary processing queue
        binaryQueue = [[Queue alloc] init];
    }
    
    return self;
}

//enumerate all tasks
// calls back into app delegate to update task (top) table when pau
-(void)enumerateTasks:(NSNumber*)pid
{
    //(new) task item
    Task* newTask = nil;
    
    //dead tasks
    NSArray *deadTasks = nil;

    //new tasks
    OrderedDictionary* newTasks = nil;
    
    //counter
    int count = 0;
    
    //save thread
    // allows to be cancelled on refresh, etc
    self.enumerator = [NSThread currentThread];
    
    //set state
    self.state = ENUMERATION_STATE_TASKS;
    
    //get all tasks
    // pids and binary obj with just path/name
    newTasks = [self getAllTasks];
    
    //build ancestries
    // do here, and use 'new tasks' since there might be new parents too
    [self generateAncestries:newTasks];
    
    //exit if thread was cancelled
    if(YES == [[NSThread currentThread] isCancelled])
    {
        //exit
        [NSThread exit];
    }
    
    //only interested in one task?
    if(nil != pid)
    {
        //enumerate task
        [self enumerateTask:newTasks[pid]];

        //done
        goto bail;
    }
    
    //get all tasks that are pau
    deadTasks = [self.tasks.allKeys filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"NOT SELF IN %@", newTasks.allKeys]];
    
    //remove any old tasks that have exited/died
    // invoke custom method to handle kids too...
    for(NSNumber* key in deadTasks)
    {
        //sync to remove
        @synchronized(self.tasks)
        {
            //sync
            [self removeTask:self.tasks[key]];
        }
    }
    
    //add all tasks that are really new to 'tasks' iVar
    // ensures existing task and their info are re-used
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
    
    //exit if thread was cancelled
    if(YES == [[NSThread currentThread] isCancelled])
    {
        //exit
        [NSThread exit];
    }
    
    //sort tasks
    if(YES != cmdlineMode)
    {
        //sort
        [((AppDelegate*)[[NSApplication sharedApplication] delegate]) sortTasksForView:newTasks];
    
        //reload task table
        [((AppDelegate*)[[NSApplication sharedApplication] delegate]) reloadTaskTable];
    
        //reload bottom pain
        // call on main thread
        if(YES != [NSThread isMainThread])
        {
            //main thread
            dispatch_sync(dispatch_get_main_queue(), ^{
            
                 //reload bottom pane
                 [((AppDelegate*)[[NSApplication sharedApplication] delegate]) selectBottomPaneContent:nil];
                
             });
        }
    }
    
    //for new tasks
    // now generate signing info/encryption check/packer check
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
        
        //generate signing info dynamically
        newTask.binary.signingInfo = extractSigningInfo(newTask.pid.intValue, nil, kSecCSDefaultFlags);
        if(nil == newTask.binary.signingInfo)
        {
            //extract signing info statically
            newTask.binary.signingInfo = extractSigningInfo(0, newTask.binary.path, kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSDoNotValidateResources);
        }

        //parse
        if(YES == [newTask.binary parse])
        {
            //save encrypted flag
            newTask.binary.isEncrypted = [newTask.binary.parser.binaryInfo[KEY_IS_ENCRYPTED] boolValue];
            
            //save packed flag
            newTask.binary.isPacked = [newTask.binary.parser.binaryInfo[KEY_IS_PACKED] boolValue];
        }
        
        //reload UI
        if(YES != cmdlineMode)
        {
            //reload task (row) in table
            [((AppDelegate*)[[NSApplication sharedApplication] delegate]) reloadRow:newTask];
        
            //reload bottom pane
            // ->this will only reload if new task is the currently selected one, etc
            [((AppDelegate*)[[NSApplication sharedApplication] delegate]) reloadBottomPane:newTask itemView:CURRENT_VIEW];
        }
        
        //exit if thread was cancelled
        if(YES == [[NSThread currentThread] isCancelled])
        {
            //exit
            [NSThread exit];
        }
        
    }//signing info for all new tasks

    /*
      begin enumeration of dylibs/files/network connections
      ...this is for global search, as otherwise, each is re-gen'd per task on each bottom-pane click
    */
    
    //set state
    self.state = ENUMERATION_STATE_DYLIBS;
    
    //begin dylib enumeration
    for(NSNumber* key in newTasks)
    {
        //get task
        newTask = newTasks[key];
        
        //skip kernel
        if(0 == newTask.pid.intValue)
        {
            //skip
            continue;
        }
        
        //enumerate
        // ->wait every x times
        if(0 == count++ % 10)
        {
            //enumerate
            [newTask enumerateDylibs:self.dylibs shouldWait:YES];
        }
        //enumerate
        else
        {
            //enumerate
            [newTask enumerateDylibs:self.dylibs shouldWait:NO];
        }
        
        //exit if thread was cancelled
        if(YES == [[NSThread currentThread] isCancelled])
        {
            //exit
            [NSThread exit];
        }
        
        //nap
        [NSThread sleepForTimeInterval:0.05f];
    }

    //set state
    self.state = ENUMERATION_STATE_FILES;
    
    //reset
    count = 0;
    
    //begin file enumeration
    for(NSNumber* key in newTasks)
    {
        //get task
        newTask = newTasks[key];
        
        //skip kernel
        if(0 == newTask.pid.intValue)
        {
            //skip
            continue;
        }
        
        //enumerate
        // ->wait every x times
        if(0 == count++ % 10)
        {
            //enumerate
            [newTask enumerateFiles:YES];
        }
        //enumerate
        else
        {
            //enumerate
            [newTask enumerateFiles:NO];
        }
        
        //exit if thread was cancelled
        if(YES == [[NSThread currentThread] isCancelled])
        {
            //exit
            [NSThread exit];
        }
        
        //nap
        [NSThread sleepForTimeInterval:0.05f];
    }

    //set state
    self.state = ENUMERATION_STATE_NETWORK;
    
    //reset
    count = 0;
    
    //begin network enumeration
    for(NSNumber* key in newTasks)
    {
        //get task
        newTask = newTasks[key];
        
        //skip kernel
        if(0 == newTask.pid.intValue)
        {
            //skip
            continue;
        }
        
        //enumerate
        // ->wait every x times
        if(0 == count++ % 10)
        {
            //enumerate
            [newTask enumerateNetworking:YES];
        }
        //enumerate
        else
        {
            //enumerate
            [newTask enumerateNetworking:NO];
        }
        
        //exit if thread was cancelled
        if(YES == [[NSThread currentThread] isCancelled])
        {
            //exit
            [NSThread exit];
        }
        
        //nap
        [NSThread sleepForTimeInterval:0.05f];
    }
    
    //set state
    self.state = ENUMERATION_STATE_COMPLETE;
    
bail:
    
    return;
}

//scan a single task
-(void)enumerateTask:(Task*)task
{
    //sanity check
    if(nil == task)
    {
        //bail
        goto bail;
    }

    //generate signing info dynamically
    task.binary.signingInfo = extractSigningInfo(task.pid.intValue, nil, kSecCSDefaultFlags);
    if(nil == task.binary.signingInfo)
    {
        //extract signing info statically
        task.binary.signingInfo = extractSigningInfo(0, task.binary.path, kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSDoNotValidateResources);
    }
    
    //parse
    if(YES == [task.binary parse])
    {
        //save encrypted flag
        task.binary.isEncrypted = [task.binary.parser.binaryInfo[KEY_IS_ENCRYPTED] boolValue];
        
        //save packed flag
        task.binary.isPacked = [task.binary.parser.binaryInfo[KEY_IS_PACKED] boolValue];
    }
    
    //enumerate dylibs
    [task enumerateDylibs:self.dylibs shouldWait:YES];
    
    //enumerate files
    [task enumerateFiles:YES];
    
    //enumerate networking
    [task enumerateNetworking:YES];
    
    //save task
    self.tasks[task.pid] = task;
    
bail:
    
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
    
    //status
    int status = -1;
    
    //alloc/init list
    allTasks = [[OrderedDictionary alloc] init];
    
    //# of procs
    int numberOfProcesses = 0;
    
    //array of pids
    pid_t* pids = NULL;
    
    //process ID
    NSNumber* processID = nil;
    
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
        
        //init process ID
        processID = [NSNumber numberWithInt:pids[i]];
        
        //ignore procs that have exited
        if(YES != isAlive(pids[i]))
        {
            //skip
            continue;
        }
        
        //init task
        // ->pass in pid
        task = [[Task alloc] initWithPID:processID];
        
        //again, ignore procs that have exited
        if(YES != isAlive(pids[i]))
        {
            //skip
            continue;
        }
        
        //add task to list
        // ->order by pid for now
        [allTasks setObject:task forKey:processID];
    }
    
    //always add kernel's task
    // ->hardcoded pid (0) and path to kernel
    task = [[Task alloc] initWithPID:@0];
    
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
    @synchronized(taskEnumerator.executables)
    {
        //remove dead executables
        [taskEnumerator.executables removeObjectForKey:deadTask.binary.path];
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
        if(YES != [taskEnumerator.flaggedItems containsObject:dylib])
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
        @synchronized(taskEnumerator.flaggedItems)
        {
            //remove
            [taskEnumerator.flaggedItems removeObject:dylib];
        }
    }
    
    //also remove task if its flagged and only instance
    if(YES == [taskEnumerator.flaggedItems containsObject:deadTask.binary])
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
            @synchronized(taskEnumerator.flaggedItems)
            {
                //remove
                [taskEnumerator.flaggedItems removeObject:deadTask.binary];
            }
        }
    }
    
    //when there are no flagged items
    // ->(re)set flagged icon to black
    if( (YES != cmdlineMode) &&
        (0 == taskEnumerator.flaggedItems.count) )
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
