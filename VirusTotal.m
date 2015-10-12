//
//  VirusTotal.m
//  TaskExplorer
//
//  Created by Patrick Wardle on 3/8/15.
//  Copyright (c) 2015 Objective-See. All rights reserved.
//

#import "File.h"
#import "Consts.h"
#import "ItemBase.h"
#import "VirusTotal.h"
#import "AppDelegate.h"

#import <syslog.h>

@implementation VirusTotal

@synthesize items;

//init
-(id)init
{
    //init super
    self = [super init];
    if(nil != self)
    {
        //alloc array for items
        items = [NSMutableArray array];
        
        //kick of thread to watch/flush queue
        // ->will flush if item not processed in 30 seconds
        [NSThread detachNewThreadSelector:@selector(queueFlusher) toTarget:self withObject:nil];
    }
    
    return self;
}

//watch queue
// ->manaully flush if any item in for more than 3.0 seconds
-(void)queueFlusher
{
    //last item
    Binary* lastItem = nil;
    
    //items to process
    NSMutableArray* vtItems = nil;
    
    //forever
    // ->watch/flush if needed
    while(YES)
    {
        //grab last item
        lastItem = [self.items lastObject];
        
        //sleep
        [NSThread sleepForTimeInterval:3.0];
        
        //sync
        @synchronized(self.items)
        {
            //no items?
            // ->just loop/re-nap
            if(0 == self.items.count)
            {
                //loop
                continue;
            }
        
            //check if last item, is still last
            // ->if not, loop/re-nap
            if(lastItem != [self.items lastObject])
            {
                //loop
                continue;
            }
            
            //make copy
            vtItems = [NSMutableArray arrayWithArray:self.items];
            
            //last item is same after timeout
            // ->flush the queue
            [NSThread detachNewThreadSelector:@selector(queryVT:) toTarget:self withObject:vtItems];
            
            //remove all items
            [self.items removeAllObjects];
        }

    }//forever
        
    return;
}

//add item
// ->will query VT when 25 items are hit
-(void)addItem:(Binary*)binary
{
    //items to process
    NSMutableArray* vtItems = nil;
    
    //sync
    @synchronized(self.items)
    {
        //add item
        [self.items addObject:binary];
       
        //query VT once 25 items have been gathered
        if(VT_MAX_QUERY_COUNT == self.items.count)
        {
            //make copy
            vtItems =  [NSMutableArray arrayWithArray:self.items];
    
            //kick of thread to make a query to VT
            [NSThread detachNewThreadSelector:@selector(queryVT:) toTarget:self withObject:vtItems];
            
            //remove all items
            [self.items removeAllObjects];
        }

    }//sync
    
    return;
}

//make query to VT
-(void)queryVT:(NSMutableArray*)vtItems
{
    //item data
    NSMutableDictionary* itemData = nil;
    
    //VT query URL
    NSURL* queryURL = nil;
    
    //array of queried items
    // ->needed so can save VT results back into binaries
    NSMutableDictionary* queriedItems = nil;
    
    //parameters
    NSMutableArray* parameters = nil;
    
    //results
    NSDictionary* results = nil;
    
    //alloc list for items
    parameters = [NSMutableArray array];
    
    //alloc dictionary for queried items
    queriedItems = [NSMutableDictionary dictionary];
    
    //init query URL
    queryURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", VT_QUERY_URL, VT_API_KEY]];
    
    //add all binaries to VT query
    for(Binary* item in vtItems)
    {
        //skip items with blank hashes
        // ->not sure why this would happen...
        if(nil == item.hashes[KEY_HASH_SHA1])
        {
            //skip
            continue;
        }
        
        //alloc item data
        itemData = [NSMutableDictionary dictionary];
        
        //auto start location
        itemData[@"autostart_location"] = @"n/a";
        
        //set item name
        itemData[@"autostart_entry"] = item.name;
        
        //set item path
        itemData[@"image_path"] = item.path;
        
        //set hash
        itemData[@"hash"] = item.hashes[KEY_HASH_SHA1];
        
        //set creation times
        itemData[@"creation_datetime"] = [item.attributes.fileCreationDate description];
        
        //add item to parameters
        [parameters addObject:itemData];
        
        //save as queried item
        queriedItems[item.hashes[KEY_HASH_SHA1]] = item;
    }
    
    //make query to VT
    results = [self postRequest:queryURL parameters:parameters];
    if(nil != results)
    {
        //process results
        [self processResults:queriedItems results:results];
    }
    
    return;
}

//get VT info for a single item
// ->will then callback into AppDelegate to reload item in UI
-(void)getInfoForItem:(Binary*)item scanID:(NSString*)scanID
{
    //VT query URL
    NSURL* queryURL = nil;
    
    //results
    NSDictionary* results = nil;
    
    //init query URL
    queryURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@?apikey=%@&resource=%@", VT_REQUERY_URL, VT_API_KEY, scanID]];
    
    //make queries until response is recieved
    while(YES)
    {
        //make query to VT
        results = [self postRequest:queryURL parameters:nil];
        
        //check if scan is complete
        if( (nil != results) &&
            (1 == [results[VT_RESULTS_RESPONSE] integerValue]) )
        {
            //save result
            item.vtInfo = results;
            
            //save flagged item
            if(0 != [results[VT_RESULTS_POSITIVES] unsignedIntegerValue])
            {
                //save
                [((AppDelegate*)[[NSApplication sharedApplication] delegate]) saveFlaggedBinary:item];
            }
            //for non-flagged items
            // ->remove from list, if they were previously flagged
            else
            {
                //check if previously flagged
                // ->then remove
                if(YES == [((AppDelegate*)[[NSApplication sharedApplication] delegate]).flaggedItems containsObject:item])
                {
                    //sync to remove
                    @synchronized(((AppDelegate*)[[NSApplication sharedApplication] delegate]).flaggedItems)
                    {
                        //remove
                        [((AppDelegate*)[[NSApplication sharedApplication] delegate]).flaggedItems removeObject:item];
                    }
                }
            }
            
            //call up into app delegate to smartly reload
            [((AppDelegate*)[[NSApplication sharedApplication] delegate]) reloadBinary:item];
            
            //exit loop
            break;
        }
        
        //nap
        [NSThread sleepForTimeInterval:60.0f];
    }
    
    return;
}


//make the (POST)query to VT
-(NSDictionary*)postRequest:(NSURL*)url parameters:(id)params
{
    //results
    NSDictionary* results = nil;
    
    //request
    NSMutableURLRequest *request = nil;
    
    //post data
    // ->JSON'd items
    NSData* postData = nil;
    
    //error var
    NSError* error = nil;
    
    //data from VT
    NSData* vtData = nil;
    
    //response (HTTP) from VT
    NSURLResponse* httpResponse = nil;
    
    //alloc/init request
    request = [[NSMutableURLRequest alloc] initWithURL:url];
    
    //set user agent
    [request setValue:VT_USER_AGENT forHTTPHeaderField:@"User-Agent"];
    
    //serialize JSON
    if(nil != params)
    {
        //convert items to JSON'd data for POST request
        // ->wrap since we are serializing JSON
        @try
        {
            //convert items
            postData = [NSJSONSerialization dataWithJSONObject:params options:kNilOptions error:nil];
            if(nil == postData)
            {
                //err msg
                syslog(LOG_ERR, "OBJECTIVE-SEE ERROR: failed to convert request %s to JSON", [[postData description] UTF8String]);
                
                //bail
                goto bail;
            }
            
        }
        //bail on exceptions
        @catch(NSException *exception)
        {
            //bail
            goto bail;
        }
        
        //set content type
        [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
        
        //set content length
        [request setValue:[NSString stringWithFormat:@"%lu", (unsigned long)[postData length]] forHTTPHeaderField:@"Content-length"];
        
        //add POST data
        [request setHTTPBody:postData];
    }
    
    //set method type
    [request setHTTPMethod:@"POST"];
    
    //send request
    // ->synchronous, so will block
    vtData = [NSURLConnection sendSynchronousRequest:request returningResponse:&httpResponse error:&error];
    
    //sanity check(s)
    if( (nil == vtData) ||
        (nil != error) ||
        (200 != (long)[(NSHTTPURLResponse *)httpResponse statusCode]) )
    {
        //err msg
        syslog(LOG_ERR, "OBJECTIVE-SEE ERROR: failed to query VirusTotal (%s, %s)", [[error description] UTF8String], [[httpResponse description] UTF8String]);
        
        //bail
        goto bail;
    }
    
    //serialize response into NSData obj
    // ->wrap since we are serializing JSON
    @try
    {
        //serialized
        results = [NSJSONSerialization JSONObjectWithData:vtData options:kNilOptions error:nil];
    }
    //bail on any exceptions
    @catch (NSException *exception)
    {
        //err msg
        syslog(LOG_ERR, "OBJECTIVE-SEE ERROR: converting response %s to JSON threw %s", [[vtData description] UTF8String], [[exception description] UTF8String]);
        
        //bail
        goto bail;
    }
    
    //sanity check
    if(nil == results)
    {
        //err msg
        syslog(LOG_ERR, "OBJECTIVE-SEE ERROR: failed to convert response %s to JSON", [[vtData description] UTF8String]);
        
        //bail
        goto bail;
    }
    
//bail
bail:
    
    return results;
}

//submit a file to VT
-(NSDictionary*)submit:(Binary*)item
{
    //results
    NSDictionary* results = nil;
    
    //submit URL
    NSURL* submitURL = nil;
    
    //request
    NSMutableURLRequest *request = nil;
    
    //body of request
    NSMutableData* body = nil;
    
    //file data
    NSData* fileContents = nil;
    
    //error var
    NSError* error = nil;
    
    //data from Vt
    NSData* vtData = nil;
    
    //response (HTTP) from VT
    NSURLResponse* httpResponse = nil;
    
    //remove item's vt info
    // ->as its about to be outdated
    item.vtInfo =  nil;
    
    //call up into app delegate to smartly reload
    // ->it's VT button will be '...'
    [((AppDelegate*)[[NSApplication sharedApplication] delegate]) reloadBinary:item];

    //init submit URL
    submitURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@?apikey=%@&resource=%@", VT_SUBMIT_URL, VT_API_KEY, item.hashes[KEY_HASH_MD5]]];
    
    //init request
    request = [[NSMutableURLRequest alloc] initWithURL:submitURL];
    
    //set boundary string
    NSString *boundary = @"qqqq___taskexplorer___qqqq";
    
    //set HTTP method (POST)
    [request setHTTPMethod:@"POST"];
    
    //set the HTTP header 'Content-type' to the boundary
    [request setValue:[NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary] forHTTPHeaderField: @"Content-Type"];
    
    //set HTTP header, 'User-Agent'
    [request setValue:VT_USER_AGENT forHTTPHeaderField:@"User-Agent"];

    //init body
    body = [NSMutableData data];
    
    //load file into memory
    fileContents = [NSData dataWithContentsOfFile:item.pathForFinder];
    
    //sanity check
    if(nil == fileContents)
    {
        //err msg
        syslog(LOG_ERR, "OBJECTIVE-SEE ERROR: failed to load %s into memory for submission", [item.path UTF8String]);
        
        //bail
        goto bail;
    }
        
    //append boundary
    [body appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    
    //append 'Content-Disposition' file name, etc
    [body appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"file\"; filename=\"%@\"\r\n", item.name] dataUsingEncoding:NSUTF8StringEncoding]];
    
    //append 'Content-Type'
    [body appendData:[@"Content-Type: application/octet-stream\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
    
    //append file's contents
    [body appendData:fileContents];
    
    //append '\r\n'
    [body appendData:[[NSString stringWithFormat:@"\r\n"] dataUsingEncoding:NSUTF8StringEncoding]];
    
    //append final boundary
    [body appendData:[[NSString stringWithFormat:@"--%@--\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    
    //set body
    [request setHTTPBody:body];
    
    //set content length
    [request setValue:[NSString stringWithFormat:@"%lu", (unsigned long)[body length]] forHTTPHeaderField:@"Content-length"];

    //send request
    // ->synchronous, so will block
    vtData = [NSURLConnection sendSynchronousRequest:request returningResponse:&httpResponse error:&error];
    
    //sanity check(s)
    if( (nil == vtData) ||
        (nil != error) ||
        (200 != (long)[(NSHTTPURLResponse *)httpResponse statusCode]) )
    {
        //err msg
        syslog(LOG_ERR, "OBJECTIVE-SEE ERROR: failed to query VirusTotal (%s, %s)", [[error description] UTF8String], [[httpResponse description] UTF8String]);
        
        //bail
        goto bail;
    }
    
    //serialize response into NSData obj
    // ->wrap since we are serializing JSON
    @try
    {
        //serialize
        results = [NSJSONSerialization JSONObjectWithData:vtData options:kNilOptions error:nil];
    }
    //bail on any exceptions
    @catch (NSException *exception)
    {
        //err msg
        syslog(LOG_ERR, "OBJECTIVE-SEE ERROR: converting response %s to JSON threw %s", [[vtData description] UTF8String], [[exception description] UTF8String]);
        
        //bail
        goto bail;
    }
    
    //sanity check
    if(nil == results)
    {
        //err msg
        syslog(LOG_ERR, "OBJECTIVE-SEE ERROR: failed to convert response %s to JSON", [[vtData description] UTF8String]);
        
        //bail
        goto bail;
    }
    
//bail
bail:
    
    return results;
}


//submit a rescan request
-(NSDictionary*)reScan:(Binary*)item
{
    //result data
    NSDictionary* result = nil;
    
    //scan url
    NSURL* reScanURL = nil;
    
    //remove item's vt info
    // ->as its about to be outdates
    item.vtInfo =  nil;
    
    //call up into app delegate to smartly reload
    // ->will change item's VT button back to '...'
    [((AppDelegate*)[[NSApplication sharedApplication] delegate]) reloadBinary:item];
    
    //init scan url
    reScanURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@?apikey=%@&resource=%@", VT_RESCAN_URL, VT_API_KEY, item.hashes[KEY_HASH_MD5]]];
    
    //make request to VT
    result = [self postRequest:reScanURL parameters:nil];
    if(nil == result)
    {
        //err msg
        syslog(LOG_ERR, "OBJECTIVE-SEE ERROR: failed to re-scan %s", [item.name UTF8String]);
        
        //bail
        goto bail;
    }
    
//bail
bail:
    
    return result;
}

//process results
// ->save VT info into Binary object & reload relevant pane
-(void)processResults:(NSMutableDictionary*)queriedItems results:(NSDictionary*)results
{
    //queried binary obj
    Binary* queriedItem = nil;
        
    //process all results
    // ->save VT result dictionary into File obj
    for(NSDictionary* result in results[VT_RESULTS])
    {
        //extract ('match') queried item
        // ->VT gives us back a hash
        queriedItem = queriedItems[result[@"hash"]];
        
        //sanity check
        if(nil == queriedItem)
        {
            //skip
            continue;
        }
        
        //save VT results into item
        queriedItem.vtInfo = result;
        
        //save flagged item
        if(0 != [result[VT_RESULTS_POSITIVES] unsignedIntegerValue])
        {
            //save
            [((AppDelegate*)[[NSApplication sharedApplication] delegate]) saveFlaggedBinary:queriedItem];
        }
        
        //call up into app delegate to smartly reload
        [((AppDelegate*)[[NSApplication sharedApplication] delegate]) reloadBinary:queriedItem];
    }
    
    return;
}


@end
