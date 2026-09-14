//
//  file: Update.m
//  TaskExplorer
//  description: checks for new versions of LuLu
//
//  created by Patrick Wardle
//  copyright (c) 2017 Objective-See. All rights reserved.
//

#import "Consts.h"
#import "Update.h"
#import "Utilities.h"
#import "AppDelegate.h"


@implementation Update

//check for an update
// ->will invoke app delegate method to update UI when check completes
-(void)checkForUpdate:(void (^)(NSUInteger result, NSString* latestVersion))completionHandler
{
    //latest version
    __block NSString* latestVersion = nil;
    
    //result
    __block NSInteger result = -1;

    //get latest version in background
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        
        //grab latest version
        latestVersion = [self getLatestVersion];
        if(nil != latestVersion)
        {
            //check
            result = (NSOrderedAscending == [getAppVersion() compare:latestVersion options:NSNumericSearch]);
        }
        
        //invoke app delegate method
        // ->will update UI/show popup if necessart
        dispatch_async(dispatch_get_main_queue(),
        ^{
            completionHandler(result, latestVersion);
        });
        
    });
    
    return;
}

//query interwebz to get latest version
-(NSString*)getLatestVersion
{
    //product version(s) data
    NSData* productsVersionData = nil;
    
    //version dictionary
    NSDictionary* productsVersionDictionary = nil;
    
    //latest version
    NSString* latestVersion = nil;
    
    //get version from remote URL
    //fetch (w/ a timeout; 'initWithContentsOfURL:' has none)
    {
        //semaphore
        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

        //request
        NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:PRODUCT_VERSIONS_URL] cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:15];

        //response data
        __block NSData* responseData = nil;

        //fetch
        [[NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData* data, NSURLResponse* response, NSError* error) {

            //ok?
            if( (nil == error) &&
                (200 == ((NSHTTPURLResponse*)response).statusCode) )
            {
                //save
                responseData = data;
            }

            //signal
            dispatch_semaphore_signal(semaphore);

        }] resume];

        //wait
        dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(20 * NSEC_PER_SEC)));

        //save
        productsVersionData = responseData;
    }
    if(nil == productsVersionData)
    {
        //bail
        goto bail;
    }
    
    //convert JSON to dictionary
    // ->wrap as may throw exception
    @try
    {
        //convert
        productsVersionDictionary = [NSJSONSerialization JSONObjectWithData:productsVersionData options:0 error:nil];
        if(nil == productsVersionDictionary)
        {
            //bail
            goto bail;
        }
    }
    @catch(NSException* exception)
    {
        //bail
        goto bail;
    }
    
    //extract latest version
    // ->type-checked: a server (or captive portal) returning something JSON-shaped but different must not crash us
    if( (YES == [productsVersionDictionary isKindOfClass:[NSDictionary class]]) &&
        (YES == [productsVersionDictionary[PRODUCT_NAME] isKindOfClass:[NSDictionary class]]) &&
        (YES == [productsVersionDictionary[PRODUCT_NAME][@"version"] isKindOfClass:[NSString class]]) )
    {
        //extract
        latestVersion = productsVersionDictionary[PRODUCT_NAME][@"version"];
    }
    
bail:
    
    return latestVersion;
}

@end
