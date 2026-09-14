//
//  main.m
//  TaskExplorer
//
//  Created by Patrick Wardle
//  Copyright (c) 2015 Objective-See. All rights reserved.
//

//FOR LOGGING:
// % log stream --level debug --predicate="subsystem='com.objective-see.taskexplorer'"

#import "main.h"
#import "Extension.h"
#import "TaskExplorer-Swift.h"

//main interface
// contains extra logic to handle app translocation
int main(int argc, char *argv[])
{
    //return
    int status = -1;

    //untranslocated URL
    NSURL* untranslocatedURL = nil;

    //init log
    logHandle = os_log_create(BUNDLE_ID, "app");

    //get original url
    untranslocatedURL = getUnTranslocatedURL();
    if(nil != untranslocatedURL)
    {
        //remove quarantine attributes of original
        execTask(XATTR, @[@"-cr", untranslocatedURL.path], NO);

        //nap
        [NSThread sleepForTimeInterval:0.5];

        //relaunch
        // use 'open' since allows two instances of app to be run
        execTask(OPEN, @[@"-n", @"-a", untranslocatedURL.path], NO);

        //happy
        status = 0;

        //bail
        goto bail;
    }

    //init set of (privacy) protected directories
    // these will be skipped, as otherwise we will generate a privacy prompt
    protectedDirectories = expandPaths(PROTECTED_DIRECTORIES, sizeof(PROTECTED_DIRECTORIES)/sizeof(PROTECTED_DIRECTORIES[0]));

    //handle '-h' or '-help'
    if( (YES == [[[NSProcessInfo processInfo] arguments] containsObject:@"-h"]) ||
        (YES == [[[NSProcessInfo processInfo] arguments] containsObject:@"-help"]) )
    {
        //print usage
        usage();

        //done
        goto bail;
    }

    //handle cmdline
    // scan, explore, etc
    if( (YES == [[[NSProcessInfo processInfo] arguments] containsObject:@"-scan"]) ||
        (YES == [[[NSProcessInfo processInfo] arguments] containsObject:@"-explore"]) )

    {
        //set flag
        cmdlineMode = YES;

        //cli
        cmdlineInterface();

        //happy
        status = 0;

        //done
        goto bail;
    }

    //otherwise
    // just kick off app for UI instance
    else
    {
        //set flag
        cmdlineMode = NO;

        //make foreground so it has an dock icon, etc
        transformProcess(kProcessTransformToForegroundApplication);

        //set (app) delegate
        // ->no main nib, so must be done manually (and retained, as 'delegate' is weak)
        appDelegate = [[AppDelegate alloc] init];
        //note: our NSApplication subclass (routes ⌘X/C/V/A/Z without an Edit menu); creating it here is what makes it
        //      the shared app, as 'NSApplicationMain' only honors NSPrincipalClass when no app object exists yet
        [TaskExplorerApplication sharedApplication].delegate = appDelegate;

        //invoke app's main
        status = NSApplicationMain(argc, (const char **)argv);
    }

bail:

    return status;
}


//print usage
void usage(void)
{
    //usage
    printf("\nTASKEXPLORER USAGE:\n");
    printf(" -h or -help  display this usage info\n");
    printf(" -scan        scan all tasks and dylibs \n");
    printf(" -explore     enumerate all tasks and dylibs\n");
    printf("\noptions:\n");
    printf(" -pretty      json output is 'pretty-printed'\n");
    printf(" -pid [pid]   just scan/explore the specified task\n");
    printf(" -skipVT      do not query VirusTotal (when '-explore' is specified)\n");
    printf(" -key [key]   VirusTotal API key (default: key saved via app's preferences)\n");
    printf(" -detailed    for each task; include dylibs, files, & network connections\n");
    printf("\nnote: requires TaskExplorer's system extension to be installed & approved (run the app once)\n\n");

    return;
}

//perform a cmdline interface
void cmdlineInterface(void)
{
    //args
    NSArray* arguments = nil;

    //xpc client
    XPCExtensionClient* xpcClient = nil;

    //flag
    BOOL includeApple = NO;

    //flag
    BOOL skipVirusTotal = NO;

    //flag
    BOOL prettyPrint = NO;

    //flag
    BOOL detailed = NO;

    //output
    NSMutableString* output = nil;

    //formatter
    NSNumberFormatter* formatter = nil;

    //pid
    // if single task was specified
    NSNumber* pid = nil;

    //grab args
    arguments = [[NSProcessInfo processInfo] arguments];

    //Apple: item's w/ System Extensions must be run from /Applications
    if(YES != [NSBundle.mainBundle.bundlePath hasPrefix:@"/Applications/"])
    {
        //err msg
        printf("{\"ERROR\": \"TASKEXPLORER (cmdline) must be run from within /Applications\"}\n");

        //bail
        goto bail;
    }

    //activate extension
    // note: must have been approved (via the app) already
    if(YES != activateExtension())
    {
        //err msg
        printf("{\"ERROR\": \"TASKEXPLORER (cmdline) failed to activate system extension (is it approved? ...run the app once)\"}\n");

        //bail
        goto bail;
    }

    //init xpc client
    xpcClient = [[XPCExtensionClient alloc] init];

    //wait for extension
    if(YES != [xpcClient waitForExtension:40])
    {
        //err msg
        printf("{\"ERROR\": \"TASKEXPLORER (cmdline) failed to connect to system extension (is it approved? ...run the app once)\"}\n");

        //bail
        goto bail;
    }

    //init task enumerator object
    taskEnumerator = [[TaskEnumerator alloc] initWithClient:xpcClient];

    //set flag
    // skip virus total?
    skipVirusTotal = [arguments containsObject:@"-skipVT"];

    //virus total?
    if(YES != skipVirusTotal)
    {
        //init virus total object
        // ->loads api key from keychain
        virusTotal = [[VirusTotal alloc] init];

        //api key specified via cmdline?
        if( (YES == [arguments containsObject:@"-key"]) &&
            (YES != [@"-key" isEqualToString:arguments.lastObject]) )
        {
            //set
            virusTotal.apiKey = arguments[[arguments indexOfObject:@"-key"] + 1];
        }

        //no key?
        // ->warn (and skip VT)
        if(0 == virusTotal.apiKey.length)
        {
            //err msg
            fprintf(stderr, "NOTE: no VirusTotal API key (specify via '-key', or save one via the app's preferences), skipping VirusTotal\n");

            //skip
            skipVirusTotal = YES;
        }
    }

    //be nice
    nice(15);

    //scan just one pid?
    if( (YES == [arguments containsObject:@"-pid"]) &&
        (YES != [@"-pid" isEqualToString:arguments.lastObject]) )
    {
        //init formatter
        formatter = [[NSNumberFormatter alloc] init];

        //set style
        formatter.numberStyle = NSNumberFormatterDecimalStyle;

        //extract/convert pid
        pid = [formatter numberFromString:arguments[[arguments indexOfObject:@"-pid"] + 1]];

        //sanity check
        if( (nil == pid) ||
            (YES != isAlive(pid.intValue)) )
        {
            //err msg
            printf("{\"ERROR\" : \"specified pid, %s, does not exist\"}\n", [arguments[[arguments indexOfObject:@"-pid"] + 1] UTF8String]);

            //bail
            goto bail;
        }
    }

    //enumerate all tasks/dylibs/files/etc
    [taskEnumerator enumerateTasks:pid];

    //wait for items to complete processing
    while(taskEnumerator.binaryQueue.itemsIn != taskEnumerator.binaryQueue.itemsOut)
    {
        //nap
        [NSThread sleepForTimeInterval:1.0f];
    }

    //wait for all VT threads to exit
    if(YES != skipVirusTotal)
    {
        //wait
        completeVTQuery();
    }

    //set flag
    // include apple items?
    includeApple = [arguments containsObject:@"-apple"];

    //set flag
    // pretty print json?
    prettyPrint = [arguments containsObject:@"-pretty"];

    //set flag
    // full output?
    detailed = [arguments containsObject:@"-detailed"];

    //alloc output JSON
    output = [NSMutableString string];

    //only flagged items?
    if(YES == [arguments containsObject:@"-scan"])
    {
        //start JSON
        [output appendString:@"{\"flagged items\":["];

        //add each item
        for(Binary* flaggedItem in taskEnumerator.flaggedItems)
        {
            [output appendFormat:@"{%@},", [flaggedItem toJSON]];
        }

        //remove last ','
        if(YES == [output hasSuffix:@","])
        {
            //remove
            [output deleteCharactersInRange:NSMakeRange([output length]-1, 1)];
        }

        //terminate list/output
        [output appendString:@"]}"];
    }

    //all items
    else
    {
        //start JSON
        [output appendString:@"{\"tasks\":["];

        //get tasks
        for(NSNumber* taskPid in taskEnumerator.tasks)
        {
            //skip apple?
            // unless we're scanning a single proc
            if( (YES != includeApple) &&
                (1  != taskEnumerator.tasks.count) &&
                (YES == ((Task*)taskEnumerator.tasks[taskPid]).binary.isApple) )
            {
                //skip
                continue;
            }

            //append task JSON
            [output appendFormat:@"{%@},", [taskEnumerator.tasks[taskPid] toJSON:detailed]];
        }

        //remove last ','
        if(YES == [output hasSuffix:@","])
        {
            //remove
            [output deleteCharactersInRange:NSMakeRange([output length]-1, 1)];
        }

        //not detailed or not just scanning 1 task
        // add separate array of for all the dylibs
        if( (YES != detailed) &&
            (1 != taskEnumerator.tasks.count) )
        {
            //append
            [output appendString:@"],\"dylibs\":["];

            //add each dylib
            for(NSString* dylib in taskEnumerator.dylibs)
            {
                //add
                [output appendFormat:@"{%@},", [((Binary*)taskEnumerator.dylibs[dylib]) toJSON]];
            }

            //remove last ','
            if(YES == [output hasSuffix:@","])
            {
                //remove
                [output deleteCharactersInRange:NSMakeRange([output length]-1, 1)];
            }
        }

        //terminate list/output
        [output appendString:@"]}"];
    }

    //pretty print?
    if(YES == prettyPrint)
    {
        //make me pretty!
        prettyPrintJSON(output);
    }
    else
    {
        //output
        printf("%s\n", output.UTF8String);
    }

bail:

    //stop extension's monitoring & tear down XPC
    // ->extension stays resident (idle); deactivation requires admin authorization
    if(nil != xpcClient)
    {
        //stop
        [xpcClient stopMonitoring];

        //tear down XPC
        [xpcClient.extension invalidate];
    }

    return;
}

//activate extension (synchronously)
// ->for cmdline mode
BOOL activateExtension(void)
{
    //flag
    __block BOOL activated = NO;

    //extension
    Extension* extension = nil;

    //semaphore
    dispatch_semaphore_t semaphore = nil;

    //init extension object
    extension = [[Extension alloc] init];

    //init semaphore
    semaphore = dispatch_semaphore_create(0);

    //activate
    [extension toggleExtension:ACTION_ACTIVATE reply:^(NSError* error) {

        //error?
        if(nil != error)
        {
            //err msg
            fprintf(stderr, "ERROR: failed to activate system extension: %s\n", error.localizedDescription.UTF8String);
        }
        //activated
        else
        {
            //set flag
            activated = YES;
        }

        //signal
        dispatch_semaphore_signal(semaphore);
    }];

    //wait
    // ->up to 30 seconds (in case user needs to approve)
    dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(30 * NSEC_PER_SEC)));

    return activated;
}

//block until vt queries are done
// ->queue is empty & worker isn't busy
void completeVTQuery(void)
{
    //nap
    // ->allow queued items to be picked up
    [NSThread sleepForTimeInterval:1.0f];

    //wait till queue is drained
    while(YES)
    {
        //done?
        // ->note: rate limited items are deferred (& retried); once the quota is hit they're resolved as errors
        if( (0 == virusTotal.items.count) &&
            (0 == virusTotal.deferred.count) &&
            (YES != virusTotal.isBusy) )
        {
            //done
            break;
        }

        //nap
        [NSThread sleepForTimeInterval:1.0f];
    }

    return;
}

//pretty print JSON
void prettyPrintJSON(NSString* output)
{
    //data
    NSData* data = nil;

    //object
    id object = nil;

    //pretty data
    NSData* prettyData = nil;

    //pretty string
    NSString* prettyString = nil;

    //covert to data
    data = [output dataUsingEncoding:NSUTF8StringEncoding];

    //convert to JSON
    // wrap since we are serializing JSON
    @try
    {
        //serialize
        object = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];

        //covert to pretty data
        prettyData =  [NSJSONSerialization dataWithJSONObject:object options:NSJSONWritingPrettyPrinted error:nil];
    }
    @catch(NSException *exception)
    {
        ;
    }

    //covert to pretty string
    if(nil != prettyData)
    {
        //convert to string
        prettyString = [[NSString alloc] initWithData:prettyData encoding:NSUTF8StringEncoding];
    }
    else
    {
        //error
        prettyString = @"{\"ERROR\" : \"failed to covert output to JSON\"}";
    }

    //output
    printf("%s\n", prettyString.UTF8String);

    return;
}
