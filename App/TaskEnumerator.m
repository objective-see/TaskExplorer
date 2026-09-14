//
//  TaskEnumerator.m
//
//
//  Created by Patrick Wardle on 5/2/15.
//
//

#import "ModelNotify.h"
#import "TaskEnumerator.h"
#import "AppDelegate.h"
#import "UIUtilities.h"

#import <os/log.h>

/* GLOBALS */

//log handle
extern os_log_t logHandle;

//cmdline mode flag
extern BOOL cmdlineMode;

@implementation TaskEnumerator

@synthesize state;
@synthesize tasks;
@synthesize dylibs;
@synthesize files;
@synthesize connections;
@synthesize xpcClient;
@synthesize enumerator;
@synthesize eventQueue;
@synthesize binaryQueue;
@synthesize executables;
@synthesize flaggedItems;
@synthesize isMonitoring;

//init
// ->w/ xpc client
-(id)initWithClient:(XPCExtensionClient*)client
{
    //init super
    self = [super init];
    if(nil != self)
    {
        //save client
        self.xpcClient = client;

        //init tasks dictionary
        tasks = [[OrderedDictionary alloc] init];

        //alloc executables dictionary
        executables = [NSMutableDictionary dictionary];

        //alloc dylibs dictionary
        dylibs = [NSMutableDictionary dictionary];

        //alloc files dictionary
        files = [NSMutableDictionary dictionary];

        //init connections
        connections = [NSArray array];

        //alloc flagged items
        flaggedItems = [NSMutableArray array];

        //init binary processing queue
        binaryQueue = [[Queue alloc] init];

        //init (serial) event queue
        eventQueue = dispatch_queue_create("com.objective-see.taskexplorer.events", DISPATCH_QUEUE_SERIAL);

        //init refresh queue
        // ->user-driven refreshes never wait behind a burst of live events
        self.refreshQueue = dispatch_queue_create("com.objective-see.taskexplorer.refresh", DISPATCH_QUEUE_SERIAL);

        //init (shared cache enumeration) slots
        self.cacheSlots = dispatch_semaphore_create(3);

        //queue for per-exec dylib/file enumeration (bounded: a fork storm must not fan out into hundreds of XPC round trips)
        self.enumerationQueue = [[NSOperationQueue alloc] init];
        self.enumerationQueue.name = @"com.objective-see.taskexplorer.enumeration";
        self.enumerationQueue.maxConcurrentOperationCount = 3;
        self.enumerationQueue.qualityOfService = NSQualityOfServiceUtility;
    }

    return self;
}

//run a block on the main thread (synchronously)
// ->mutations of 'tasks' are done on the main thread, as that's where the UI reads them
//   (in cmdline mode, just run inline)
-(void)onMainThread:(dispatch_block_t)block
{
    //cmdline mode or already on main thread?
    // ->just run
    if( (YES == cmdlineMode) ||
        (YES == [NSThread isMainThread]) )
    {
        //run
        block();
    }
    //otherwise
    // ->run on main thread
    else
    {
        //run
        dispatch_sync(dispatch_get_main_queue(), block);
    }

    return;
}

//enumerate all tasks
// calls back into app delegate to update task (top) table when pau
-(void)enumerateTasks:(NSNumber*)pid
{
    //(new) task item
    __block Task* newTask = nil;

    //dead tasks
    __block NSArray *deadTasks = nil;

    //new tasks
    OrderedDictionary* newTasks = nil;

    //snapshot time
    // ->tasks discovered (via live events) after this are never 'dead' just because they aren't in the snapshot
    __block NSDate* snapshotTime = nil;

    //connections
    NSArray* connections = nil;

    //save thread
    // allows to be cancelled on refresh, etc
    self.enumerator = [NSThread currentThread];

    //set state
    self.state = ENUMERATION_STATE_TASKS;
    notifyEnumerationState();

    //start (live) monitoring (first)
    // ->so processes that start/exit during the (lengthy) snapshot are not missed; no-op if already monitoring
    //   note: events are applied on the event queue; tasks they add after 'snapshotTime' are kept by the diff below
    if(YES != cmdlineMode)
    {
        //start
        [self startMonitoring];
    }

    //snapshot time
    snapshotTime = [NSDate date];

    //get all tasks
    // pids and binary obj with just path/name
    newTasks = [self getAllTasks];
    if(nil == newTasks)
    {
        //err msg
        os_log_error(logHandle, "ERROR: process snapshot failed, keeping existing tasks");

        //set state
        self.state = ENUMERATION_STATE_COMPLETE;
        notifyEnumerationState();

        //bail
        return;
    }

    //only interested in one task?
    if(nil != pid)
    {
        //enumerate task
        [self enumerateTask:newTasks[pid]];

        //done
        return;
    }

    //diff tasks, build ancestries, etc
    // ->on main thread, as that's where UI reads 'tasks'
    [self onMainThread:^{

    //sync
    @synchronized(self.tasks)
    {
        //get all tasks that are pau
        deadTasks = [self.tasks.allKeys filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSNumber* key, NSDictionary* bindings) {

            //task
            Task* candidate = self.tasks[key];

            //dead: not in snapshot, and discovered before the snapshot was taken
            return ( (nil == newTasks[key]) &&
                     (NSOrderedAscending == [candidate.discoveredAt compare:snapshotTime]) );
        }]];

        //remove any old tasks that have exited/died
        // invoke custom method to handle kids too...
        for(NSNumber* key in deadTasks)
        {
            //remove
            [self removeTask:self.tasks[key]];
        }

        //add all tasks that are really new to 'tasks' iVar
        // ensures existing task and their info are re-used
        for(NSNumber* key in newTasks.allKeys)
        {
            //get task
            newTask = newTasks[key];

            //handle and non-new (i.e. existing) tasks
            // ->delete the task from the 'newTasks' array - since its not new :)
            if(nil != self.tasks[newTask.pid])
            {
                //not new
                // ->so remove
                [newTasks removeObjectForKey:key];

                //next
                continue;
            }

            //exited during the (lengthy) snapshot?
            // ->its exit event was already applied (removed it); don't resurrect it
            if( (0 != newTask.pid.intValue) &&
                (YES != isAlive(newTask.pid.intValue)) )
            {
                //dbg msg
                os_log_debug(logHandle, "skipping %{public}@ (%{public}@): exited during snapshot", newTask.binary.name, newTask.pid);

                //remove
                [newTasks removeObjectForKey:key];

                //next
                continue;
            }

            //add new task
            [self.tasks setObject:newTask forKey:newTask.pid];

        }//add new tasks

        //(re)build ancestries
        // do here, and use all tasks since there might be new parents too
        [self generateAncestries:self.tasks];

    }//sync

    }];

    //exit if thread was cancelled
    if(YES == [[NSThread currentThread] isCancelled])
    {
        //exit
        [NSThread exit];
    }

    //notify
    notifyTasksChanged();

    //for new tasks
    // now generate signing info/encryption check/packer check
    for(NSNumber* key in newTasks)
    {
        //get task
        newTask = newTasks[key];

        //don't need to regerate signing info if its already there
        // ->e.g. task is just another instance of the same binary (unless the previous attempt failed, which is worth a retry)
        if( (nil != newTask.binary.signingInfo) &&
            (SIGNING_STATUS_XPC_FAILED != [newTask.binary.signingInfo[KEY_SIGNATURE_STATUS] intValue]) )
        {
            //skip
            continue;
        }

        //generate signing info
        @autoreleasepool
        {
            //generate
            [newTask generateSigningInfo];
        }

        //notify
        notifyTaskChanged(newTask);

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
    notifyEnumerationState();

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
        //note: w/o shared cache dylibs (vmmap); the index pass (if enabled) adds those afterwards
        //      (pool per task: thousands of temporaries per task, on a thread that lives for the whole pass)
        @autoreleasepool
        {
            //enumerate
            [newTask enumerateDylibs:self.dylibs includeCache:NO];
        }

        //exit if thread was cancelled
        if(YES == [[NSThread currentThread] isCancelled])
        {
            //exit
            [NSThread exit];
        }
    }

    //set state
    self.state = ENUMERATION_STATE_FILES;
    notifyEnumerationState();

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
        @autoreleasepool
        {
            //enumerate
            [newTask enumerateFiles];
        }

        //exit if thread was cancelled
        if(YES == [[NSThread currentThread] isCancelled])
        {
            //exit
            [NSThread exit];
        }
    }

    //set state
    self.state = ENUMERATION_STATE_NETWORK;
    notifyEnumerationState();

    //enumerate (all) network connections
    // ->then assign to each task
    connections = [self.xpcClient enumerateConnections];
    if(nil != connections)
    {
        //update
        [self updateConnections:connections];
    }

    //set state
    self.state = ENUMERATION_STATE_COMPLETE;
    notifyEnumerationState();

    //start (live) monitoring
    // ->(new) processes, dylib loads, network connections
    if(YES != cmdlineMode)
    {
        //start
        [self startMonitoring];
    }

    //index shared cache dylibs (all tasks)?
    if( (YES != cmdlineMode) &&
        (YES == getPreferenceBool(PREF_INDEX_CACHE_DYLIBS)) )
    {
        //index
        [self indexCacheDylibs];
    }

bail:

    return;
}

//scan a single task
-(void)enumerateTask:(Task*)task
{
    //connections
    NSArray* connections = nil;

    //sanity check
    if(nil == task)
    {
        //bail
        goto bail;
    }

    //generate signing info
    [task generateSigningInfo];

    //enumerate dylibs
    [task enumerateDylibs:self.dylibs includeCache:NO];

    //enumerate files
    [task enumerateFiles];

    //enumerate networking
    connections = [self.xpcClient enumerateConnections];
    if(nil != connections)
    {
        //set (just those for this task)
        [task setConnectionsFromInfo:[connections filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"%K == %@", KEY_PROCESS_ID, task.pid]]];
    }

    //save task
    self.tasks[task.pid] = task;

bail:

    return;
}

//get list of all pids
// ->via extension
-(OrderedDictionary*)getAllTasks
{
    //tasks
    // ->pid/name
    OrderedDictionary* allTasks = nil;

    //task
    Task* task = nil;

    //processes (from extension)
    NSArray* processes = nil;

    //alloc/init list
    allTasks = [[OrderedDictionary alloc] init];

    //get all processes
    processes = [self.xpcClient enumerateProcesses];
    if(nil == processes)
    {
        //err msg
        os_log_error(logHandle, "ERROR: failed to enumerate processes via extension");

        //unset
        // ->nil (not empty), so caller knows it failed & keeps the existing model
        allTasks = nil;

        //bail
        goto bail;
    }

    //iterate over all processes
    // ->init a task for each
    for(NSDictionary* process in processes)
    {
        //skip blank pids
        if(0 == [process[KEY_PROCESS_ID] intValue])
        {
            //skip
            continue;
        }

        //init task
        task = [[Task alloc] initWithInfo:process];
        if(nil == task)
        {
            //skip
            continue;
        }

        //add task to list
        // ->order by pid for now
        [allTasks setObject:task forKey:task.pid];
    }

    //always add kernel's task
    // ->hardcoded pid (0) and path to kernel
    task = [[Task alloc] initWithInfo:@{KEY_PROCESS_ID:@0, KEY_PROCESS_PPID:@0, KEY_PROCESS_PATH:path2Kernel()}];

    //add kernel task
    [allTasks setObject:task forKey:@0];

//bail
bail:

    return allTasks;
}

//insert tasks into appropriate parent
// ->ensures order of parent's (by pid), is preserved
-(void)generateAncestries:(OrderedDictionary*)allTasks
{
    //task
    Task* task = nil;

    //reset all children
    for(NSNumber* key in allTasks.allKeys)
    {
        //reset
        [((Task*)allTasks[key]).children removeAllObjects];
    }

    //interate over all tasks
    // ->insert task into parent's *ordered* child array
    for(NSNumber* key in allTasks.allKeys)
    {
        //get task
        task = allTasks[key];

        //insert
        [self generateAncestry:task];
    }

    return;
}

//insert a (single) task into its parent
// note: caller should hold 'tasks' lock
-(void)generateAncestry:(Task*)task
{
    //parent
    Task* parent = nil;

    //comparator
    NSComparator comparator = nil;

    //index
    // ->where task should be inserted into parent's child array
    NSUInteger childIndex = 0;

    //init comparator
    // ->sort pids
    comparator = ^(NSNumber* obj1, NSNumber* obj2)
    {
        return [obj1 compare:obj2];
    };

    //ignore tasks that are their own parent
    // ->i.e. kernel_task
    if(YES == [task.pid isEqualToNumber:task.ppid])
    {
        //bail
        goto bail;
    }

    //get parent
    parent = self.tasks[task.ppid];

    //when parent is nil or dead
    // ->default to launchd (pid 0x1)
    if(nil == parent)
    {
        //default
        parent = self.tasks[@1];

        //update task's ppid
        task.ppid = @1;
    }

    //sanity check
    if( (nil == parent) ||
        (YES == [parent.children containsObject:task.pid]) )
    {
        //bail
        goto bail;
    }

    //get index where child should be inserted
    childIndex = [parent.children indexOfObject:task.pid
                  inSortedRange:(NSRange){0, [parent.children count]}
                  options:NSBinarySearchingInsertionIndex usingComparator:comparator];

    //insert child
    [parent.children insertObject:task.pid atIndex:childIndex];

bail:

    return;
}

//remove a task
// ->contains extra logic to remove children, flagged items, etc
// note: caller should hold 'tasks' lock
-(void)removeTask:(Task*)deadTask
{
    //dead task's dylibs (snapshot)
    NSArray* deadDylibs = nil;

    //parent
    Task* parent = nil;

    //child
    Task* child = nil;

    //launchd
    // ->will host orphaned kids
    Task* launchdTask = nil;

    //children
    NSMutableArray* children = nil;

    //sanity check
    if(nil == deadTask)
    {
        //bail
        goto bail;
    }

    //alloc array for children
    children = [NSMutableArray array];

    //ensure that flagged item list is accurate
    // ->the dead task or its dylibs might have been flagged
    [self updateFlaggedItems:deadTask];

    //un-host all (dylibs, files, connections)
    [deadTask unhostAll];

    //remove any dylibs that are no longer loaded anywhere
    //dead task's dylibs
    // ->snapshot taken before the global lock: lock order is always global -> task, never the reverse
    deadDylibs = [deadTask dylibsSnapshot];

    //sync
    @synchronized(self.dylibs)
    {
        //check all (dead task's) dylibs
        for(Binary* dylib in deadDylibs)
        {
            //no more hosts?
            if(0 == dylib.hostCount)
            {
                //remove
                [self.dylibs removeObjectForKey:dylib.path];
            }
        }
    }

    //get launchd's task
    // ->its 'pid' is 0x1
    launchdTask = self.tasks[@1];

    //get all (direct) children
    [children addObjectsFromArray:deadTask.children];

    //these are now orphans :/
    // ->add under launchd
    for(NSNumber* childPid in children)
    {
        //get child task
        child = self.tasks[childPid];

        //update child's parent
        if( (nil != child) &&
            (nil != launchdTask) )
        {
            //update parent
            child.ppid = @1;

            //force adoption
            if(YES != [launchdTask.children containsObject:childPid])
            {
                //add
                [launchdTask.children addObject:childPid];
            }
        }
    }

    //remove dead task task
    [self.tasks removeObjectForKey:deadTask.pid];

    //remove dead executables
    // ->but only if no other task is using it
    if(0 == [self tasksForBinary:deadTask.binary].count)
    {
        //sync
        @synchronized(self.executables)
        {
            //remove
            [self.executables removeObjectForKey:deadTask.binary.path];
        }
    }

    //get parent
    parent = [self.tasks objectForKey:deadTask.ppid];

    //remove task from parent's list of children
    [parent.children removeObject:deadTask.pid];

bail:

    return;
}

//ensure that the list of flagged items is correctly updated
// when a dead task or any of its dylibs were flagged...
-(void)updateFlaggedItems:(Task*)deadTask
{
    //flagged items (snapshot)
    NSArray* flagged = [self flaggedItemsSnapshot];

    //task
    Task* task = nil;

    //number of task instances
    NSUInteger taskInstances = 0;

    //tasks that host flagged dylib
    NSMutableArray* taskHosts = nil;

    //remove any dylibs that are flagged and loaded (only!) in dead task
    for(Binary* dylib in [deadTask dylibsSnapshot])
    {
        //skip dylibs that aren't flagged
        if(YES != [flagged containsObject:dylib])
        {
            //skip
            continue;
        }

        //get all tasks that host the flagged dylib
        taskHosts = [self loadedIn:dylib];

        //skip dylibs that are hosted in more than one task
        // or aren't hosted in dead task
        if( (1 != taskHosts.count) ||
            (taskHosts.firstObject != deadTask) )
        {
            //skip
            continue;
        }

        //dylib is flagged and only hosted in dead task
        // ->remove it from flaggedItems
        @synchronized(self.flaggedItems)
        {
            //remove
            [self.flaggedItems removeObject:dylib];
        }
    }

    //also remove task if its flagged and only instance
    if(YES == [flagged containsObject:deadTask.binary])
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
            @synchronized(self.flaggedItems)
            {
                //remove
                [self.flaggedItems removeObject:deadTask.binary];
            }
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

    return matchingTasks;
}

//get all tasks a dylib/file is loaded into
// ->via item's (live) host pids
-(NSMutableArray*)loadedIn:(id)item
{
    //hosts
    NSMutableArray* hostTasks = nil;

    //init
    hostTasks = [NSMutableArray array];

    //sanity check
    if(YES != [item isKindOfClass:[ItemBase class]])
    {
        //bail
        goto bail;
    }

    //resolve hosts
    [hostTasks addObjectsFromArray:[(ItemBase*)item hostTasks]];

bail:

    return hostTasks;
}

#pragma mark -
#pragma mark query api

//all tasks (snapshot)
-(NSArray*)allTasks
{
    //tasks
    NSArray* snapshot = nil;

    //sync
    @synchronized(self.tasks)
    {
        //copy
        snapshot = [self.tasks.allValues copy];
    }

    return snapshot;
}

//all dylibs (snapshot)
-(NSArray*)allDylibs
{
    //dylibs
    NSArray* snapshot = nil;

    //sync
    @synchronized(self.dylibs)
    {
        //copy
        snapshot = [self.dylibs.allValues copy];
    }

    return snapshot;
}

//all (open) files (snapshot)
-(NSArray*)allFiles
{
    //files
    NSArray* snapshot = nil;

    //sync
    @synchronized(self.files)
    {
        //copy
        snapshot = [self.files.allValues copy];
    }

    return snapshot;
}

//all network connections (snapshot)
//index dyld shared cache dylibs for all tasks
// ->vmmap per task (~ms to ~2s each), 3 at a time, on a background queue; progress via 'enumeration state' notifications
-(void)indexCacheDylibs
{
    //sync
    @synchronized(self)
    {
        //already running?
        if(YES == self.cacheIndexing)
        {
            //bail
            return;
        }

        //set flag
        self.cacheIndexing = YES;
    }

    //in background
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{

        //tasks (that need indexing)
        NSMutableArray* pending = [NSMutableArray array];

        //concurrency limit
        //concurrency limit (shared w/ the per-exec path)
        dispatch_semaphore_t slots = self.cacheSlots;

        //group
        dispatch_group_t group = dispatch_group_create();

        //collect
        for(Task* task in [self allTasks])
        {
            //skip kernel, and those already done
            if( (0 == task.pid.intValue) ||
                (YES == task.cacheDylibsEnumerated) )
            {
                //skip
                continue;
            }

            //add
            [pending addObject:task];
        }

        //init progress
        self.cacheIndexDone = 0;
        self.cacheIndexTotal = pending.count;
        notifyEnumerationState();

        //dbg msg
        os_log_debug(logHandle, "indexing shared cache dylibs for %lu tasks", (unsigned long)pending.count);

        //index each
        for(Task* task in pending)
        {
            //pref turned off meanwhile?
            if(YES != getPreferenceBool(PREF_INDEX_CACHE_DYLIBS))
            {
                //stop
                break;
            }

            //wait for a slot
            dispatch_semaphore_wait(slots, DISPATCH_TIME_FOREVER);

            //index (concurrently)
            dispatch_group_async(group, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{

                //still current & alive?
                if( (YES == [self isCurrent:task]) &&
                    (YES == isAlive(task.pid.intValue)) )
                {
                    //enumerate (incl. cache)
                    [task enumerateDylibs:self.dylibs includeCache:YES];
                }

                //progress
                @synchronized(self)
                {
                    //inc
                    self.cacheIndexDone++;
                }
                notifyEnumerationState();

                //release slot
                dispatch_semaphore_signal(slots);
            });
        }

        //wait for all
        dispatch_group_wait(group, DISPATCH_TIME_FOREVER);

        //done
        self.cacheIndexing = NO;
        self.cacheIndexComplete = YES;
        notifyEnumerationState();
        notifyTasksChanged();

        //dbg msg
        os_log_debug(logHandle, "shared cache dylib indexing complete (%lu tasks)", (unsigned long)self.cacheIndexDone);
    });

    return;
}

-(BOOL)isCurrent:(Task*)task
{
    //current?
    BOOL current = NO;

    //sync
    @synchronized(self.tasks)
    {
        //check
        current = (self.tasks[task.pid] == task);
    }

    return current;
}

//flagged (VirusTotal) items (snapshot)
-(NSArray*)flaggedItemsSnapshot
{
    //flagged
    NSArray* snapshot = nil;

    //sync
    @synchronized(self.flaggedItems)
    {
        //copy
        snapshot = [self.flaggedItems copy];
    }

    return snapshot;
}

//all network connections (snapshot)
-(NSArray*)allConnections
{
    //connections
    NSArray* snapshot = nil;

    //sync
    @synchronized(self)
    {
        //copy
        snapshot = [self.connections copy];
    }

    return snapshot;
}

//tasks matching predicate
-(NSArray*)tasksMatching:(NSPredicate*)predicate
{
    return [[self allTasks] filteredArrayUsingPredicate:predicate];
}

//dylibs matching predicate
-(NSArray*)dylibsMatching:(NSPredicate*)predicate
{
    return [[self allDylibs] filteredArrayUsingPredicate:predicate];
}

//files matching predicate
-(NSArray*)filesMatching:(NSPredicate*)predicate
{
    return [[self allFiles] filteredArrayUsingPredicate:predicate];
}

//connections matching predicate
-(NSArray*)connectionsMatching:(NSPredicate*)predicate
{
    return [[self allConnections] filteredArrayUsingPredicate:predicate];
}

//(re)enumerate a single task's items (dylibs, files, or connections)
// ->runs on the (serial) event queue, so it's ordered w/ live events
-(void)refreshItems:(Task*)task view:(NSUInteger)view
{
    //sanity check
    if( (nil == task) ||
        (nil == self.xpcClient.extension) )
    {
        //bail
        return;
    }

    //in background
    //on (serial) refresh queue
    dispatch_async(self.refreshQueue, ^{

        //start
        NSTimeInterval start = [NSDate timeIntervalSinceReferenceDate];


        //connections
        NSArray* connections = nil;

        //gone?
        //gone (or pid reused by another task)?
        if( (YES != isAlive(task.pid.intValue)) ||
            (YES != [self isCurrent:task]) )
        {
            //bail
            //notify (so the UI ends its 'enumerating' state)
            notifyItemsChanged(task, view);

            //bail
            return;
        }

        //dbg msg
        os_log_debug(logHandle, "refreshing items (view: %lu) for %{public}@ (%{public}@)", (unsigned long)view, task.binary.name, task.pid);

        switch(view)
        {
            //dylibs
            // ->(user-requested) shared cache dylibs are included synchronously (the UI shows 'enumerating' meanwhile)
            case DYLIBS_VIEW:
                [task enumerateDylibs:self.dylibs];

                //index on, but this task's shared cache dylibs not (yet) enumerated?
                // ->add them in the background, so the click itself stays instant
                if( (YES != task.cacheDylibsEnumerated) &&
                    (YES == getPreferenceBool(PREF_INDEX_CACHE_DYLIBS)) )
                {
                    //in background
                    [self enumerateCacheDylibsInBackground:task];
                }
                break;

            //files
            case FILES_VIEW:
                [task enumerateFiles];
                break;

            //networking
            // ->(re)enumerate all, as its one call anyways
            case NETWORKING_VIEW:

                //monitoring?
                // ->connections are already pushed by the extension every 5s; a full (two-pass) nstat query
                //   of every socket on the system on each click is slow (seconds) and adds nothing
                if(YES != self.isMonitoring)
                {
                    //enumerate
                    connections = [self.xpcClient enumerateConnections];
                    if(nil != connections)
                    {
                        //update
                        [self updateConnections:connections];
                    }
                }

                //notify (always)
                // ->'updateConnections' only notifies on change; the UI waits for this to end its 'enumerating' state
                notifyItemsChanged(task, NETWORKING_VIEW);
                break;

            default:
                break;
        }

        //dbg msg
        os_log_debug(logHandle, "refreshed items (view: %lu) for %{public}@ in %.2fs", (unsigned long)view, task.pid, [NSDate timeIntervalSinceReferenceDate] - start);
    });

    return;
}

//start (live) monitoring
// ->via extension: ES exec/exit/mmap + network (timer)
-(void)startMonitoring
{
    //already monitoring?
    if(YES == self.isMonitoring)
    {
        //bail
        goto bail;
    }

    //start
    self.isMonitoring = [self.xpcClient startMonitoring];

    //install connection lost handler
    // ->extension exited/restarted: mark not monitoring, wait for it to come back, then re-enumerate (which re-arms monitoring)
    //   (scoped, as the block literal has a cleanup, which a 'goto' above may not jump over)
    {
    self.xpcClient.connectionLostHandler = ^{

        //unset
        self.isMonitoring = NO;
        notifyEnumerationState();

        //in background
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{

            //wait for extension
            if(YES != [self.xpcClient waitForExtension:120])
            {
                //err msg
                os_log_error(logHandle, "ERROR: extension did not come back after connection loss");
                return;
            }

            //resync (on main)
            dispatch_async(dispatch_get_main_queue(), ^{
                [(AppDelegate*)NSApp.delegate refreshTasks:nil];
            });
        });
    };
    }

    //dbg msg
    os_log_debug(logHandle, "(live) monitoring started? %d", self.isMonitoring);

bail:

    return;
}

//stop (live) monitoring
-(void)stopMonitoring
{
    //not monitoring?
    if(YES != self.isMonitoring)
    {
        //bail
        goto bail;
    }

    //stop
    [self.xpcClient stopMonitoring];

    //unset
    self.isMonitoring = NO;

bail:

    return;
}

//update (all) connections
// ->group by pid, then assign to each task
-(void)updateConnections:(NSArray*)connections
{
    //connections by pid
    NSMutableDictionary* connectionsByPID = nil;

    //pid
    NSNumber* pid = nil;

    //task
    Task* task = nil;

    //init
    connectionsByPID = [NSMutableDictionary dictionary];

    //group by pid
    for(NSDictionary* connection in connections)
    {
        //grab pid
        pid = connection[KEY_PROCESS_ID];
        if(nil == pid)
        {
            //skip
            continue;
        }

        //first time?
        // ->init array
        if(nil == connectionsByPID[pid])
        {
            //init
            connectionsByPID[pid] = [NSMutableArray array];
        }

        //add
        [connectionsByPID[pid] addObject:connection];
    }

    //all (connection objects)
    NSMutableArray* all = nil;

    //init
    all = [NSMutableArray array];

    //sync
    //update each task
    // ->tasks w/o connections get an empty list
    //   note: iterates a snapshot, so the 'tasks' lock isn't held while connection objects are built
    for(Task* current in [self allTasks])
    {
        //set
        [current setConnectionsFromInfo:connectionsByPID[current.pid]];

        //sync
        @synchronized(current.connections)
        {
            //add
            [all addObjectsFromArray:current.connections];
        }
    }

    //sync
    @synchronized(self)
    {
        //save (global) list
        self.connections = all;
    }

    return;
}

#pragma mark -
#pragma mark events (from extension)

//process started
// ->add task, generate signing info, enumerate dylibs/files
-(void)processStarted:(NSDictionary*)processInfo
{
    //on (serial) event queue
    dispatch_async(self.eventQueue, ^{

        //task
        Task* task = nil;

        //sanity check
        if(nil == processInfo[KEY_PROCESS_ID])
        {
            //bail
            return;
        }

        //init task
        task = [[Task alloc] initWithInfo:processInfo];
        if(nil == task)
        {
            //bail
            return;
        }

        //add task
        // ->on main thread, as that's where UI reads 'tasks'
        [self onMainThread:^{

            //existing task
            Task* existingTask = nil;

            //sync
            //children (of re-exec'd task)
            NSArray* children = nil;

            //sync
            @synchronized(self.tasks)
            {
                //existing task w/ same pid?
                // ->(re)exec'd, so remove old one (but keep its children; an exec doesn't reparent them)
                existingTask = self.tasks[task.pid];
                if(nil != existingTask)
                {
                    //save children
                    children = [existingTask.children copy];

                    //add the new task first
                    // ->so 'removeTask' sees another instance of a shared executable and neither purges it from
                    //   'executables' nor drops it from the flagged items (it then removes the pid's entry, re-added below)
                    [self.tasks setObject:task forKey:task.pid];

                    //remove
                    [self removeTask:existingTask];
                }

                //add task
                [self.tasks setObject:task forKey:task.pid];

                //generate ancestry
                [self generateAncestry:task];

                //re-adopt children
                // ->'removeTask' handed them to launchd
                for(NSNumber* childPid in children)
                {
                    //child
                    Task* child = self.tasks[childPid];
                    if(nil == child) continue;

                    //re-parent
                    child.ppid = task.pid;
                    [((Task*)self.tasks[@1]).children removeObject:childPid];
                    if(YES != [task.children containsObject:childPid])
                    {
                        //add
                        [task.children addObject:childPid];
                    }
                }

            }//sync
        }];

        //notify
        notifyTasksChanged();

        //generate signing info
        [task generateSigningInfo];

        //notify
        notifyTaskChanged(task);

        //enumerate dylibs/files
        // ->nap a bit first, as process is just starting (dylibs still loading, etc)
        //   note: (live) mmap events will also add dylibs as they load
        //   note: on a bounded (concurrent) queue, not the serial event queue: two XPC round trips plus hundreds of
        //         Binary objects per process would otherwise delay exit events for seconds during a fork storm
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self.enumerationQueue addOperationWithBlock:^{

            //still alive?
            //gone (or pid reused by another task)?
            if( (YES != isAlive(task.pid.intValue)) ||
                (YES != [self isCurrent:task]) )
            {
                //bail
                return;
            }

            //enumerate dylibs
            // ->w/o shared cache dylibs (fast); those are added below, in the background, if indexing is on
            [task enumerateDylibs:self.dylibs includeCache:NO];

            //enumerate files
            [task enumerateFiles];

            //shared cache index on?
            // ->add its shared cache dylibs too, but in the background (vmmap can take a second or two)
            if(YES == getPreferenceBool(PREF_INDEX_CACHE_DYLIBS))
            {
                //in background
                [self enumerateCacheDylibsInBackground:task];
            }
        }];
        });
    });

    return;
}

//enumerate a task's shared cache dylibs (vmmap) in the background
// ->gated by the (shared) cache slots, so a fork storm can't fan out into hundreds of vmmaps
-(void)enumerateCacheDylibsInBackground:(Task*)task
{
    //in background
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{

        //wait for a slot
        dispatch_semaphore_wait(self.cacheSlots, DISPATCH_TIME_FOREVER);

        //still current, alive, & not done meanwhile (e.g. by the index pass, or a user click)?
        if( (YES == [self isCurrent:task]) &&
            (YES == isAlive(task.pid.intValue)) &&
            (YES != task.cacheDylibsEnumerated) )
        {
            //enumerate (incl. cache)
            [task enumerateDylibs:self.dylibs includeCache:YES];
        }

        //release slot
        dispatch_semaphore_signal(self.cacheSlots);
    });

    return;
}

//process exited
// ->remove task
-(void)processExited:(NSDictionary*)processInfo
{
    //on (serial) event queue
    dispatch_async(self.eventQueue, ^{

        //task
        __block Task* task = nil;

        //remove task
        // ->on main thread, as that's where UI reads 'tasks'
        [self onMainThread:^{

            //sync
            @synchronized(self.tasks)
            {
                //find task
                task = self.tasks[processInfo[KEY_PROCESS_ID]];
                if(nil == task)
                {
                    //bail
                    return;
                }

                //remove
                [self removeTask:task];

            }//sync
        }];

        //no task?
        if(nil == task)
        {
            //bail
            return;
        }

        //notify
        notifyTasksChanged();
    });

    return;
}

//dylib loaded
// ->add to task's dylibs
-(void)dylibLoaded:(NSDictionary*)event
{
    //on (serial) event queue
    dispatch_async(self.eventQueue, ^{

        //task
        Task* task = nil;

        //dylib path
        NSString* dylibPath = nil;

        //extract path
        dylibPath = event[KEY_DYLIB_PATH];
        if(0 == dylibPath.length)
        {
            //bail
            return;
        }

        //sync
        @synchronized(self.tasks)
        {
            //find task
            task = self.tasks[event[KEY_PROCESS_ID]];
        }

        //no task?
        // ->likely mmap before exec event was processed, ignore
        if(nil == task)
        {
            //bail
            return;
        }

        //add
        [task addDylib:dylibPath allDylibs:self.dylibs];
    });

    return;
}

//network connections (re)enumerated
// ->update all tasks
-(void)connectionsUpdated:(NSArray*)connections
{
    //on (serial) event queue
    dispatch_async(self.eventQueue, ^{

        //update
        [self updateConnections:connections];
    });

    return;
}

@end
