//
//  Utilities.m
//  TaskExplorer (shared)
//
//  Created by Patrick Wardle on 2/7/15.
//  Copyright (c) 2015 Objective-See. All rights reserved.
//
//  note: shared between app & extension
//        so, no AppKit! (see App/UIUtilities.m for UI helpers)

#import "Consts.h"
#import "Utilities.h"

#import <signal.h>
#import <unistd.h>
#import <libproc.h>
#import <sys/sysctl.h>
#import <sys/stat.h>
#import <fcntl.h>
#import <Security/Security.h>
#import <os/log.h>
#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonDigest.h>
#import <SystemConfiguration/SystemConfiguration.h>


//(safely) convert a C string to an NSString
// ->UTF-8, falling back to Latin-1 (so invalid UTF-8, e.g. in a process' argv, never yields nil)
static NSString* safeString(const char* string)
{
    //result
    NSString* result = nil;

    //sanity check
    if(NULL == string)
    {
        //bail
        return nil;
    }

    //utf-8
    result = [NSString stringWithUTF8String:string];
    if(nil == result)
    {
        //fallback
        result = [NSString stringWithCString:string encoding:NSISOLatin1StringEncoding];
    }

    return result;
}

//given a path to binary
// parse it back up to find app's bundle
NSBundle* findAppBundle(NSString* binaryPath)
{
    //app's bundle
    NSBundle* appBundle = nil;

    //app's path
    NSString* appPath = nil;

    //first just try full path
    appPath = binaryPath;

    //try to find the app's bundle/info dictionary
    do
    {
        //try to load app's bundle
        appBundle = [NSBundle bundleWithPath:appPath];

        //check for match
        // ->binary path's match
        if( (nil != appBundle) &&
            (YES == [appBundle.executablePath isEqualToString:binaryPath]))
        {
            //all done
            break;
        }

        //always unset bundle var since it's being returned
        // ->and at this point, its not a match
        appBundle = nil;

        //remove last part
        // ->will try this next
        appPath = [appPath stringByDeletingLastPathComponent];

        //scan until we get to root
        // ->of course, loop will be exited if app info dictionary is found/loaded
    } while( (nil != appPath) &&
             (YES != [appPath isEqualToString:@"/"]) &&
             (YES != [appPath isEqualToString:@""]) );

    return appBundle;
}


//escape a string for embedding in (hand-built) JSON
// ->via NSJSONSerialization, so quotes, backslashes, control chars, etc are handled
NSString* jsonEscape(NSString* string)
{
    //escaped
    NSString* escaped = @"";

    //data
    NSData* data = nil;

    //sanity check
    if(0 == string.length)
    {
        //bail
        return escaped;
    }

    //serialize (as single element array), then strip the brackets & quotes
    data = [NSJSONSerialization dataWithJSONObject:@[string] options:0 error:nil];
    if(nil != data)
    {
        //convert
        escaped = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];

        //strip: ["..."]
        if(escaped.length >= 4)
        {
            //strip
            escaped = [escaped substringWithRange:NSMakeRange(2, escaped.length - 4)];
        }
    }

    return escaped;
}

//hash a file (md5, sha1, sha256)
// ->only regular files, not too big (MAX_FILE_SIZE), read/hashed in chunks (from KnockKnock)
NSDictionary* hashFile(NSString* path)
{
    //file descriptor
    int fd = -1;

    //file size (at open)
    off_t size = 0;

    //bytes hashed
    off_t total = 0;

    //file hashes
    NSDictionary* hashes = nil;

    //handle
    NSFileHandle* handle = nil;

    //file's contents
    // ->per chunk (to handle big files)
    NSData* chunk = nil;

    //md5 context
    CC_MD5_CTX md5Context = {0};

    //hash digest (md5)
    uint8_t md5Digest[CC_MD5_DIGEST_LENGTH] = {0};

    //md5 hash as string
    NSMutableString* md5 = nil;

    //sha1 context
    CC_SHA1_CTX sha1Context = {0};

    //hash digest (sha1)
    uint8_t sha1Digest[CC_SHA1_DIGEST_LENGTH] = {0};

    //sha1 hash as string
    NSMutableString* sha1 = nil;

    //sha256 context
    CC_SHA256_CTX sha256Context = {0};

    //hash digest (sha256)
    uint8_t sha256Digest[CC_SHA256_DIGEST_LENGTH] = {0};

    //sha256 hash as string
    NSMutableString* sha256 = nil;

    //index var
    NSUInteger index = 0;

    //init hash strings
    md5 = [NSMutableString string];
    sha1 = [NSMutableString string];
    sha256 = [NSMutableString string];

    //open file
    // ->only regular files (no devices, fifos, etc), and not too big
    fd = openRegularFile(path, MAX_FILE_SIZE, &size);
    if(-1 == fd)
    {
        //bail
        goto bail;
    }

    //init handle
    // ->will close fd on dealloc/close
    handle = [[NSFileHandle alloc] initWithFileDescriptor:fd closeOnDealloc:YES];

    //init hash contexts
    CC_MD5_Init(&md5Context);
    CC_SHA1_Init(&sha1Context);
    CC_SHA256_Init(&sha256Context);

    //read/hash file
    // ->in chunks, to handle large files
    //   note: pool per chunk, else every (1MB) chunk is autoreleased until the caller's pool drains (1GB file -> 1GB)
    while(YES)
    {
        @autoreleasepool {

        //wrap
        // ->'readDataOfLength' can throw
        @try
        {
            //done?
            // ->never hash past the size seen at open (file could be growing)
            if(total >= size) break;

            //read in chunk
            chunk = [handle readDataOfLength:(NSUInteger)MIN((off_t)(1024*1024), size - total)];
            if(0 == chunk.length) break;

            //inc
            total += chunk.length;
        }
        @catch(NSException* exception)
        {
            //bail
            goto bail;
        }

        //hash updates
        CC_MD5_Update(&md5Context, (const void *)chunk.bytes, (CC_LONG)chunk.length);
        CC_SHA1_Update(&sha1Context, (const void *)chunk.bytes, (CC_LONG)chunk.length);
        CC_SHA256_Update(&sha256Context, (const void *)chunk.bytes, (CC_LONG)chunk.length);

        //unset (so 'break' above doesn't keep the last chunk alive past the pool)
        chunk = nil;

        }//pool
    }

    //finalize hashes
    CC_MD5_Final(md5Digest, &md5Context);
    CC_SHA1_Final(sha1Digest, &sha1Context);
    CC_SHA256_Final(sha256Digest, &sha256Context);

    //convert md5 to NSString
    for(index = 0; index < CC_MD5_DIGEST_LENGTH; index++)
    {
        //format/append
        [md5 appendFormat:@"%02lX", (unsigned long)md5Digest[index]];
    }

    //convert sha1 to NSString
    for(index = 0; index < CC_SHA1_DIGEST_LENGTH; index++)
    {
        //format/append
        [sha1 appendFormat:@"%02lX", (unsigned long)sha1Digest[index]];
    }

    //convert sha256 to NSString
    for(index = 0; index < CC_SHA256_DIGEST_LENGTH; index++)
    {
        //format/append
        [sha256 appendFormat:@"%02lX", (unsigned long)sha256Digest[index]];
    }

    //init hash dictionary
    hashes = @{KEY_HASH_MD5:md5, KEY_HASH_SHA1:sha1, KEY_HASH_SHA256:sha256};

bail:

    //close handle?
    if(nil != handle)
    {
        //close
        [handle closeFile];
        handle = nil;
    }

    return hashes;
}

//get app's version
// ->extracted from Info.plist
NSString* getAppVersion(void)
{
    //read and return 'CFBundleShortVersionString' (marketing version, e.g. 3.0.0) from bundle
    // ->not 'CFBundleVersion' (build, e.g. 3.0.38): that's bumped whenever the extension must be replaced, and the
    //   update check compares against the (marketing) version published in products.json
    return [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
}

//exec a process with args
// if 'shouldWait' is set, wait and return stdout/in and termination status
NSMutableDictionary* execTask(NSString* binaryPath, NSArray* arguments, BOOL shouldWait)
{
    //task
    NSTask* task = nil;

    //output pipe for stdout
    NSPipe* stdOutPipe = nil;

    //output pipe for stderr
    NSPipe* stdErrPipe = nil;

    //read handle for stdout
    NSFileHandle* stdOutReadHandle = nil;

    //read handle for stderr
    NSFileHandle* stdErrReadHandle = nil;

    //results dictionary
    NSMutableDictionary* results = nil;

    //output for stdout
    NSMutableData *stdOutData = nil;

    //output for stderr
    NSMutableData *stdErrData = nil;

    //init dictionary for results
    results = [NSMutableDictionary dictionary];

    //init task
    task = [NSTask new];

    //only setup pipes if wait flag is set
    if(YES == shouldWait)
    {
        //init stdout pipe
        stdOutPipe = [NSPipe pipe];

        //init stderr pipe
        stdErrPipe = [NSPipe pipe];

        //init stdout read handle
        stdOutReadHandle = [stdOutPipe fileHandleForReading];

        //init stderr read handle
        stdErrReadHandle = [stdErrPipe fileHandleForReading];

        //init stdout output buffer
        stdOutData = [NSMutableData data];

        //init stderr output buffer
        stdErrData = [NSMutableData data];

        //set task's stdout
        task.standardOutput = stdOutPipe;

        //set task's stderr
        task.standardError = stdErrPipe;
    }

    //set task's path
    task.launchPath = binaryPath;

    //set task's args
    if(nil != arguments)
    {
        //set
        task.arguments = arguments;
    }

    //wrap task launch
    @try
    {
        //launch
        [task launch];
    }
    @catch(NSException *exception)
    {
        //bail
        goto bail;
    }

    //no need to wait
    // can just bail w/ no output
    if(YES != shouldWait)
    {
        //bail
        goto bail;
    }

    //read stdout & stderr concurrently (a child that fills one pipe while we block on the other would deadlock)
    // ->and with a deadline: a hung child (vmmap on a wedged process) must not pin the caller forever
    {
        //group
        dispatch_group_t group = dispatch_group_create();

        //buffers (written on the reader queues, read after the group completes)
        __block NSData* stdOutOutput = nil;
        __block NSData* stdErrOutput = nil;

        //read stdout
        dispatch_group_async(group, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            stdOutOutput = [stdOutReadHandle readDataToEndOfFileAndReturnError:nil];
        });

        //read stderr
        dispatch_group_async(group, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            stdErrOutput = [stdErrReadHandle readDataToEndOfFileAndReturnError:nil];
        });

        //wait (w/ deadline)
        if(0 != dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(EXEC_TASK_TIMEOUT * NSEC_PER_SEC))))
        {
            //err msg
            os_log_error(OS_LOG_DEFAULT, "TaskExplorer: %{public}@ did not finish within %ds; killing it", binaryPath, EXEC_TASK_TIMEOUT);

            //kill
            kill(task.processIdentifier, SIGKILL);

            //wait for the readers (the pipes close once the child is dead)
            dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
        }

        //wait for exit
        [task waitUntilExit];

        //save
        if(nil != stdOutOutput) [stdOutData appendData:stdOutOutput];
        if(nil != stdErrOutput) [stdErrData appendData:stdErrOutput];
    }

    //add stdout
    if(0 != stdOutData.length)
    {
        //add
        results[STDOUT] = stdOutData;
    }

    //add stderr
    if(0 != stdErrData.length)
    {
        //add
        results[STDERR] = stdErrData;
    }

    //add exit code
    results[EXIT_CODE] = [NSNumber numberWithInteger:task.terminationStatus];

bail:

    return results;
}

//given a pid, get its parent (ppid)
pid_t getParentID(int pid)
{
    //parent id
    pid_t parentID = -1;

    //kinfo_proc struct
    struct kinfo_proc processStruct = {0};

    //size
    size_t procBufferSize = sizeof(processStruct);

    //syscall result
    int sysctlResult = -1;

    //init mib
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, pid};

    //make syscall
    sysctlResult = sysctl(mib, sizeof(mib)/sizeof(*mib), &processStruct, &procBufferSize, NULL, 0);

    //check if got ppid
    if( (STATUS_SUCCESS == sysctlResult) &&
        (0 != procBufferSize) )
    {
        //save ppid
        parentID = processStruct.kp_eproc.e_ppid;
    }

    return parentID;
}

//given a pid, get its path
// via 'proc_pidpath()', or if that fails, via task's args ('KERN_PROCARGS2')
NSString* getProcessPath(pid_t pid)
{
    //task path
    NSString* processPath = nil;

    //buffer for process path
    char pathBuffer[PROC_PIDPATHINFO_MAXSIZE] = {0};

    //status
    int status = -1;

    //(process) arguments
    NSMutableArray* arguments = nil;

    //get task's path via 'proc_pidpath()'
    status = proc_pidpath(pid, pathBuffer, sizeof(pathBuffer));
    if(0 != status)
    {
        //init task's name
        processPath = [NSString stringWithUTF8String:pathBuffer];
    }
    //try via the exec path the kernel recorded ('KERN_PROCARGS2')
    // ->not argv[0], which the process chooses freely (and could point at some other, clean, binary)
    else
    {
        //extract
        processPath = getProcessExecPath(pid);
    }

    return processPath;
}

//exec path of a process, from 'KERN_PROCARGS2'
// ->the (kernel recorded) path precedes argv; nil if unavailable
NSString* getProcessExecPath(pid_t pid)
{
    //path
    NSString* execPath = nil;

    //mib
    int mib[3] = {CTL_KERN, KERN_PROCARGS2, pid};

    //buffer
    char* buffer = NULL;

    //size
    size_t size = 0;

    //max args
    int maxArgs = 0;

    //size of max args
    size_t maxArgsSize = sizeof(maxArgs);

    //mib (max args)
    int maxArgsMIB[2] = {CTL_KERN, KERN_ARGMAX};

    //get max args
    if(-1 == sysctl(maxArgsMIB, 2, &maxArgs, &maxArgsSize, NULL, 0))
    {
        //bail
        goto bail;
    }

    //alloc
    buffer = malloc(maxArgs);
    if(NULL == buffer)
    {
        //bail
        goto bail;
    }

    //get args
    size = (size_t)maxArgs;
    if( (-1 == sysctl(mib, 3, buffer, &size, NULL, 0)) ||
        (size <= sizeof(int)) )
    {
        //bail
        goto bail;
    }

    //exec path: NULL-terminated string right after the (int) arg count
    // ->bounded by the buffer (strnlen), and must be non-empty
    {
        //length
        size_t length = strnlen(buffer + sizeof(int), size - sizeof(int));
        if( (0 != length) &&
            (length < size - sizeof(int)) )
        {
            //init
            execPath = [[NSString alloc] initWithBytes:buffer + sizeof(int) length:length encoding:NSUTF8StringEncoding];
        }
    }

bail:

    //free
    if(NULL != buffer)
    {
        //free
        free(buffer);
        buffer = NULL;
    }

    return execPath;
}

//get task's commandline args
// via 'KERN_PROCARGS2' sysctl
NSMutableArray* getProcessArguments(pid_t pid)
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
    mib[2] = pid;

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

    //note: the exec path follows the # of args (int), NULL-terminated; it's skipped, as argv[0] (normally the same)
    //      follows, and the args are meant to be argv (matching what Endpoint Security reports for new processes)

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
                //add (nil-safe; argv may contain invalid utf-8)
                if(nil != safeString(argStart))
                {
                    //add
                    [arguments addObject:safeString(argStart)];
                }
            }

            //init string pointer to (possibly) next arg
            //next arg starts after this NULL (note: loop's 'parser++' advances; consecutive NULLs are empty args)
            argStart = parser + 1;

            //bail if we've hit arg cnt
            if(arguments.count == numberOfArgs)
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

    return arguments;
}

//find (running) processes by name
// returns array of pids
NSMutableArray* findProcesses(NSString* processName)
{
    //status
    int status = -1;

    //pids
    NSMutableArray* processes = nil;

    //# of procs
    int numberOfProcesses = 0;

    //array of pids
    pid_t* pids = NULL;

    //process path
    NSString* processPath = nil;

    //init
    processes = [NSMutableArray array];

    //get size (bytes) needed for pids
    // ->note: 'proc_listpids' returns byte counts, not pid counts
    numberOfProcesses = proc_listpids(PROC_ALL_PIDS, 0, NULL, 0);
    if(numberOfProcesses <= 0)
    {
        //bail
        goto bail;
    }

    //to pids (plus some slack, for processes started meanwhile)
    numberOfProcesses = (numberOfProcesses / (int)sizeof(pid_t)) + 64;

    //alloc buffer for pids
    pids = calloc((unsigned long)numberOfProcesses, sizeof(pid_t));
    if(NULL == pids)
    {
        //bail
        goto bail;
    }

    //get list of pids
    status = proc_listpids(PROC_ALL_PIDS, 0, pids, numberOfProcesses * (int)sizeof(pid_t));
    if(status <= 0)
    {
        //bail
        goto bail;
    }

    //actual count (bytes returned / sizeof(pid))
    numberOfProcesses = MIN(numberOfProcesses, status / (int)sizeof(pid_t));

    //iterate over all pids
    // get name for each via helper function
    for(int i = 0; i < numberOfProcesses; ++i)
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

            //get path
            processPath = getProcessPath(pids[i]);
            if(0 == processPath.length)
            {
                //skip
                continue;
            }

            //no match?
            if(YES != [processPath.lastPathComponent isEqualToString:processName])
            {
                //skip
                continue;
            }

            //save
            [processes addObject:[NSNumber numberWithInt:pids[i]]];

        }//pool

    }//all procs

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

//get path to kernel
NSString* path2Kernel(void)
{
    return KERNEL_PATH;
}

//determine if process is (still) alive
BOOL isAlive(pid_t targetPID)
{
    //flag
    BOOL isAlive = YES;

    //'management info base' array
    int mib[4] = {0};

    //kinfo proc
    struct kinfo_proc procInfo = {0};

    //size
    size_t size = 0;

    //reset errno
    errno = 0;

    //try 'kill' with 0
    // ->no harm done, but will fail with 'ESRCH' if process is dead
    kill(targetPID, 0);

    //dead proc -> 'ESRCH'
    // ->'No such process'
    if(ESRCH == errno)
    {
        //dead
        isAlive = NO;

        //bail
        goto bail;
    }

    //init mib
    mib[0] = CTL_KERN;
    mib[1] = KERN_PROC;
    mib[2] = KERN_PROC_PID;
    mib[3] = targetPID;

    //init size
    size = sizeof(procInfo);

    //get task's flags
    // ->allows to check for zombies
    if(0 == sysctl(mib, sizeof(mib)/sizeof(*mib), &procInfo, &size, NULL, 0))
    {
        //check for zombies
        if(((procInfo.kp_proc.p_stat) & SZOMB) == SZOMB)
        {
            //dead
            isAlive = NO;

            //bail
            goto bail;
        }
    }

//bail
bail:

    return isAlive;
}

//check if computer has network connection
BOOL isNetworkConnected(void)
{
    //flag
    BOOL isConnected = NO;

    //sock addr stuct
    struct sockaddr zeroAddress = {0};

    //reachability ref
    SCNetworkReachabilityRef reachabilityRef = NULL;

    //reachability flags
    SCNetworkReachabilityFlags flags = 0;

    //reachable flag
    BOOL isReachable = NO;

    //connection required flag
    BOOL connectionRequired = NO;

    //ensure its cleared out
    bzero(&zeroAddress, sizeof(zeroAddress));

    //set size
    zeroAddress.sa_len = sizeof(zeroAddress);

    //set family
    zeroAddress.sa_family = AF_INET;

    //create reachability ref
    reachabilityRef = SCNetworkReachabilityCreateWithAddress(NULL, (const struct sockaddr*)&zeroAddress);

    //sanity check
    if(NULL == reachabilityRef)
    {
        //bail
        goto bail;
    }

    //get flags
    if(TRUE != SCNetworkReachabilityGetFlags(reachabilityRef, &flags))
    {
        //bail
        goto bail;
    }

    //set reachable flag
    isReachable = ((flags & kSCNetworkFlagsReachable) != 0);

    //set connection required flag
    connectionRequired = ((flags & kSCNetworkFlagsConnectionRequired) != 0);

    //finally
    // ->determine if network is available
    isConnected = (isReachable && !connectionRequired) ? YES : NO;

//bail
bail:

    //cleanup
    if(NULL != reachabilityRef)
    {
        //release
        CFRelease(reachabilityRef);
    }

    return isConnected;
}

//check if file is in shared cache
// uses private _dyld_shared_cache_contains_path API
BOOL isInSharedCache(NSString* path)
{
    //flag
    BOOL inCache = NO;

    //macOS 11+
    if (@available(macOS 11.0, *))
    {
        //check
        inCache = _dyld_shared_cache_contains_path(path.UTF8String);
    }

    return inCache;
}

//save (user's) VT API key to keychain
// note: empty key deletes existing
BOOL saveAPIKeyToKeychain(NSString* apiKey)
{
    return saveKeychainItem(VT_API_KEYCHAIN_ATTR, apiKey);
}

//(re)load VT API key from keychain
NSString* loadAPIKeyFromKeychain(void)
{
    return loadKeychainItem(VT_API_KEYCHAIN_ATTR);
}

//save a (generic password) keychain item
// note: empty value deletes existing
BOOL saveKeychainItem(NSString* service, NSString* apiKey)
{
    //status
    OSStatus status = errSecSuccess;

    //key (as data)
    NSData* apiKeyData = nil;

    //query
    NSMutableDictionary* query = nil;

    //convert
    apiKeyData = [apiKey dataUsingEncoding:NSUTF8StringEncoding];

    //init query
    query = [@{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
               (__bridge id)kSecAttrService: service,
               (__bridge id)kSecAttrAccount: VT_API_KEYCHAIN_ACCOUNT} mutableCopy];

    //delete old
    SecItemDelete((__bridge CFDictionaryRef)query);

    //no (new) key?
    // just the delete then, we're done
    if(0 == apiKeyData.length)
    {
        //bail
        goto bail;
    }

    //add new
    query[(__bridge id)kSecValueData] = apiKeyData;

    //save
    status = SecItemAdd((__bridge CFDictionaryRef)query, NULL);
    if(errSecSuccess != status)
    {
        //err msg
        os_log_error(OS_LOG_DEFAULT, "TaskExplorer: failed to save keychain item (%{public}@) (status: %d)", service, (int)status);
    }

bail:

    return (errSecSuccess == status);
}

//load a (generic password) keychain item
NSString* loadKeychainItem(NSString* service)
{
    //key
    NSString* key = nil;

    //result
    CFTypeRef result = NULL;

    //query
    NSDictionary* query = nil;

    //init query
    query = @{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
              (__bridge id)kSecAttrService: service,
              (__bridge id)kSecAttrAccount: VT_API_KEYCHAIN_ACCOUNT,
              (__bridge id)kSecReturnData: @YES,
              (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne};

    //lookup
    if(errSecSuccess == SecItemCopyMatching((__bridge CFDictionaryRef)query, &result))
    {
        //convert
        key = [[NSString alloc] initWithData:(__bridge_transfer NSData*)result encoding:NSUTF8StringEncoding];
    }

    return key;
}

//delete a (generic password) keychain item
void deleteKeychainItem(NSString* service)
{
    //delete
    SecItemDelete((__bridge CFDictionaryRef)@{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
                                              (__bridge id)kSecAttrService: service,
                                              (__bridge id)kSecAttrAccount: VT_API_KEYCHAIN_ACCOUNT});
    return;
}

//open a regular file (no devices, fifos, etc) of at most 'maxSize'
// returns fd (or -1), and optionally the file's size
int openRegularFile(NSString* path, off_t maxSize, off_t* size)
{
    //file descriptor
    int fd = -1;

    //file info
    struct stat fileInfo = {0};

    //open
    // non-blocking, so a fifo, etc. won't hang us
    fd = open(path.fileSystemRepresentation, O_RDONLY | O_NONBLOCK | O_CLOEXEC);
    if(-1 == fd)
    {
        //bail
        goto bail;
    }

    //stat (via fd, so no race)
    // then make sure it's a regular file, that isn't too big
    if( (0 != fstat(fd, &fileInfo)) ||
        (!S_ISREG(fileInfo.st_mode)) ||
        (fileInfo.st_size > maxSize) )
    {
        //close
        close(fd);

        //reset
        fd = -1;

        //bail
        goto bail;
    }

    //save size
    if(NULL != size)
    {
        //save
        *size = fileInfo.st_size;
    }

bail:

    return fd;
}

