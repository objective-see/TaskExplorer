//
//  Task.m
//  TaskExplorer
//
//  Created by Patrick Wardle on 5/2/15.
//  Copyright (c) 2015 Objective-See, LLC. All rights reserved.
//

#import "File.h"
#import "Task.h"
#import "Consts.h"
#import "Signing.h"
#import "Utilities.h"
#import "UIUtilities.h"
#import "Connection.h"
#import "ModelNotify.h"
#import "TaskEnumerator.h"
#import "XPCExtensionClient.h"

#import <os/log.h>

/* GLOBALS */

//log handle
extern os_log_t logHandle;

//shared enumerator
extern TaskEnumerator* taskEnumerator;

@implementation Task

@synthesize pid;
@synthesize uid;
@synthesize info;
@synthesize ppid;
@synthesize rpid;
@synthesize files;
@synthesize binary;
@synthesize dylibs;
@synthesize children;
@synthesize arguments;
@synthesize startTime;
@synthesize auditToken;
@synthesize connections;

//init w/ process info (dictionary) from extension
// note: time consuming init's are done in other methods
-(id)initWithInfo:(NSDictionary*)processInfo
{
    //task's path
    // ->not iVar, as assigned into task's binary obj
    NSString* taskPath = nil;

    //existing binaries
    NSMutableDictionary* existingBinaries = nil;

    //existing binary
    // ->can re-use for tasks w/ same binary
    Binary* existingBinary = nil;

    //init super
    self = [super init];
    if(nil != self)
    {
        //grab existings binaries
        existingBinaries = taskEnumerator.executables;

        //save info
        self.info = processInfo;

        //save pid
        self.pid = processInfo[KEY_PROCESS_ID];

        //save ppid
        self.ppid = processInfo[KEY_PROCESS_PPID];
        if(nil == self.ppid)
        {
            //default
            self.ppid = [NSNumber numberWithInteger:getParentID(self.pid.intValue)];
        }

        //save rpid
        self.rpid = processInfo[KEY_PROCESS_RPID];

        //save uid
        // ->missing (the extension couldn't get it) means unknown, not root (uid 0)
        self.uid = (nil != processInfo[KEY_PROCESS_UID]) ? [processInfo[KEY_PROCESS_UID] unsignedIntValue] : (uid_t)-1;

        //save args
        self.arguments = [processInfo[KEY_PROCESS_ARGS] mutableCopy];

        //save start time
        self.startTime = processInfo[KEY_PROCESS_START];

        //save audit token
        self.auditToken = processInfo[KEY_PROCESS_AUDIT_TOKEN];

        //alloc array for children
        children = [NSMutableArray array];

        //alloc array for dylibs
        dylibs = [NSMutableArray array];

        //alloc array for open files
        files = [NSMutableArray array];

        //alloc array for network connections
        connections = [NSMutableArray array];

        //kernel 'task' is special
        if(0 == self.pid.intValue)
        {
            //set
            taskPath = path2Kernel();
        }
        //otherwise
        // path from extension
        else
        {
            //extract
            taskPath = processInfo[KEY_PROCESS_PATH];

            //when path is still nil
            // ->set to const for unknown path...
            if(0 == taskPath.length)
            {
                //set
                taskPath = TASK_PATH_UNKNOWN;
            }
        }

        //try extract existing binary
        // ->but only if task's path is known
        if(YES != [taskPath isEqualToString:TASK_PATH_UNKNOWN])
        {
            //sync
            @synchronized(existingBinaries)
            {
                //lookup
                existingBinary = existingBinaries[taskPath];
            }
        }

        //re-use existing binaries
        //discovered (now)
        self.discoveredAt = [NSDate date];

        //re-use existing binaries
        if(nil != existingBinary)
        {
            //re-use
            self.binary = existingBinary;
        }
        //generate new binary
        else
        {
            //generate binary obj
            // ->time-consuming tasks are preformed in background block
            self.binary = [[Binary alloc] initWithParams:@{KEY_RESULT_PATH:taskPath}];

            //skip those that error out
            if(nil == self.binary)
            {
                //bail
                goto bail;
            }

            //indicate that binary is a task (main) executable
            self.binary.isTaskBinary = YES;

            //sync
            // ->add to 'global' list, unless another thread beat us to it (then use theirs)
            @synchronized(existingBinaries)
            {
                //existing?
                if(nil != existingBinaries[taskPath])
                {
                    //use existing
                    self.binary = existingBinaries[taskPath];
                    existingBinary = self.binary;
                }
                //add
                else
                {
                    //add
                    existingBinaries[taskPath] = self.binary;
                }
            }
        }

        //platform binary (per ES / csops)?
        // ->flag binary, so it's excluded from VirusTotal lookups, etc (before queueing!)
        if(YES == [processInfo[KEY_PROCESS_PLATFORM_BINARY] boolValue])
        {
            //set
            self.binary.isPlatformBinary = YES;
        }

        //new binary?
        // ->queue for background processing (hashes, VirusTotal)
        if(nil == existingBinary)
        {
            //add to queue
            [taskEnumerator.binaryQueue enqueue:self.binary];
        }

    }//init self

//bail
bail:

    return self;
}

//generate signing info (for main binary)
// dynamic (via audit token/pid), falling back to static
-(void)generateSigningInfo
{
    //generate (via extension)
    // ->signing info (dynamic via pid, static for the kernel), hashes, & mach-o flags
    [self.binary generateInfo:self.pid.intValue auditToken:self.auditToken];

    return;
}

//enumerate all dylibs (via extension)
// ->new ones are added to 'existingDylibs' (global) dictionary
-(void)enumerateDylibs:(NSMutableDictionary*)allDylibs
{
    //include shared cache dylibs?
    // ->only when asked for (per task, via the 'Include shared cache dylibs' checkbox), and only once: after that,
    //   'includeCache:NO' keeps the known cache dylibs (so a per-click refresh doesn't re-run vmmap, which takes a second or two)
    //   note: when the index pref is on, the caller ('refreshItems:view:') adds the cache dylibs in the background
    [self enumerateDylibs:allDylibs includeCache:( (YES != self.cacheDylibsEnumerated) && (YES == self.includeCacheDylibs) )];

    return;
}

//enumerate all dylibs (via extension)
// ->new ones are added to 'existingDylibs' (global) dictionary
-(void)enumerateDylibs:(NSMutableDictionary*)allDylibs includeCache:(BOOL)includeCache
{
    //dylib paths
    NSArray* dylibPaths = nil;

    //dylib instance (as Binary) obj
    Binary* dylib = nil;

    //new dylibs
    // ->ones that should be hashed/processed
    NSMutableArray* newDylibs = nil;

    //(new) dylibs
    NSMutableArray* enumeratedDylibs = nil;

    //dylibs to purge from the global list (zero hosts)
    NSMutableArray* purge = [NSMutableArray array];

    //dylibs before the (slow) XPC call
    NSArray* beforeSnapshot = nil;

    //(resolved) path of main binary
    NSString* resolvedBinaryPath = nil;

    //got shared cache dylibs (via vmmap)?
    BOOL gotCache = NO;

    //alloc array for new dylibs
    newDylibs = [NSMutableArray array];

    //alloc array for enumerated dylibs
    enumeratedDylibs = [NSMutableArray array];

    //skip kernel
    if(0 == self.pid.intValue)
    {
        //notify (nothing to enumerate; ends the UI's 'enumerating' state)
        notifyItemsChanged(self, DYLIBS_VIEW);

        //bail
        goto bail;
    }

    //snapshot (before the slow part)
    beforeSnapshot = [self dylibsSnapshot];

    //enumerate (via extension)
    dylibPaths = [taskEnumerator.xpcClient enumerateDylibs:self.pid.intValue];
    if(nil == dylibPaths)
    {
        //err msg
        // ->XPC error (not 'no dylibs'); keep what we have
        os_log_error(logHandle, "ERROR: failed to enumerate dylibs for %{public}@ via extension", self.pid);

        //notify (so the UI ends its 'enumerating' state)
        notifyItemsChanged(self, DYLIBS_VIEW);

        //bail
        goto bail;
    }

    //include dyld shared cache dylibs?
    // ->via vmmap (in extension); union w/ the (file-backed) mappings
    //   ...never for an endpoint security client: vmmap suspends its target, and a suspended ES client is killed by the
    //   kernel once it misses an auth deadline (the extension refuses too; this saves the round trip)
    //   ...nor for ourselves: vmmap would suspend the app (and its UI) while it runs
    if( (YES == includeCache) &&
        ((YES == self.isESClient) || (getpid() == self.pid.intValue) || (YES == isProtectedSystemProcess(self.binary.path))) )
    {
        //dbg msg
        os_log_debug(logHandle, "not enumerating shared cache dylibs for %{public}@ (endpoint security client, or ourselves)", self.pid);

        //skip
        includeCache = NO;
    }
    if(YES == includeCache)
    {
        //all (incl. cache)
        NSArray* allPaths = [taskEnumerator.xpcClient enumerateAllDylibs:self.pid.intValue];
        if(0 != allPaths.count)
        {
            //union
            NSMutableOrderedSet* merged = [NSMutableOrderedSet orderedSetWithArray:dylibPaths];
            [merged addObjectsFromArray:allPaths];
            dylibPaths = merged.array;

            //set flag (published w/ the dylibs, below)
            gotCache = YES;
        }
    }
    //not (this time)
    // ->keep the shared cache dylibs already known for this task (they don't unload), so a plain refresh doesn't drop them
    else
    {
        //known cache dylibs
        NSMutableArray* knownCache = [NSMutableArray array];

        //sync
        @synchronized(self.dylibs)
        {
            //collect
            for(Binary* existing in (self.cacheDylibsEnumerated ? self.dylibs : @[]))
            {
                //cache?
                if(YES == existing.inCache)
                {
                    //add
                    [knownCache addObject:existing.path];
                }
            }
        }

        //union
        if(0 != knownCache.count)
        {
            //merge
            NSMutableOrderedSet* merged = [NSMutableOrderedSet orderedSetWithArray:dylibPaths];
            [merged addObjectsFromArray:knownCache];
            dylibPaths = merged.array;
        }
    }

    //(resolved) path of main binary
    // ->hoisted; resolving per dylib was ~1200 lstat chains per enumeration
    resolvedBinaryPath = [self.binary.path stringByResolvingSymlinksInPath];

    //create/add all dylibs
    for(NSString* dylibPath in dylibPaths)
    {
        //skip main executable image
        // ->making sure to resolve symlinks
        if( (YES == [dylibPath isEqualToString:self.binary.path]) ||
            (YES == [dylibPath isEqualToString:resolvedBinaryPath]) )
        {
            //skip
            continue;
        }

        //first try grab from 'global' list of all dylibs
        // ->will be non-nil if its already been processed
        //   note: hosted right there, under the global lock: a concurrent zero-host purge (another task exiting) can't
        //   interleave between 'found' and 'hosted' and orphan the object
        @synchronized(allDylibs)
        {
            //lookup
            dylib = allDylibs[dylibPath];
            if(nil != dylib)
            {
                //host
                [dylib addHost:self.pid];
            }
        }

        //first time seen?
        // ->create Binary obj & save into 'global' list
        if(nil == dylib)
        {
            //create Binary obj
            dylib = [[Binary alloc] initWithParams:@{KEY_RESULT_PATH:dylibPath}];

            //skip any that error out
            if(nil == dylib)
            {
                //skip
                continue;
            }

            //sync
            // ->add to global list, unless another thread beat us to it (then use theirs); host under the same lock
            @synchronized(allDylibs)
            {
                //existing?
                if(nil != allDylibs[dylib.path])
                {
                    //use existing
                    dylib = allDylibs[dylib.path];
                }
                //add
                else
                {
                    //add
                    allDylibs[dylib.path] = dylib;

                    //add to queue
                    // ->this will trigger background processing
                    [taskEnumerator.binaryQueue enqueue:dylib];

                    //add to list of new dylibs
                    // ->will allow for post processing
                    [newDylibs addObject:dylib];
                }

                //host
                [dylib addHost:self.pid];
            }
        }

        //add to task's dylibs
        [enumeratedDylibs addObject:dylib];

    }//all dylibs

    //sync
    @synchronized(self.dylibs)
    {
        //current (as sets)
        NSSet* enumerated = [NSSet setWithArray:enumeratedDylibs];
        NSSet* before = [NSSet setWithArray:beforeSnapshot];

        //dylibs added since the (slow) XPC/vmmap call began (e.g. via live mmap events)
        // ->keep them; they're not in this enumeration only because it started before they were mapped
        for(Binary* existing in self.dylibs)
        {
            //added since?
            if( (YES != [before containsObject:existing]) &&
                (YES != [enumerated containsObject:existing]) )
            {
                //keep
                [enumeratedDylibs addObject:existing];
            }
        }
        enumerated = [NSSet setWithArray:enumeratedDylibs];

        //un-host any dylibs that are no longer loaded
        for(Binary* existing in self.dylibs)
        {
            //gone?
            if(YES != [enumerated containsObject:existing])
            {
                //un-host
                [existing removeHost:self.pid];

                //no more hosts?
                // ->purge from global list (after this lock is released; lock order is always global -> task)
                if(0 == existing.hostCount)
                {
                    //add
                    [purge addObject:existing];
                }
            }
        }

        //reset existing dylibs
        [self.dylibs removeAllObjects];

        //add all
        [self.dylibs addObjectsFromArray:enumeratedDylibs];

        //sort by name
        [self.dylibs sortUsingComparator:^NSComparisonResult(id a, id b)
        {
            //sort
            return [[(Binary*)a name] compare:[(Binary*)b name] options:NSCaseInsensitiveSearch];
        }];

        //publish cache flag (w/ the dylibs)
        if(YES == gotCache)
        {
            //set
            self.cacheDylibsEnumerated = YES;
        }

    }//sync

    //purge (zero-host) dylibs from global list
    if(0 != purge.count)
    {
        //sync
        @synchronized(allDylibs)
        {
            //remove each (if still unhosted)
            for(Binary* gone in purge)
            {
                //still unhosted?
                if(0 == gone.hostCount)
                {
                    //remove
                    [allDylibs removeObjectForKey:gone.path];

                    //flagged? (loaded nowhere now)
                    // ->drop from the flagged list too
                    @synchronized(taskEnumerator.flaggedItems)
                    {
                        //remove
                        [taskEnumerator.flaggedItems removeObject:gone];
                    }
                }
            }
        }
    }

    //note: hosting happened above (under the global lock), so nothing to do here

    //notify
    notifyItemsChanged(self, DYLIBS_VIEW);

    //complete dylib processing for new dylib
    // ->get signing info, hash, etc, & save into global list
    for(Binary* newDylib in newDylibs)
    {
        //process
        [self processNewDylib:newDylib];
    }

bail:

    return;
}

//add a (single) dylib
// ->e.g. from a (live) mmap event
-(Binary*)addDylib:(NSString*)dylibPath allDylibs:(NSMutableDictionary*)allDylibs
{
    //dylib
    Binary* dylib = nil;

    //flag
    BOOL isNew = NO;

    //index
    // ->where dylib should be inserted (sorted by name)
    NSUInteger index = 0;

    //skip main executable image
    // ->making sure to resolve symlinks
    if( (YES == [dylibPath isEqualToString:self.binary.path]) ||
        (YES == [dylibPath isEqualToString:[self.binary.path stringByResolvingSymlinksInPath]]) )
    {
        //bail
        goto bail;
    }

    //first try grab from 'global' list of all dylibs
    // ->hosted under the global lock, so a concurrent zero-host purge can't orphan it
    @synchronized(allDylibs)
    {
        //lookup
        dylib = allDylibs[dylibPath];
        if(nil != dylib)
        {
            //host
            [dylib addHost:self.pid];
        }
    }

    //first time seen?
    // ->create Binary obj & save into 'global' list
    if(nil == dylib)
    {
        //create Binary obj
        dylib = [[Binary alloc] initWithParams:@{KEY_RESULT_PATH:dylibPath}];
        if(nil == dylib)
        {
            //bail
            goto bail;
        }

        //new
        //sync
        // ->add to global list, unless another thread beat us to it (then use theirs)
        @synchronized(allDylibs)
        {
            //existing?
            if(nil != allDylibs[dylib.path])
            {
                //use existing
                dylib = allDylibs[dylib.path];
            }
            //add
            else
            {
                //add
                allDylibs[dylib.path] = dylib;

                //new
                isNew = YES;

                //add to queue
                // ->this will trigger background processing
                [taskEnumerator.binaryQueue enqueue:dylib];
            }
        }

        //host (still under the global lock)
        [dylib addHost:self.pid];
    }

    //sync
    @synchronized(self.dylibs)
    {
        //already have it?
        if(YES == [self.dylibs containsObject:dylib])
        {
            //unset
            dylib = nil;
        }
        //new to this task
        // ->insert (sorted by name)
        else
        {
            //get index
            index = [self.dylibs indexOfObject:dylib inSortedRange:NSMakeRange(0, self.dylibs.count) options:NSBinarySearchingInsertionIndex usingComparator:^NSComparisonResult(id a, id b)
            {
                //sort
                return [[(Binary*)a name] compare:[(Binary*)b name] options:NSCaseInsensitiveSearch];
            }];

            //insert
            [self.dylibs insertObject:dylib atIndex:index];
        }

    }//sync

    //nothing new?
    if(nil == dylib)
    {
        //bail
        goto bail;
    }

    //note: hosted above (under the global lock)

    //notify
    notifyItemsChanged(self, DYLIBS_VIEW);

    //new dylib?
    // complete processing (signing info, etc)
    if(YES == isNew)
    {
        //process
        [self processNewDylib:dylib];
    }

bail:

    return dylib;
}

//complete processing of new dylib
// ->generate signing info, parse, & reload row (if task is still current)
-(void)processNewDylib:(Binary*)newDylib
{
    //generate signing info, hashes, etc
    [newDylib generatedSigningInfo];

    //notify
    notifyBinaryChanged(newDylib);

    return;
}

//enumerate all open files (via extension)
-(void)enumerateFiles
{
    //file paths
    NSArray* filePaths = nil;

    //File object
    File* file = nil;

    //(new) files
    NSMutableArray* enumeratedFiles = nil;

    //enumerated files (as set)
    NSSet* enumeratedSet = nil;

    //files to purge from the global list (zero hosts)
    NSMutableArray* purge = [NSMutableArray array];

    //alloc array for enumerated files
    enumeratedFiles = [NSMutableArray array];

    //skip kernel
    if(0 == self.pid.intValue)
    {
        //notify (nothing to enumerate; ends the UI's 'enumerating' state)
        notifyItemsChanged(self, FILES_VIEW);

        //bail
        goto bail;
    }

    //enumerate (via extension)
    filePaths = [taskEnumerator.xpcClient enumerateFiles:self.pid.intValue];
    if(nil == filePaths)
    {
        //err msg
        // ->XPC error (not 'no files'); keep what we have
        os_log_error(logHandle, "ERROR: failed to enumerate files for %{public}@ via extension", self.pid);

        //notify (so the UI ends its 'enumerating' state)
        notifyItemsChanged(self, FILES_VIEW);

        //bail
        goto bail;
    }

    //create/add all files
    // ->each is {path, type} (from the extension)
    for(NSDictionary* fileInfo in filePaths)
    {
        //path
        NSString* filePath = [fileInfo isKindOfClass:[NSDictionary class]] ? fileInfo[KEY_RESULT_PATH] : (NSString*)fileInfo;
        if(YES != [filePath isKindOfClass:[NSString class]] || 0 == filePath.length)
        {
            //skip
            continue;
        }

        //sync
        // ->hosted under the global lock (see 'enumerateDylibs:')
        @synchronized(taskEnumerator.files)
        {
            //first try grab from 'global' list of all files
            file = taskEnumerator.files[filePath];
            if(nil != file)
            {
                //host
                [file addHost:self.pid];
            }
        }

        //first time seen?
        // ->create File obj (outside the lock; never hold a lock while doing i/o), then save into 'global' list
        if(nil == file)
        {
            //alloc/init File obj
            file = [[File alloc] initWithParams:@{KEY_RESULT_PATH:filePath, KEY_FILE_TYPE:([fileInfo isKindOfClass:[NSDictionary class]] ? (fileInfo[KEY_FILE_TYPE] ?: FILE_TYPE_UNKNOWN) : FILE_TYPE_UNKNOWN)}];
            if(nil == file)
            {
                //skip
                continue;
            }

            //sync
            @synchronized(taskEnumerator.files)
            {
                //another thread beat us to it?
                // ->use that one
                if(nil != taskEnumerator.files[filePath])
                {
                    //use existing
                    file = taskEnumerator.files[filePath];
                }
                //add
                else
                {
                    //add
                    taskEnumerator.files[filePath] = file;
                }

                //host
                [file addHost:self.pid];
            }
        }

        //add
        [enumeratedFiles addObject:file];
    }

    //sort by name
    [enumeratedFiles sortUsingComparator:^NSComparisonResult(id a, id b)
    {
        //sort
        return [[(File*)a name] compare:[(File*)b name] options:NSCaseInsensitiveSearch];
    }];

    //sync
    //as set (for fast 'gone' checks)
    enumeratedSet = [NSSet setWithArray:enumeratedFiles];

    //sync
    @synchronized(self.files)
    {
        //un-host any files that are no longer open
        for(File* existing in self.files)
        {
            //gone?
            if(YES != [enumeratedSet containsObject:existing])
            {
                //un-host
                [existing removeHost:self.pid];

                //no more hosts?
                // ->purge from global list (after this lock is released; lock order is always global -> task)
                if(0 == existing.hostCount)
                {
                    //add
                    [purge addObject:existing];
                }
            }
        }

        //reset existing files
        [self.files removeAllObjects];

        //add all
        [self.files addObjectsFromArray:enumeratedFiles];

    }//sync

    //purge (zero-host) files from global list
    if(0 != purge.count)
    {
        //sync
        @synchronized(taskEnumerator.files)
        {
            //remove each (if still unhosted)
            for(File* gone in purge)
            {
                //still unhosted?
                if(0 == gone.hostCount)
                {
                    //remove
                    [taskEnumerator.files removeObjectForKey:gone.path];
                }
            }
        }
    }

    //notify
    notifyItemsChanged(self, FILES_VIEW);

bail:

   return;
}

//set network connections
// ->from array of connection dictionaries (from extension)
-(void)setConnectionsFromInfo:(NSArray*)connectionInfos
{
    //Connection object
    Connection* connection = nil;

    //(new) connections
    NSMutableArray* newConnections = nil;

    //flag
    BOOL changed = NO;

    //alloc array for new connections
    newConnections = [NSMutableArray array];

    //create/add all network sockets/connection
    for(NSDictionary* connectionInfo in connectionInfos)
    {
        //alloc/init Connection obj
        connection = [[Connection alloc] initWithParams:connectionInfo];
        if(nil == connection)
        {
            //skip
            continue;
        }

        //host
        [connection addHost:self.pid];

        //add
        [newConnections addObject:connection];
    }

    //sort by endpoints
    [newConnections sortUsingComparator:^NSComparisonResult(id a, id b)
    {
        //sort
        //endpoints, then proto, then state (the fields 'isEqual' compares), so equal lists sort identically
        NSComparisonResult result = [[(Connection*)a endpoints] compare:[(Connection*)b endpoints] options:NSCaseInsensitiveSearch];
        if(NSOrderedSame == result) result = [[(Connection*)a proto] compare:[(Connection*)b proto]];
        if(NSOrderedSame == result) result = [([(Connection*)a state] ?: @"") compare:([(Connection*)b state] ?: @"")];
        return result;
    }];

    //sync
    @synchronized(self.connections)
    {
        //anything changed?
        // ->compare (sorted) lists
        changed = (YES != [self.connections isEqualToArray:newConnections]);

        //update
        if(YES == changed)
        {
            //remove any existing
            [self.connections removeAllObjects];

            //add all
            [self.connections addObjectsFromArray:newConnections];
        }
        //same connections
        // ->still refresh byte counters (not part of equality), and notify if any moved
        else
        {
            for(NSUInteger i = 0; i < self.connections.count; i++)
            {
                //existing / new
                Connection* existing = self.connections[i];
                Connection* updated = newConnections[i];

                //counters moved?
                if( (existing.bytesUp != updated.bytesUp) ||
                    (existing.bytesDown != updated.bytesDown) )
                {
                    //update
                    existing.bytesUp = updated.bytesUp;
                    existing.bytesDown = updated.bytesDown;

                    //notify
                    changed = YES;
                }
            }
        }

    }//sync

    //notify
    if(YES == changed)
    {
        //notify
        notifyItemsChanged(self, NETWORKING_VIEW);
    }

    return;
}

//remove self as host from all items (dylibs, files, connections)
// ->invoked when task exits
-(void)unhostAll
{
    //sync
    @synchronized(self.dylibs)
    {
        //un-host all dylibs
        for(Binary* dylib in self.dylibs)
        {
            //un-host
            [dylib removeHost:self.pid];
        }
    }

    //files to purge (zero hosts)
    NSMutableArray* purge = [NSMutableArray array];

    //sync
    @synchronized(self.files)
    {
        //un-host all files
        for(File* file in self.files)
        {
            //un-host
            [file removeHost:self.pid];

            //no more hosts?
            // ->purge from global list (after this lock is released; lock order is always global -> task)
            if(0 == file.hostCount)
            {
                //add
                [purge addObject:file];
            }
        }
    }

    //purge
    if(0 != purge.count)
    {
        //sync
        @synchronized(taskEnumerator.files)
        {
            //remove each (if still unhosted)
            for(File* gone in purge)
            {
                //still unhosted?
                if(0 == gone.hostCount)
                {
                    //remove
                    [taskEnumerator.files removeObjectForKey:gone.path];
                }
            }
        }
    }

    //sync
    @synchronized(self.connections)
    {
        //un-host all connections
        for(Connection* connection in self.connections)
        {
            //un-host
            [connection removeHost:self.pid];
        }
    }

    return;
}

/* (KVC) QUERY PROPERTIES */

//name (of binary)
-(NSString*)name
{
    return self.binary.name;
}

//path (of binary)
-(NSString*)path
{
    return self.binary.path;
}

//has network connections?
-(BOOL)hasConnections
{
    //flag
    BOOL has = NO;

    //sync
    @synchronized(self.connections)
    {
        //check
        has = (0 != self.connections.count);
    }

    return has;
}

//has listening socket(s)?
-(BOOL)isListening
{
    //flag
    BOOL listening = NO;

    //sync
    @synchronized(self.connections)
    {
        //check all
        for(Connection* connection in self.connections)
        {
            //listening?
            if(YES == [connection.state isEqualToString:@"listening"])
            {
                //set
                listening = YES;

                //done
                break;
            }
        }
    }

    return listening;
}

//endpoint security client (per ES / csops)
-(BOOL)isESClient
{
    return [self.info[KEY_PROCESS_ES_CLIENT] boolValue];
}

//platform binary (per ES)
// ->falls back to apple check
-(BOOL)isPlatformBinary
{
    //from ES?
    if(nil != self.info[KEY_PROCESS_PLATFORM_BINARY])
    {
        return [self.info[KEY_PROCESS_PLATFORM_BINARY] boolValue];
    }

    return self.binary.isApple;
}

//team id (from ES, or signing info)
-(NSString*)teamID
{
    //team id
    NSString* team = nil;

    //from ES?
    team = self.info[KEY_PROCESS_TEAM_ID];
    if(0 == team.length)
    {
        //from signing info
        team = self.binary.teamID;
    }

    return team;
}

//dylibs whose team id differs from the task's
// ->ignores apple/dyld-cache dylibs (and apple tasks)
-(NSArray*)mismatchedDylibs
{
    //mismatched
    NSMutableArray* mismatched = nil;

    //task's team id
    NSString* team = nil;

    //init
    mismatched = [NSMutableArray array];

    //apple task?
    // ->skip
    if(YES == self.binary.isApple)
    {
        //bail
        goto bail;
    }

    //grab team
    team = self.teamID;

    //sync
    @synchronized(self.dylibs)
    {
        //check all
        for(Binary* dylib in self.dylibs)
        {
            //skip apple/dyld-cache dylibs
            if(YES == dylib.isApple)
            {
                //skip
                continue;
            }

            //same team?
            if( (nil != team) &&
                (YES == [team isEqualToString:dylib.teamID]) )
            {
                //skip
                continue;
            }

            //mismatch
            [mismatched addObject:dylib];
        }
    }

bail:

    return mismatched;
}

//has mismatched dylibs?
-(BOOL)hasMismatchedDylibs
{
    return (0 != self.mismatchedDylibs.count);
}

//forward unknown (KVC) keys to binary
// ->allows binary keywords (e.g. 'isApple', 'signer') to be evaluated against tasks
-(id)valueForUndefinedKey:(NSString*)key
{
    return [self.binary valueForKey:key];
}

//(thread-safe) snapshots
-(NSUInteger)dylibCount
{
    //count
    NSUInteger count = 0;

    //sync
    @synchronized(self.dylibs)
    {
        //count
        count = self.dylibs.count;
    }

    return count;
}

-(NSArray*)dylibsSnapshot
{
    @synchronized(self.dylibs) { return [self.dylibs copy]; }
}

//children (copy)
// ->under the (global) tasks lock, which is what guards 'children' mutations
-(NSArray*)childrenSnapshot
{
    @synchronized(taskEnumerator.tasks) { return [self.children copy]; }
}
-(NSArray*)filesSnapshot
{
    @synchronized(self.files) { return [self.files copy]; }
}
-(NSArray*)connectionsSnapshot
{
    @synchronized(self.connections) { return [self.connections copy]; }
}

//compare
// ->uses binary name
-(NSComparisonResult)compare:(Task*)otherTask
{
    return [self.binary.name compare:otherTask.binary.name options:NSCaseInsensitiveSearch];
}

//convert self to JSON string
-(NSString*)toJSON:(BOOL)detailed
{
    //json string
    NSString *json = nil;

    //json data
    // ->for intermediate conversions
    NSData *jsonData = nil;

    //task command line
    NSString* taskCommandLine = nil;

    //hashes
    NSString* fileHashes = nil;

    //signing info
    NSString* fileSigs = nil;

    //VT detection ratio
    NSString* vtDetectionRatio = nil;

    //dylibs
    NSMutableString* dylibsJSON = nil;

    //files
    NSMutableString* filesJSON = nil;

    //network connections
    NSMutableString* connectionsJSON = nil;

    //init string for dylibs
    dylibsJSON = [NSMutableString string];

    //init string for files
    filesJSON = [NSMutableString string];

    //init string for connections
    connectionsJSON = [NSMutableString string];

    //init task's command line
    taskCommandLine = [self.arguments componentsJoinedByString:@" "];

    //no args
    // ->provide default
    if((nil == taskCommandLine) ||
       (0 == taskCommandLine.length))
    {
        //default
        taskCommandLine = @"no arguments/unknown";
    }

    //init file hash to default string
    // ->used when hashes are nil, or serialization fails
    fileHashes = @"\"unknown\"";

    //init file signature to default string
    // ->used when signatures are nil, or serialization fails
    fileSigs = @"\"unknown\"";

    //convert hashes to JSON
    if(nil != self.binary.hashes)
    {
        //convert hash dictionary
        // ->wrap since we are serializing JSON
        @try
        {
            //convert
            jsonData = [NSJSONSerialization dataWithJSONObject:self.binary.hashes options:kNilOptions error:NULL];
            if(nil != jsonData)
            {
                //convert data to string
                fileHashes = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
            }
        }
        //ignore exceptions
        // ->file hashes will just be 'unknown'
        @catch(NSException *exception)
        {
            ;
        }
    }

    //convert signing dictionary to JSON
    if(nil != self.binary.signingInfo)
    {
        //convert signing dictionary
        // ->wrap since we are serializing JSON
        @try
        {
            //convert
            jsonData = [NSJSONSerialization dataWithJSONObject:self.binary.signingInfo options:kNilOptions error:NULL];
            if(nil != jsonData)
            {
                //convert data to string
                fileSigs = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
            }
        }
        //ignore exceptions
        // ->file sigs will just be 'unknown'
        @catch(NSException *exception)
        {
            ;
        }
    }

    //init VT detection ratio
    vtDetectionRatio = [NSString stringWithFormat:@"%lu/%lu", (unsigned long)[self.binary.vtInfo[VT_RESULTS_POSITIVES] unsignedIntegerValue], (unsigned long)[self.binary.vtInfo[VT_RESULTS_TOTAL] unsignedIntegerValue]];

    //detailed?
    // generate full json
    if(YES == detailed)
    {
        //convert all dylibs and add
        // ->from a snapshot: 'toJSON' takes the (global) tasks lock, which must never nest inside the task lock
        for(Binary* dylib in [self dylibsSnapshot])
        {
            //convert/add
            [dylibsJSON appendFormat:@"{%@},", [dylib toJSON]];
        }

        //remove last ','
        if(YES == [dylibsJSON hasSuffix:@","])
        {
            //remove
            [dylibsJSON deleteCharactersInRange:NSMakeRange([dylibsJSON length]-1, 1)];
        }

        //sync
        @synchronized(self.files)
        {
            //convert all file and add
            for(File* file in self.files)
            {
                //convert/add
                [filesJSON appendFormat:@"{%@},", [file toJSON]];
            }
        }

        //remove last ','
        if(YES == [filesJSON hasSuffix:@","])
        {
            //remove
            [filesJSON deleteCharactersInRange:NSMakeRange([filesJSON length]-1, 1)];
        }

        //sync
        @synchronized(self.connections)
        {
            //convert all connections and add
            for(Connection* connection in self.connections)
            {
                //convert/add
                [connectionsJSON appendFormat:@"{%@},", [connection toJSON]];
            }
        }

        //remove last ','
        if(YES == [connectionsJSON hasSuffix:@","])
        {
            //remove
            [connectionsJSON deleteCharactersInRange:NSMakeRange([connectionsJSON length]-1, 1)];
        }

        //init json
        json = [NSString stringWithFormat:@"\"name\": \"%@\", \"path\": \"%@\", \"pid\": %@, \"command line\": \"%@\", \"hashes\": %@, \"signature(s)\": %@, \"VT detection\": \"%@\", \"encrypted\": %s, \"packed\": %s, \"not found\": %s, \"es client\": %s, \"dylibs\": [%@], \"files\": [%@], \"connections\": [%@]", jsonEscape(self.binary.name), jsonEscape(self.binary.path), self.pid, jsonEscape(taskCommandLine), fileHashes, fileSigs, vtDetectionRatio, (YES == self.binary.isEncrypted) ? "true" : "false", (YES == self.binary.isPacked) ? "true" : "false", (YES == self.binary.notFound) ? "true" : "false", (YES == self.isESClient) ? "true" : "false", dylibsJSON, filesJSON, connectionsJSON];
    }

    //basic
    else
    {
        //init json
        json = [NSString stringWithFormat:@"\"name\": \"%@\", \"path\": \"%@\", \"pid\": %@, \"command line\": \"%@\", \"hashes\": %@, \"signature(s)\": %@, \"VT detection\": \"%@\", \"encrypted\": %s, \"packed\": %s, \"not found\": %s, \"es client\": %s", jsonEscape(self.binary.name), jsonEscape(self.binary.path), self.pid, jsonEscape(taskCommandLine), fileHashes, fileSigs, vtDetectionRatio, (YES == self.binary.isEncrypted) ? "true" : "false", (YES == self.binary.isPacked) ? "true" : "false", (YES == self.binary.notFound) ? "true" : "false", (YES == self.isESClient) ? "true" : "false"];
    }

    return json;
}

@end
