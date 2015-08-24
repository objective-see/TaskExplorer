//
//  File.m
//  KnockKnock
//
//  Created by Patrick Wardle on 2/19/15.
//  Copyright (c) 2015 Objective-See. All rights reserved.
//
#import "File.h"
#import "Consts.h"
#import "Utilities.h"
#import "AppDelegate.h"

#import <syslog.h>

@implementation File

@synthesize type;


//init method
-(id)initWithParams:(NSDictionary*)params
{
    //super
    // ->saves path, etc
    self = [super initWithParams:params];
    if(self)
    {
        //always skip not-existent paths
        if(YES != [[NSFileManager defaultManager] fileExistsAtPath:params[KEY_RESULT_PATH]])
        {
            //err msg
            //syslog(LOG_ERR, "OBJECTIVE-SEE ERROR: %s not found", [params[KEY_RESULT_PATH] UTF8String]);
            
            //set self to nil
            self = nil;
            
            //bail
            goto bail;
        }
        
        //extract name
        self.name = [[self.path lastPathComponent] stringByDeletingPathExtension];
     
        //set icon
        self.icon = [[NSWorkspace sharedWorkspace] iconForFile:self.path];
        
        //grab attributes
        self.attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:self.path error:nil];

    }
           
//bail
bail:
    
    return self;
}

//set file type
// ->invokes 'file' cmd, the parses out result
-(void)setFileType
{
    //results from 'file' cmd
    NSString* results = nil;
    
    //array of parsed results
    NSArray* parsedResults = nil;
    
    //exec 'file' to get file type
    results = [[NSString alloc] initWithData:execTask(@"/usr/bin/file", @[self.path]) encoding:NSUTF8StringEncoding];
    
    //sanity check
    if(nil == results)
    {
        //bail
        goto bail;
    }
    
    //parse results
    // ->format: <file path>: <file types>
    parsedResults = [results componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@":\n"]];
    
    //sanity check
    // ->should be two items in array, <file path> and <file type>
    if(parsedResults.count < 2)
    {
        //bail
        goto bail;
    }
    
    //file type comes second
    // ->also trim whitespace
    self.type = [parsedResults[1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    
//bail
bail:
    ;
    
    
    return;
}


//get detailed info (which takes a while to generate)
// ->only shown to user if they click 'info' so this method is called in the background
-(void)generateDetailedInfo
{
    //set type
    [self setFileType];
    
    return;
}


//convert object to JSON string
-(NSString*)toJSON
{
    //json string
    NSString *json = nil;
    
    //json data
    // ->for intermediate conversions
    //NSData *jsonData = nil;
    
    //hashes
    //NSString* fileHashes = nil;
    
    //signing info
    //NSString* fileSigs = nil;
    
    //init file hash to default string
    // ->used when hashes are nil, or serialization fails
    //fileHashes = @"\"unknown\"";
    
    //init file signature to default string
    // ->used when signatures are nil, or serialization fails
    //fileSigs = @"\"unknown\"";
    
    /*
    //convert hashes to JSON
    if(nil != self.hashes)
    {
        //convert hash dictionary
        // ->wrap since we are serializing JSON
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
        // ->file hashes will just be 'unknown'
        @catch(NSException *exception)
        {
            ;
        }
    }
    
    //convert signing dictionary to JSON
    if(nil != self.signingInfo)
    {
        //convert signing dictionary
        // ->wrap since we are serializing JSON
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
    
    //provide a default string if the file doesn't have a plist
    if(nil == self.plist)
    {
        //set
        filePlist = @"n/a";
    }
    //use plist as is
    else
    {
        //set
        filePlist = self.plist;
    }
    
    //init VT detection ratio
    //vtDetectionRatio = [NSString stringWithFormat:@"%lu/%lu", (unsigned long)[self.vtInfo[VT_RESULTS_POSITIVES] unsignedIntegerValue], (unsigned long)[self.vtInfo[VT_RESULTS_TOTAL] unsignedIntegerValue]];
    
    
    //init json
    json = [NSString stringWithFormat:@"\"name\": \"%@\", \"path\": \"%@\", \"plist\": \"%@\", \"hashes\": %@, \"signature(s)\": %@", self.name, self.path, filePlist, fileHashes, fileSigs];
     
    */
    
    return json;
}


@end
