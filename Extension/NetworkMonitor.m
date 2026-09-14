//
//  file: NetworkMonitor.m
//  project: TaskExplorer (extension)
//  description: network (connection) monitor, via (private) NetworkStatistics framework
//
//  created by Patrick Wardle
//  copyright (c) 2026 Objective-See. All rights reserved.
//
//  note: based on Netiquette's Monitor.m

#import "Consts.h"
#import "NetworkMonitor.h"

#import <os/log.h>
#import <dlfcn.h>
#import <net/if.h>
#import <arpa/inet.h>
#import <netinet/in.h>
#import <sys/socket.h>

/* GLOBALS */

//log handle
extern os_log_t logHandle;

//path to (private) NetworkStatistics framework
#define NETWORK_STATISTICS_FRAMEWORK "/System/Library/PrivateFrameworks/NetworkStatistics.framework/NetworkStatistics"

//resolved (private) APIs
static NStatManagerCreate_t NStatManagerCreate = NULL;
static NStatSourceSetDescriptionBlock_t NStatSourceSetDescriptionBlock = NULL;
static NStatSourceSetRemovedBlock_t NStatSourceSetRemovedBlock = NULL;
static NStatManagerAddAll_t NStatManagerAddAllTCP = NULL;
static NStatManagerAddAll_t NStatManagerAddAllUDP = NULL;
static NStatManagerQueryAll_t NStatManagerQueryAllSourcesDescriptions = NULL;
static NStatManagerDestroy_t NStatManagerDestroy = NULL;
static NStatManagerSetFlags_t NStatManagerSetFlags = NULL;

//query all sources (w/ counts)
// ->note: byte counters (txBytes/rxBytes) are only populated in the 'counts' callback, never in the description
static NStatManagerQueryAll_t NStatManagerQueryAllSources = NULL;

//resolved (private) keys
static NSString* kNStatSrcKeyPID = nil;
static NSString* kNStatSrcKeyUUID = nil;
static NSString* kNStatSrcKeyLocal = nil;
static NSString* kNStatSrcKeyRemote = nil;
static NSString* kNStatSrcKeyTxBytes = nil;
static NSString* kNStatSrcKeyRxBytes = nil;
static NSString* kNStatSrcKeyProvider = nil;
static NSString* kNStatSrcKeyTCPState = nil;
static NSString* kNStatSrcKeyInterface = nil;

//resolve a (private) NSString constant
// ->dlsym gives address of the pointer, so deref
static NSString* resolveKey(void* handle, const char* name)
{
    //pointer to string
    NSString* __strong* pointer = NULL;
    
    //resolve
    pointer = (NSString* __strong*)dlsym(handle, name);
    if(NULL == pointer)
    {
        //err msg
        os_log_error(logHandle, "ERROR: failed to resolve '%{public}s'", name);
        
        //bail
        return nil;
    }
    
    return *pointer;
}

//load (private) NetworkStatistics framework
// ->and resolve all APIs/keys we need
static BOOL loadNetworkStatistics(void)
{
    //flag
    static BOOL loaded = NO;
    
    //once
    static dispatch_once_t once = 0;
    
    //load/resolve once
    dispatch_once(&once, ^{
        
        //handle
        void* handle = NULL;
        
        //load framework
        handle = dlopen(NETWORK_STATISTICS_FRAMEWORK, RTLD_NOW);
        if(NULL == handle)
        {
            //err msg
            os_log_error(logHandle, "ERROR: failed to load %{public}s (%{public}s)", NETWORK_STATISTICS_FRAMEWORK, dlerror());
            
            //bail
            return;
        }
        
        //resolve functions
        NStatManagerCreate = (NStatManagerCreate_t)dlsym(handle, "NStatManagerCreate");
        NStatSourceSetDescriptionBlock = (NStatSourceSetDescriptionBlock_t)dlsym(handle, "NStatSourceSetDescriptionBlock");
        NStatSourceSetRemovedBlock = (NStatSourceSetRemovedBlock_t)dlsym(handle, "NStatSourceSetRemovedBlock");
        NStatManagerAddAllTCP = (NStatManagerAddAll_t)dlsym(handle, "NStatManagerAddAllTCP");
        NStatManagerAddAllUDP = (NStatManagerAddAll_t)dlsym(handle, "NStatManagerAddAllUDP");
        NStatManagerQueryAllSourcesDescriptions = (NStatManagerQueryAll_t)dlsym(handle, "NStatManagerQueryAllSourcesDescriptions");
        NStatManagerDestroy = (NStatManagerDestroy_t)dlsym(handle, "NStatManagerDestroy");
        NStatManagerSetFlags = (NStatManagerSetFlags_t)dlsym(handle, "NStatManagerSetFlags");
        NStatManagerQueryAllSources = (NStatManagerQueryAll_t)dlsym(handle, "NStatManagerQueryAllSources");
        
        //resolve keys
        kNStatSrcKeyPID = resolveKey(handle, "kNStatSrcKeyPID");
        kNStatSrcKeyUUID = resolveKey(handle, "kNStatSrcKeyUUID");
        kNStatSrcKeyLocal = resolveKey(handle, "kNStatSrcKeyLocal");
        kNStatSrcKeyRemote = resolveKey(handle, "kNStatSrcKeyRemote");
        kNStatSrcKeyTxBytes = resolveKey(handle, "kNStatSrcKeyTxBytes");
        kNStatSrcKeyRxBytes = resolveKey(handle, "kNStatSrcKeyRxBytes");
        kNStatSrcKeyProvider = resolveKey(handle, "kNStatSrcKeyProvider");
        kNStatSrcKeyTCPState = resolveKey(handle, "kNStatSrcKeyTCPState");
        kNStatSrcKeyInterface = resolveKey(handle, "kNStatSrcKeyInterface");
        
        //sanity check
        // ->all functions & (required) keys resolved?
        if( (NULL == NStatManagerCreate) || (NULL == NStatSourceSetDescriptionBlock) || (NULL == NStatSourceSetRemovedBlock) ||
            (NULL == NStatManagerAddAllTCP) || (NULL == NStatManagerAddAllUDP) || (NULL == NStatManagerQueryAllSourcesDescriptions) ||
            (NULL == NStatManagerDestroy) || (NULL == NStatManagerSetFlags) ||
            (NULL == NStatManagerQueryAllSources) ||
            (nil == kNStatSrcKeyPID) || (nil == kNStatSrcKeyLocal) || (nil == kNStatSrcKeyRemote) || (nil == kNStatSrcKeyProvider) )
        {
            //err msg
            os_log_error(logHandle, "ERROR: failed to resolve (all) NetworkStatistics APIs");
            
            //bail
            return;
        }
        
        //dbg msg
        os_log_debug(logHandle, "loaded/resolved NetworkStatistics framework");
        
        //happy
        loaded = YES;
    });
    
    return loaded;
}

@implementation NetworkMonitor

@synthesize queue;
@synthesize timer;
@synthesize manager;
@synthesize connections;

//init
// create queue & nstat manager
-(id)init
{
    //super
    self = [super init];
    if(nil != self)
    {
        //load (private) framework
        if(YES != loadNetworkStatistics())
        {
            //unset
            self = nil;
            
            //bail
            goto bail;
        }
        
        //init queue
        self.queue = dispatch_queue_create("com.objective-see.taskexplorer.network", NULL);

        //init dictionary for connections
        connections = [NSMutableDictionary dictionary];

        //create manager
        // callback invoked for each (new) source
        self.manager = NStatManagerCreate(kCFAllocatorDefault, self.queue, ^(NStatSourceRef source, void *unknown)
        {
            //set description block
            // ->invoked when source is described (queried); note: 'NStatManagerQueryAllSources' also invokes this,
            //   but w/ (real) byte counters, which a plain 'NStatManagerQueryAllSourcesDescriptions' leaves at zero
            NStatSourceSetDescriptionBlock(source, ^(NSDictionary* description)
            {
                //connection
                NSDictionary* connection = nil;

                //convert
                connection = [self connectionFromDescription:description];
                if(nil == connection)
                {
                    //bail
                    return;
                }

                //sync
                @synchronized(self.connections)
                {
                    //save
                    self.connections[[NSValue valueWithPointer:source]] = connection;
                }
            });

            //set removed block
            // ->invoked when source goes away
            NStatSourceSetRemovedBlock(source, ^()
            {
                //sync
                @synchronized(self.connections)
                {
                    //remove
                    [self.connections removeObjectForKey:[NSValue valueWithPointer:source]];
                }
            });
        });

        //sanity check
        if(nil == self.manager)
        {
            //err msg
            os_log_error(logHandle, "ERROR: NStatManagerCreate() failed");

            //unset
            self = nil;

            //bail
            goto bail;
        }

        //set flags
        NStatManagerSetFlags(self.manager, 0);

        //watch UDP
        NStatManagerAddAllUDP(self.manager);

        //watch TCP
        NStatManagerAddAllTCP(self.manager);
    }

bail:

    return self;
}

//enumerate (all) connections
// async, invokes callback when done
-(void)enumerate:(NetworkCallbackBlock)callback
{
    //no manager (init failed)?
    // ->reply w/ nothing, so callers never hang
    if(nil == self.manager)
    {
        //err msg
        os_log_error(logHandle, "ERROR: no NetworkStatistics manager, can't enumerate connections");

        //empty
        callback(@[]);

        //bail
        return;
    }

    //query all sources' descriptions, then all sources (w/ counts)
    // ->the latter (re)invokes each source's description block w/ real byte counters (as Netiquette does)
    //   when done, invoke callback w/ (copy of) all connections
    NStatManagerQueryAllSourcesDescriptions(self.manager, ^{ ; });
    NStatManagerQueryAllSources(self.manager, ^{

        //connections
        NSArray* current = nil;

        //sync
        @synchronized(self.connections)
        {
            //grab (copy of) all
            current = [self.connections.allValues copy];
        }

        //dbg msg
        os_log_debug(logHandle, "network query complete: %lu connections", (unsigned long)current.count);

        //invoke callback
        callback(current);
    });

    return;
}

//start (network) monitoring
// (re)enumerates every 'refreshRate' seconds, invoking callback each time
-(void)start:(NSUInteger)refreshRate callback:(NetworkCallbackBlock)callback
{
    //sync
    @synchronized(self)
    {
        //already started?
        if(nil != self.timer)
        {
            //dbg msg
            os_log_debug(logHandle, "network monitor already started");

            //bail
            goto bail;
        }

        //init timer
        self.timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, self.queue);

        //set timer
        dispatch_source_set_timer(self.timer, dispatch_time(DISPATCH_TIME_NOW, refreshRate * NSEC_PER_SEC), refreshRate * NSEC_PER_SEC, 1 * NSEC_PER_SEC);

        //set timer event handler
        // (re)enumerate, then invoke callback
        dispatch_source_set_event_handler(self.timer, ^{

            //enumerate
            [self enumerate:callback];
        });

        //go!
        dispatch_resume(self.timer);

        //dbg msg
        os_log_debug(logHandle, "network monitor started (refresh: %lus)", (unsigned long)refreshRate);
    }

bail:

    return;
}

//stop
-(void)stop
{
    //sync
    @synchronized(self)
    {
        //not started?
        if(nil == self.timer)
        {
            //bail
            goto bail;
        }

        //cancel timer
        dispatch_source_cancel(self.timer);

        //unset
        self.timer = nil;

        //dbg msg
        os_log_debug(logHandle, "network monitor stopped");
    }

bail:

    return;
}

//convert an nstat (source) description into a connection dictionary
-(NSDictionary*)connectionFromDescription:(NSDictionary*)description
{
    //connection
    NSMutableDictionary* connection = nil;

    //address
    NSDictionary* address = nil;

    //interface name
    char interfaceName[IF_NAMESIZE+1] = {0};

    //sanity check
    // ignore pid 0 (kernel) sources
    if(0 == [description[kNStatSrcKeyPID] intValue])
    {
        //bail
        goto bail;
    }

    //init
    connection = [NSMutableDictionary dictionary];

    //add pid
    connection[KEY_PROCESS_ID] = description[kNStatSrcKeyPID];

    //add uuid
    if(nil != description[kNStatSrcKeyUUID])
    {
        //add
        connection[KEY_CONNECTION_UUID] = description[kNStatSrcKeyUUID];
    }

    //add provider (TCP/UDP)
    if(nil != description[kNStatSrcKeyProvider])
    {
        //add
        connection[KEY_PROVIDER] = description[kNStatSrcKeyProvider];
    }

    //add (tcp) state
    // note: nil, unless provider is TCP
    if(nil != description[kNStatSrcKeyTCPState])
    {
        //add
        connection[KEY_SOCKET_STATE] = description[kNStatSrcKeyTCPState];
    }

    //parse/add local address
    address = [self parseAddress:description[kNStatSrcKeyLocal]];
    if(nil != address)
    {
        //add family
        connection[KEY_SOCKET_FAMILY] = address[KEY_SOCKET_FAMILY];

        //add address
        connection[KEY_LOCAL_ADDR] = address[KEY_LOCAL_ADDR];

        //add port
        connection[KEY_LOCAL_PORT] = address[KEY_LOCAL_PORT];
    }

    //parse/add remote address
    address = [self parseAddress:description[kNStatSrcKeyRemote]];
    if(nil != address)
    {
        //add address
        connection[KEY_REMOTE_ADDR] = address[KEY_LOCAL_ADDR];

        //add port
        connection[KEY_REMOTE_PORT] = address[KEY_LOCAL_PORT];
    }

    //extract and convert interface (number) to name
    if(NULL != if_indextoname([description[kNStatSrcKeyInterface] intValue], (char*)&interfaceName))
    {
        //add
        connection[KEY_INTERFACE] = [NSString stringWithUTF8String:interfaceName];
    }

    //add bytes up
    if(nil != description[kNStatSrcKeyTxBytes])
    {
        //add
        connection[KEY_BYTES_UP] = description[kNStatSrcKeyTxBytes];
    }

    //add bytes down
    if(nil != description[kNStatSrcKeyRxBytes])
    {
        //add
        connection[KEY_BYTES_DOWN] = description[kNStatSrcKeyRxBytes];
    }

bail:

    return connection;
}

//parse/extract addr, port, etc...
// note: returns dictionary w/ family, address, port (keyed w/ 'local' keys)
-(NSDictionary*)parseAddress:(NSData*)data
{
    //address
    NSMutableDictionary* address = nil;

    //ipv4 struct
    struct sockaddr_in *ipv4 = NULL;

    //ipv6 struct
    struct sockaddr_in6 *ipv6 = NULL;

    //address (string)
    char addressString[INET6_ADDRSTRLEN] = {0};

    //sanity check
    if(data.length < sizeof(struct sockaddr))
    {
        //bail
        goto bail;
    }

    //init
    address = [NSMutableDictionary dictionary];

    //parse
    // for now, only support IPv4 and IPv6
    switch(((struct sockaddr *)data.bytes)->sa_family)
    {
        //IPv4
        case AF_INET:

            //sanity check
            if(data.length < sizeof(struct sockaddr_in))
            {
                //unset
                address = nil;

                //bail
                goto bail;
            }

            //typecast
            ipv4 = (struct sockaddr_in *)data.bytes;

            //add family
            address[KEY_SOCKET_FAMILY] = [NSNumber numberWithInt:AF_INET];

            //add port
            address[KEY_LOCAL_PORT] = [NSNumber numberWithUnsignedShort:ntohs(ipv4->sin_port)];

            //format/add address
            inet_ntop(AF_INET, &ipv4->sin_addr, addressString, sizeof(addressString));
            address[KEY_LOCAL_ADDR] = [NSString stringWithUTF8String:addressString];

            break;

        //IPv6
        case AF_INET6:

            //sanity check
            if(data.length < sizeof(struct sockaddr_in6))
            {
                //unset
                address = nil;

                //bail
                goto bail;
            }

            //typecast
            ipv6 = (struct sockaddr_in6 *)data.bytes;

            //add family
            address[KEY_SOCKET_FAMILY] = [NSNumber numberWithInt:AF_INET6];

            //add port
            address[KEY_LOCAL_PORT] = [NSNumber numberWithUnsignedShort:ntohs(ipv6->sin6_port)];

            //format/add address
            inet_ntop(AF_INET6, &ipv6->sin6_addr, addressString, sizeof(addressString));
            address[KEY_LOCAL_ADDR] = [NSString stringWithUTF8String:addressString];

            break;

        //unsupported
        default:

            //unset
            address = nil;

            break;
    }

bail:

    return address;
}

@end
