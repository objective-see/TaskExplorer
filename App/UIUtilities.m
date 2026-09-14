//
//  UIUtilities.m
//  TaskExplorer (app)
//
//  Created by Patrick Wardle on 2/7/15.
//  Copyright (c) 2015 Objective-See. All rights reserved.
//
//  note: app-only (AppKit) helpers
//        (shared helpers live in Shared/Utilities.m)

#import "Consts.h"
#import "Utilities.h"
#import "UIUtilities.h"

#import <dlfcn.h>
#import <unistd.h>
#import <Security/Security.h>
#import <Foundation/Foundation.h>
#import <CoreServices/CoreServices.h>
#import <Collaboration/Collaboration.h>

//get all users
// includes name/home directory
static NSMutableDictionary* allUsers(void);





//check if app is translocated
// ->based on http://lapcatsoftware.com/articles/detect-app-translocation.html
NSURL* getUnTranslocatedURL(void)
{
    //orignal URL
    NSURL* untranslocatedURL = nil;

    //function def for 'SecTranslocateIsTranslocatedURL'
    Boolean (*mySecTranslocateIsTranslocatedURL)(CFURLRef path, bool *isTranslocated, CFErrorRef * __nullable error);

    //function def for 'SecTranslocateCreateOriginalPathForURL'
    CFURLRef __nullable (*mySecTranslocateCreateOriginalPathForURL)(CFURLRef translocatedPath, CFErrorRef * __nullable error);

    //flag for API request
    bool isTranslocated = false;

    //handle for security framework
    void *handle = NULL;

    //app path
    NSURL* appPath = nil;

    //init app's path
    appPath = [NSURL fileURLWithPath:[[NSBundle mainBundle] bundlePath]];

    //open security framework
    handle = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY);
    if(NULL == handle)
    {
        //bail
        goto bail;
    }

    //get 'SecTranslocateIsTranslocatedURL' API
    mySecTranslocateIsTranslocatedURL = dlsym(handle, "SecTranslocateIsTranslocatedURL");
    if(NULL == mySecTranslocateIsTranslocatedURL)
    {
        //bail
        goto bail;
    }

    //get
    mySecTranslocateCreateOriginalPathForURL = dlsym(handle, "SecTranslocateCreateOriginalPathForURL");
    if(NULL == mySecTranslocateCreateOriginalPathForURL)
    {
        //bail
        goto bail;
    }

    //invoke it
    if(true != mySecTranslocateIsTranslocatedURL((__bridge CFURLRef)appPath, &isTranslocated, NULL))
    {
        //bail
        goto bail;
    }

    //bail if app isn't translocated
    if(true != isTranslocated)
    {
        //bail
        goto bail;
    }

    //get original URL
    untranslocatedURL = (__bridge NSURL*)mySecTranslocateCreateOriginalPathForURL((__bridge CFURLRef)appPath, NULL);

//bail
bail:

    //close handle
    if(NULL != handle)
    {
        //close
        dlclose(handle);
    }

    return untranslocatedURL;
}

//get all user
// includes name/home directory
static NSMutableDictionary* allUsers(void)
{
    //users
    NSMutableDictionary* users = nil;

    //query
    CSIdentityQueryRef query = nil;

    //query results
    CFArrayRef results = NULL;

    //error
    CFErrorRef error = NULL;

    //identiry
    CBIdentity* identity = NULL;

    //alloc dictionary
    users = [NSMutableDictionary dictionary];

    //init query
    query = CSIdentityQueryCreate(NULL, kCSIdentityClassUser, CSGetLocalIdentityAuthority());

    //exec query
    if(true != CSIdentityQueryExecute(query, 0, &error))
    {
        //bail
        goto bail;
    }

    //grab results
    results = CSIdentityQueryCopyResults(query);

    //process all results
    // add user and home directory
    for (int i = 0; i < CFArrayGetCount(results); ++i)
    {
        //grab identity
        identity = [CBIdentity identityWithCSIdentity:(CSIdentityRef)CFArrayGetValueAtIndex(results, i)];

        //add user
        users[identity.UUIDString] = @{USER_NAME:identity.posixName, USER_DIRECTORY:NSHomeDirectoryForUser(identity.posixName)};
    }

bail:

    //release results
    if(NULL != results)
    {
        //release
        CFRelease(results);
    }

    //release query
    if(NULL != query)
    {
        //release
        CFRelease(query);
    }

    return users;
}

//give a list of paths
// convert any `~` to all or current user
NSMutableArray* expandPaths(const __strong NSString* const paths[], int count)
{
    //expanded paths
    NSMutableArray* expandedPaths = nil;

    //(current) path
    const NSString* path = nil;

    //all users
    NSMutableDictionary* users = nil;

    //grab all users
    users = allUsers();

    //alloc list
    expandedPaths = [NSMutableArray array];

    //iterate/expand
    for(NSInteger i = 0; i < count; i++)
    {
        //grab path
        path = paths[i];

        //no `~`?
        // just add and continue
        if(YES != [path hasPrefix:@"~"])
        {
            //add as is
            [expandedPaths addObject:path];

            //next
            continue;
        }

        //handle '~' case
        // root? add each user
        if(0 == geteuid())
        {
            //add each user
            for(NSString* user in users)
            {
                [expandedPaths addObject:[users[user][USER_DIRECTORY] stringByAppendingPathComponent:[path substringFromIndex:1]]];
            }
        }
        //otherwise
        // just convert to current user
        else
        {
            [expandedPaths addObject:[path stringByExpandingTildeInPath]];
        }
    }

    return expandedPaths;
}


//bring an app to foreground (to get an icon in the dock) or background
void transformProcess(ProcessApplicationTransformState location)
{
    //process serial no
    ProcessSerialNumber processSerialNo;

    //init process stuct
    // ->high to 0
    processSerialNo.highLongOfPSN = 0;

    //init process stuct
    // ->low to self
    processSerialNo.lowLongOfPSN = kCurrentProcess;

    //transform to foreground
    TransformProcessType(&processSerialNo, location);

    return;
}

//show an alert
NSModalResponse showAlert(NSAlertStyle style, NSString* messageText, NSString* informativeText, NSArray* buttons)
{
    //alert
    NSAlert* alert = nil;

    //response
    NSModalResponse response = 0;

    //init alert
    alert = [[NSAlert alloc] init];

    //set style
    alert.alertStyle = style;

    //set main text
    alert.messageText = messageText;

    //set detailed text
    alert.informativeText = informativeText;

    //add buttons
    for(NSString* title in buttons)
    {
        //add
        [alert addButtonWithTitle:title];
    }

    //make app active
    [NSApp activateIgnoringOtherApps:YES];

    //show
    response = [alert runModal];

    return response;
}

//check for full disk access
// ->no API for this, so just try to read a (TCC) protected file
BOOL hasFullDiskAccess(void)
{
    //flag
    BOOL hasFDA = NO;
    
    //protected file
    // ->user's TCC database
    NSString* protectedFile = nil;
    
    //init
    protectedFile = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/com.apple.TCC/TCC.db"];
    
    //readable?
    hasFDA = [[NSFileManager defaultManager] isReadableFileAtPath:protectedFile];
    
    return hasFDA;
}

//(registered) preference defaults
NSDictionary* preferenceDefaults(void)
{
    return @{PREF_DISABLE_VT_QUERIES:@NO};
}

//get a (bool) preference (or its registered default)
BOOL getPreferenceBool(NSString* key)
{
    //value
    id value = nil;
    
    //read
    value = [NSUserDefaults.standardUserDefaults objectForKey:key];
    
    //unset?
    // use registered default
    if(nil == value)
    {
        //default
        value = preferenceDefaults()[key];
    }
    
    //bool (or number)?
    if(YES == [value isKindOfClass:[NSNumber class]])
    {
        return [value boolValue];
    }
    
    return NO;
}

//set a preference
void setPreference(NSString* key, id value)
{
    //write
    [NSUserDefaults.standardUserDefaults setObject:value forKey:key];
    
    return;
}
