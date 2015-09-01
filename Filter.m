//
//  Filter.m
//  TaskExplorer
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

//file filter keywords
//NSString * const FILE_FILTERS[] = {@"#apple", @"#nonapple", @"#signed", @"#unsigned", @"#flagged"};

//binary filter keywords
NSString * const BINARY_KEYWORDS[] = {@"#apple", @"#nonapple", @"#signed", @"#unsigned", @"#flagged"};

@implementation Filter

//@synthesize fileFilters;
@synthesize binaryFilters;

//init
-(id)init
{
    //init super
    self = [super init];
    if(nil != self)
    {
        //alloc file filter keywords
        //fileFilters = [NSMutableArray array];
        
        //alloc binary filter keywords
        binaryFilters = [NSMutableArray array];

        //init binary filters
        for(NSUInteger i=0; i < sizeof(BINARY_KEYWORDS)/sizeof(BINARY_KEYWORDS[0]); i++)
        {
            //add
            [self.binaryFilters addObject:BINARY_KEYWORDS[i]];
        }
    }
    
    return self;
}

//determine if search string is #keyword
-(BOOL)isKeyword:(NSString*)searchString
{
    //for now just check in binary keywords
    return [self.binaryFilters containsObject:searchString];
    
    /*
    //flag
    BOOL isKeyword = NO;
    
    //iterate over all keywords
    // ->check for match
    for(NSUInteger i=0; i < sizeof(KEYWORDS)/sizeof(KEYWORDS[0]); i++)
    {
        //check
        if(YES == [KEYWORDS[i] isEqualToString:searchString])
        {
            //match
            isKeyword = YES;
            
            //bail
            break;
        }
    }
    
    return isKeyword;
    */
    
}


//filter tasks
// ->name, path, pid
-(void)filterTasks:(NSString*)filterText items:(NSMutableDictionary*)items results:(NSMutableArray*)results
{
    //task
    Task* task = nil;
    
    //flag for keyword filter
    BOOL isKeyword = NO;
    
    //first reset filter'd items
    [results removeAllObjects];
    
    //set keyword flag
    // ->note: already checked its a full/matching keyword
    isKeyword = [filterText hasPrefix:@"#"];
    
    //iterate over all tasks
    for(NSNumber* taskKey in items)
    {
        //extract task
        task = items[taskKey];
        
        //handle keyword filtering
        if( (YES == isKeyword) &&
            (YES == [self binaryFulfillsKeyword:filterText binary:task.binary]) )
        {
            //add
            [results addObject:task];

        }//keywords
       
        //no keyword search
        else
        {
            //check path first
            // ->mostly likely to match
            if(NSNotFound != [task.binary.path rangeOfString:filterText options:NSCaseInsensitiveSearch].location)
            {
                //save match
                [results addObject:task];
                
                //next
                continue;
            }
            
            //check name
            if(NSNotFound != [task.binary.name rangeOfString:filterText options:NSCaseInsensitiveSearch].location)
            {
                //save match
                [results addObject:task];
                
                //next
                continue;
            }
            
            //check pid
            if(NSNotFound != [[task.pid stringValue] rangeOfString:filterText options:NSCaseInsensitiveSearch].location)
            {
                //save match
                [results addObject:task];
                
                //next
                continue;
            }
        }

    }//all tasks
    
    return;
}


//filter dylibs and files
// ->name and path
-(void)filterFiles:(NSString*)filterText items:(NSMutableArray*)items results:(NSMutableArray*)results
{
    //flag for keyword filter
    BOOL isKeyword = NO;
    
    //first reset filter'd items
    [results removeAllObjects];
    
    //set keyword flag
    // ->note: already checked its a full/matching keyword
    isKeyword = [filterText hasPrefix:@"#"];
    
    //iterate over all tasks
    for(ItemBase* item in items)
    {
        //handle keyword filtering
        // ->for now, only for dylibs (binaries)
        if( (YES == [item isKindOfClass:[Binary class]]) &&
            (YES == isKeyword) &&
            (YES == [self binaryFulfillsKeyword:filterText binary:(Binary*)item]) )
        {
            //add
            [results addObject:item];
        
        }//keywords
        
        //no keyword search
        else
        {
            //check path first
            // ->most likely to match
            if(NSNotFound != [item.path rangeOfString:filterText options:NSCaseInsensitiveSearch].location)
            {
                //save match
                [results addObject:item];
                
                //next
                continue;
            }

            //check name
            if(NSNotFound != [item.name rangeOfString:filterText options:NSCaseInsensitiveSearch].location)
            {
                //save match
                [results addObject:item];
                
                //next
                continue;
            }
        }
        
    }//all items
    
    return;
}

//filter network connections
//TODO: match on family/connection type
-(void)filterConnections:(NSString*)filterText items:(NSMutableArray*)items results:(NSMutableArray*)results
{
    //first reset filter'd items
    [results removeAllObjects];
    
    //iterate over all tasks
    for(Connection* item in items)
    {
        //check local ip
        if(NSNotFound != [item.localIPAddr rangeOfString:filterText options:NSCaseInsensitiveSearch].location)
        {
            //save match
            [results addObject:item];
            
            //next
            continue;
        }
        
        //check local port
        if(NSNotFound != [[NSString stringWithFormat:@"%d", [item.localPort unsignedShortValue]] rangeOfString:filterText options:NSCaseInsensitiveSearch].location)
        {
            //save match
            [results addObject:item];
            
            //next
            continue;
        }
        
        //check remote ip
        if( (nil != item.remoteIPAddr) &&
            (NSNotFound != [item.remoteIPAddr rangeOfString:filterText options:NSCaseInsensitiveSearch].location) )
        {
            //save match
            [results addObject:item];
            
            //next
            continue;
        }
        
        //check remote port
        if( (nil != item.remoteIPAddr) &&
            (NSNotFound != [[NSString stringWithFormat:@"%d", [item.remotePort unsignedShortValue]] rangeOfString:filterText options:NSCaseInsensitiveSearch].location) )
        {
            //save match
            [results addObject:item];
            
            //next
            continue;
        }
        
    }//all connections
    
    return;
}

//check if a binary fulfills a keyword
-(BOOL)binaryFulfillsKeyword:(NSString*)keyword binary:(Binary*)binary
{
    //flag
    BOOL fulfills = NO;
    
    //handle '#apple'
    // ->signed by apple
    if( (YES == [keyword isEqualToString:@"#apple"]) &&
        (YES == [self isApple:binary]) )
    {
        //happy
        fulfills = YES;
        
        //bail
        goto bail;
    }
    
    //handle '#nonapple'
    // ->not signed by apple
    else if( (YES == [keyword isEqualToString:@"#nonapple"]) &&
        (YES != [self isApple:binary]) )
    {
        //happy
        fulfills = YES;
        
        //bail
        goto bail;
    }
    
    //handle '#signed'
    // ->signed
    else if( (YES == [keyword isEqualToString:@"#signed"]) &&
             (YES == [self isSigned:binary]) )
    {
        //happy
        fulfills = YES;
        
        //bail
        goto bail;
    }
    
    //handle '#unsigned'
    // ->not signed
    else if( (YES == [keyword isEqualToString:@"#unsigned"]) &&
             (YES != [self isSigned:binary]) )
    {
        //happy
        fulfills = YES;
        
        //bail
        goto bail;
    }
    
    //handle '#flagged'
    // ->flagged by VT
    else if( (YES == [keyword isEqualToString:@"#flagged"]) &&
             (YES == [self isFlagged:binary]) )
    {
        //happy
        fulfills = YES;
        
        //bail
        goto bail;
    }
    
//bail
bail:
    
    return fulfills;
}


//keyword filter '#apple' (and indirectly #nonapple)
// ->determine if binary is signed by apple
-(BOOL)isApple:(Binary*)item
{
    //flag
    BOOL isApple = NO;
    
    //make sure signing info has been generated
    // ->when no, generate it
    if(nil == item.signingInfo)
    {
        //generate
        [item generatedSigningInfo];
    }
    
    //check
    // ->just look at signing info
    if(YES == [item.signingInfo[KEY_SIGNING_IS_APPLE] boolValue])
    {
        //set flag
        isApple = YES;
    }
    
    return isApple;
}

//keyword filter '#signed' (and indirectly #unsigned)
// ->determine if binary is signed
-(BOOL)isSigned:(Binary*)item
{
    //flag
    BOOL isSigned = NO;
    
    //make sure signing info has been generated
    // ->when no, generate it
    if(nil == item.signingInfo)
    {
        //generate
        [item generatedSigningInfo];
    }
    
    //check
    // ->just look at signing info
    if(STATUS_SUCCESS == [item.signingInfo[KEY_SIGNATURE_STATUS] integerValue])
    {
        //set flag
        isSigned = YES;
    }
    
    return isSigned;
}

//keyword filter '#flagged'
// ->determine if binary is flagged by VT
-(BOOL)isFlagged:(Binary*)item
{
    //flag
    BOOL isFlagged = NO;
    
    //check
    // ->note: assumes that VT query has already completed...
    if( (nil != item.vtInfo) &&
        (0 != [item.vtInfo[VT_RESULTS_POSITIVES] unsignedIntegerValue]) )
    {
        //set flag
        isFlagged = YES;
    }
    
    return isFlagged;
}


@end
