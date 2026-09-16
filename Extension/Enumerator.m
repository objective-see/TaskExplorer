//
//  file: Enumerator.m
//  project: TaskExplorer (extension)
//  description: enumerate processes, dylibs, files
//
//  created by Patrick Wardle
//  copyright (c) 2026 Objective-See. All rights reserved.
//
//  note: dylibs via 'PROC_PIDREGIONPATHINFO' (executable regions), files via 'PROC_PIDLISTFDS' (vnodes)

#import "Consts.h"
#import "Utilities.h"
#import "Enumerator.h"

#import <os/log.h>
#import <dlfcn.h>
#import <libproc.h>
#import <sys/sysctl.h>
#import <mach/mach.h>
#import <sys/proc_info.h>
#import <sys/un.h>

//code signing ops (private)
#define CS_OPS_STATUS 0
#define CS_OPS_ENTITLEMENTS_BLOB 7
extern int csops(pid_t pid, unsigned int ops, void* useraddr, size_t usersize);

//is process an endpoint security client? (has the ES entitlement)
// ->via csops, as the ES message flag ('is_es_client') is only available for processes seen via ES events
//   note: an ES client that is suspended (e.g. by vmmap) can miss its auth deadlines, and the kernel then kills it
BOOL isESClient(pid_t pid)
{
    //flag
    BOOL esClient = NO;

    //blob (8-byte header: magic, length; then a plist)
    NSMutableData* blob = nil;

    //entitlements
    NSDictionary* entitlements = nil;

    //kernel, launchd: never
    if(pid <= 1)
    {
        goto bail;
    }

    //fetch blob (grow on ERANGE)
    for(size_t size = 32 * 1024; size <= 1024 * 1024; size *= 2)
    {
        blob = [NSMutableData dataWithLength:size];
        if(0 == csops(pid, CS_OPS_ENTITLEMENTS_BLOB, blob.mutableBytes, size))
        {
            break;
        }
        blob = nil;
        if(ERANGE != errno)
        {
            break;
        }
    }
    if( (nil == blob) ||
        (blob.length < 8) )
    {
        goto bail;
    }

    //length (big endian) from header
    uint32_t length = ntohl(*(uint32_t*)((uint8_t*)blob.bytes + 4));
    if( (length <= 8) ||
        (length > blob.length) )
    {
        goto bail;
    }

    //parse plist
    entitlements = [NSPropertyListSerialization propertyListWithData:[blob subdataWithRange:NSMakeRange(8, length - 8)] options:NSPropertyListImmutable format:NULL error:NULL];
    if(YES != [entitlements isKindOfClass:[NSDictionary class]])
    {
        goto bail;
    }

    //3rd-party ES clients
    if(YES == [entitlements[@"com.apple.developer.endpoint-security.client"] boolValue])
    {
        esClient = YES;
        goto bail;
    }

    //apple's own ES clients
    for(NSString* key in entitlements)
    {
        if( (YES == [key isKindOfClass:[NSString class]]) &&
            (YES == [key hasPrefix:@"com.apple.private.endpoint-security"]) )
        {
            esClient = YES;
            goto bail;
        }
    }

bail:

    return esClient;
}

/* GLOBALS */

//log handle
extern os_log_t logHandle;

//pointer to function
// responsibility_get_pid_responsible_for_pid()
static pid_t (*getRPID)(pid_t pid) = NULL;

@implementation Enumerator

//init
-(id)init
{
    //super
    self = [super init];
    if(nil != self)
    {
        //get function pointer
        getRPID = dlsym(RTLD_NEXT, "responsibility_get_pid_responsible_for_pid");
    }

    return self;
}

//enumerate all (running) processes
// returns array of process dictionaries (see KEY_PROCESS_* in Consts.h)
-(NSArray*)enumerateProcesses
{
    //processes
    NSMutableArray* processes = nil;

    //process (info)
    NSDictionary* process = nil;

    //status
    int status = -1;

    //# of procs
    int numberOfProcesses = 0;

    //array of pids
    pid_t* pids = NULL;

    //init
    processes = [NSMutableArray array];

    //get # of procs
    numberOfProcesses = proc_listpids(PROC_ALL_PIDS, 0, NULL, 0);
    if(numberOfProcesses <= 0)
    {
        //bail
        goto bail;
    }

    //alloc buffer for pids
    pids = calloc((unsigned long)numberOfProcesses, sizeof(pid_t));
    if(NULL == pids)
    {
        //bail
        goto bail;
    }

    //get list of pids
    status = proc_listpids(PROC_ALL_PIDS, 0, pids, numberOfProcesses * (int)sizeof(pid_t));
    if(status < 0)
    {
        //err msg
        os_log_error(logHandle, "ERROR: proc_listpids() failed with %d", status);

        //bail
        goto bail;
    }

    //iterate over all pids
    // build (basic) info for each
    //note: proc_listpids() returns bytes, not a count
    for(int i = 0; i < (status / (int)sizeof(pid_t)); ++i)
    {
        //pool
        @autoreleasepool
        {
            //skip blank pids
            if(0 == pids[i])
            {
                //skip
                continue;
            }

            //skip dead procs
            if(YES != isAlive(pids[i]))
            {
                //skip
                continue;
            }

            //build info
            process = [self processInfo:pids[i]];
            if(nil == process)
            {
                //skip
                continue;
            }

            //add
            [processes addObject:process];

        }//pool
    }

bail:

    //free buffer
    if(NULL != pids)
    {
        //free
        free(pids);
        pids = NULL;
    }

    return processes;
}

//build a process dictionary for a pid
-(NSDictionary*)processInfo:(pid_t)pid
{
    //info
    NSMutableDictionary* info = nil;

    //path
    NSString* path = nil;

    //arguments
    NSArray* arguments = nil;

    //audit token
    NSData* auditToken = nil;

    //bsd info
    struct proc_bsdinfo bsdInfo = {0};

    //get path
    path = getProcessPath(pid);
    if(0 == path.length)
    {
        //dbg msg
        os_log_debug(logHandle, "failed to get path for pid %d", pid);

        //set to unknown
        path = TASK_PATH_UNKNOWN;
    }

    //init
    info = [NSMutableDictionary dictionary];

    //add pid
    info[KEY_PROCESS_ID] = [NSNumber numberWithInt:pid];

    //add path
    info[KEY_PROCESS_PATH] = path;

    //get bsd info
    // gives ppid, uid, start time, etc
    if(PROC_PIDTBSDINFO_SIZE == proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsdInfo, PROC_PIDTBSDINFO_SIZE))
    {
        //add ppid
        info[KEY_PROCESS_PPID] = [NSNumber numberWithInt:bsdInfo.pbi_ppid];

        //add uid
        info[KEY_PROCESS_UID] = [NSNumber numberWithUnsignedInt:bsdInfo.pbi_uid];

        //add start time
        info[KEY_PROCESS_START] = [NSDate dateWithTimeIntervalSince1970:bsdInfo.pbi_start_tvsec];
    }
    //fallback
    // get ppid via sysctl
    else
    {
        //add ppid
        info[KEY_PROCESS_PPID] = [NSNumber numberWithInt:getParentID(pid)];
    }

    //code signing flags
    // ->also gives 'platform binary', matching what ES provides for live processes
    uint32_t csFlags = 0;
    if(0 == csops(pid, CS_OPS_STATUS, &csFlags, sizeof(csFlags)))
    {
        //add flags
        info[KEY_PROCESS_CS_FLAGS] = [NSNumber numberWithUnsignedInt:csFlags];

        //add platform binary
        info[KEY_PROCESS_PLATFORM_BINARY] = [NSNumber numberWithBool:(0 != (csFlags & CS_PLATFORM_BINARY))];
    }

    //add es client
    info[KEY_PROCESS_ES_CLIENT] = [NSNumber numberWithBool:isESClient(pid)];

    //add rpid
    if(NULL != getRPID)
    {
        //add
        info[KEY_PROCESS_RPID] = [NSNumber numberWithInt:getRPID(pid)];
    }

    //add arguments
    arguments = getProcessArguments(pid);
    if(0 != arguments.count)
    {
        //add
        info[KEY_PROCESS_ARGS] = arguments;
    }

    //add audit token
    auditToken = [self auditToken:pid];
    if(nil != auditToken)
    {
        //add
        info[KEY_PROCESS_AUDIT_TOKEN] = auditToken;
    }

    return info;
}

//get audit token for a process
// via 'task_name_for_pid' & 'task_info'
-(NSData*)auditToken:(pid_t)pid
{
    //audit token
    NSData* auditToken = nil;

    //task
    task_name_t task = MACH_PORT_NULL;

    //token
    audit_token_t token = {0};

    //status
    kern_return_t status = KERN_FAILURE;

    //size
    mach_msg_type_number_t size = TASK_AUDIT_TOKEN_COUNT;

    //get task (name port) for process
    status = task_name_for_pid(mach_task_self(), pid, &task);
    if(KERN_SUCCESS != status)
    {
        //bail
        goto bail;
    }

    //get audit token
    status = task_info(task, TASK_AUDIT_TOKEN, (task_info_t)&token, &size);
    if(KERN_SUCCESS != status)
    {
        //bail
        goto bail;
    }

    //convert
    auditToken = [NSData dataWithBytes:&token length:sizeof(audit_token_t)];

bail:

    //deallocate task port
    if(MACH_PORT_NULL != task)
    {
        //deallocate
        mach_port_deallocate(mach_task_self(), task);

        //unset
        task = MACH_PORT_NULL;
    }

    return auditToken;
}

//enumerate (loaded) dylibs for a process
// walks all (memory) regions, saving paths of executable ones
-(NSArray*)enumerateDylibs:(pid_t)pid
{
    //dylibs
    NSMutableOrderedSet* dylibs = nil;

    //region info
    struct proc_regionwithpathinfo region = {0};

    //address
    uint64_t address = 0;

    //path
    NSString* path = nil;

    //init
    dylibs = [NSMutableOrderedSet orderedSet];

    //walk regions
    // each call returns the (next) region at/after address
    while(PROC_PIDREGIONPATHINFO_SIZE == proc_pidinfo(pid, PROC_PIDREGIONPATHINFO, address, &region, PROC_PIDREGIONPATHINFO_SIZE))
    {
        //executable region?
        // and has path? ...then it's a dylib (or main executable)
        if( (0 != (region.prp_prinfo.pri_protection & VM_PROT_EXECUTE)) &&
            (0 != region.prp_vip.vip_path[0]) )
        {
            //convert
            path = [NSString stringWithUTF8String:region.prp_vip.vip_path];
            if(0 != path.length)
            {
                //add
                [dylibs addObject:path];
            }
        }

        //sanity check
        // avoid infinite loop on bogus region
        if(0 == region.prp_prinfo.pri_size)
        {
            //bail
            break;
        }

        //next region
        address = region.prp_prinfo.pri_address + region.prp_prinfo.pri_size;
    }

    return dylibs.array;
}

//enumerate (open) files for a process
// via 'PROC_PIDLISTFDS', then 'PROC_PIDFDVNODEPATHINFO' for each (vnode) fd
-(NSArray*)enumerateFiles:(pid_t)pid
{
    //files
    NSMutableOrderedSet* files = nil;

    //size
    int size = 0;

    //file
    NSString* file = nil;

    //file descriptor info
    struct proc_fdinfo *fdInfo = NULL;

    //vnode info
    struct vnode_fdinfowithpath vnodeInfo = {0};

    //file types (path -> type)
    NSMutableDictionary* types = [NSMutableDictionary dictionary];

    //init
    files = [NSMutableOrderedSet orderedSet];

    //get size needed to hold list of file descriptors
    size = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, NULL, 0);
    if(size <= 0)
    {
        //bail
        goto bail;
    }

    //alloc list for open file descriptors
    fdInfo = (struct proc_fdinfo *)malloc(size);
    if(NULL == fdInfo)
    {
        //bail
        goto bail;
    }

    //get list of open file descriptors
    size = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, fdInfo, size);
    if(size <= 0)
    {
        //bail
        goto bail;
    }

    //iterate over file descriptors
    // extract / parse files (vnodes), and unix domain sockets (which have paths too)
    for(int i = 0; i < (size/PROC_PIDLISTFD_SIZE); i++)
    {
        //unix domain socket?
        // ->add its path (or its peer's path, for clients), just like lsof
        if(PROX_FDTYPE_SOCKET == fdInfo[i].proc_fdtype)
        {
            //socket info
            struct socket_fdinfo socketInfo = {0};

            //path
            NSString* socketPath = nil;

            //get socket info
            if(PROC_PIDFDSOCKETINFO_SIZE != proc_pidfdinfo(pid, fdInfo[i].proc_fd, PROC_PIDFDSOCKETINFO, &socketInfo, PROC_PIDFDSOCKETINFO_SIZE))
            {
                //skip
                continue;
            }

            //only unix domain sockets
            if(SOCKINFO_UN != socketInfo.psi.soi_kind)
            {
                //skip
                continue;
            }

            //own (bound) path, else peer's path
            if(0 != socketInfo.psi.soi_proto.pri_un.unsi_addr.ua_sun.sun_path[0])
            {
                //own
                socketPath = [[NSString alloc] initWithBytes:socketInfo.psi.soi_proto.pri_un.unsi_addr.ua_sun.sun_path length:strnlen(socketInfo.psi.soi_proto.pri_un.unsi_addr.ua_sun.sun_path, sizeof(socketInfo.psi.soi_proto.pri_un.unsi_addr.ua_sun.sun_path)) encoding:NSUTF8StringEncoding];
            }
            else if(0 != socketInfo.psi.soi_proto.pri_un.unsi_caddr.ua_sun.sun_path[0])
            {
                //peer
                socketPath = [[NSString alloc] initWithBytes:socketInfo.psi.soi_proto.pri_un.unsi_caddr.ua_sun.sun_path length:strnlen(socketInfo.psi.soi_proto.pri_un.unsi_caddr.ua_sun.sun_path, sizeof(socketInfo.psi.soi_proto.pri_un.unsi_caddr.ua_sun.sun_path)) encoding:NSUTF8StringEncoding];
            }

            //add (if it has a path)
            if(0 != socketPath.length)
            {
                //add
                [files addObject:socketPath];
                types[socketPath] = FILE_TYPE_SOCKET;
            }

            //next
            continue;
        }

        //only care about files (vnodes)
        if(PROX_FDTYPE_VNODE != fdInfo[i].proc_fdtype)
        {
            //skip
            continue;
        }

        //reset
        memset(&vnodeInfo, 0, sizeof(vnodeInfo));

        //get (more) info about file
        if(PROC_PIDFDVNODEPATHINFO_SIZE != proc_pidfdinfo(pid, fdInfo[i].proc_fd, PROC_PIDFDVNODEPATHINFO, &vnodeInfo, PROC_PIDFDVNODEPATHINFO_SIZE))
        {
            //skip
            continue;
        }

        //extract path
        file = [NSString stringWithUTF8String:vnodeInfo.pvip.vip_path];
        if(0 == file.length)
        {
            //skip
            continue;
        }

        //skip files such as '/', /dev/null, etc
        if( (YES == [file isEqualToString:@"/"]) ||
            (YES == [file isEqualToString:@"/dev/null"]) )
        {
            //skip
            continue;
        }

        //add
        [files addObject:file];

        //type (from the vnode's mode)
        switch(vnodeInfo.pvip.vip_vi.vi_stat.vst_mode & S_IFMT)
        {
            case S_IFREG: types[file] = FILE_TYPE_FILE; break;
            case S_IFDIR: types[file] = FILE_TYPE_DIRECTORY; break;
            case S_IFCHR:
            case S_IFBLK: types[file] = FILE_TYPE_DEVICE; break;
            case S_IFIFO: types[file] = FILE_TYPE_FIFO; break;
            case S_IFLNK: types[file] = FILE_TYPE_LINK; break;
            case S_IFSOCK: types[file] = FILE_TYPE_SOCKET; break;
            default: types[file] = FILE_TYPE_UNKNOWN; break;
        }
    }

bail:

    //cleanup
    if(NULL != fdInfo)
    {
        //free
        free(fdInfo);
        fdInfo = NULL;
    }

    //build result
    // ->{path, type} per file
    NSMutableArray* results = [NSMutableArray arrayWithCapacity:files.count];
    for(NSString* path in files)
    {
        //add
        [results addObject:@{KEY_RESULT_PATH:path, KEY_FILE_TYPE:(types[path] ?: FILE_TYPE_UNKNOWN)}];
    }

    return results;
}

//enumerate all dylibs (incl. dyld shared cache) via vmmap
// ->vmmap (Apple-entitled) reads dyld's image list, which is the only way to attribute shared cache dylibs to a process
//   parses '__TEXT' region lines, whose path (last column) is the image
-(NSArray*)enumerateAllDylibs:(pid_t)pid
{
    //dylibs
    NSMutableOrderedSet* dylibs = nil;

    //results
    NSMutableDictionary* results = nil;

    //output
    NSString* output = nil;

    //init
    //sanity check
    if(pid <= 0)
    {
        //bail
        goto bail;
    }

    //never suspend launchd, core system daemons, or an endpoint security client (vmmap suspends its target; an ES
    //client that misses its auth deadlines while suspended is killed by the kernel) ...the app skips these too; this
    //is the backstop
    if( (1 == pid) ||
        (YES == isProtectedSystemProcess(getProcessPath(pid))) ||
        (YES == isESClient(pid)) )
    {
        //dbg msg
        os_log_debug(logHandle, "not running vmmap on pid %d (launchd, a core system daemon, or an endpoint security client)", pid);

        //empty (not nil: 'none', not 'failed')
        results = nil;
        dylibs = [NSMutableOrderedSet orderedSet];
        goto bail;
    }

    //exec vmmap (wide, so paths aren't truncated)
    results = execTask(VMMAP_PATH, @[@"-w", [NSString stringWithFormat:@"%d", pid]], YES);
    if( (nil == results[EXIT_CODE]) ||
        (0 != [results[EXIT_CODE] integerValue]) )
    {
        //err msg
        //dbg msg (process likely exited)
        os_log_debug(logHandle, "vmmap failed for pid %d (exit code: %{public}@)", pid, results[EXIT_CODE]);

        //bail
        goto bail;
    }

    //convert output
    output = [[NSString alloc] initWithData:results[STDOUT] encoding:NSUTF8StringEncoding];
    if(nil == output)
    {
        //dbg msg
        os_log_debug(logHandle, "vmmap output for pid %d isn't utf-8", pid);

        //bail
        goto bail;
    }

    //init
    // ->note: nil (not empty) is returned on failure, so callers can tell
    dylibs = [NSMutableOrderedSet orderedSet];

    //parse
    for(NSString* line in [output componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]])
    {
        //range of 'SM='
        NSRange range = {0};

        //path
        NSString* path = nil;

        //only text segments
        if(YES != [line hasPrefix:@"__TEXT"])
        {
            //skip
            continue;
        }

        //path follows the share mode column ('SM=COW', etc)
        //path is the last column: the first absolute path after the share mode column ('SM=xxx')
        // ->so extra columns (if any) never break parsing
        range = [line rangeOfString:@" SM="];
        if(NSNotFound == range.location)
        {
            //skip
            continue;
        }
        range = [line rangeOfString:@" /" options:0 range:NSMakeRange(range.location, line.length - range.location)];
        if(NSNotFound == range.location)
        {
            //skip (no path)
            continue;
        }
        path = [[line substringFromIndex:range.location] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

        //only absolute paths
        if(YES != [path hasPrefix:@"/"])
        {
            //skip
            continue;
        }

        //add
        [dylibs addObject:path];
    }

bail:

    return dylibs.array;
}

@end
