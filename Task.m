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
#import "Utilities.h"
#import "Connection.h"
#import "AppDelegate.h"
#import "remoteTaskService.h"

#import <syslog.h>
#import <libproc.h>
#import <sys/sysctl.h>
#import <sys/proc_info.h>

@implementation Task

@synthesize pid;
@synthesize uid;
@synthesize ppid;
@synthesize files;
@synthesize binary;
@synthesize dylibs;
@synthesize children;
@synthesize arguments;
@synthesize connections;

//init w/ a pid
// note: time consuming init's are done in other methods
-(id)initWithPID:(NSNumber*)taskPID
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
        
        //get task's path
        taskPath = [self getPath];

        //try extract existing binary
        // ->but only if task's path is known
        if(YES != [taskPath isEqualToString:TASK_PATH_UNKNOWN])
        {
            //lookup
            existingBinary = existingBinaries[taskPath];
        }
        
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
            
            //sync
            @synchronized(existingBinaries)
            {
                //add it to 'global' list
                existingBinaries[taskPath] = self.binary;
            }
        }
        
    }//init self
    
//bail
bail:
    
    return self;
}

//get task's path
// ->via 'proc_pidpath()' or via task's args (via XPC) if that fails...
-(NSString*)getPath
{
    //task path
    NSString* taskPath = nil;
    
    //buffer for process path
    char pathBuffer[PROC_PIDPATHINFO_MAXSIZE] = {0};
    
    //status
    int status = -1;
    
    //reset buffer
    bzero(pathBuffer, PROC_PIDPATHINFO_MAXSIZE);
    
    //kernel 'task' is special
    if(0 == self.pid.intValue)
    {
        //set
        taskPath = path2Kernel();
        
        //all set
        goto bail;
    }
    
    //get task's path via 'proc_pidpath()'
    // ->this might fail, so will then attempt via task's args ('KERN_PROCARGS2')
    status = proc_pidpath(self.pid.intValue, pathBuffer, sizeof(pathBuffer));
    if(0 != status)
    {
        //init task's name
        taskPath = [NSString stringWithUTF8String:pathBuffer];
    }
    //try via task's args (via XPC)
    else
    {
        //grab args
        // ->set's 'arguments' iVar
        [self getArguments];
        
        //sanity check
        if( (nil == self.arguments) ||
            (0 == self.arguments.count) )
        {
            //bail
            goto bail;
        }
        
        //arg[0] should be full path
        taskPath = self.arguments.firstObject;
    }
    
//bail
bail:
    
    //when task path is still nil
    // ->set to const for unknown path...
    if(nil == taskPath)
    {
        //set
        taskPath = TASK_PATH_UNKNOWN;
    }
    
    return taskPath;
}

//get command-line args via XPC request to remote service
// ->waits for XPC, then sets 'arguments' iVar
-(void)getArguments
{
    //xpc connection
    __block NSXPCConnection* xpcConnection = nil;
    
    //wait semaphore
    dispatch_semaphore_t waitSema = nil;
    
    //alloc XPC connection
    xpcConnection = [[NSXPCConnection alloc] initWithServiceName:@"com.objective-see.remoteTaskService"];
    
    //set remote object interface
    xpcConnection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(remoteTaskProto)];
    
    //set classes
    // ->arrays & strings are what is ok to vend
    [xpcConnection.remoteObjectInterface setClasses: [NSSet setWithObjects: [NSMutableArray class], [NSString class], nil]
     forSelector: @selector(getTaskArgs:withReply:) argumentIndex: 0 ofReply: YES];
    
    //resume
    [xpcConnection resume];
    
    //init wait semaphore
    waitSema = dispatch_semaphore_create(0);
    
    //invoke XPC service (running as r00t)
    // ->will enumerate files, then invoke reply block so can save into iVar
    [[xpcConnection remoteObjectProxy] getTaskArgs:self.pid withReply:^(NSMutableArray* taskArguments)
    {
        //close connection
        [xpcConnection invalidate];
        
        //nil out
        xpcConnection = nil;
        
        //grab array
        self.arguments = taskArguments;
        
        //signal sema
        dispatch_semaphore_signal(waitSema);
        
    }];
    
    //wait until XPC is done
    // ->XPC reply block will signal semaphore
    dispatch_semaphore_wait(waitSema, DISPATCH_TIME_FOREVER);

    return;
}

//enumerate all dylibs
// ->new ones are added to 'existingDylibs' (global) dictionary
-(void)enumerateDylibs:(NSMutableDictionary*)allDylibs shouldWait:(BOOL)shouldWait
{
    //xpc connection
    __block NSXPCConnection* xpcConnection = nil;
    
    //dylib instance (as Binary) obj
    __block Binary* dylib = nil;
    
    //new dylibs
    // ->ones that should be hashed/processed
    __block NSMutableArray* newDylibs = nil;
    
    //wait semaphore
    dispatch_semaphore_t waitSema = nil;
    
    //alloc array for new dylibs
    newDylibs = [NSMutableArray array];
    
    //alloc XPC connection
    xpcConnection = [[NSXPCConnection alloc] initWithServiceName:@"com.objective-see.remoteTaskService"];

    //set remote object interface
    xpcConnection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(remoteTaskProto)];
    
    //set classes
    // ->arrays, dictionaries, & strings are what is ok to vend
    [xpcConnection.remoteObjectInterface
     setClasses: [NSSet setWithObjects: [NSMutableArray class], [NSMutableDictionary class], [NSString class], nil]
     forSelector: @selector(enumerateDylibs:withReply:)
     argumentIndex: 0  // the first parameter
     ofReply: YES // in the method itself.
     ];
    
    //resume
    [xpcConnection resume];
    
    //init wait semaphore
    waitSema = dispatch_semaphore_create(0);

    //invoke XPC service (running as r00t)
    // ->will enumerate dylibs, then invoke reply block to save into iVar
    [[xpcConnection remoteObjectProxy] enumerateDylibs:self.pid withReply:^(NSMutableArray* dylibPaths) {
        
        //close connection
        [xpcConnection invalidate];
        
        //nil out
        xpcConnection = nil;
        
        //sync
        @synchronized(self.dylibs)
        {
        
        //reset existing dylibs
        [self.dylibs removeAllObjects];
        
        //add all dylibs
        for(NSString* dylibPath in dylibPaths)
        {
            //skip main executable image
            // ->making sure to resolve symlinks
            if(YES == [dylibPath isEqualToString:[self.binary.path stringByResolvingSymlinksInPath]])
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
            
            //add to task's dylibs
            [self.dylibs addObject:dylib];
    
        }//all dylibs
        
        //sort by name
        self.dylibs = [[self.dylibs sortedArrayUsingComparator:^NSComparisonResult(id a, id b)
        {
            //sort
            return [[(Binary*)a name] compare:[(Binary*)b name] options:NSCaseInsensitiveSearch];
            
        }] mutableCopy];
        
        //reload bottom pane now
        // note: this will only reload if new task is the currently selected one, etc
        [((AppDelegate*)[[NSApplication sharedApplication] delegate]) reloadBottomPane:self itemView:DYLIBS_VIEW];
            
        }//sync
        
        //complete dylib processing for new dylib
        // ->get signing info, hash, etc, & save into global list
        //   ...reloads each row (if task is still current)
        for(Binary* newDylib in newDylibs)
        {
            //generate signing info
            // ->do this before macho parsing!
            [newDylib generatedSigningInfo];
            
            //parse
            if(YES == [newDylib parse])
            {
                //save encrypted flag
                newDylib.isEncrypted = [newDylib.parser.binaryInfo[KEY_IS_ENCRYPTED] boolValue];
                
                //save packed flag
                newDylib.isPacked = [newDylib.parser.binaryInfo[KEY_IS_PACKED] boolValue];
            }
        
            //no need to reload if task is now longer current/selected
            if(((AppDelegate*)[[NSApplication sharedApplication] delegate]).currentTask != self)
            {
                //skip reload
                continue;
            }
            
            //reload row
            [((AppDelegate*)[[NSApplication sharedApplication] delegate]) reloadRow:newDylib];
        }
        
        //signal sema
        dispatch_semaphore_signal(waitSema);
    }];
    
    //wait until XPC is done?
    if(YES == shouldWait)
    {
        //wait
        dispatch_semaphore_wait(waitSema, DISPATCH_TIME_FOREVER);
    }

    return;
}

//enumerate all file descriptors
-(void)enumerateFiles:(BOOL)shouldWait
{
    //xpc connection
    __block NSXPCConnection* xpcConnection = nil;
    
    //File object
    __block File* file = nil;
    
    //wait semaphore
    dispatch_semaphore_t waitSema = nil;
    
    //file path
    __block NSString* filePath = nil;
    
    //alloc XPC connection
    xpcConnection = [[NSXPCConnection alloc] initWithServiceName:@"com.objective-see.remoteTaskService"];
    
    //set remote object interface
    xpcConnection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(remoteTaskProto)];
    
    //set classes
    // ->arrays, dictionaries, & strings are what is ok to vend
    [xpcConnection.remoteObjectInterface
     setClasses: [NSSet setWithObjects: [NSMutableArray class], [NSMutableDictionary class], [NSString class], nil]
     forSelector: @selector(enumerateFiles:withReply:)
     argumentIndex: 0  // the first parameter
     ofReply: YES // in the method itself.
     ];
    
    //resume
    [xpcConnection resume];
    
    //init wait semaphore
    waitSema = dispatch_semaphore_create(0);
    
    //invoke XPC service (running as r00t)
    // ->will enumerate files, then invoke reply block so can save into iVar
    [[xpcConnection remoteObjectProxy] enumerateFiles:self.pid withReply:^(NSMutableArray* fileDescriptors) {
        
        //close connection
        [xpcConnection invalidate];
        
        //nil out
        xpcConnection = nil;
        
        //sync
        @synchronized(self.files)
        {
        
        //reset existing files
        [self.files removeAllObjects];
        
        //create/add all files
        for(NSMutableDictionary* fileDescriptor in fileDescriptors)
        {
            //extract file path
            filePath = fileDescriptor[KEY_FILE_PATH];
            
            //alloc/init File obj
            file = [[File alloc] initWithParams:@{KEY_RESULT_PATH:filePath}];
            
            //sync
            @synchronized(self.files)
            {
                //add to task's files
                [self.files addObject:file];
            }
        }
        
        //sort by name
        self.files = [[self.files sortedArrayUsingComparator:^NSComparisonResult(id a, id b)
        {
            //sort
            return [[(File*)a name] compare:[(File*)b name] options:NSCaseInsensitiveSearch];
            
        }] mutableCopy];
        
        //reload bottom pane
        [((AppDelegate*)[[NSApplication sharedApplication] delegate]) reloadBottomPane:self itemView:FILES_VIEW];
            
        }//sync
        
        //signal sema
        dispatch_semaphore_signal(waitSema);
        
    }];
    
    //wait until XPC is done?
    if(YES == shouldWait)
    {
        //wait
        dispatch_semaphore_wait(waitSema, DISPATCH_TIME_FOREVER);
    }
    
   return;
}

//enumerate network sockets/connections
-(void)enumerateNetworking:(BOOL)shouldWait
{
    //xpc connection
    __block NSXPCConnection* xpcConnection = nil;
    
    //Connection object
    __block Connection* connection = nil;
    
    //wait semaphore
    dispatch_semaphore_t waitSema = nil;
    
    //alloc XPC connection
    xpcConnection = [[NSXPCConnection alloc] initWithServiceName:@"com.objective-see.remoteTaskService"];
    
    //set remote object interface
    xpcConnection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(remoteTaskProto)];
    
    //set classes
    // ->arrays & strings are what is ok to vend
    [xpcConnection.remoteObjectInterface
     setClasses: [NSSet setWithObjects: [NSMutableArray class], [NSMutableDictionary class], [NSString class], [NSNumber class], nil]
     forSelector: @selector(enumerateNetwork:withReply:)
     argumentIndex: 0  // the first parameter
     ofReply: YES // in the method itself.
     ];
    
    //resume
    [xpcConnection resume];
    
    //init wait semaphore
    waitSema = dispatch_semaphore_create(0);
    
    //invoke XPC service (running as r00t)
    // ->will enumerate network sockets/connections, then invoke reply block so can save into iVar
    [[xpcConnection remoteObjectProxy] enumerateNetwork:self.pid withReply:^(NSMutableArray* networkItems) {
        
        //close connection
        [xpcConnection invalidate];
        
        //nil out
        xpcConnection = nil;
    
        //sync
        @synchronized(self.connections)
        {
        
        //remove any existing enum'd networking sockets/connections
        [self.connections removeAllObjects];
            
        //create/add all network sockets/connection
        for(NSMutableDictionary* networkItem in networkItems)
        {
            //alloc/init File obj
            connection = [[Connection alloc] initWithParams:networkItem];
            
            //add connection obj
            if(nil != connection)
            {
                //add
                [self.connections addObject:connection];
            }
        }
            
        //reload bottom pane
        [((AppDelegate*)[[NSApplication sharedApplication] delegate]) reloadBottomPane:self itemView:NETWORKING_VIEW];
            
        }//sync
        
        //signal sema
        dispatch_semaphore_signal(waitSema);
        
    }];
    
    //wait until XPC is done?
    if(YES == shouldWait)
    {
        //wait
        dispatch_semaphore_wait(waitSema, DISPATCH_TIME_FOREVER);
    }
    
    return;
}

//compare
// ->uses binary name
-(NSComparisonResult)compare:(Task*)otherTask
{
    return [self.binary.name compare:otherTask.binary.name options:NSCaseInsensitiveSearch];
}

//convert self to JSON string
-(NSString*)toJSON
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
    
    //sync
    @synchronized(self.dylibs)
    {
        //convert all dylibs and add
        for(Binary* dylib in self.dylibs)
        {
            //convert/add
            [dylibsJSON appendFormat:@"{%@},", [dylib toJSON]];
        }
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
    json = [NSString stringWithFormat:@"\"name\": \"%@\", \"path\": \"%@\", \"pid\": \"%@\", \"command line\": \"%@\", \"hashes\": %@, \"signature(s)\": %@, \"VT detection\": \"%@\", \"encrypted\": %d, \"packed\": %d, \"not found\": %d, \"dylibs\": [%@], \"files\": [%@], \"connections\": [%@]", self.binary.name, self.binary.path, self.pid, taskCommandLine, fileHashes, fileSigs, vtDetectionRatio, self.binary.isEncrypted, self.binary.isPacked, self.binary.notFound, dylibsJSON, filesJSON, connectionsJSON];
    
    return json;
}





@end
