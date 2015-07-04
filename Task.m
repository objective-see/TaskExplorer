//
//  Task.m
//  TaskExplorer
//
//  Created by Patrick Wardle on 5/2/15.
//  Copyright (c) 2015 Lucas Derraugh. All rights reserved.
//

#import "Task.h"
#import "Consts.h"
#import "Utilities.h"
#import "File.h"
#import "Connection.h"
#import "remoteTaskService.h"
#import "AppDelegate.h"

#import <mach-o/dyld_images.h>
#import <mach/mach_init.h>
#import <mach/mach_vm.h>
#import <sys/types.h>
#import <mach/mach.h>
#import <sys/ptrace.h>
#import <sys/wait.h>
#import <sys/sysctl.h>
#import <sys/proc_info.h>
#import <libproc.h>
#import <arpa/inet.h>
#import <netinet/tcp_fsm.h>


@implementation Task

@synthesize pid;
@synthesize uid;
//@synthesize icon;
//@synthesize name;
//@synthesize path;
@synthesize ppid;
@synthesize files;
@synthesize binary;
//@synthesize bundle;
@synthesize dylibs;
@synthesize children;
@synthesize arguments;
@synthesize connections;

//TODO: make sure we only check signature of binary once!!!

//init w/ a pid + path
// note: time consuming init's are done in '' method
-(id)initWithPID:(NSNumber*)taskPID andPath:(NSString*)taskPath
{
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
        existingBinaries = ((AppDelegate*)[[NSApplication sharedApplication] delegate]).taskEnumerator.executables;
        
        //since root UID is zero
        // ->init UID to -1
        //self.uid = -1;
        
        //save pid
        self.pid = taskPID;
        
        //alloc array for children
        children = [NSMutableArray array];
        
        //alloc array for dylibs
        dylibs = [NSMutableArray array];
        
        //alloc array for open files
        files = [NSMutableArray array];
        
        //alloc array for network connections
        connections = [NSMutableArray array];
        
        //get parent id
        self.ppid = [NSNumber numberWithInteger:getParentID([taskPID intValue])];
        
        //try extract existing binary
        // ->will succeed for multiple instances of the same task (process)
        existingBinary = existingBinaries[taskPath];
        
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
            
            //add to queue
            // ->this will process in background
            [((AppDelegate*)[[NSApplication sharedApplication] delegate]).taskEnumerator.binaryQueue enqueue:self.binary];
            
            //add it to 'global' list
            existingBinaries[taskPath] = self.binary;
        }
        
    }//init self
    
//bail
bail:
    
    return self;
}

//
-(void)generateBinaryInfo
{
    //create main binary
    //self.binary = [[Binary alloc] initWithParams:@{KEY_RESULT_PATH:self.path}];
    
    return;
}

//get command-line args
-(void)getArguments
{
    //'management info base' array
    int mib[3] = {0};
    
    //system's size for max args
    int systemMaxArgs = 0;
    
    //process's args
    char* processArgs = NULL;
    
    //# of args
    int numberOfArgs = 0;
    
    //start of (each) arg
    char* argStart = NULL;
    
    //size of buffers, etc
    size_t size = 0;
    
    //parser pointer
    char *parser;
    
    //init mib
    // ->want system's size for max args
    mib[0] = CTL_KERN;
    mib[1] = KERN_ARGMAX;
    
    //first time
    // ->alloc array for args
    if(nil == self.arguments)
    {
        //alloc
        arguments = [NSMutableArray array];
    }
    
    //set size
    size = sizeof(systemMaxArgs);
    
    //get system's size for max args
    if(-1 == sysctl(mib, 2, &systemMaxArgs, &size, NULL, 0))
    {
        //bail
        goto bail;
    }
    
    //alloc space for args
    processArgs = malloc(systemMaxArgs);
    if(NULL == processArgs)
    {
        //bail
        goto bail;
    }
    
    //init mib
    // ->want process args
    mib[0] = CTL_KERN;
    mib[1] = KERN_PROCARGS2;
    mib[2] = [self.pid intValue];
    
    //set size
    size = (size_t)systemMaxArgs;
    
    //get process's args
    if(-1 == sysctl(mib, 3, processArgs, &size, NULL, 0))
    {
        //bail
        goto bail;
    }
    
    //extract number of args
    // ->at start of buffer
    memcpy(&numberOfArgs, processArgs, sizeof(numberOfArgs));
    
    //skip procs w/ no args
    // ->note: don't care about arg[0]
    if(numberOfArgs < 2)
    {
        //no args
        goto bail;
    }
    
    //init point to start of args
    // ->they start right after # of args
    parser = processArgs + sizeof(numberOfArgs);
    
    //skip over exe name
    // ->always at front, yes, even before arg[0] (which is also exe name)
    while(parser < &processArgs[size])
    {
        //scan till NULL-terminator
        if(0x0 == *parser)
        {
            //end of exe name
            break;
        }
        
        //next char
        parser++;
    }
    
    //sanity check
    // ->make sure end-of-buffer wasn't reached
    if(parser == &processArgs[size])
    {
        //bail
        goto bail;
    }
    
    //skip all trailing NULLs
    // ->scan will non-NULL is found
    while(parser < &processArgs[size])
    {
        //scan till NULL-terminator
        if(0x0 != *parser)
        {
            //ok, got to argv[0]
            break;
        }
        
        //next char
        parser++;
    }
    
    //sanity check
    // ->(again), make sure end-of-buffer wasn't reached
    if(parser == &processArgs[size])
    {
        //bail
        goto bail;
    }
    
    //keep scanning until all args are found
    // ->each is NULL-terminated
    while(parser < &processArgs[size])
    {
        //bail if we've hit arg cnt
        // ->note: don't save arg[0], so add 1
        if(self.arguments.count + 1 == numberOfArgs)
        {
            //bail
            break;
        }
        
        //each arg is NULL-terminated
        if(*parser == '\0')
        {
            //save arg
            // ->'argStart' is purposely NULL for argv[0]
            if(NULL != argStart)
            {
                [self.arguments addObject:[NSString stringWithUTF8String:argStart]];
            }
            
            //init string pointer to (possibly) next arg
            argStart = ++parser;
        }
        
        //next char
        parser++;
    }
    
//bail
bail:
    
    //free process args
    if(NULL != processArgs)
    {
        //free
        free(processArgs);
        
    }
    
    return;
}

//enumerate all dylibs
// ->new ones are added to 'existingDylibs' (global) dictionary
-(void)enumerateDylibs:(NSXPCConnection*)xpcConnection allDylibs:(NSMutableDictionary*)allDylibs
{
    //dylib instance (as Binary) obj
    __block Binary* dylib = nil;
    
    //new dylibs
    // ->ones that should be hashed/processed
    __block NSMutableArray* newDylibs = nil;
    
    //alloc array for new dylibs
    newDylibs = [NSMutableArray array];
    
    //sync
    @synchronized(self.dylibs)
    {
        //reset existing dylibs
        [self.dylibs removeAllObjects];
    }
    
    //invoke XPC service (running as r00t)
    // ->will enumerate dylibs, then invoke reply block to save into iVar
    [[xpcConnection remoteObjectProxy] enumerateDylibs:self.pid withReply:^(NSMutableArray* dylibPaths) {
        
        //add all dylibs
        for(NSString* dylibPath in dylibPaths)
        {
            //skip main image
            if(YES == [dylibPath isEqualToString:self.binary.path])
            {
                //skip
                continue;
            }
            
            //skip 'cl_kernels'
            // ->not an on-disk/'real' dylib
            if(YES == [dylibPath isEqualToString:@"cl_kernels"])
            {
                //skip
                continue;
            }
            
            //first try grab from 'global' list of all dylibs
            // ->will be non-nil if its already been processed
            dylib = allDylibs[dylibPath];
            
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
                
                //add to queue
                // ->this will trigger background processing
                [((AppDelegate*)[[NSApplication sharedApplication] delegate]).taskEnumerator.binaryQueue enqueue:dylib];
                
                //add to list of new dylibs
                // ->will allow for post processing
                [newDylibs addObject:dylib];
                
                //sync
                // ->add to global list
                @synchronized(allDylibs)
                {
                    //add
                    allDylibs[dylib.path] = dylib;
                }
            }
            
            //sync
            @synchronized(self.dylibs)
            {
                //add to task's dylibs
                [self.dylibs addObject:dylib];
            }
            
        } //all dylibs
        
        //sync to sort
        @synchronized(self.dylibs)
        {
            //sort by name
            self.dylibs = [[self.dylibs sortedArrayUsingComparator:^NSComparisonResult(id a, id b)
            {
                //sort
                return [[(Binary*)a name] compare:[(Binary*)b name] options:NSCaseInsensitiveSearch];
                
            }] mutableCopy];
        }
        
        //reload bottom pane now
        // ->this will only reload if new task is the currently selected one, etc
        [((AppDelegate*)[[NSApplication sharedApplication] delegate]) reloadBottomPane:self itemView:DYLIBS_VIEW];
        
        //complete dylib processing for new dylib
        // ->get signing info, hash, etc, & save into global list
        //   ...reloads each row (if task is still current)
        for(Binary* newDylib in newDylibs)
        {
            //generate signing info
            [newDylib generatedSigningInfo];
            
            //no need to reload if task is now longer current/selected
            if(((AppDelegate*)[[NSApplication sharedApplication] delegate]).currentTask != self)
            {
                //skip reload
                continue;
            }
            
            //reload row
            [((AppDelegate*)[[NSApplication sharedApplication] delegate]) reloadRow:newDylib];
        }
        
    }];
    
    return;
}

//enumerate all file descriptors
-(void)enumerateFiles:(NSXPCConnection*)xpcConnection
{
    //File object
    __block File* file = nil;
    
    //new files
    NSMutableArray* newFiles = nil;
    
    //file path
    __block NSString* filePath = nil;
    
    //alloc array for new files
    newFiles = [NSMutableArray array];
    
    //sync
    @synchronized(self.files)
    {
        //reset existing files
        [self.files removeAllObjects];
    }
    
    //invoke XPC service (running as r00t)
    // ->will enumerate files, then invoke reply block so can save into iVar
    [[xpcConnection remoteObjectProxy] enumerateFiles:self.pid withReply:^(NSMutableArray* fileDescriptors) {
        
        //create/add all files
        for(NSMutableDictionary* fileDescriptor in fileDescriptors)
        {
            //extract file path
            filePath = fileDescriptor[KEY_FILE_PATH];
            
            //alloc/init File obj
            file = [[File alloc] initWithParams:@{KEY_RESULT_PATH:filePath}];
            
            //skip nil files
            //TODO: look into what files err out!!
            if(nil == file)
            {
                //next
                continue;
            }
        
            //sync
            @synchronized(self.files)
            {
                //add to task's files
                [self.files addObject:file];
            }
            
            //save new files
            // ->will be processed below
            if(nil == [((AppDelegate*)[[NSApplication sharedApplication] delegate]).taskEnumerator.files objectForKey:filePath])
            {
                //save as new
                [newFiles addObject:file];
            }
        }
        
        //sync to sort
        @synchronized(self.files)
        {
            //sort by name
            self.files = [[self.files sortedArrayUsingComparator:^NSComparisonResult(id a, id b)
            {
                //sort
                return [[(File*)a name] compare:[(File*)b name] options:NSCaseInsensitiveSearch];
                
            }] mutableCopy];
        }
        
        //reload bottom pane
        [((AppDelegate*)[[NSApplication sharedApplication] delegate]) reloadBottomPane:self itemView:FILES_VIEW];
        
        //process all new files
        // ->calculate hash, etc & save into global list
        for(File* newFile in newFiles)
        {
            //generate detailed info
            [newFile generateDetailedInfo];
            
            //TODO: sync!
            //save into global list
            [((AppDelegate*)[[NSApplication sharedApplication] delegate]).taskEnumerator.files setObject:newFile forKey:filePath];
        }
    }];
    
   return;
}

//enumerate network sockets/connections
-(void)enumerateNetworking:(NSXPCConnection*)xpcConnection
{
    //File object
    __block Connection* connection = nil;
    
    //remove any existing enum'd networking sockets/connections
    [self.connections removeAllObjects];
    
    NSLog(@"invoking XPC to enumer networking");
    
    //invoke XPC service (running as r00t)
    // ->will enumerate network sockets/connections, then invoke reply block so can save into iVar
    [[xpcConnection remoteObjectProxy] enumerateNetwork:self.pid withReply:^(NSMutableArray* networkItems) {
        
        //
        //NSLog(@"found %d connections", networkItems.count);
        
        //create/add all network sockets/connection
        for(NSMutableDictionary* networkItem in networkItems)
        {
            //alloc/init File obj
            connection = [[Connection alloc] initWithParams:networkItem];
            
            //add File obj
            if(nil != connection)
            {
                //add
                [self.connections addObject:connection];
            }
        }
    
        ////TODO: on main thead?
        //reload bottom pane
        [((AppDelegate*)[[NSApplication sharedApplication] delegate]) reloadBottomPane:self itemView:NETWORKING_VIEW];
        
    }];
    
    return;
}


- (NSComparisonResult)compare:(Task*)otherTask
{
    return [self.binary.name compare:otherTask.binary.name options:NSCaseInsensitiveSearch];
}





@end
