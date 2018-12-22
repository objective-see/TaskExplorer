//
//  main.m
//  TaskExplorer
//
//  Created by Patrick Wardle
//  Copyright (c) 2015 Objective-See. All rights reserved.
//

#import "main.h"

//main interface
// contains extra logic to handle app translocation
int main(int argc, char *argv[])
{
    //return
    int status = -1;
    
    //disable stderr
    // sentry dumps to this, and we want only JSON to output...
    disableSTDERR();
    
    //init crash reporting
    initCrashReporting();
    
    //untranslocated URL
    NSURL* untranslocatedURL = nil;
    
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
    
    //set network connection flag
    isConnected = isNetworkConnected();
    
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
        //first check rooot
        if(0 != geteuid())
        {
            //err msg
            printf("{\"ERROR\": \"TASKEXPLORER (cmdline) requires root\"}\n");
            
            //bail
            goto bail;
        }
        
        //set flag
        cmdlineMode = YES;
        
        //scan
        cmdlineExplore();
        
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
        
        //invoke app's main
        status = NSApplicationMain(argc, (const char **)argv);
    }
    
bail:
    
    return status;
}


//print usage
void usage()
{
    //usage
    printf("\nTASKEXPLORER USAGE:\n");
    printf(" -h or -help  display this usage info\n");
    printf(" -scan        scan all tasks and dylibs \n");
    printf(" -explore     enumerate all tasks and dylibs\n");
    printf("\noptions:\n");
    printf(" -pretty      json output is 'pretty-printed'\n");
    printf(" -pid [pid]   just scan/explore the specified task'\n");
    printf(" -skipVT      do not query VirusTotal (when '-explore' is specified)\n");
    printf(" -detailed    for each task; include dylibs, files, & network connections\n\n");

    return;
}

//perform a cmdline enumeration of all things
void cmdlineExplore()
{
    //args
    NSArray* arguments = nil;
    
    //filter obj
    Filter* filter = nil;

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
    
    //init filter obj
    filter = [[Filter alloc] init];
    
    //init task enumerator object
    taskEnumerator = [[TaskEnumerator alloc] init];
    
    //set flag
    // skip virus total?
    skipVirusTotal = [arguments containsObject:@"-skipVT"];
    
    //virus total?
    if(YES != skipVirusTotal)
    {
        //init virus total object
        virusTotal = [[VirusTotal alloc] init];
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
    }
    
    //enumerate all tasks/dylibs/files/etc
    [taskEnumerator enumerateTasks:pid];
    
    //wait for items to complete processing
    while(taskEnumerator.binaryQueue.itemsOut != taskEnumerator.binaryQueue.itemsOut)
    {
        //nap
        [NSThread sleepForTimeInterval:1.0f];
    }
    
    //determine what each dylib is loaded in
    // do here as all tasks and all dylibs are (now) enum'd
    for(NSString* dylib in taskEnumerator.dylibs)
    {
        //loaded in
        ((Binary*)taskEnumerator.dylibs[dylib]).loadedIn = [taskEnumerator loadedIn:taskEnumerator.dylibs[dylib]];
        
    }//sync
    
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
                (YES == [filter isApple:((Task*)taskEnumerator.tasks[taskPid]).binary]) )
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
     
    return;
}

//block until vt queries are done
void completeVTQuery()
{
    //flag
    BOOL queryingVT = NO;
    
    //nap
    // VT threads take some time to spawn/process
    [NSThread sleepForTimeInterval:5.0f];
    
    //wait till threads are done
    while(YES)
    {
        //reset flag
        queryingVT = NO;
        
        //wait for vt to complete
        @synchronized(virusTotal.vtThreads)
        {
            //check all threads
            for(NSThread* vtThread in virusTotal.vtThreads)
            {
                //check if still running?
                if(YES == [vtThread isExecuting])
                {
                    //set flag
                    queryingVT = YES;
                    
                    //bail
                    break;
                }
            }
        }
        
        //check flag
        if(YES != queryingVT)
        {
            //finally no active threads
            break;
        }
        
        //nap
        [NSThread sleepForTimeInterval:5.0f];
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
