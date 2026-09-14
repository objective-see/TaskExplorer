//
//  file: XPCExtension.m
//  project: TaskExplorer (extension)
//  description: interface for XPC methods, invoked by app
//
//  created by Patrick Wardle
//  copyright (c) 2026 Objective-See. All rights reserved.
//

#import "Consts.h"
#import "MachO.h"
#import "Signing.h"
#import <bsm/libbsm.h>
#import "Utilities.h"
#import "Enumerator.h"
#import "XPCListener.h"
#import "XPCExtension.h"
#import "XPCAppClient.h"
#import "ProcessMonitor.h"
#import "NetworkMonitor.h"

#import <os/log.h>
#import <mach-o/fat.h>
#import <mach-o/loader.h>
#import <sys/stat.h>
#import <fcntl.h>

/* GLOBALS */

//log handle
extern os_log_t logHandle;

//enumerator
extern Enumerator* enumerator;

//(ES) process monitor
extern ProcessMonitor* processMonitor;

//network monitor
extern NetworkMonitor* networkMonitor;

/* HEAVY REQUESTS */

//queue for 'heavy' requests (whole-binary reads, hashing)
// ->bounded concurrency: NSXPC runs requests concurrently; w/o a bound, peak memory is (concurrent callers) x (largest buffer)
//   note: an operation queue (not a semaphore) so excess requests wait as operations, not as blocked GCD worker threads
static NSOperationQueue* heavyQueue(void)
{
    //queue
    static NSOperationQueue* queue = nil;

    //once
    static dispatch_once_t onceToken = 0;
    dispatch_once(&onceToken, ^{
        queue = [[NSOperationQueue alloc] init];
        queue.name = @"com.objective-see.taskexplorer.heavy";
        queue.maxConcurrentOperationCount = 2;
        queue.qualityOfService = NSQualityOfServiceUtility;
    });

    return queue;
}

//queue for vmmap children (each ~1-2s and a few MB of output for big processes)
static NSOperationQueue* vmmapQueue(void)
{
    //queue
    static NSOperationQueue* queue = nil;

    //once
    static dispatch_once_t onceToken = 0;
    dispatch_once(&onceToken, ^{
        queue = [[NSOperationQueue alloc] init];
        queue.name = @"com.objective-see.taskexplorer.vmmap";
        queue.maxConcurrentOperationCount = 4;
        queue.qualityOfService = NSQualityOfServiceUtility;
    });

    return queue;
}

//is path a (regular) mach-o file?
// ->the only thing this extension (running as root) will open on behalf of the app for hashing/signing checks
//   note: SecStaticCodeCreateWithPath() does a blocking open(), so a FIFO at the path would wedge the request forever
static BOOL isMachOFile(NSString* path)
{
    //flag
    BOOL isMachO = NO;

    //file descriptor
    int fd = -1;

    //file info
    struct stat fileInfo = {0};

    //magic
    uint32_t magic = 0;

    //sanity check
    if(0 == path.length)
    {
        //bail
        goto bail;
    }

    //open (non-blocking, so a FIFO/device can't hang us)
    fd = open(path.fileSystemRepresentation, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC);
    if(-1 == fd)
    {
        //maybe a symlink (dylib paths often are)? resolve, then retry
        NSString* resolved = [path stringByResolvingSymlinksInPath];
        if( (nil == resolved) ||
            (YES == [resolved isEqualToString:path]) ||
            (-1 == (fd = open(resolved.fileSystemRepresentation, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC))) )
        {
            //bail
            goto bail;
        }
    }

    //regular file?
    if( (0 != fstat(fd, &fileInfo)) ||
        (YES != S_ISREG(fileInfo.st_mode)) ||
        (fileInfo.st_size < (off_t)sizeof(magic)) )
    {
        //bail
        goto bail;
    }

    //read magic
    if(sizeof(magic) != read(fd, &magic, sizeof(magic)))
    {
        //bail
        goto bail;
    }

    //mach-o (thin, either endianness) or fat?
    switch(magic)
    {
        case MH_MAGIC:
        case MH_MAGIC_64:
        case MH_CIGAM:
        case MH_CIGAM_64:
        case FAT_MAGIC:
        case FAT_CIGAM:
        case FAT_MAGIC_64:
        case FAT_CIGAM_64:
            isMachO = YES;
            break;

        default:
            break;
    }

bail:

    //close
    if(-1 != fd)
    {
        //close
        close(fd);
    }

    return isMachO;
}

/* EVENT BATCHING */

//queue (serial) for batching dylib (mmap) events
static dispatch_queue_t batchQueue = nil;

//pending dylib events (deduped by pid|path)
static NSMutableArray* pendingDylibs = nil;
static NSMutableSet* pendingDylibKeys = nil;

//flush scheduled?
static BOOL flushScheduled = NO;

//last resync request
static NSTimeInterval lastResync = 0;

//queue a dylib (mmap) event
// ->flushed to the app (as one 'dylibsLoaded:' message) every 250ms
static void queueDylibEvent(NSDictionary* event)
{
    //once
    static dispatch_once_t onceToken = 0;
    dispatch_once(&onceToken, ^{
        batchQueue = dispatch_queue_create("com.objective-see.taskexplorer.batch", DISPATCH_QUEUE_SERIAL);
        pendingDylibs = [NSMutableArray array];
        pendingDylibKeys = [NSMutableSet set];
    });

    //add (async)
    dispatch_async(batchQueue, ^{

        //key
        NSString* key = [NSString stringWithFormat:@"%@|%@", event[KEY_PROCESS_ID], event[KEY_DYLIB_PATH]];

        //dupe (within batch)?
        if(YES == [pendingDylibKeys containsObject:key])
        {
            //skip
            return;
        }

        //add
        [pendingDylibKeys addObject:key];
        [pendingDylibs addObject:event];

        //schedule flush?
        if(YES != flushScheduled)
        {
            //set
            flushScheduled = YES;

            //flush (later)
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), batchQueue, ^{

                //batch
                NSArray* batch = [pendingDylibs copy];

                //reset
                [pendingDylibs removeAllObjects];
                [pendingDylibKeys removeAllObjects];
                flushScheduled = NO;

                //send
                if(0 != batch.count)
                {
                    //send
                    [[XPCAppClient sharedInstance] dylibsLoaded:batch];
                }
            });
        }
    });

    return;
}

//request (app) resync
// ->rate limited to once per 10s
static void requestResync(void)
{
    //now
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];

    //rate limit
    if(now - lastResync < 10.0)
    {
        //skip
        return;
    }

    //save
    lastResync = now;

    //request
    [[XPCAppClient sharedInstance] resyncRequired];

    return;
}

@implementation XPCExtension

//check in
// used by the client to confirm the extension is up & accepting XPC connections
-(void)checkIn:(void (^)(BOOL))reply
{
    //dbg msg
    os_log_debug(logHandle, "XPC request: check in");

    //reply
    reply(YES);

    return;
}

//check if extension has full disk access
// note: required for endpoint security (es_new_client fails w/ ERR_NOT_PERMITTED otherwise)
-(void)hasFullDiskAccess:(void (^)(BOOL))reply
{
    //permitted?
    BOOL permitted = NO;

    //check
    permitted = [processMonitor isPermitted];

    //dbg msg
    os_log_debug(logHandle, "XPC request: has full disk access? %d", permitted);

    //reply
    reply(permitted);

    return;
}

//enumerate all (running) processes
-(void)enumerateProcesses:(void (^)(NSArray*))reply
{
    //off the connection's (serial) queue
    // ->NSXPC runs a connection's handlers one at a time; a slow request (vmmap, hashing) must not stall the fast ones
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        //pool
        // ->these allocate a lot (whole binaries, vmmap output); drain per request, not per (concurrent) queue drain
        @autoreleasepool {
        //dbg msg
        os_log_debug(logHandle, "XPC request: enumerate processes");

        //enumerate & reply
        //enumerate & reply
        // ->wrapped, so one bad process (e.g. invalid utf-8 in argv) can't take down the whole request
        @try
        {
            //reply
            reply([enumerator enumerateProcesses]);
        }
        @catch(NSException* exception)
        {
            //err msg
            os_log_error(logHandle, "ERROR: exception during '%s': %{public}@", __PRETTY_FUNCTION__, exception);

            //reply (nil: failed; an empty array would mean 'no processes' and wipe the app's model)
            reply(nil);
        }

        return;
        }

    });

}

//enumerate (loaded) dylibs for a process
-(void)enumerateDylibs:(pid_t)pid reply:(void (^)(NSArray*))reply
{
    //off the connection's (serial) queue
    // ->NSXPC runs a connection's handlers one at a time; a slow request (vmmap, hashing) must not stall the fast ones
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        //pool
        // ->these allocate a lot (whole binaries, vmmap output); drain per request, not per (concurrent) queue drain
        @autoreleasepool {
        //dbg msg
        os_log_debug(logHandle, "XPC request: enumerate dylibs for %d", pid);

        //enumerate & reply
        //enumerate & reply
        // ->wrapped, so one bad process (e.g. invalid utf-8 in argv) can't take down the whole request
        @try
        {
            //reply
            reply([enumerator enumerateDylibs:pid]);
        }
        @catch(NSException* exception)
        {
            //err msg
            os_log_error(logHandle, "ERROR: exception during '%s': %{public}@", __PRETTY_FUNCTION__, exception);

            //reply (nil: failed, not 'none')
            reply(nil);
        }

        return;
        }

    });

}

//enumerate (open) files for a process
-(void)enumerateFiles:(pid_t)pid reply:(void (^)(NSArray*))reply
{
    //off the connection's (serial) queue
    // ->NSXPC runs a connection's handlers one at a time; a slow request (vmmap, hashing) must not stall the fast ones
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        //pool
        // ->these allocate a lot (whole binaries, vmmap output); drain per request, not per (concurrent) queue drain
        @autoreleasepool {
        //dbg msg
        os_log_debug(logHandle, "XPC request: enumerate files for %d", pid);

        //enumerate & reply
        //enumerate & reply
        // ->wrapped, so one bad process (e.g. invalid utf-8 in argv) can't take down the whole request
        @try
        {
            //reply
            reply([enumerator enumerateFiles:pid]);
        }
        @catch(NSException* exception)
        {
            //err msg
            os_log_error(logHandle, "ERROR: exception during '%s': %{public}@", __PRETTY_FUNCTION__, exception);

            //reply (nil: failed, not 'none')
            reply(nil);
        }

        return;
        }

    });

}

//enumerate (all) network connections
//enumerate all dylibs (incl. dyld shared cache) via vmmap
-(void)enumerateAllDylibs:(pid_t)pid reply:(void (^)(NSArray*))reply
{
    //off the connection's (serial) queue
    // ->NSXPC runs a connection's handlers one at a time; a slow request (vmmap, hashing) must not stall the fast ones
    [vmmapQueue() addOperationWithBlock:^{
        //pool
        // ->these allocate a lot (vmmap output); drain per request
        @autoreleasepool {
        //dbg msg
        os_log_debug(logHandle, "XPC request: enumerate all dylibs (vmmap) for %d", pid);

        //enumerate & reply
        @try
        {
            //reply
            reply([enumerator enumerateAllDylibs:pid]);
        }
        @catch(NSException* exception)
        {
            //err msg
            os_log_error(logHandle, "ERROR: exception during '%s': %{public}@", __PRETTY_FUNCTION__, exception);

            //reply (nil: failed, not 'none')
            reply(nil);
        }

        return;
        }

    }];

}

-(void)enumerateConnections:(void (^)(NSArray*))reply
{
    //dbg msg
    os_log_debug(logHandle, "XPC request: enumerate connections");

    //no network monitor (failed to init)?
    // ->reply (empty) now; a message to nil would never invoke the reply, and the app would wait out its timeout
    if(nil == networkMonitor)
    {
        //err msg
        os_log_error(logHandle, "ERROR: no network monitor (failed to init), can't enumerate connections");

        //reply
        reply(@[]);

        return;
    }

    //enumerate
    // note: this is async (queries nstat), and will invoke reply when done
    [networkMonitor enumerate:^(NSArray* connections) {

        //reply
        reply(connections);
    }];

    return;
}

//start monitoring
// ES (exec/exit/mmap) + network (timer)
//extract binary info (as root)
// ->code signing info (dynamic via pid, then static via path), hashes, & mach-o flags
-(void)extractBinaryInfo:(pid_t)pid auditToken:(NSData*)auditToken path:(NSString*)path reply:(void (^)(NSDictionary*))reply
{
    //off the connection's (serial) queue
    // ->NSXPC runs a connection's handlers one at a time; a slow request (vmmap, hashing) must not stall the fast ones
    [heavyQueue() addOperationWithBlock:^{
        //pool
        // ->these allocate a lot (whole binaries); drain per request
        @try { @autoreleasepool {
        //info
        NSMutableDictionary* info = nil;

        //signing info
        NSDictionary* signingInfo = nil;

        //parser
        MachO* parser = nil;

        //dbg msg
        os_log_debug(logHandle, "XPC request: extract binary info for %d / %{public}@", pid, path);

        //init
        info = [NSMutableDictionary dictionary];

        //signing info (dynamic)
        //signing info (dynamic)
        // ->via audit token (exact, pid-reuse safe) if provided; else via pid, but only if the pid's (current) path still matches
        if(sizeof(audit_token_t) == auditToken.length)
        {
            //token
            audit_token_t token = {0};

            //extract
            [auditToken getBytes:&token length:sizeof(audit_token_t)];

            //extract (dynamic)
            signingInfo = extractSigningInfoForToken(&token, kSecCSDefaultFlags);
        }
        else if( (0 != pid) &&
                 (YES == [getProcessPath(pid) isEqualToString:path]) )
        {
            //extract (dynamic)
            signingInfo = extractSigningInfo(pid, nil, kSecCSDefaultFlags);
        }

        //signing info (static)
        // ->no pid, or dynamic check failed
        //   note: only for (regular) mach-o files: the Security framework's blocking open() on e.g. a FIFO planted at
        //   a dylib's path would otherwise wedge this request (and its slot) forever
        if( (0 != path.length) &&
            ( (nil == signingInfo) ||
              (errSecSuccess != [signingInfo[KEY_SIGNATURE_STATUS] intValue]) ) )
        {
            //mach-o?
            if(YES == isMachOFile(path))
            {
                //extract
                signingInfo = extractSigningInfo(0, path, kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSDoNotValidateResources);
            }
            //not a (regular) mach-o file
            // ->report as unsigned/not found (rather than checking nothing)
            else
            {
                //dbg msg (common: binaries deleted after exec, '<unknown>' paths)
                os_log_debug(logHandle, "%{public}@ is not a (regular) mach-o file; skipping static signing check", path);

                //unsigned
                signingInfo = @{KEY_SIGNATURE_STATUS:@(errSecCSStaticCodeNotFound)};
            }
        }

        //add
        if(nil != signingInfo)
        {
            //add
            info[KEY_BINARY_SIGNING_INFO] = signingInfo;
        }

        //parse (mach-o)
        // ->encrypted & packed flags
        parser = [[MachO alloc] init];
        if(YES == [parser parse:path classify:YES])
        {
            //add encrypted flag
            info[KEY_BINARY_ENCRYPTED] = [NSNumber numberWithBool:[parser.binaryInfo[KEY_IS_ENCRYPTED] boolValue]];

            //add packed flag
            // ->unset for apple signed binaries, as apple doesn't pack, but the packer heuristic has some false positives
            if( (errSecSuccess == [signingInfo[KEY_SIGNATURE_STATUS] intValue]) &&
                (Apple == [signingInfo[KEY_SIGNATURE_SIGNER] intValue]) )
            {
                //no
                info[KEY_BINARY_PACKED] = @NO;
            }
            else
            {
                //from parser
                info[KEY_BINARY_PACKED] = [NSNumber numberWithBool:[parser.binaryInfo[KEY_IS_PACKED] boolValue]];
            }
        }

        //dbg msg
        os_log_debug(logHandle, "extracted binary info for %d / %{public}@: signing status %d, signer %{public}@", pid, path, [signingInfo[KEY_SIGNATURE_STATUS] intValue], signingInfo[KEY_SIGNATURE_SIGNER]);

        //reply
        reply(info);

        return;
        } }
        @catch(NSException* exception)
        {
            //err msg
            os_log_error(logHandle, "ERROR: exception during '%s': %{public}@", __PRETTY_FUNCTION__, exception);

            //reply (failed)
            reply(nil);
        }

    }];

}

//hash a file (as root)
-(void)hashFile:(NSString*)path reply:(void (^)(NSDictionary*))reply
{
    //off the connection's (serial) queue
    // ->NSXPC runs a connection's handlers one at a time; a slow request (vmmap, hashing) must not stall the fast ones
    [heavyQueue() addOperationWithBlock:^{
        //pool
        // ->these allocate a lot (whole binaries); drain per request
        @autoreleasepool {
        //dbg msg
        os_log_debug(logHandle, "XPC request: hash %{public}@", path);

        //policy: only (regular) mach-o files are hashed for the app
        // ->this runs as root; hashing arbitrary files (and shipping the hashes to VirusTotal) is not what the app needs
        if(YES != isMachOFile(path))
        {
            //err msg
            os_log_error(logHandle, "ERROR: %{public}@ is not a (regular) mach-o file; refusing to hash", path);

            //reply (failed)
            reply(nil);

            return;
        }

        //hash & reply
        // ->wrapped, so an unexpected exception can't take down the extension
        @try
        {
            //reply
            reply(hashFile(path));
        }
        @catch(NSException* exception)
        {
            //err msg
            os_log_error(logHandle, "ERROR: exception during '%s': %{public}@", __PRETTY_FUNCTION__, exception);

            //reply (failed)
            reply(nil);
        }

        return;
        }

    }];

}

-(void)startMonitoring:(void (^)(BOOL))reply
{
    //flag
    BOOL started = NO;

    //dbg msg
    os_log_debug(logHandle, "XPC request: start monitoring");

    //start (ES) process monitor
    // events delivered to client via XPCAppClient
    started = [processMonitor start:^(NSUInteger type, NSDictionary* event) {

        //handle event
        switch(type)
        {
            //exec
            case ES_EVENT_TYPE_NOTIFY_EXEC:
                [[XPCAppClient sharedInstance] processStarted:event];
                break;

            //exit
            case ES_EVENT_TYPE_NOTIFY_EXIT:
                [[XPCAppClient sharedInstance] processExited:event];
                break;

            //mmap
            // ->batched (these can come in the thousands per second), deduped per (pid, path), flushed every 250ms
            case ES_EVENT_TYPE_NOTIFY_MMAP:
                queueDylibEvent(event);
                break;

            //dropped events (see ProcessMonitor)
            // ->ask app to resync (rate limited)
            case ES_EVENT_TYPE_LAST:
                requestResync();
                break;

            default:
                break;
        }
    }];

    //start network monitor
    // ->only if ES started (otherwise, app is told nothing is running)
    if(YES == started)
    {
        //start
        [networkMonitor start:NETWORK_REFRESH_INTERVAL callback:^(NSArray* connections) {

            //forward
            [[XPCAppClient sharedInstance] connectionsUpdated:connections];
        }];
    }

    reply(started);

    return;
}

//stop monitoring
-(void)stopMonitoring:(void (^)(BOOL))reply
{
    //dbg msg
    os_log_debug(logHandle, "XPC request: stop monitoring");

    //stop (ES) process monitor
    [processMonitor stop];

    //stop network monitor
    [networkMonitor stop];

    //reply
    reply(YES);

    return;
}

@end
