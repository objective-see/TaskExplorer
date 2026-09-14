//
//  file: ProcessMonitor.m
//  project: TaskExplorer (extension)
//  description: (endpoint security) process/dylib monitor
//
//  created by Patrick Wardle
//  copyright (c) 2026 Objective-See. All rights reserved.
//
//  note: only 'notify' events, so no deadline/auth handling needed

#import "Consts.h"
#import "Utilities.h"
#import "ProcessMonitor.h"

#import <os/log.h>
#import <sys/mman.h>
#import <mach/mach.h>
#import <bsm/libbsm.h>
#import <EndpointSecurity/EndpointSecurity.h>

//cd hash length (kern/cs_blobs.h)
#ifndef CS_CDHASH_LEN
#define CS_CDHASH_LEN 20
#endif

/* GLOBALS */

//log handle
extern os_log_t logHandle;

//last sequence number, per event type
// ->reset whenever a (new) ES client is created, as sequence numbers restart at 0
static uint64_t lastSeq[ES_EVENT_TYPE_LAST] = {0};

//seen an event (of each type) yet?
static BOOL seenSeq[ES_EVENT_TYPE_LAST] = {0};

@implementation ProcessMonitor

@synthesize client;
@synthesize callback;

//start monitoring
// subscribes to ES exec, exit, and mmap (notify) events
-(BOOL)start:(ProcessCallbackBlock)callback
{
    //flag
    BOOL started = NO;

    //result
    es_new_client_result_t result = 0;

    //events
    es_event_type_t events[] = {ES_EVENT_TYPE_NOTIFY_EXEC, ES_EVENT_TYPE_NOTIFY_EXIT, ES_EVENT_TYPE_NOTIFY_MMAP};

    //sync
    @synchronized(self)
    {
        //already started?
        if(NULL != self.client)
        {
            //dbg msg
            os_log_debug(logHandle, "(ES) process monitor already started");

            //happy
            started = YES;

            //bail
            goto bail;
        }

        //save callback
        self.callback = callback;

        //create client
        // handler processes events & invokes (user) callback
        result = es_new_client(&client, ^(es_client_t *client, const es_message_t *message)
        {
            //pool
            @autoreleasepool
            {
                //process message
                [self processMessage:message];
            }
        });

        //error?
        if(ES_NEW_CLIENT_RESULT_SUCCESS != result)
        {
            //err msg
            os_log_error(logHandle, "ERROR: es_new_client() failed with %d", result);

            //provide more info
            switch(result)
            {
                //not entitled
                case ES_NEW_CLIENT_RESULT_ERR_NOT_ENTITLED:
                    os_log_error(logHandle, "ES_NEW_CLIENT_RESULT_ERR_NOT_ENTITLED: \"The caller is not properly entitled to connect\"");
                    break;

                //not permitted
                case ES_NEW_CLIENT_RESULT_ERR_NOT_PERMITTED:
                    os_log_error(logHandle, "ES_NEW_CLIENT_RESULT_ERR_NOT_PERMITTED: \"The caller is not permitted to connect. They lack Transparency, Consent, and Control (TCC) approval form the user.\"");
                    break;

                //not privileged
                case ES_NEW_CLIENT_RESULT_ERR_NOT_PRIVILEGED:
                    os_log_error(logHandle, "ES_NEW_CLIENT_RESULT_ERR_NOT_PRIVILEGED: \"The caller is not running as root\"");
                    break;

                //too many clients
                case ES_NEW_CLIENT_RESULT_ERR_TOO_MANY_CLIENTS:
                    os_log_error(logHandle, "ES_NEW_CLIENT_RESULT_ERR_TOO_MANY_CLIENTS: \"Too many ES clients\"");
                    break;

                default:
                    break;
            }

            //unset
            self.client = NULL;

            //bail
            goto bail;
        }

        //clear cache
        //reset sequence tracking
        // ->new client, sequence numbers restart at 0
        memset(lastSeq, 0, sizeof(lastSeq));
        memset(seenSeq, 0, sizeof(seenSeq));

        //clear cache
        // ->not required for a notify-only client; and ES throttles this call, so a failure (e.g. a quick stop/start)
        //   is logged, not fatal
        if(ES_CLEAR_CACHE_RESULT_SUCCESS != es_clear_cache(self.client))
        {
            //err msg
            os_log_error(logHandle, "ERROR: es_clear_cache() failed (continuing)");
        }

        //mute self
        // don't need events for our own process
        // ->via (own) audit token, which can't collide (unlike a path)
        {
            //own token
            audit_token_t ownToken = {0};

            //count
            mach_msg_type_number_t count = TASK_AUDIT_TOKEN_COUNT;

            //get token & mute
            if( (KERN_SUCCESS != task_info(mach_task_self(), TASK_AUDIT_TOKEN, (task_info_t)&ownToken, &count)) ||
                (ES_RETURN_SUCCESS != es_mute_process(self.client, &ownToken)) )
            {
                //err msg
                os_log_error(logHandle, "ERROR: failed to mute self (es_mute_process)");
            }

            //mute our vmmap children too
            // ->spawned (as root) for each shared cache dylib enumeration; their exec/exit/mmap events are just noise for the app
            //   note: both as the (executing) process (exit, mmap events) and as the exec target (the exec event's
            //   process is the pre-exec image, i.e. our own child)
            if( (ES_RETURN_SUCCESS != es_mute_path(self.client, VMMAP_PATH.UTF8String, ES_MUTE_PATH_TYPE_LITERAL)) ||
                (ES_RETURN_SUCCESS != es_mute_path(self.client, VMMAP_PATH.UTF8String, ES_MUTE_PATH_TYPE_TARGET_LITERAL)) )
            {
                //err msg
                os_log_error(logHandle, "ERROR: failed to mute vmmap (es_mute_path)");
            }
        }

        //subscribe
        if(ES_RETURN_SUCCESS != es_subscribe(self.client, events, sizeof(events)/sizeof(events[0])))
        {
            //err msg
            os_log_error(logHandle, "ERROR: es_subscribe() failed");

            //bail
            goto bail;
        }

        //dbg msg
        os_log_debug(logHandle, "(ES) process monitor started (exec, exit, mmap)");

        //happy
        started = YES;

    } //sync

bail:

    //error?
    // cleanup client (& callback)
    if(YES != started)
    {
        //client?
        if(NULL != self.client)
        {
            //delete
            es_delete_client(self.client);

            //unset
            self.client = NULL;
        }

        //unset callback
        self.callback = nil;
    }

    return started;
}

//stop monitoring
-(BOOL)stop
{
    //flag
    BOOL stopped = NO;

    //sync
    @synchronized(self)
    {
        //not started?
        if(NULL == self.client)
        {
            //bail
            goto bail;
        }

        //unsubscribe
        if(ES_RETURN_SUCCESS != es_unsubscribe_all(self.client))
        {
            //err msg
            os_log_error(logHandle, "ERROR: es_unsubscribe_all() failed");
        }

        //delete client
        if(ES_RETURN_SUCCESS != es_delete_client(self.client))
        {
            //err msg
            os_log_error(logHandle, "ERROR: es_delete_client() failed");

            //bail
            goto bail;
        }

        //unset
        self.client = NULL;

        //unset callback
        self.callback = nil;

        //dbg msg
        os_log_debug(logHandle, "(ES) process monitor stopped");

        //happy
        stopped = YES;

    } //sync

bail:

    return stopped;
}

//check if we're permitted to create an ES client
// ->just try to create one (then delete it), and check the result
//   ES_NEW_CLIENT_RESULT_ERR_NOT_PERMITTED means the extension lacks full disk access (TCC)
-(BOOL)isPermitted
{
    //client
    es_client_t* probe = NULL;

    //result
    es_new_client_result_t result = 0;

    //already have a (live) client?
    // ->then we're obviously permitted (and a probe would just hit the per-process client limit)
    if(NULL != self.client)
    {
        //permitted
        return YES;
    }

    //try create client
    result = es_new_client(&probe, ^(es_client_t *client, const es_message_t *message) { ; });

    //dbg msg
    os_log_debug(logHandle, "es_new_client() (probe) returned %d", result);

    //delete (probe) client
    if(NULL != probe)
    {
        //delete
        es_delete_client(probe);
    }

    //permitted, unless ES says otherwise
    // ->'not permitted' is the (only) full disk access failure; 'too many clients' (a client from a previous
    //   session still winding down) is not a permission problem, so don't make the app ask the user for access
    return (ES_NEW_CLIENT_RESULT_ERR_NOT_PERMITTED != result) && (ES_NEW_CLIENT_RESULT_ERR_NOT_ENTITLED != result);
}

//process an ES message
// builds event dictionary & invokes callback
-(void)processMessage:(const es_message_t*)message
{
    //sequence tracking (per event type)
    // ->a gap means the kernel dropped events (slow client); tell the app to resync
    if( (message->version >= 2) &&
        (message->event_type < ES_EVENT_TYPE_LAST) )
    {
        //gap?
        // ->note: 'seen' flag (not 'lastSeq != 0'), so a drop right after the first event (seq 0) is caught too
        if( (YES == seenSeq[message->event_type]) &&
            (message->seq_num != lastSeq[message->event_type] + 1) )
        {
            //err msg
            os_log_error(logHandle, "ERROR: dropped ES events detected (type: %d, expected seq %llu, got %llu)", message->event_type, lastSeq[message->event_type] + 1, message->seq_num);

            //notify
            // ->'ES_EVENT_TYPE_LAST' is (ab)used as 'resync required'
            if(nil != self.callback)
            {
                //invoke
                self.callback(ES_EVENT_TYPE_LAST, @{});
            }
        }

        //save
        lastSeq[message->event_type] = message->seq_num;
        seenSeq[message->event_type] = YES;
    }

    //event
    NSDictionary* event = nil;

    //handle event
    switch(message->event_type)
    {
        //exec
        case ES_EVENT_TYPE_NOTIFY_EXEC:

            //build event
            event = [self processInfo:message->event.exec.target message:message];

            break;

        //exit
        case ES_EVENT_TYPE_NOTIFY_EXIT:

            //build event
            event = @{KEY_PROCESS_ID:[NSNumber numberWithInt:audit_token_to_pid(message->process->audit_token)], KEY_PROCESS_EXIT_STATUS:[NSNumber numberWithInt:message->event.exit.stat]};

            break;

        //mmap
        // only care about executable mappings (of files) ...i.e. dylib loads
        case ES_EVENT_TYPE_NOTIFY_MMAP:
        {
            //dylib path
            NSString* dylib = nil;

            //ignore non-executable mappings
            if(0 == (message->event.mmap.protection & PROT_EXEC))
            {
                //bail
                goto bail;
            }

            //ignore mappings that aren't file-backed
            if(NULL == message->event.mmap.source)
            {
                //bail
                goto bail;
            }

            //convert path
            dylib = convertStringToken(&message->event.mmap.source->path);
            if(0 == dylib.length)
            {
                //bail
                goto bail;
            }

            //build event
            event = @{KEY_PROCESS_ID:[NSNumber numberWithInt:audit_token_to_pid(message->process->audit_token)], KEY_DYLIB_PATH:dylib};

            break;
        }

        default:

            //bail
            goto bail;
    }

    //invoke callback
    if( (nil != event) &&
        (nil != self.callback) )
    {
        //invoke
        self.callback(message->event_type, event);
    }

bail:

    return;
}

//build a process dictionary from an ES process
-(NSDictionary*)processInfo:(es_process_t*)process message:(const es_message_t*)message
{
    //info
    NSMutableDictionary* info = nil;

    //arguments
    NSMutableArray* arguments = nil;

    //string
    NSString* string = nil;

    //cd hash
    NSMutableString* cdHash = nil;

    //init
    info = [NSMutableDictionary dictionary];

    //add pid
    info[KEY_PROCESS_ID] = [NSNumber numberWithInt:audit_token_to_pid(process->audit_token)];

    //add ppid
    info[KEY_PROCESS_PPID] = [NSNumber numberWithInt:process->ppid];

    //add rpid
    if(message->version >= 4)
    {
        //add
        info[KEY_PROCESS_RPID] = [NSNumber numberWithInt:audit_token_to_pid(process->responsible_audit_token)];
    }

    //add uid
    info[KEY_PROCESS_UID] = [NSNumber numberWithUnsignedInt:audit_token_to_euid(process->audit_token)];

    //add audit token
    info[KEY_PROCESS_AUDIT_TOKEN] = [NSData dataWithBytes:&process->audit_token length:sizeof(audit_token_t)];

    //add path
    if(nil != (string = convertStringToken(&process->executable->path)))
    {
        //add
        info[KEY_PROCESS_PATH] = string;
    }

    //add start time
    info[KEY_PROCESS_START] = [NSDate dateWithTimeIntervalSince1970:process->start_time.tv_sec];

    //add cs flags
    info[KEY_PROCESS_CS_FLAGS] = [NSNumber numberWithUnsignedInt:process->codesigning_flags];

    //add signing id
    if(nil != (string = convertStringToken(&process->signing_id)))
    {
        //add
        info[KEY_PROCESS_SIGNING_ID] = string;
    }

    //add team id
    if(nil != (string = convertStringToken(&process->team_id)))
    {
        //add
        info[KEY_PROCESS_TEAM_ID] = string;
    }

    //add platform binary
    info[KEY_PROCESS_PLATFORM_BINARY] = [NSNumber numberWithBool:process->is_platform_binary];

    //add cd hash
    // as hex string
    cdHash = [NSMutableString string];
    for(int i = 0; i < CS_CDHASH_LEN; i++)
    {
        //append
        [cdHash appendFormat:@"%02X", process->cdhash[i]];
    }
    info[KEY_PROCESS_CDHASH] = cdHash;

    //add arguments
    // only for exec events
    if(ES_EVENT_TYPE_NOTIFY_EXEC == message->event_type)
    {
        //init
        arguments = [NSMutableArray array];

        //extract each
        for(uint32_t i = 0; i < es_exec_arg_count(&message->event.exec); i++)
        {
            //current arg
            es_string_token_t argument = es_exec_arg(&message->event.exec, i);

            //convert/add
            if(nil != (string = convertStringToken(&argument)))
            {
                //add
                [arguments addObject:string];
            }
        }

        //add
        info[KEY_PROCESS_ARGS] = arguments;
    }

    return info;
}

//convert an ES string token to a string
NSString* convertStringToken(es_string_token_t* stringToken)
{
    //string
    NSString* string = nil;

    //sanity check(s)
    if( (NULL == stringToken) ||
        (NULL == stringToken->data) ||
        (stringToken->length <= 0) )
    {
        //bail
        goto bail;
    }

    //convert to data, then to string
    string = [[NSString alloc] initWithBytes:stringToken->data length:stringToken->length encoding:NSUTF8StringEncoding];

bail:

    return string;
}

@end
