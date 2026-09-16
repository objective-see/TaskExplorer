//
//  Binary.m
//  TaskExplorer
//
//  Created by Patrick Wardle on 2/19/15.
//  Copyright (c) 2015 Objective-See. All rights reserved.
//

#import "Binary.h"
#import "Consts.h"
#import "Signing.h"
#import "Utilities.h"
#import "AppDelegate.h"
#import "TaskEnumerator.h"

#import <os/log.h>

//log handle
extern os_log_t logHandle;

//(shared) icon for dyld shared cache dylibs
// ->they have no file on disk; all get the generic dylib icon, and there are ~1200 per process
static NSImage* sharedCacheDylibIcon(void)
{
    //icon
    static NSImage* icon = nil;

    //once
    static dispatch_once_t onceToken = 0;
    dispatch_once(&onceToken, ^{
        icon = [[NSWorkspace sharedWorkspace] iconForFile:@"/usr/lib/libSystem.B.dylib"];
    });

    return icon;
}

@implementation Binary

@synthesize path;
@synthesize name;
@synthesize icon;
@synthesize bundle;
@synthesize hashes;
@synthesize vtInfo;
@synthesize isPacked;
@synthesize notFound;
@synthesize isEncrypted;
@synthesize signingInfo;
@synthesize isTaskBinary;

//init method
-(id)initWithParams:(NSDictionary*)params
{
    //super
    // ->saves path, etc
    self = [super initWithParams:params];
    if(self)
    {
        //since path is always full path to binary
        // ->manaully try to find & load bundle (for .apps)
        self.bundle = findAppBundle(self.path);

        /* now we have bundle (maybe), try get name and icon */

        //get task's name
        // ->either from bundle or path's last component
        self.name = [self getName];

        //is in dyld cache
        // ->determined first, as such dylibs share one (generic) icon; ~1200 per process, so no per-object image
        self.inCache = isInSharedCache(self.path);

        //get task's icon
        // ->either from bundle or just use system icon
        self.icon = (YES == self.inCache) ? sharedCacheDylibIcon() : [self getIcon];


        //determine if its on disk
        // though ignore files in dyld cache
        if(YES != self.inCache)
        {
            //set
            self.notFound = ![[NSFileManager defaultManager] fileExistsAtPath:self.path];
        }

        //get attributes
        self.attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:self.path error:nil];
    }

//bail
bail:

    return self;
}

//machO parse
//get task's name
// ->either from bundle or path's last component
-(NSString*)getName
{
    //name
    NSString* taskName = nil;

    //try to get name from bundle
    // ->key 'CFBundleName' (some system frameworks, e.g. MLCompilerRuntime, set it to an empty string; treat as unset)
    if(nil != self.bundle)
    {
        //extract name
        taskName = [self.bundle infoDictionary][@"CFBundleName"];
        if( (YES != [taskName isKindOfClass:[NSString class]]) ||
            (0 == [taskName length]) )
        {
            //unset
            taskName = nil;
        }
    }

    //no bundle/ or bundle lookup failed
    // ->just use last component of path
    if(nil == taskName)
    {
        //special case
        // ->kernel -> 'kernel_task'
        if(YES == [self.path isEqualToString:path2Kernel()])
        {
            //set kernel
            taskName = @"kernel_task";
        }
        //default
        // ->name is just last component of path
        else
        {
            //extract name
            taskName = [self.path lastPathComponent];
        }
    }

    return taskName;
}

//get an icon for a process
// ->for apps, this will be app's icon, otherwise just a standard system one
-(NSImage*)getIcon
{
    //icon's file name
    NSString* iconFile = nil;

    //icon's path
    NSString* iconPath = nil;

    //icon's path extension
    NSString* iconExtension = nil;

    //icon
    NSImage* taskIcon = nil;

    //for app's
    // ->extract their icon
    if(nil != self.bundle)
    {
        //get file
        iconFile = self.bundle.infoDictionary[@"CFBundleIconFile"];

        //get path extension
        iconExtension = [iconFile pathExtension];

        //if its blank (i.e. not specified)
        // ->go with 'icns'
        if(YES == [iconExtension isEqualTo:@""])
        {
            //set type
            iconExtension = @"icns";
        }

        //set full path
        iconPath = [self.bundle pathForResource:[iconFile stringByDeletingPathExtension] ofType:iconExtension];

        //load it
        taskIcon = [[NSImage alloc] initWithContentsOfFile:iconPath];
    }

    //process is not an app or couldn't get icon
    // ->try to get it via shared workspace
    if( (nil == self.bundle) ||
        (nil == taskIcon) )
    {
        //extract icon
        taskIcon = [[NSWorkspace sharedWorkspace] iconForFile:self.path];
    }

    return taskIcon;
}

//get signing info (which takes a while to generate)
// ->this method should be called in the background
-(void)generatedSigningInfo
{
    //generate (statically)
    [self generateInfo:0 auditToken:nil];

    return;
}

//generate (binary) info via the extension: signing info, hashes, & mach-o flags
// ->all done by the extension (as root), since the app can't read everything (e.g. 0511 root binaries)
-(void)generateInfo:(pid_t)pid auditToken:(NSData*)auditToken
{
    //binary info
    NSDictionary* binaryInfo = nil;

    //sync
    // ->only for the checks & publishing; the XPC call itself runs outside the lock (never block others on I/O)
    @synchronized(self)
    {
        //already generated (or another thread is generating)?
        // ->unless it was an (XPC) error, which is worth retrying (e.g. extension was being replaced)
        if( (YES == self.generatingInfo) ||
            ( (nil != self.signingInfo) &&
              (SIGNING_STATUS_XPC_FAILED != [self.signingInfo[KEY_SIGNATURE_STATUS] intValue]) ) )
        {
            //bail
            goto bail;
        }

        //in the dyld shared cache?
        // ->no file on disk to check; the cache is Apple's (and only Apple's), so synthesize
        if(YES == self.inCache)
        {
            //set
            self.signingInfo = @{KEY_SIGNATURE_STATUS:@(errSecSuccess), KEY_SIGNATURE_SIGNER:@(Apple)};

            //bail
            goto bail;
        }

        //set flag
        self.generatingInfo = YES;
    }

    //via extension (outside the lock)
    binaryInfo = [taskEnumerator.xpcClient extractBinaryInfo:pid auditToken:auditToken path:self.path];

    //sync
    // ->publish
    @synchronized(self)
    {
        //failed?
        if( (nil == binaryInfo) ||
            (nil == binaryInfo[KEY_BINARY_SIGNING_INFO]) )
        {
            //err msg
            os_log_error(logHandle, "ERROR: extension failed to extract binary info for %{public}@ (%d)", self.path, pid);

            //set error
            self.signingInfo = @{KEY_SIGNATURE_STATUS:@(SIGNING_STATUS_XPC_FAILED)};
        }
        //ok
        else
        {
            //save signing info
            self.signingInfo = binaryInfo[KEY_BINARY_SIGNING_INFO];

            //save flags
            self.isEncrypted = [binaryInfo[KEY_BINARY_ENCRYPTED] boolValue];
            self.isPacked = [binaryInfo[KEY_BINARY_PACKED] boolValue];
        }

        //unset flag
        self.generatingInfo = NO;
    }

bail:

    return;
}

//get detailed info (which takes a while to generate)
// ->only shown to user if they click 'info' so this method should be called in the background
-(void)generateDetailedInfo
{
    //grab file attributes
    self.attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:self.path error:nil];

    //(re)check if it's still on disk
    // ->a binary that unlinks itself after exec (classic dropper behavior) was there when first seen
    if(YES != self.inCache)
    {
        //set
        self.notFound = (nil == self.attributes);
    }

    //generate (binary) info
    // ->signing info & mach-o flags (no-op if already done)
    [self generateInfo:0 auditToken:nil];

    //hashes
    // ->via extension (as root), as the app can't read everything; skip shared cache dylibs (no file on disk)
    if( (nil == self.hashes) &&
        (YES != self.inCache) )
    {
        //hash
        self.hashes = [taskEnumerator.xpcClient hashFile:self.path];
    }

    return;
}

//format the signing info dictionary
-(NSString*)formatSigningInfo
{
    //pretty print
    NSMutableString* prettyPrint = nil;

    //sanity check
    if(nil == self.signingInfo)
    {
        //bail
        goto bail;
    }

    //switch on signing status
    switch([self.signingInfo[KEY_SIGNATURE_STATUS] integerValue])
    {
        //unsigned
        case errSecCSUnsigned:
        {
            //set string
            prettyPrint = [NSMutableString stringWithString:@"unsigned"];

            //brk
            break;
        }

        //errSecCSSignatureFailed
        case errSecCSSignatureFailed:
        {
            //set string
            prettyPrint = [NSMutableString stringWithString:@"invalid signature"];

            //brk
            break;
        }

        //happily signed
        case STATUS_SUCCESS:
        {
            //init
            prettyPrint = [NSMutableString string];//stringWithString:@"signed by:"];

            //add each signing auth
            for(NSString* signingAuthority in self.signingInfo[KEY_SIGNATURE_AUTHORITIES])
            {
                //append
                [prettyPrint appendString:[NSString stringWithFormat:@"%@, ", signingAuthority]];
            }

            //remove last comma & space
            if(YES == [prettyPrint hasSuffix:@", "])
            {
                //remove
                [prettyPrint deleteCharactersInRange:NSMakeRange([prettyPrint length]-2, 2)];
            }

            //brk
            break;
        }

        //unknown
        default:

            //set string
            prettyPrint = [NSMutableString stringWithFormat:@"unknown (status/error: %ld)", (long)[self.signingInfo[KEY_SIGNATURE_STATUS] integerValue]];

            //brk
            break;
    }

//bail
bail:

    return prettyPrint;
}

//loaded in
// ->host tasks (resolved from 'hosts')
-(NSArray*)loadedIn
{
    return [self hostTasks];
}

/* (KVC) QUERY PROPERTIES */

//signer (enum Signer)
-(NSNumber*)signer
{
    //no signing info (yet)?
    // ->nil (pending); note: never generate here, as the UI reads this on the main thread
    //   (generation is a synchronous XPC call to the extension, done by the enumeration thread / queue)
    if(nil == self.signingInfo)
    {
        //pending
        return nil;
    }

    return (errSecSuccess == [self.signingInfo[KEY_SIGNATURE_STATUS] intValue]) ? self.signingInfo[KEY_SIGNATURE_SIGNER] : [NSNumber numberWithInt:None];
}

//signed by apple (or in dyld shared cache, or the kernel)
-(BOOL)isApple
{
    return ( (YES == self.inCache) ||
             (YES == [self.path isEqualToString:path2Kernel()]) ||
             (Apple == [self.signer intValue]) );
}

//validly signed (or in dyld shared cache)
-(BOOL)isExcludedFromVT
{
    //note: a (temporarily) failed signing check is 'unknown', not 'non-Apple'; it's retried, so don't spend VT quota yet
    return ( (YES == self.inCache) ||
             (YES == self.isPlatformBinary) ||
             (YES == self.isApple) ||
             (SIGNING_STATUS_XPC_FAILED == [self.signingInfo[KEY_SIGNATURE_STATUS] intValue]) );
}

-(BOOL)isSigned
{
    //note: 'isApple' covers dyld cache & the kernel (which has no signature to check)
    return ( (YES == self.isApple) ||
             (None != [self.signer intValue]) );
}

//flagged by VT
-(BOOL)isFlagged
{
    return ( (nil != self.vtInfo) &&
             (0 != [self.vtInfo[VT_RESULTS_POSITIVES] unsignedIntegerValue]) );
}

//unknown to VT
// ->looked up, but no results
-(BOOL)isUnknownToVT
{
    return ( (nil != self.vtInfo) &&
             (0 == self.vtInfo.count) );
}

//team id (from signing info)
-(NSString*)teamID
{
    return self.signingInfo[KEY_SIGNATURE_TEAM_ID];
}

//signing id (from signing info)
-(NSString*)signingID
{
    return self.signingInfo[KEY_SIGNATURE_IDENTIFIER];
}

//override method
// ->hash
-(NSUInteger)hash
{
    return [self.path hash];
}

//override method
// ->equality check
-(BOOL)isEqual:(id)object
{
    //flag
    BOOL objEqual = NO;

    //check self
    if(self == object)
    {
        //match
        objEqual = YES;

        //bail
        goto bail;
    }

    //check for type
    if(YES != [object isKindOfClass:[Binary class]])
    {
        //no match
        objEqual = NO;

        //bail
        goto bail;
    }

    //do check
    if(YES == [((Binary*)object).path isEqualToString:self.path])
    {
        //happy
        objEqual = YES;

        //bail
        goto bail;
    }

//bail
bail:

    return objEqual;
}

//convert object to JSON string
-(NSString*)toJSON
{
    //json string
    NSMutableString *json = nil;

    //json data
    // for intermediate conversions
    NSData *jsonData = nil;

    //hashes
    NSString* fileHashes = nil;

    //signing info
    NSString* fileSigs = nil;

    //VT detection ratio
    NSString* vtDetectionRatio = nil;

    //tasks loaded in
    NSMutableArray* taskPids = nil;

    //'loaded in' list
    NSString* tasks = nil;

    //init file hash to default string
    // used when hashes are nil, or serialization fails
    fileHashes = @"\"unknown\"";

    //init file signature to default string
    // used when signatures are nil, or serialization fails
    fileSigs = @"\"unknown\"";

    //convert hashes to JSON
    if(nil != self.hashes)
    {
        //convert hash dictionary
        // wrap since we are serializing JSON
        @try
        {
            //convert
            jsonData = [NSJSONSerialization dataWithJSONObject:self.hashes options:kNilOptions error:NULL];
            if(nil != jsonData)
            {
                //convert data to string
                fileHashes = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
            }
        }
        //ignore exceptions
        // file hashes will just be 'unknown'
        @catch(NSException *exception)
        {
            ;
        }
    }

    //convert signing dictionary to JSON
    if(nil != self.signingInfo)
    {
        //convert signing dictionary
        // wrap since we are serializing JSON
        @try
        {
            //convert
            jsonData = [NSJSONSerialization dataWithJSONObject:self.signingInfo options:kNilOptions error:NULL];
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

    //dylibs
    //covert 'loaded in' array to JSON
    if(YES != isTaskBinary)
    {
        //init
        taskPids = [NSMutableArray array];

        //tasks loaded in
        for(Task* task in self.loadedIn)
        {
            //add pid
            [taskPids addObject:task.pid];
        }

        //wrap since we are serializing JSON
        @try
        {
            //convert
            jsonData = [NSJSONSerialization dataWithJSONObject:taskPids options:kNilOptions error:NULL];
            if(nil != jsonData)
            {
                //convert data to string
                tasks = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
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
    vtDetectionRatio = [NSString stringWithFormat:@"%lu/%lu", (unsigned long)[self.vtInfo[VT_RESULTS_POSITIVES] unsignedIntegerValue], (unsigned long)[self.vtInfo[VT_RESULTS_TOTAL] unsignedIntegerValue]];

    //init json
    json = [NSMutableString stringWithFormat:@"\"name\": \"%@\", \"path\": \"%@\", \"hashes\": %@, \"signature(s)\": %@, \"VT detection\": \"%@\", \"encrypted\": %s, \"packed\": %s, \"deleted\": %s", jsonEscape(self.name), jsonEscape(self.path), fileHashes, fileSigs, vtDetectionRatio, (YES == self.isEncrypted) ? "true" : "false", (YES == self.isPacked) ? "true" : "false", (YES == self.notFound) ? "true" : "false"];

    //dylibs
    // add tasks they are loaded in
    if(YES != self.isTaskBinary)
    {
        //add
        [json appendString:[NSString stringWithFormat:@", \"loaded in\": %@", (nil != tasks) ? tasks : @"[]"]];
    }

    return json;
}

@end
