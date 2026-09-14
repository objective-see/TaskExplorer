//
//  VirusTotal.m
//  TaskExplorer
//
//  Created by Patrick Wardle on 3/8/15.
//  Copyright (c) 2015 Objective-See. All rights reserved.
//
//  note: uses VirusTotal's (v3) API, w/ the user's own API key (stored in the keychain)
//        ...ported from KnockKnock

#import "File.h"
#import "Consts.h"
#import "ItemBase.h"
#import "Utilities.h"
#import "UIUtilities.h"
#import "VirusTotal.h"
#import "ModelNotify.h"
#import "TaskEnumerator.h"

#import <os/log.h>

/* GLOBALS */

//log handle
extern os_log_t logHandle;

//task enumerator
extern TaskEnumerator* taskEnumerator;

//a (numeric) count from VT's stats (0 if missing, or not a number)
static NSInteger vtCount(NSDictionary* stats, NSString* key)
{
    return ([stats[key] isKindOfClass:[NSNumber class]]) ? [stats[key] integerValue] : 0;
}

@implementation VirusTotal

@synthesize items;
@synthesize deferred;
@synthesize apiKey;
@synthesize isBusy;
@synthesize queueCondition;

//init
-(id)init
{
    //worker thread
    NSThread* worker = nil;

    //init super
    self = [super init];
    if(nil != self)
    {
        //alloc array for items
        items = [NSMutableArray array];

        //alloc array for deferred items
        deferred = [NSMutableArray array];

        //init condition
        queueCondition = [[NSCondition alloc] init];

        //init results cache
        self.resultsByHash = [NSMutableDictionary dictionary];

        //load (persisted) results cache
        [self loadCache];

        //load api key
        [self reloadAPIKey];

        //init worker thread
        // ->processes queue (one lookup at a time, as free api keys are rate limited)
        worker = [[NSThread alloc] initWithTarget:self selector:@selector(processQueue) object:nil];

        //name
        worker.name = @"VirusTotal";

        //start
        [worker start];
    }

    return self;
}

//(re)load api key from keychain
-(void)reloadAPIKey
{
    //load
    self.apiKey = loadAPIKeyFromKeychain();

    //reset backoff & rejected flag, and wake worker (deferred items can go again)
    [self.queueCondition lock];
    self.retryAfter = nil;
    self.rateLimitHits = 0;
    self.keyRejected = NO;
    [self.queueCondition broadcast];
    [self.queueCondition unlock];

    //dbg msg
    os_log_debug(logHandle, "VirusTotal api key %{public}s", (0 != self.apiKey.length) ? "loaded" : "not set");

    return;
}

//is VT enabled?
// ->api key, and not disabled (pref)
-(BOOL)isEnabled
{
    //flag
    BOOL enabled = NO;

    //no key?
    if(0 == self.apiKey.length)
    {
        //bail
        goto bail;
    }

    //disabled via pref?
    // ->note: cmdline mode ignores pref (uses '-skipVT' instead)
    if( (YES != cmdlineMode) &&
        (YES == getPreferenceBool(PREF_DISABLE_VT_QUERIES)) )
    {
        //bail
        goto bail;
    }

    //enabled
    enabled = YES;

bail:

    return enabled;
}

//add item
// ->will be looked up (in background) by worker thread
-(void)addItem:(Binary*)binary
{
    //sanity check
    if(nil == binary)
    {
        //bail
        goto bail;
    }

    //lock
    [self.queueCondition lock];

    //add (if not already queued, or deferred)
    if( (YES != [self.items containsObject:binary]) &&
        (YES != [self.deferred containsObject:binary]) )
    {
        //add
        [self.items addObject:binary];
    }

    //signal
    [self.queueCondition signal];

    //unlock
    [self.queueCondition unlock];

bail:

    return;
}

//(re)queue all known binaries that don't have VT results
// ->e.g. when user just added an api key
-(void)requeueAll
{
    //binaries
    NSMutableArray* binaries = nil;

    //init
    binaries = [NSMutableArray array];

    //sync
    @synchronized(taskEnumerator.executables)
    {
        //add all task binaries
        [binaries addObjectsFromArray:taskEnumerator.executables.allValues];
    }

    //sync
    @synchronized(taskEnumerator.dylibs)
    {
        //add all dylibs
        [binaries addObjectsFromArray:taskEnumerator.dylibs.allValues];
    }

    //(re)queue those w/o results
    // ->or those that errored out (e.g. no api key at the time)
    for(Binary* binary in binaries)
    {
        //skip excluded (apple/platform/dyld-cache)
        // ->but not those whose signing check failed (the lookup retries it; same as the queue)
        if( (YES == binary.isExcludedFromVT) &&
            (SIGNING_STATUS_XPC_FAILED != [binary.signingInfo[KEY_SIGNATURE_STATUS] intValue]) )
        {
            //skip
            continue;
        }

        //skip those w/ results
        if( (nil != binary.vtInfo) &&
            (nil == binary.vtInfo[VT_ERROR]) )
        {
            //skip
            continue;
        }

        //reset
        binary.vtInfo = nil;

        //add
        [self addItem:binary];
    }

    //dbg msg
    os_log_debug(logHandle, "VirusTotal: (re)queued binaries for lookup");

    return;
}

//process queue
// ->forever: wait for items, then lookup (one at a time)
-(void)processQueue
{
    //item
    Binary* item = nil;

    //forever
    while(YES)
    {
        //pool
        @autoreleasepool
        {
            //lock
            [self.queueCondition lock];

            //wait while queue is empty
            while(0 == self.items.count)
            {
                //deferred items?
                if(0 != self.deferred.count)
                {
                    //backoff still running? wait it out (or for a wake-up: key reloaded, new items)
                    if( (nil != self.retryAfter) &&
                        (NSOrderedAscending == [[NSDate date] compare:self.retryAfter]) )
                    {
                        //wait
                        [self.queueCondition waitUntilDate:self.retryAfter];
                    }
                    //backoff passed (or cleared)?
                    // ->re-queue deferred items
                    else
                    {
                        //dbg msg
                        os_log_debug(logHandle, "VirusTotal: backoff passed, re-queuing %lu deferred item(s)", (unsigned long)self.deferred.count);

                        //re-queue
                        [self.items addObjectsFromArray:self.deferred];
                        [self.deferred removeAllObjects];
                    }

                    //re-check
                    continue;
                }

                //wait
                [self.queueCondition wait];
            }

            //grab first item
            item = self.items.firstObject;

            //remove
            [self.items removeObjectAtIndex:0];

            //set flag
            self.isBusy = YES;

            //unlock
            [self.queueCondition unlock];

            //lookup
            [self lookup:item];

            //unset flag
            self.isBusy = NO;

        }//pool

    }//forever

    return;
}

//lookup an item (synchronously)
// ->local first (signing info, hash, cache), then one request; rate limits / network errors defer the item (see 'defer:')
-(void)lookup:(Binary*)item
{
    //hash
    NSString* sha1 = nil;

    //cached result
    NSDictionary* cached = nil;

    //semaphore for synchronous request
    dispatch_semaphore_t semaphore = nil;

    //request
    NSMutableURLRequest* request = nil;

    //no signing info yet (or the extension failed to provide it earlier)?
    // ->generate (needed for apple check); 'generateInfo' retries after an (XPC) failure
    if( (nil == item.signingInfo) ||
        (SIGNING_STATUS_XPC_FAILED == [item.signingInfo[KEY_SIGNATURE_STATUS] intValue]) )
    {
        //generate
        [item generatedSigningInfo];
    }

    //skip apple/platform binaries & those in the dyld shared cache
    // ->these won't be malware, and (personal) api keys are limited (~500 lookups/day)
    if(YES == item.isExcludedFromVT)
    {
        //signing check (still) failed? resolve as an error (rather than leaving the item 'pending' forever)
        if(SIGNING_STATUS_XPC_FAILED == [item.signingInfo[KEY_SIGNATURE_STATUS] intValue])
        {
            //mark
            [self markError:item];
        }

        //bail
        goto bail;
    }

    //grab hash
    // ->none yet (extension hiccup, e.g. it was being replaced)? retry (no-op for anything already generated)
    if( (0 == [item.hashes[KEY_HASH_SHA1] length]) &&
        (YES != item.inCache) )
    {
        //(re)generate
        [item generateDetailedInfo];
    }

    //still none (not a regular mach-o, unreadable, gone)? nothing to look up, so resolve as an error
    // ->rather than leaving the item 'pending' forever
    sha1 = item.hashes[KEY_HASH_SHA1];
    if(0 == sha1.length)
    {
        //dbg msg
        os_log_debug(logHandle, "VirusTotal: no hash for %{public}@, can't look up", item.name);

        //mark
        [self markError:item];

        //bail
        goto bail;
    }

    //already looked up (same hash; this session, or persisted from a previous one)?
    // ->just (re)use result, no need to burn a lookup
    //   note: a modified binary has a new hash, so it's (automatically) looked up again
    cached = [self cachedResult:sha1];
    if(nil != cached)
    {
        //dbg msg
        os_log_debug(logHandle, "VirusTotal: reusing (cached) result for %{public}@ (sha1: %{public}@)", item.name, sha1);

        //apply
        [self applyResult:cached item:item];

        //bail
        goto bail;
    }

    //note: everything above is local; from here on the network (and the api key) is needed

    //key rejected (HTTP 401) earlier?
    // ->don't bother
    if(YES == self.keyRejected)
    {
        //mark
        [self markError:item];

        //bail
        goto bail;
    }

    //still enabled?
    // ->user might have disabled/removed key while items were queued
    if(YES != [self isEnabled])
    {
        //bail
        goto bail;
    }

    //backing off (rate limited / network error)?
    // ->defer (item stays 'pending'; re-queued once the backoff passes)
    if( (nil != self.retryAfter) &&
        (NSOrderedAscending == [[NSDate date] compare:self.retryAfter]) )
    {
        //defer
        [self defer:item];

        //bail
        goto bail;
    }

    //init semaphore
    semaphore = dispatch_semaphore_create(0);

    //init request
    request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[VT_QUERY_URL stringByAppendingString:sha1]]];
    [request setValue:self.apiKey forHTTPHeaderField:@"x-apikey"];

    //request
    // ->in its own scope (the block literal is a declaration the 'goto bail's above may not jump over)
    {
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData* data, NSURLResponse* response, NSError* error) {

        //network error?
        // ->back off a bit, and defer
        if(nil != error)
        {
            //err msg
            os_log_error(logHandle, "ERROR: VirusTotal lookup failed: %{public}@", error);

            //back off
            self.retryAfter = [NSDate dateWithTimeIntervalSinceNow:VT_BACKOFF_NETWORK];

            //defer
            [self defer:item];
        }
        //response
        else
        {
            //handle (http) status
            switch(((NSHTTPURLResponse*)response).statusCode)
            {
                //ok
                case 200:

                    //reset
                    self.rateLimitHits = 0;

                    //process
                    [self processResponse:data item:item];

                    break;

                //unknown file
                case 404:

                    //dbg msg
                    os_log_debug(logHandle, "%{public}@ is unknown to VirusTotal (sha1: %{public}@)", item.name, sha1);

                    //reset
                    self.rateLimitHits = 0;

                    //cache & apply (empty) results
                    [self cacheResult:@{} forHash:sha1];
                    [self applyResult:@{} item:item];

                    break;

                //api key issue
                case 401:

                    //err msg
                    os_log_error(logHandle, "ERROR: VirusTotal rejected api key (HTTP 401)");

                    //set flag
                    // ->no point sending the rest of the queue w/ a bad key (cleared when key is reloaded)
                    self.keyRejected = YES;

                    //alert user (once)
                    [self alertInvalidKey];

                    //mark
                    [self markError:item];

                    break;

                //rate limited
                // ->back off (escalating), and defer
                case 429:

                    //back off
                    [self rateLimited];

                    //defer
                    [self defer:item];

                    break;

                //all other error(s)
                default:

                    //err msg
                    os_log_error(logHandle, "ERROR: VirusTotal lookup failed (HTTP %ld)", (long)((NSHTTPURLResponse*)response).statusCode);

                    //mark
                    [self markError:item];

                    break;
            }
        }

        //signal
        dispatch_semaphore_signal(semaphore);

    }] resume];
    }

    //wait for request to finish
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);

bail:

    return;
}

//defer an item
// ->re-queued by the worker once 'retryAfter' passes
-(void)defer:(Binary*)item
{
    //lock
    [self.queueCondition lock];

    //defer
    [self.deferred addObject:item];

    //unlock
    [self.queueCondition unlock];

    return;
}

//rate limited (HTTP 429)
// ->back off: 15s, 30s, 60s, then 15 minutes (the per-minute limit clears within 60s, so that's the daily quota; alert once)
-(void)rateLimited
{
    //backoff steps
    static const NSTimeInterval steps[] = {VT_BACKOFF_STEPS};

    //step
    NSUInteger step = MIN(self.rateLimitHits, (sizeof(steps) / sizeof(steps[0])) - 1);

    //inc
    self.rateLimitHits++;

    //set
    self.retryAfter = [NSDate dateWithTimeIntervalSinceNow:steps[step]];

    //dbg msg
    os_log_debug(logHandle, "VirusTotal: rate limited (HTTP 429), backing off %.0fs", steps[step]);

    //last step?
    // ->quota exhausted; alert user (once)
    if(step == (sizeof(steps) / sizeof(steps[0])) - 1)
    {
        //err msg
        os_log_error(logHandle, "ERROR: VirusTotal rate limit / quota exhausted, deferring lookups (15 minutes)");

        //alert
        [self alertRateLimited];

        //cmdline mode?
        // ->nobody waits 15 minutes for a scan: resolve deferred items as errors, so the scan can complete
        if(YES == cmdlineMode)
        {
            //lock
            [self.queueCondition lock];

            //mark all
            for(Binary* deferredItem in self.deferred) [self markError:deferredItem];
            [self.deferred removeAllObjects];

            //unlock
            [self.queueCondition unlock];
        }
    }

    return;
}

//process (successful) response
// ->parse JSON, then apply (& cache) the result
-(void)processResponse:(NSData*)data item:(Binary*)item
{
    //(type-checked) parts of response
    NSDictionary* payload = nil;
    NSDictionary* attributes = nil;
    NSString* analysisID = nil;
    NSDictionary* stats = nil;

    //json
    NSDictionary* json = nil;

    //counts
    NSInteger malicious = 0;
    NSInteger total = 0;

    //result
    NSDictionary* result = nil;

    //parse
    // ->VirusTotal (or a proxy) could return an unexpected shape; never index blindly
    json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    payload = ([json isKindOfClass:[NSDictionary class]] && [json[@"data"] isKindOfClass:[NSDictionary class]]) ? json[@"data"] : nil;
    attributes = ([payload[@"attributes"] isKindOfClass:[NSDictionary class]]) ? payload[@"attributes"] : nil;
    analysisID = ([payload[@"id"] isKindOfClass:[NSString class]]) ? payload[@"id"] : nil;
    stats = ([attributes[@"last_analysis_stats"] isKindOfClass:[NSDictionary class]]) ? attributes[@"last_analysis_stats"] : nil;
    if( (nil == stats) ||
        (0 == analysisID.length) )
    {
        //err msg
        os_log_error(logHandle, "ERROR: VirusTotal response is invalid, or missing expected fields");

        //mark
        [self markError:item];

        //bail
        goto bail;
    }

    //counts (type-checked: a JSON null would be NSNull, which doesn't answer 'integerValue')
    malicious = vtCount(stats, @"malicious");
    total = malicious + vtCount(stats, @"suspicious") + vtCount(stats, @"undetected") + vtCount(stats, @"harmless");

    //no engines (yet)?
    // ->the file is known, but its analysis hasn't completed (e.g. just submitted): no verdict, so show as 'unknown'
    //   ...but don't cache that (the next lookup should ask again)
    if(0 == total)
    {
        //dbg msg
        os_log_debug(logHandle, "VirusTotal: %{public}@ has no analysis results yet (sha1: %{public}@)", item.name, item.hashes[KEY_HASH_SHA1]);

        //apply (empty) results
        [self applyResult:@{} item:item];

        //bail
        goto bail;
    }

    //init result
    result = @{VT_RESULTS_POSITIVES: @(malicious),
               VT_RESULTS_TOTAL: @(total),
               VT_RESULTS_RATIO: [NSString stringWithFormat:@"%ld/%ld", (long)malicious, (long)total],
               VT_RESULTS_URL: [VT_REPORT_URL stringByAppendingString:analysisID]};

    //cache (by hash)
    // ->so identical binaries aren't looked up again
    [self cacheResult:result forHash:item.hashes[KEY_HASH_SHA1]];

    //apply
    [self applyResult:result item:item];

bail:

    return;
}

//mark an item's VT lookup as failed, and reload UI
// ->so its row resolves (shows an error), rather than staying 'pending' forever
-(void)markError:(Binary*)item
{
    //mark
    item.vtInfo = @{VT_ERROR:@YES};

    //reload
    [self reload:item];

    return;
}

//apply a result to an item
// ->sets vt info, updates flagged items, and reloads UI
-(void)applyResult:(NSDictionary*)result item:(Binary*)item
{
    //set
    item.vtInfo = result;

    //sync
    @synchronized(taskEnumerator.flaggedItems)
    {
        //malicious?
        // ->flag
        if( (0 != [result[VT_RESULTS_POSITIVES] integerValue]) &&
            (YES != [taskEnumerator.flaggedItems containsObject:item]) )
        {
            //save
            [taskEnumerator.flaggedItems addObject:item];
        }
        //not malicious
        // ->remove from flagged items, if it was previously flagged
        else if( (0 == [result[VT_RESULTS_POSITIVES] integerValue]) &&
                 (YES == [taskEnumerator.flaggedItems containsObject:item]) )
        {
            //remove
            [taskEnumerator.flaggedItems removeObject:item];
        }
    }

    //reload
    [self reload:item];

    return;
}

//forget cached result (for hash of binary)
-(void)forgetResult:(Binary*)binary
{
    //hash
    NSString* sha1 = binary.hashes[KEY_HASH_SHA1];
    if(0 == sha1.length)
    {
        //bail
        return;
    }

    //sync
    @synchronized(self.resultsByHash)
    {
        //remove
        [self.resultsByHash removeObjectForKey:sha1];

        //dirty
        self.cacheDirty = YES;
    }

    //save (debounced)
    [self scheduleSave];

    return;
}

//is a cache entry expired?
// ->known results are good for VT_CACHE_TTL_KNOWN, 'unknown' (404) ones for VT_CACHE_TTL_UNKNOWN
+(BOOL)isExpired:(NSDictionary*)entry
{
    //age
    NSTimeInterval age = [NSDate date].timeIntervalSince1970 - [entry[@"date"] doubleValue];

    //expired (or from the future)?
    return ( (age < 0) ||
             (age > ((0 == [entry[@"info"] count]) ? VT_CACHE_TTL_UNKNOWN : VT_CACHE_TTL_KNOWN)) );
}

//cached result for a hash (nil if none, or expired)
-(NSDictionary*)cachedResult:(NSString*)sha1
{
    //result
    NSDictionary* result = nil;

    //sync
    @synchronized(self.resultsByHash)
    {
        //entry
        NSDictionary* entry = self.resultsByHash[sha1];

        //expired?
        // ->remove
        if( (nil != entry) &&
            (YES == [VirusTotal isExpired:entry]) )
        {
            //remove
            [self.resultsByHash removeObjectForKey:sha1];

            //dirty
            self.cacheDirty = YES;

            //unset
            entry = nil;
        }

        //grab
        result = entry[@"info"];
    }

    return result;
}

//cache a result (and persist, debounced)
-(void)cacheResult:(NSDictionary*)info forHash:(NSString*)sha1
{
    //sync
    @synchronized(self.resultsByHash)
    {
        //save (with date)
        self.resultsByHash[sha1] = @{@"info": (nil != info) ? info : @{}, @"date": @([NSDate date].timeIntervalSince1970)};

        //dirty
        self.cacheDirty = YES;
    }

    //save (debounced)
    [self scheduleSave];

    return;
}

//path of the (per user) cache file
// ->~/Library/Caches/<bundle id>/VirusTotal.json
+(NSString*)cacheDirectory
{
    //caches dir
    NSString* caches = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
    if(0 == caches.length)
    {
        //bail
        return nil;
    }

    return [caches stringByAppendingPathComponent:APP_ID];
}

//load cache from disk
// ->drops expired entries & anything that doesn't look right (the file is ours, but not trusted blindly)
-(void)loadCache
{
    //error
    NSError* error = nil;

    //data
    NSData* data = nil;

    //json
    NSDictionary* json = nil;

    //(persisted) results
    NSDictionary* results = nil;

    //loaded
    NSUInteger loaded = 0;

    //init path
    self.cachePath = [[VirusTotal cacheDirectory] stringByAppendingPathComponent:VT_CACHE_FILE];
    if(0 == self.cachePath.length)
    {
        //bail
        goto bail;
    }

    //read
    data = [NSData dataWithContentsOfFile:self.cachePath];
    if(0 == data.length)
    {
        //bail
        goto bail;
    }

    //parse
    json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if(YES != [json isKindOfClass:[NSDictionary class]])
    {
        //err msg
        os_log_error(logHandle, "ERROR: VirusTotal cache (%{public}@) is invalid, ignoring", self.cachePath);

        //bail
        goto bail;
    }

    //results
    results = json[@"results"];
    if(YES != [results isKindOfClass:[NSDictionary class]])
    {
        //bail
        goto bail;
    }

    //sync
    @synchronized(self.resultsByHash)
    {
        //add each (valid, unexpired) entry
        for(NSString* sha1 in results)
        {
            //entry
            NSDictionary* entry = results[sha1];

            //info
            NSDictionary* info = nil;

            //sanity check
            if( (YES != [sha1 isKindOfClass:[NSString class]]) ||
                (40 != sha1.length) ||
                (YES != [entry isKindOfClass:[NSDictionary class]]) ||
                (YES != [entry[@"date"] isKindOfClass:[NSNumber class]]) ||
                (YES != [entry[@"info"] isKindOfClass:[NSDictionary class]]) )
            {
                //skip
                continue;
            }

            //info
            info = entry[@"info"];

            //known result? check shape
            if( (0 != info.count) &&
                ( (YES != [info[VT_RESULTS_POSITIVES] isKindOfClass:[NSNumber class]]) ||
                  (YES != [info[VT_RESULTS_TOTAL] isKindOfClass:[NSNumber class]]) ||
                  (YES != [info[VT_RESULTS_URL] isKindOfClass:[NSString class]]) ||
                  (YES != [info[VT_RESULTS_URL] hasPrefix:VT_REPORT_URL]) ) )
            {
                //skip
                continue;
            }

            //expired?
            if(YES == [VirusTotal isExpired:entry])
            {
                //skip
                continue;
            }

            //add
            self.resultsByHash[sha1] = entry;

            //inc
            loaded++;
        }
    }

    //dbg msg
    os_log_debug(logHandle, "VirusTotal: loaded %lu cached result(s) from %{public}@", (unsigned long)loaded, self.cachePath);

    //dropped some (expired/invalid)?
    // ->rewrite the file
    if(loaded != results.count)
    {
        //dirty
        self.cacheDirty = YES;

        //save (debounced)
        [self scheduleSave];
    }

bail:

    return;
}

//schedule a (debounced) save
-(void)scheduleSave
{
    //once per window
    static BOOL scheduled = NO;

    //sync
    @synchronized(self)
    {
        //already scheduled?
        if(YES == scheduled)
        {
            //bail
            return;
        }

        //set
        scheduled = YES;
    }

    //save in a bit
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{

        //sync
        @synchronized(self)
        {
            //reset
            scheduled = NO;
        }

        //save
        [self flushCache];
    });

    return;
}

//save cache to disk (if dirty)
// ->atomic write; capped (oldest entries dropped)
-(void)flushCache
{
    //error
    NSError* error = nil;

    //snapshot
    NSMutableDictionary* results = nil;

    //data
    NSData* data = nil;

    //no path?
    if(0 == self.cachePath.length)
    {
        //bail
        goto bail;
    }

    //sync
    @synchronized(self.resultsByHash)
    {
        //nothing to do?
        if(YES != self.cacheDirty)
        {
            //bail
            goto bail;
        }

        //over the cap?
        // ->drop the oldest
        if(self.resultsByHash.count > VT_CACHE_MAX_ENTRIES)
        {
            //sorted (oldest first)
            NSArray* sorted = [self.resultsByHash keysSortedByValueUsingComparator:^NSComparisonResult(NSDictionary* a, NSDictionary* b) {
                return [a[@"date"] compare:b[@"date"]];
            }];

            //drop
            [self.resultsByHash removeObjectsForKeys:[sorted subarrayWithRange:NSMakeRange(0, self.resultsByHash.count - VT_CACHE_MAX_ENTRIES)]];
        }

        //snapshot
        results = [self.resultsByHash copy];

        //reset
        self.cacheDirty = NO;
    }

    //serialize
    data = [NSJSONSerialization dataWithJSONObject:@{@"version": @1, @"results": results} options:0 error:&error];
    if(nil == data)
    {
        //err msg
        os_log_error(logHandle, "ERROR: failed to serialize VirusTotal cache: %{public}@", error);

        //bail
        goto bail;
    }

    //create directory (0700)
    if(YES != [NSFileManager.defaultManager createDirectoryAtPath:self.cachePath.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions: @0700} error:&error])
    {
        //err msg
        os_log_error(logHandle, "ERROR: failed to create VirusTotal cache directory: %{public}@", error);

        //bail
        goto bail;
    }

    //write (atomically)
    if(YES != [data writeToFile:self.cachePath options:NSDataWritingAtomic error:&error])
    {
        //err msg
        os_log_error(logHandle, "ERROR: failed to write VirusTotal cache: %{public}@", error);

        //bail
        goto bail;
    }

    //dbg msg
    os_log_debug(logHandle, "VirusTotal: saved %lu cached result(s)", (unsigned long)results.count);

bail:

    return;
}

//delete cache (directory)
// ->on uninstall
+(void)deleteCache
{
    //error
    NSError* error = nil;

    //directory
    NSString* directory = [VirusTotal cacheDirectory];
    if(0 == directory.length)
    {
        //bail
        return;
    }

    //remove
    if( (YES == [NSFileManager.defaultManager fileExistsAtPath:directory]) &&
        (YES != [NSFileManager.defaultManager removeItemAtPath:directory error:&error]) )
    {
        //err msg
        os_log_error(logHandle, "ERROR: failed to remove %{public}@: %{public}@", directory, error);
    }

    return;
}

-(void)reload:(Binary*)item
{
    //cmdline mode?
    // ->no UI
    if(YES == cmdlineMode)
    {
        //bail
        goto bail;
    }

    //notify
    notifyBinaryChanged(item);

bail:

    return;
}

//alert the user (once per issue), or print in cmdline mode
-(void)alertOnce:(NSString*)title message:(NSString*)message
{
    //shown
    static NSMutableSet* shown = nil;

    //init
    if(nil == shown) shown = [NSMutableSet set];

    //sync
    @synchronized(shown)
    {
        //already shown?
        if(YES == [shown containsObject:title]) return;

        //save
        [shown addObject:title];
    }

    //cmdline mode?
    // ->just print
    if(YES == cmdlineMode)
    {
        //print
        printf("\nERROR (VirusTotal): %s\n", message.UTF8String);

        //bail
        return;
    }

    //alert (on main thread)
    dispatch_async(dispatch_get_main_queue(), ^{
        showAlert(NSAlertStyleWarning, title, message, @[@"OK"]);
    });

    return;
}

//alert user that api key was rejected
-(void)alertInvalidKey
{
    //masked key (last 4 chars)
    // ->never show the full key
    NSString* maskedKey = (self.apiKey.length > 4) ? [@"..." stringByAppendingString:[self.apiKey substringFromIndex:self.apiKey.length - 4]] : @"...";

    //alert
    [self alertOnce:@"VirusTotal rejected the API key" message:[NSString stringWithFormat:@"The API key (ending in '%@') was rejected (HTTP 401), and is likely invalid.\r\n\r\nPlease (re)enter it via Settings.", maskedKey]];

    return;
}

//alert user that rate limit / quota was hit
-(void)alertRateLimited
{
    //alert
    [self alertOnce:@"VirusTotal rate limit reached" message:@"The API key's rate limit (or daily quota) has been reached. Remaining lookups will resume automatically, in a few minutes."];

    return;
}

//wait (poll, in background) for a submitted file's analysis to complete
// ->VT queues uploads; a lookup right after would find no verdict (or nothing at all), so poll /analyses/<id> first
-(void)waitForAnalysis:(NSString*)analysisID completion:(void (^)(BOOL completed))completion
{
    //in background
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{

        //completed?
        __block BOOL completed = NO;

        //give up?
        __block BOOL giveUp = NO;

        //deadline
        NSDate* deadline = [NSDate dateWithTimeIntervalSinceNow:VT_ANALYSIS_POLL_MAX];

        //poll
        while( (YES != completed) &&
               (YES != giveUp) &&
               (NSOrderedAscending == [[NSDate date] compare:deadline]) )
        {
            //semaphore for synchronous request
            dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

            //request
            NSMutableURLRequest* request = nil;

            //still enabled (key, pref, network)?
            if(YES != [self isEnabled])
            {
                //give up
                break;
            }

            //init request
            request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[VT_ANALYSIS_URL stringByAppendingString:analysisID]]];
            [request setValue:self.apiKey forHTTPHeaderField:@"x-apikey"];

            //request
            [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData* data, NSURLResponse* response, NSError* error) {

                //json
                NSDictionary* json = nil;

                //status
                NSString* status = nil;

                //http status
                NSInteger httpStatus = ((NSHTTPURLResponse*)response).statusCode;

                //ok?
                if( (nil == error) &&
                    (200 == httpStatus) )
                {
                    //parse (type-checked)
                    json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                    if(YES == [json isKindOfClass:[NSDictionary class]])
                    {
                        //status
                        status = [json[@"data"] isKindOfClass:[NSDictionary class]] && [json[@"data"][@"attributes"] isKindOfClass:[NSDictionary class]] ? json[@"data"][@"attributes"][@"status"] : nil;
                        if( (YES == [status isKindOfClass:[NSString class]]) &&
                            (YES == [status isEqualToString:@"completed"]) )
                        {
                            //done
                            completed = YES;
                        }
                    }
                }
                //gone / rejected?
                // ->no point polling on
                else if( (nil == error) &&
                         ( (401 == httpStatus) ||
                           (404 == httpStatus) ) )
                {
                    //err msg
                    os_log_error(logHandle, "ERROR: VirusTotal analysis poll failed (HTTP %ld)", (long)httpStatus);

                    //give up
                    giveUp = YES;
                }

                //signal
                dispatch_semaphore_signal(semaphore);

            }] resume];

            //wait for request
            dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);

            //not done? nap, then poll again
            if( (YES != completed) &&
                (YES != giveUp) )
            {
                //nap
                [NSThread sleepForTimeInterval:VT_ANALYSIS_POLL_INTERVAL];
            }
        }

        //dbg msg
        os_log_debug(logHandle, "VirusTotal: analysis %{public}@ %{public}s", analysisID, (YES == completed) ? "completed" : "not completed (timeout/error), looking up anyway");

        //done
        completion(completed);
    });

    return;
}

//submit a file to VT
// ->completion invoked w/ result dictionary (VT_RESULTS_URL + VT_ANALYSIS_ID, or VT_ERROR)
-(void)submit:(Binary*)item completion:(void (^)(NSDictionary* result))completion
{
    //file descriptor
    int fd = -1;

    //file size
    off_t fileSize = 0;

    //file data
    NSData* fileData = nil;

    //boundary
    NSString* boundary = nil;

    //request
    NSMutableURLRequest* request = nil;

    //body
    NSMutableData* body = nil;

    //task
    NSURLSessionDataTask* task = nil;

    //no api key?
    if(0 == self.apiKey.length)
    {
        //complete w/ error
        completion(@{VT_ERROR:[NSError errorWithDomain:@"VirusTotal" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"API key is blank (set one via Settings)"}]});

        //bail
        goto bail;
    }

    //open file
    // ->must be a regular file (no devices, fifos, etc), 32MB or less (limit for regular endpoint)
    fd = openRegularFile(item.pathForFinder, VT_MAX_SUBMIT_SIZE, &fileSize);
    if(-1 == fd)
    {
        //complete w/ error
        completion(@{VT_ERROR:[NSError errorWithDomain:@"VirusTotal" code:-3 userInfo:@{NSLocalizedDescriptionKey: @"File must be a regular file, 32MB or less (limit of VT endpoint)"}]});

        //bail
        goto bail;
    }

    //read file data
    // ->just what was stat'd, in case file is growing
    @try
    {
        //read
        fileData = [[[NSFileHandle alloc] initWithFileDescriptor:fd closeOnDealloc:YES] readDataOfLength:(NSUInteger)fileSize];
    }
    @catch(NSException* exception)
    {
        //unset
        fileData = nil;
    }

    //sanity check
    if(nil == fileData)
    {
        //complete w/ error
        completion(@{VT_ERROR:[NSError errorWithDomain:@"VirusTotal" code:-4 userInfo:@{NSLocalizedDescriptionKey: @"Could not read file"}]});

        //bail
        goto bail;
    }

    //init boundary
    boundary = [[NSUUID UUID] UUIDString];

    //init request
    request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:VT_SUBMIT_URL]];

    //set method
    [request setHTTPMethod:@"POST"];

    //set api key
    [request setValue:self.apiKey forHTTPHeaderField:@"x-apikey"];

    //set content type
    [request setValue:[NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary] forHTTPHeaderField:@"Content-Type"];

    //init body
    body = [NSMutableData data];

    //add file parameter
    [body appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"file\"; filename=\"%@\"\r\n", item.pathForFinder.lastPathComponent] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[@"Content-Type: application/octet-stream\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:fileData];
    [body appendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];

    //end boundary
    [body appendData:[[NSString stringWithFormat:@"--%@--\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];

    //set body
    [request setHTTPBody:body];

    {
    //init task
    task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData* data, NSURLResponse* response, NSError* error) {

        //http response
        NSHTTPURLResponse* httpResponse = nil;

        //json
        NSDictionary* json = nil;

        //json error
        NSError* jsonError = nil;

        //analysis id
        NSString* analysisID = nil;

        //decoded analysis id
        NSString* decodedID = nil;

        //file hash
        NSString* fileHash = nil;

        //error?
        if(nil != error)
        {
            //complete w/ error
            completion(@{VT_ERROR:error});

            //bail
            return;
        }

        //typecast
        httpResponse = (NSHTTPURLResponse*)response;

        //check status
        if(200 != httpResponse.statusCode)
        {
            //complete w/ error
            completion(@{VT_ERROR:[NSError errorWithDomain:@"VirusTotal" code:httpResponse.statusCode userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"HTTP %ld", (long)httpResponse.statusCode]}]});

            //bail
            return;
        }

        //parse
        json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        if( (nil != jsonError) ||
            (YES != [json isKindOfClass:[NSDictionary class]]) )
        {
            //complete w/ error
            completion(@{VT_ERROR:[NSError errorWithDomain:@"VirusTotal" code:-5 userInfo:@{NSLocalizedDescriptionKey: @"Invalid JSON response"}]});

            //bail
            return;
        }

        //extract analysis id
        // ->base64 of "<sha256>:<timestamp>"
        analysisID = ([json[@"data"] isKindOfClass:[NSDictionary class]] && [json[@"data"][@"id"] isKindOfClass:[NSString class]]) ? json[@"data"][@"id"] : nil;
        if(0 == analysisID.length)
        {
            //err msg
            os_log_error(logHandle, "ERROR: VirusTotal submission response is missing analysis id");

            //bail
            completion(@{VT_ERROR:[NSError errorWithDomain:@"VirusTotal" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Unexpected response from VirusTotal"}]});
            return;
        }

        //decode
        decodedID = [[NSString alloc] initWithData:[[NSData alloc] initWithBase64EncodedString:analysisID options:0] encoding:NSUTF8StringEncoding];

        //extract hash
        fileHash = [decodedID componentsSeparatedByString:@":"].firstObject;
        if(0 == fileHash.length)
        {
            //complete w/ error
            completion(@{VT_ERROR:[NSError errorWithDomain:@"VirusTotal" code:-6 userInfo:@{NSLocalizedDescriptionKey: @"Failed to decode analysis ID"}]});

            //bail
            return;
        }

        //complete w/ report url (& analysis id, so the caller can wait for the analysis)
        completion(@{VT_RESULTS_URL: [VT_REPORT_URL stringByAppendingString:fileHash], VT_ANALYSIS_ID: analysisID});
    }];

    //start
    [task resume];
    }

bail:

    return;
}

@end
