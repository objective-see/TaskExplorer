//
//  Filter.m
//  KnockKnock
//
//  Created by Patrick Wardle on 2/21/15.
//  Copyright (c) 2015 Objective-See. All rights reserved.
//
#import "Consts.h"
#import "Filter.h"
#import "Utilities.h"
#import "Task.h"
#import "ItemBase.h"
#import "Connection.h"

@implementation Filter

@synthesize trustedFiles;
@synthesize knownCommands;
@synthesize trustedExtensions;

#define SOFTWARE_SIGNING @"Software Signing"
#define APPLE_SIGNING_AUTH @"Apple Code Signing Certification Authority"
#define APPLE_ROOT_CA @"Apple Root CA"

//init
-(id)init
{
    //super
    self = [super init];
    if(self)
    {
        //load known file hashes
        //self.trustedFiles = [self loadWhitelist:WHITE_LISTED_FILES];
        
        //load known commands
        //self.knownCommands = [self loadWhitelist:WHITE_LISTED_COMMANDS];
        
        //load known extensions
        //self.trustedExtensions = [self loadWhitelist:WHITE_LISTED_EXTENSIONS];
    }
    
    return self;
}

//TODO: add filter tasks


//filter dylibs and files
// ->name and path
-(void)filterFiles:(NSString*)filterText items:(NSMutableArray*)items results:(NSMutableArray*)results
{
    //name range
    NSRange nameRange = {0};
    
    //path range
    NSRange pathRange = {0};
    
    //first reset filter'd items
    [results removeAllObjects];
    
    //iterate over all tasks
    for(ItemBase* item in items)
    {
        //init name range
        nameRange = [item.name rangeOfString:filterText options:NSCaseInsensitiveSearch];
        
        //init path range
        pathRange = [item.path rangeOfString:filterText options:NSCaseInsensitiveSearch];
        
        //check for match
        if( (NSNotFound != nameRange.location) ||
           (NSNotFound != pathRange.location) )
        {
            //save match
            [results addObject:item];
        }
        
    }//all items
    
    return;
}

//filter network connections
-(void)filterConnections:(NSString*)filterText items:(NSMutableArray*)items results:(NSMutableArray*)results
{
    //local IP addr range
    NSRange localIPRange = {0};
    
    //local port range
    NSRange localPortRange = {0};

    //TODO: add remote ip/port, state, proto, family?
    
    //first reset filter'd items
    [results removeAllObjects];
    
    //iterate over all tasks
    for(Connection* item in items)
    {
        //init name range
        localIPRange = [item.localIPAddr rangeOfString:filterText options:NSCaseInsensitiveSearch];
        
        //init path range
        localPortRange = [[NSString stringWithFormat:@"%d", [item.localPort unsignedShortValue]] rangeOfString:filterText options:NSCaseInsensitiveSearch];
        
        //check for match
        if( (NSNotFound != localIPRange.location) ||
            (NSNotFound != localPortRange.location) )
        {
            //save match
            [results addObject:item];
        }
        
    }//all items
    
    return;
}

//load a (JSON) white list
// ->file hashes, known commands, etc
-(NSDictionary*)loadWhitelist:(NSString*)fileName
{
    //whitelisted data
    NSDictionary* whiteList = nil;
    
    //path
    NSString* path = nil;
    
    //error var
    NSError *error = nil;
    
    //json data
    NSData* whiteListJSON = nil;
    
    //init path
    path = [[NSBundle mainBundle] pathForResource:fileName ofType: @"json"];
    
    //load whitelist file data
    whiteListJSON = [NSData dataWithContentsOfFile:path];
    
    //convert JSON into dictionary
    whiteList = [NSJSONSerialization JSONObjectWithData:whiteListJSON options:kNilOptions error:&error];
    
    return whiteList;
}


//check if a File obj is known
// ->whitelisted *or* signed by apple
-(BOOL)isTrustedFile:(Binary*)fileObj
{
    //flag
    BOOL isTrusted = NO;
    
    //known hashes for file name
    NSArray* knownHashes = nil;
    
    //lookup based on name
    knownHashes = self.trustedFiles[fileObj.path];
    
    //first check if hash is known
    if( (nil != knownHashes) &&
        (YES == [knownHashes containsObject:[fileObj.hashes[KEY_HASH_MD5] lowercaseString]]) )
    {
        //got match
        isTrusted = YES;
    }
    //then check if its signed by apple
    // ->apple-signed files are always trusted
    else
    {
        //check for apple signature
        isTrusted = isApple(fileObj.path);
    }
    
    return isTrusted;
}


@end
