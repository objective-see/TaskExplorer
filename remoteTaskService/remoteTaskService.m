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
#import <netdb.h>
#import <syslog.h>

//socket states
// ->note, index correspondes to numberic value
static const char* socketStates[] =
{
    "closed",
    "listening",
    "syn sent",
    "syn received",
    "established",
    "close/wait",
    "fin wait 1",
    "closing",
    "last act",
    "fin wait 2",
    "time wait",
};

static const char *socketFamilies[] =
{
    "AF_UNSPEC",
    "AF_UNIX",
    "AF_INET",
    "AF_IMPLINK",
    "AF_PUP",
    "AF_CHAOS",
    "AF_NS",
    "AF_ISO",
    "AF_ECMA",
    "AF_DATAKIT",
    "AF_CCITT",
    "AF_SNA",
    "AF_DECnet",
    "AF_DLI",
    "AF_LAT",
    "AF_HYLINK",
    "AF_APPLETALK",
    "AF_ROUTE",
    "AF_LINK",
    "#define",
    "AF_COIP",
    "AF_CNT",
    "pseudo_AF_RTIP",
    "AF_IPX",
    "AF_SIP",
    "pseudo_AF_PIP",
    "pseudo_AF_BLUE",
    "AF_NDRV",
    "AF_ISDN",
    "pseudo_AF_KEY",
    "AF_INET6",
    "AF_NATM",
    "AF_SYSTEM",
    "AF_NETBIOS",
    "AF_PPP",
    "pseudo_AF_HDRCMPLT",
    "AF_RESERVED_36",
};
#define SOCKET_FAMILY_MAX (int)(sizeof(socketFamilies)/sizeof(char *))


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

//enumerate dylibs for a specified task
// ->dylibs returned in array arg
-(void)enumerateDylibs:(NSNumber*)taskPID withReply:(void (^)(NSMutableArray *))reply;
{
    //dylibs
    NSMutableArray* dylibPaths = nil;
    
    //minor OS X version
    SInt32 versionMinor = 0;
    
    //get minor version
    versionMinor = getVersion(gestaltSystemVersionMinor);
    
    //when OS version is older then el capitan
    // ->read memory directly
    if(versionMinor < OS_MINOR_VERSION_EL_CAPITAN)
    {
        //enum dylibs
        dylibPaths = [self enumerateDylibsOld:(NSNumber*)taskPID];
        
    }
    //OS version is el capitan
    // ->have to use vmmap, since we don't com.apple.system-task-ports entitlement
    else
    {
        //enum dylibs
        dylibPaths = [self enumerateDylibsNew:(NSNumber*)taskPID];
    }
    
    //invoke reply block
    reply(dylibPaths);
    
    return;
}

//enumerate dylibs via direct memory reading
// ->can only do this pre-el capitan
-(NSMutableArray*)enumerateDylibsOld:(NSNumber*)pid
{
    //status
    kern_return_t status = !KERN_SUCCESS;
    
    //task for remote process
    task_t remoteTask = 0;
    
    //remote read addr
    vm_address_t remoteReadAddr = 0;
    
    //number of remote bytes to read
    mach_msg_type_number_t bytesToRead = 0;
    
    //dyld info structure
    // ->contains remote addr/size of dyld_all_image_infos
    struct task_dyld_info dyldInfo = {0};
    
    //set size of task info
    mach_msg_type_number_t taskInfoSize = 0;
    
    //pointer to structure for...
    // ->populated by mach_vm_read()
    struct dyld_all_image_infos* allImageInfo = NULL;
    
    //number of bytes read for dyld_all_image_infos
    mach_msg_type_number_t aifBytesRead = 0;
    
    //array of structs w/ dylib info
    void* dyldImageInfos = NULL;
    
    //number of bytes read for list of dyld_image_infos
    mach_msg_type_number_t diiBytesRead = 0;
    
    //pointer to dylib info struct
    // ->depending on remote (target) process either dyld_image_info or dyld_image_info_32
    void* imageInfo = NULL;
    
    //buffer for dylib path
    char* dylibPath = NULL;
    
    //number of bytes read for dyld_all_image_infos
    mach_msg_type_number_t dpBytesRead = 0;
    
    //dylibs
    NSMutableArray* dylibs = nil;
    
    //alloc array for dylibs
    dylibs = [NSMutableArray array];
    
    //get task for pid
    // ->allows access to read remote process memory
    status = task_for_pid(mach_task_self(), [pid intValue], &remoteTask);
    if(KERN_SUCCESS != status)
    {
        //err msg
        syslog(LOG_ERR, "OBJECTIVE-SEE ERROR: task_for_pid() failed w/ %d", status);
        
        //bail
        goto bail;
    }
    
    //set task info size
    taskInfoSize = TASK_DYLD_INFO_COUNT;
    
    //get TASK_DYLD_INFO
    // ->populates task_dyld_info structure
    status = task_info(remoteTask, TASK_DYLD_INFO, (task_info_t)&dyldInfo, &taskInfoSize);
    if(KERN_SUCCESS != status)
    {
        //bail
        goto bail;
    }
    
    //remotely read dyld_all_image_infos
    status = mach_vm_read(remoteTask, (vm_address_t)dyldInfo.all_image_info_addr, dyldInfo.all_image_info_size, (vm_offset_t*)&allImageInfo, &aifBytesRead);
    if(KERN_SUCCESS != status)
    {
        //err msg
        syslog(LOG_ERR, "OBJECTIVE-SEE ERROR: mach_vm_read() failed w/ %d", status);
        
        //bail
        goto bail;
    }
    
    //set remote read addr & size
    // ->64bit mode
    if(TASK_DYLD_ALL_IMAGE_INFO_64 == dyldInfo.all_image_info_format)
    {
        //straight assign
        remoteReadAddr = (vm_address_t)allImageInfo->infoArray;
        
        //init output size
        bytesToRead = allImageInfo->infoArrayCount * sizeof(struct dyld_image_info);
    }
    //set remote read addr & size
    // ->32bit mode
    else
    {
        //hack, can use 64bit version of struct (since 'infoArray' is first pointer)
        // ->but zero out top bits
        remoteReadAddr = (vm_address_t)allImageInfo->infoArray & 0xFFFFFFFF;
        
        //init output size
        bytesToRead = allImageInfo->infoArrayCount * sizeof(struct dyld_image_info_32);
    }
    
    //read remote array of dyld_image_info/32 structs
    status = mach_vm_read(remoteTask, (vm_address_t)remoteReadAddr, bytesToRead, (vm_offset_t*)&dyldImageInfos, &diiBytesRead);
    
    //check
    if(KERN_SUCCESS != status)
    {
        //err msg
        syslog(LOG_ERR, "OBJECTIVE-SEE ERROR: mach_vm_read() failed w/ %d", status);
        
        //bail
        goto bail;
    }
    
    //iterate over all dyld_image_info_32/dyld_image_info structs
    // ->extract and remotely read address to dylib path
    for(NSUInteger i = 0; i<allImageInfo->infoArrayCount; i++)
    {
        //reset
        dpBytesRead = 0;
        
        //advance to next image_info struct and set remote read addr
        // ->64bit mode
        if(TASK_DYLD_ALL_IMAGE_INFO_64 == dyldInfo.all_image_info_format)
        {
            //next dyld_image_info struct
            imageInfo = (unsigned char*)dyldImageInfos + i * sizeof(struct dyld_image_info);
            
            //remote read addr
            remoteReadAddr = (vm_address_t)((struct dyld_image_info*)imageInfo)->imageFilePath;
        }
        //advance to next image_info struct and set remote read addr
        // ->64bit mode
        else
        {
            //next dyld_image_info_32 struct
            imageInfo = (unsigned char*)dyldImageInfos + i * sizeof(struct dyld_image_info_32);
            
            //remote read addr
            remoteReadAddr = (vm_address_t)((struct dyld_image_info_32*)imageInfo)->imageFilePath & 0xFFFFFFFF;
        }
        
        //remotely read into dylib's path!
        // ->seems to always fail for first image, which is base executable...
        status = mach_vm_read(remoteTask, (vm_address_t)remoteReadAddr, PATH_MAX, (vm_offset_t*)&dylibPath, &dpBytesRead);
        
        //sanity check
        if( (KERN_SUCCESS != status) ||
            (NULL == dylibPath) )
        {
            //try next
            continue;
        }
        
        //save it
        [dylibs addObject:[NSString stringWithUTF8String:dylibPath]];
        
        //dealloc
        mach_vm_deallocate(mach_task_self(), (vm_offset_t)dylibPath, dpBytesRead);
        
    }//for all dyld_image_info_32/dyld_image_info structs
    
//bail
bail:
    
    //dealloc list of dylib info structs
    if(NULL != dyldImageInfos)
    {
        //dealloc
        mach_vm_deallocate(mach_task_self(), (vm_offset_t)dyldImageInfos, diiBytesRead);
    }
    
    //dealloc dyld_all_image_infos struct
    if(NULL != allImageInfo)
    {
        //dealloc
        mach_vm_deallocate(mach_task_self(), (vm_offset_t)allImageInfo, aifBytesRead);
    }
    
    //remove dups
    [dylibs setArray:[[[NSSet setWithArray:dylibs] allObjects] mutableCopy]];
    
    return dylibs;
    
}

//enumerate dylibs via vmmap
// ->OS version is el capitan, and we don't have the com.apple.system-task-ports entitlement :/
-(NSMutableArray*)enumerateDylibsNew:(NSNumber*)pid
{
    //dylibs
    NSMutableArray* dylibs = nil;

    //results from 'file' cmd
    NSString* results = nil;
    
    //path offset
    NSRange pathOffset = {0};
    
    //dylib
    NSString* dylib = nil;
    
    //alloc array for dylibs
    dylibs = [NSMutableArray array];
    
    //vmmap can't directly handle 32bit procs
    // ->so either exec 'vmmap32' or on older OSs, exec via 'arch -i386 vmmap <32bit pid>'
    if(YES == Is32Bit(pid.unsignedIntValue))
    {
        //when system has 32bit version of vmmap ('vmmap32')
        // ->use that
        if(YES == [[NSFileManager defaultManager] fileExistsAtPath:VMMAP_32])
        {
            //exec vmmap32
            results = [[NSString alloc] initWithData:execTask(VMMAP_32, @[@"-w", [pid stringValue]]) encoding:NSUTF8StringEncoding];
        }
        //otherwise
        // ->assume vmmap is 'fat', and exec 32bit version (pre El Capitan)
        else
        {
            //exec 'file' to get file type
            results = [[NSString alloc] initWithData:execTask(ARCH, @[@"-i386", VMMAP, [pid stringValue]]) encoding:NSUTF8StringEncoding];
        }
    }
    //for 64bit procs
    // ->just exec vmmap directly
    else
    {
        //exec vmmap
        results = [[NSString alloc] initWithData:execTask(VMMAP, @[@"-w", [pid stringValue]]) encoding:NSUTF8StringEncoding];
    }
    
    //sanity check
    if( (nil == results) ||
        (0 == results.length))
    {
        //bail
        goto bail;
    }
    
    //iterate over all results
    // ->line by line, looking for '__TEXT'
    for(NSString* line in [results componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\n"]])
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

//bail
bail:
    
    return dylibs;
    
}

//enumerate open files
// ->accomplish this via lsof, since proc_pidinfo() misses some files...
-(void)enumerateFiles:(NSNumber*)taskPID withReply:(void (^)(NSMutableArray *))reply;
{
    //results
    NSData* results = nil;
    
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
    results = execTask(LSOF, @[@"-Fn", @"-p", taskPID.stringValue]);
    
    //sanity check(s)
    if( (nil == results) ||
        (0 == results.length) )
    {
        //bail
        goto bail;
    }
    
    //split results into array
    splitResults = [[[NSString alloc] initWithData:results encoding:NSUTF8StringEncoding] componentsSeparatedByString:@"\n"];
    
    //sanity check(s)
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
-(void)enumerateNetwork:(NSNumber*)taskPID withReply:(void (^)(NSMutableArray *))reply;
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
    
    //socket handle struct
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
        socket[KEY_SOCKET_TYPE] = socketType2String(socketInfo.psi.soi_type);
        
        //set family
        // ->for now this will only be 'AF_INET' or 'AF_INET6'
        socket[KEY_SOCKET_FAMILY] = socketFamily2String(socketInfo.psi.soi_family);
        
        //set protocol
        socket[KEY_SOCKET_PROTO] = socketProto2String(socketInfo.psi.soi_protocol);
        
        //get state
        // ->only for stream stockets though
        if(SOCK_STREAM == socketInfo.psi.soi_type)
        {
            //set state
            socket[KEY_SOCKET_STATE] = socketState2String(socketInfo.psi.soi_proto.pri_tcp.tcpsi_state);
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


//convert a socket type into string
NSString* socketType2String(int type)
{
    //socket type
    NSString* socketType = nil;
    
    //convert
    switch(type)
    {
        //stream
        case SOCK_STREAM:
            socketType = @"SOCK_STREAM";
            break;
            
        //dgram
        case SOCK_DGRAM:
            socketType = @"SOCK_DGRAM";
            break;
          
        //raw
        case SOCK_RAW:
            socketType = @"SOCK_RAW";
            break;
            
        //rdm
        case SOCK_RDM:
            socketType = @"SOCK_RDM";
            break;
            
        //seq packet
        case SOCK_SEQPACKET:
            socketType = @"SOCK_SEQPACKET";
            break;
            
        default:
            break;
    }
    
    return socketType;
}


//convert a socket family into string
NSString* socketFamily2String(int family)
{
    //socket family
    NSString* socketFamily = nil;
    
    //sanity check
    if( (family < 0) ||
        (family >= SOCKET_FAMILY_MAX) )
    {
        //bail
        goto bail;
    }
    
    //init socket family string
    socketFamily = [NSString stringWithUTF8String:socketFamilies[family]];
    
//bail
bail:
    
    return socketFamily;
}

//convert a socket protocol into string
NSString* socketProto2String(int proto)
{
    //socket proto
    NSString* socketProto = nil;
    
    //proto struct
    struct protoent *protoInfo = NULL;
    
    //get proto info
    protoInfo = getprotobynumber(proto);
    
    //sanity check
    if(NULL == protoInfo)
    {
        //bail
        goto bail;
    }
    
    //init proto string
    // ->name comes from struct
    socketProto = [NSString stringWithUTF8String:protoInfo->p_name];
    
//bail
bail:
    
    return socketProto;
}


//convert a socket state into string
NSString* socketState2String(int state)
{
    //socket proto
    NSString* socketState = nil;
    
    //set state
    if(state < TCP_NSTATES)
    {
        //set state
        socketState = [NSString stringWithUTF8String:socketStates[state]];
    }
    //invalid/unknown socket state
    else
    {
        socketState = [NSString stringWithFormat:@"unknown state (%d)", state];
    }
    
    return socketState;
}




