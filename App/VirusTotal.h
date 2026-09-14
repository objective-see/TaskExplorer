//
//  VirusTotal.h
//  TaskExplorer
//
//  Created by Patrick Wardle on 3/8/15.
//  Copyright (c) 2015 Objective-See. All rights reserved.
//
//  note: uses VirusTotal's (v3) API, w/ the user's own API key (stored in the keychain)

#import "Binary.h"
#import <Foundation/Foundation.h>

/* GLOBALS */

//cmdline flag
extern BOOL cmdlineMode;

//network connected flag

@interface VirusTotal : NSObject
{

}

/* PROPERTIES */

//api key
// ->loaded from keychain (or specified via cmdline)
@property(atomic, retain)NSString* apiKey;

//queue of items to lookup
@property(nonatomic, retain)NSMutableArray* items;

//condition for queue
@property(nonatomic, retain)NSCondition* queueCondition;

//items deferred (rate limited / network error)
// ->re-queued once 'retryAfter' passes (or the key is reloaded); cached results keep flowing meanwhile
@property(nonatomic, retain)NSMutableArray* deferred;

//no (network) lookups before this date
// ->set on HTTP 429 (escalating backoff: 15s, 30s, 60s, then 15 minutes = daily quota) or a network error
@property(atomic, retain)NSDate* retryAfter;

//consecutive rate limit (HTTP 429) responses
@property NSUInteger rateLimitHits;

//flag
// ->api key was rejected (HTTP 401); cleared when the key is reloaded
@property BOOL keyRejected;

//flag
// ->worker is busy (processing an item)
@property BOOL isBusy;

//results, by (sha1) hash: sha1 -> @{@"info": <vt info>, @"date": <epoch>}
// ->so identical binaries (e.g. same file at multiple paths) are only looked up once, and (persisted, with a ttl)
//   so relaunches don't repeat every lookup
@property(nonatomic, retain)NSMutableDictionary* resultsByHash;

//cache needs saving?
@property BOOL cacheDirty;

//cache path (nil in cmdline mode w/o a home, etc)
@property(atomic, retain)NSString* cachePath;

/* METHODS */

//(re)load api key from keychain
-(void)reloadAPIKey;

//is VT enabled?
// ->api key, and not disabled (pref)
-(BOOL)isEnabled;

//add item
// ->will be looked up (in background) by worker thread
-(void)addItem:(Binary*)binary;

//save results cache (if dirty)
// ->e.g. on quit
-(void)flushCache;

//delete results cache (file)
// ->e.g. on uninstall
+(void)deleteCache;

//forget cached result (for hash of binary)
// ->e.g. after a submission, so the next lookup hits VirusTotal again
-(void)forgetResult:(Binary*)binary;

//(re)queue all known binaries that don't have VT results
// ->e.g. when user just added an api key
-(void)requeueAll;

//lookup an item (synchronously)
// ->sets item's 'vtInfo', flags item, & reloads UI
-(void)lookup:(Binary*)item;

//submit a file to VT
// ->completion invoked w/ result dictionary (VT_RESULTS_URL + VT_ANALYSIS_ID, or VT_ERROR)
-(void)submit:(Binary*)item completion:(void (^)(NSDictionary* result))completion;

//wait (poll, in background) for a submitted file's analysis to complete
// ->completion invoked (on a background queue) once it's completed, or polling gave up (timeout, error, VT disabled)
-(void)waitForAnalysis:(NSString*)analysisID completion:(void (^)(BOOL completed))completion;

@end
