//
//  remoteTaskService.m
//  remoteTaskService
//
//  Created by Patrick Wardle on 5/27/15.
//  Copyright (c) 2015 Patrick Wardle. All rights reserved.
//

#import "Consts.h"
#import "Utilities.h"
#import "remoteTaskService.h"

#import <syslog.h>
#import <libproc.h>
#import <arpa/inet.h>
#import <sys/sysctl.h>
#import <mach/mach_vm.h>
#import <mach-o/dyld_images.h>

//32bit
struct dyld_image_info_32 {
    int	imageLoadAddress;
    int	imageFilePath;
    int imageFileModDate;
};

@implementation remoteTaskService

+(remoteTaskService *)defaultService
{
    static dispatch_once_t onceToken;
    static remoteTaskService *shared;
    dispatch_once(&onceToken, ^{
        shared = [remoteTaskService new];
    });
    return shared;
}

//get task's commandline args
// ->args returned in array arg
-(void)getTaskArgs:(NSNumber*)taskPID withReply:(void (^)(NSMutableArray *))reply
{
    //task's args
    NSMutableArray* arguments = nil;
    
    //'management info base' array
    int mib[3] = {0};
    
    //system's size for max args
    int systemMaxArgs = 0;
    
    //process's args
    char* taskArgs = NULL;
    
    //# of args
    int numberOfArgs = 0;
    
    //start of (each) arg
    char* argStart = NULL;
    
    //size of buffers, etc
    size_t size = 0;
    
    //parser pointer
    char* parser = NULL;
    
    //init mib
    // ->want system's size for max args
    mib[0] = CTL_KERN;
    mib[1] = KERN_ARGMAX;
    
    //alloc array for args
    arguments = [NSMutableArray array];

    //set size
    size = sizeof(systemMaxArgs);
    
    //get system's size for max args
    if(-1 == sysctl(mib, 2, &systemMaxArgs, &size, NULL, 0))
    {
        //bail
        goto bail;
    }
    
    //alloc space for args
    taskArgs = malloc(systemMaxArgs);
    if(NULL == taskArgs)
    {
        //bail
        goto bail;
    }
    
    //init mib
    // ->want process args
    mib[0] = CTL_KERN;
    mib[1] = KERN_PROCARGS2;
    mib[2] = taskPID.intValue;
    
    //set size
    size = (size_t)systemMaxArgs;
    
    //get process's args
    if(-1 == sysctl(mib, 3, taskArgs, &size, NULL, 0))
    {
        //bail
        goto bail;
    }
    
    //sanity check
    // ->ensure buffer is somewhat sane
    if(size <= sizeof(int))
    {
        //bail
        goto bail;
    }
    
    //extract number of args
    // ->at start of buffer
    memcpy(&numberOfArgs, taskArgs, sizeof(numberOfArgs));
    
    //extract task's name
    // ->follows # of args (int) and is NULL-terminated
    [arguments addObject:[NSString stringWithUTF8String:taskArgs + sizeof(int)]];
    
    //init point to start of args
    // ->they start right after # of args
    parser = taskArgs + sizeof(numberOfArgs);
    
    //scan until end of task's NULL-terminated path
    while(parser < &taskArgs[size])
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
    if(parser == &taskArgs[size])
    {
        //bail
        goto bail;
    }
    
    //skip all trailing NULLs
    // ->scan will non-NULL is found
    while(parser < &taskArgs[size])
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
    if(parser == &taskArgs[size])
    {
        //bail
        goto bail;
    }
    
    //parser should now point to argv[0], task name
    // ->init arg start
    argStart = parser;
    
    //keep scanning until all args are found
    // ->each is NULL-terminated
    while(parser < &taskArgs[size])
    {
        //each arg is NULL-terminated
        // ->so scan till NULL, then save into array
        if(*parser == '\0')
        {
            //save arg
            if(NULL != argStart)
            {
                //save
                [arguments addObject:[NSString stringWithUTF8String:argStart]];
            }
            
            //init string pointer to (possibly) next arg
            argStart = ++parser;
            
            //bail if we've hit arg cnt
            // ->note: added full process path as faux arg[0], so add 1
            if(arguments.count == numberOfArgs + 1)
            {
                //bail
                break;
            }
        }
        
        //next char
        parser++;
    }
    
//bail
bail:
    
    //free process args
    if(NULL != taskArgs)
    {
        //free
        free(taskArgs);
        
        //reset
        taskArgs = NULL;
    }
    
    //invoke reply block
    reply(arguments);

    return;
}

//enumerate dylibs for a specified task
-(void)enumerateDylibs:(NSNumber*)pid withReply:(void (^)(NSMutableArray *))reply
{
    //dylibs
    NSMutableArray* dylibs = nil;

    //results from 'file' cmd
    NSMutableDictionary* results = nil;
    
    //output (stdout) from 'file' cmd
    NSString* output = nil;
    
    //path offset
    NSRange pathOffset = {0};
    
    //dylib
    NSString* dylib = nil;
    
    //skip self
    // can't vmmap self :|
    if(pid.intValue != getpid())
    {
        goto bail;
    }
    
    //alloc array for dylibs
    dylibs = [NSMutableArray array];
    
    //exec vmmap
    results = execTask(VMMAP, @[@"-w", [pid stringValue]], YES);
    if( (nil == results[EXIT_CODE]) ||
        (0 != [results[EXIT_CODE] integerValue]) )
    {
        //bail
        goto bail;
    }
    
    //convert stdout data to string
    output = [[NSString alloc] initWithData:results[STDOUT] encoding:NSUTF8StringEncoding];
    
    //iterate over all results
    // line by line, looking for '__TEXT'
    for(NSString* line in [output componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]])
    {
        //ignore any line that doesn't start with '__TEXT'
        if(YES != [line hasPrefix:@"__TEXT"])
        {
            //skip
            continue;
        }
        
        //format of line is: __TEXT 00007fff63564000-00007fff6359b000 [  220K] r-x/rwx SM=COW  /usr/lib/dyld
        // ->grab path, by finding: '  /'
        pathOffset = [line rangeOfString:@"  /"];
        
        //sanity check
        // ->make sure path was found
        if(NSNotFound == pathOffset.location)
        {
            //not found
            continue;
        }
        
        //extract dylib's path
        // ->trim leading whitespace
        dylib = [[line substringFromIndex:pathOffset.location] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        
        //sanity check
        if(nil == dylib)
        {
            //skip
            continue;
        }
        
        //add to results array
        [dylibs addObject:dylib];
    }
    
    //remove dups
    [dylibs setArray:[[[NSSet setWithArray:dylibs] allObjects] mutableCopy]];
    
    //send back
    reply(dylibs);
    
bail:

    return;
}

//enumerate open files
// ->accomplish this via lsof, since proc_pidinfo() misses some files...
-(void)enumerateFiles:(NSNumber*)taskPID withReply:(void (^)(NSMutableArray *))reply
{
    //results
    NSMutableDictionary* results = nil;
    
    //results split on '\n'
    NSArray* splitResults = nil;
    
    //file path
    NSString* filePath = nil;
    
    //file info dictionary
    NSMutableDictionary* fileInfo = nil;
    
    //just file paths
    // ->helps detect/ignore dups
    NSMutableArray* filePaths = nil;
    
    //unique files
    NSMutableArray* files = nil;
    
    //init array for file paths
    filePaths = [NSMutableArray array];
    
    //init array for unqiue files
    files = [NSMutableArray array];
   
    //exec 'file' to get file type
    results = execTask(LSOF, @[@"-Fn", @"-p", taskPID.stringValue], YES);
    if( (nil == results[EXIT_CODE]) ||
        (0 != [results[EXIT_CODE] integerValue]) )
    {
        //bail
        goto bail;
    }
    
    //split results into array
    splitResults = [[[NSString alloc] initWithData:results[STDOUT] encoding:NSUTF8StringEncoding] componentsSeparatedByString:@"\n"];
    if( (nil == splitResults) ||
        (0 == splitResults.count) )
    {
        //bail
        goto bail;
    }

    //iterate over all results
    // ->make file info dictionary for files (not sockets, etc)
    for(NSString* result in splitResults)
    {
        //skip any odd/weird/short lines
        // lsof outpupt will be in format: 'n<filePath'>
        if( (YES != [result hasPrefix:@"n"]) ||
            (result.length < 0x2) )
        {
            //skip
            continue;
        }
        
        //init file path
        // ->result, minus first (lsof-added) char
        filePath = [result substringFromIndex:0x1];
        
        //skip 'non files'
        if(YES != [[NSFileManager defaultManager] fileExistsAtPath:filePath])
        {
            //skip
            continue;
        }
        
        //also skip files such as '/', /dev/null, etc
        if( (YES == [filePath isEqualToString:@"/"]) ||
            (YES == [filePath isEqualToString:@"/dev/null"]) )
        {
            //skip
            continue;
        }
        
        //also avoid duplicates
        if(YES == [filePaths containsObject:filePath])
        {
            //skip
            continue;
        }
        
        //alloc info dictionary
        fileInfo = [NSMutableDictionary dictionary];
        
        //add path
        fileInfo[KEY_FILE_PATH] = filePath;
        
        //save
        [files addObject:fileInfo];
        
        //add to list of paths
        // ->prevents dups
        [filePaths addObject:filePath];
    }
    
//bail
bail:
    
    //invoke reply
    reply(files);
    
    return;
}

//TODO: soi_rcv/soi_snd to get packets!?
//enumerate network connections
-(void)enumerateNetwork:(NSNumber*)taskPID withReply:(void (^)(NSMutableArray *))reply
{
    //task's sockets
    NSMutableArray* sockets = nil;
    
    //socket info dictionary
    NSMutableDictionary* socket = nil;

    //size
    int bufferSize = -1;
    
    //proc handles
    struct proc_fdinfo *procFDInfo = NULL;
    
    //number of handle
    int numberOfProcFDs = 0;
    
    //socket info struct
    struct socket_fdinfo socketInfo = {0};
    
    //socket local addr
    // ->big enough for both IPv4 and IPv6
    char localIPAddr[INET6_ADDRSTRLEN] = {0};
    
    //socket remote addr
    // ->big enough for both IPv4 and IPv6
    char remoteIPAddr[INET6_ADDRSTRLEN] = {0};
    
    //socket remote port
    short remotePort = 0;
    
    //alloc array for sockets
    sockets = [NSMutableArray array];
    
    //invoke proc_pidinfo w/ NULL
    // ->get's required buffer size
    bufferSize = proc_pidinfo([taskPID intValue], PROC_PIDLISTFDS, 0, 0, 0);
    if(bufferSize <= 0)
    {
        //bail
        goto bail;
    }
    
    //alloc buffer for handles
    procFDInfo = (struct proc_fdinfo *)malloc(bufferSize);
    
    //sanity check
    if(NULL == procFDInfo)
    {
        //bail
        goto bail;
    }
    
    //get proc's handles
    bufferSize = proc_pidinfo([taskPID intValue], PROC_PIDLISTFDS, 0, procFDInfo, bufferSize);
    if(bufferSize <= 0)
    {
        //bail
        goto bail;
    }
    
    //calc number of handles
    numberOfProcFDs = bufferSize / PROC_PIDLISTFD_SIZE;
    
    //iterate over all file descriptors
    // ->only care about sockets though...
    for(NSUInteger i = 0; i < numberOfProcFDs; i++)
    {
        //skip all non-sockets
        if(PROX_FDTYPE_SOCKET != procFDInfo[i].proc_fdtype)
        {
            //skip
            continue;
        }
        
        //get (detailed) info about socket
        // ->should return # of bytes that matches size of socket struct
        if(sizeof(struct socket_fdinfo) != proc_pidfdinfo([taskPID intValue], procFDInfo[i].proc_fd, PROC_PIDFDSOCKETINFO, &socketInfo, sizeof(struct socket_fdinfo)))
        {
            //skip
            continue;
        }
            
        //skip any non-internet sockets
        if( (socketInfo.psi.soi_family != AF_INET) &&
            (socketInfo.psi.soi_family != AF_INET6) )
        {
            //skip
            continue;
        }
        
        //alloc dictionary for socket
        socket = [NSMutableDictionary dictionary];
            
        //add local port
        socket[KEY_LOCAL_PORT] = [NSNumber numberWithShort:ntohs(socketInfo.psi.soi_proto.pri_tcp.tcpsi_ini.insi_lport)];
        
        //get remote port
        remotePort = ntohs(socketInfo.psi.soi_proto.pri_tcp.tcpsi_ini.insi_fport);
        
        //IPv4 sockets
        if(socketInfo.psi.soi_family == AF_INET)
        {
            //get local ip addr
            inet_ntop(AF_INET, &socketInfo.psi.soi_proto.pri_tcp.tcpsi_ini.insi_laddr.ina_46.i46a_addr4, localIPAddr, sizeof(localIPAddr));
            
            //add local ip addr
            socket[KEY_LOCAL_ADDR] = [NSString stringWithUTF8String:localIPAddr];
            
            //for connected sessions
            // ->get/save remote ip addr
            if(0 != remotePort)
            {
                //add remote port
                socket[KEY_REMOTE_PORT] = [NSNumber numberWithShort:remotePort];
                
                //get remote ip addr
                inet_ntop(AF_INET, &socketInfo.psi.soi_proto.pri_tcp.tcpsi_ini.insi_faddr.ina_46.i46a_addr4, remoteIPAddr, sizeof(remoteIPAddr));
                
                //add remote ip addr
                socket[KEY_REMOTE_ADDR] = [NSString stringWithUTF8String:remoteIPAddr];
            }
        }
        //IPv6 sockets
        else if(socketInfo.psi.soi_family == AF_INET6)
        {
            //get local ip addr
            inet_ntop(AF_INET6, &socketInfo.psi.soi_proto.pri_tcp.tcpsi_ini.insi_laddr.ina_6, localIPAddr, sizeof(localIPAddr));
            
            //TODO: ::1 -> 'loopback' or 0:0:0:0:0:0:0:1
            // or ::0, 'unspecified' (see: https://en.wikipedia.org/wiki/IPv6_address)
            
            //add local ip addr
            socket[KEY_LOCAL_ADDR] = [NSString stringWithUTF8String:localIPAddr];
            
            //for connected sessions
            // ->get remote ip addr
            if(0 != remotePort)
            {
                //add remote port
                socket[KEY_REMOTE_PORT] = [NSNumber numberWithShort:remotePort];
                
                //get remote ip addr
                inet_ntop(AF_INET6, &socketInfo.psi.soi_proto.pri_tcp.tcpsi_ini.insi_faddr.ina_6, remoteIPAddr, sizeof(remoteIPAddr));
                
                //add remote ip addr
                socket[KEY_REMOTE_ADDR] = [NSString stringWithUTF8String:remoteIPAddr];
            }
        }
        
        //set type
        socket[KEY_SOCKET_TYPE] = [NSNumber numberWithInt:socketInfo.psi.soi_type];
        
        //set family
        // ->for now this will only be 'AF_INET' or 'AF_INET6'
        socket[KEY_SOCKET_FAMILY] = [NSNumber numberWithInt:socketInfo.psi.soi_family];
        
        //set protocol
        socket[KEY_SOCKET_PROTO] = [NSNumber numberWithInt:socketInfo.psi.soi_protocol];
        
        //get state
        // ->only for stream stockets though
        if(SOCK_STREAM == socketInfo.psi.soi_type)
        {
            //set state
            socket[KEY_SOCKET_STATE] = [NSNumber numberWithInt:socketInfo.psi.soi_proto.pri_tcp.tcpsi_state];
        }
        
        //add
        [sockets addObject:socket];
        
    }//all FDs

//bail
bail:
    
    //free buffer
    if(nil != procFDInfo)
    {
        //free
        free(procFDInfo);
    }
    
    //invoke reply
    reply(sockets);
    
    return;
}

@end


