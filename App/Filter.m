//
//  Filter.m
//  TaskExplorer
//
//  Created by Patrick Wardle on 2/21/15.
//  Copyright (c) 2015 Objective-See. All rights reserved.
//
//  note: '#keyword' filters are backed by (KVC) predicates over Task/Binary objects
//        ...the same predicates are usable by the assistant tools

#import "Task.h"
#import "Consts.h"
#import "Filter.h"
#import "ItemBase.h"
#import "Utilities.h"
#import "Connection.h"

@implementation Filter

@synthesize binaryFilters;
@synthesize keywordPredicates;
@synthesize keywordDescriptions;

//init
// ->build keyword table (keyword -> predicate + description)
-(id)init
{
    //init super
    self = [super init];
    if(nil != self)
    {
        //init keyword predicates
        // note: predicates are evaluated against a Binary (for dylibs), or a Task (for tasks)
        //       ...Task forwards binary keys (see 'valueForUndefinedKey:'), so both work
        keywordPredicates = @{
            @"#3rdparty":   [NSPredicate predicateWithFormat:@"isApple == NO"],
            @"#adhoc":      [NSPredicate predicateWithFormat:@"isSigned == YES AND inCache == NO AND signer == %d", AdHoc],
            @"#flagged":    [NSPredicate predicateWithFormat:@"isFlagged == YES"],
            @"#unknown":    [NSPredicate predicateWithFormat:@"isUnknownToVT == YES"],
            @"#obfuscated": [NSPredicate predicateWithFormat:@"isEncrypted == YES OR isPacked == YES"],
            @"#network":    [NSPredicate predicateWithFormat:@"hasConnections == YES"],
            @"#listening":  [NSPredicate predicateWithFormat:@"isListening == YES"],
            @"#root":       [NSPredicate predicateWithFormat:@"uid == 0"]
        };

        //init keyword descriptions
        keywordDescriptions = @{
            @"#3rdparty":   @"not signed by Apple",
            @"#adhoc":      @"ad-hoc signed (no certificate)",
            @"#flagged":    @"flagged by VirusTotal",
            @"#unknown":    @"unknown to VirusTotal",
            @"#obfuscated": @"packed or encrypted binary",
            @"#network":    @"tasks with network connections",
            @"#listening":  @"tasks with listening sockets",
            @"#root":       @"tasks running as root"
        };

        //init (sorted) keyword list
        binaryFilters = [[keywordPredicates.allKeys sortedArrayUsingSelector:@selector(compare:)] mutableCopy];
    }

    return self;
}

//determine if search string is (an exact) #keyword
-(BOOL)isKeyword:(NSString*)searchString
{
    return (nil != self.keywordPredicates[searchString.lowercaseString]);
}


//description of a keyword
-(NSString*)keywordDescription:(NSString*)keyword
{
    return self.keywordDescriptions[keyword.lowercaseString];
}

//predicate for a keyword
// ->nil if unknown
-(NSPredicate*)predicateForKeyword:(NSString*)keyword
{
    return self.keywordPredicates[keyword.lowercaseString];
}

//check if a binary fulfills a keyword
-(BOOL)binaryFulfillsKeyword:(NSString*)keyword binary:(Binary*)binary
{
    //flag
    BOOL fulfills = NO;

    //predicate
    NSPredicate* predicate = nil;

    //get predicate
    predicate = [self predicateForKeyword:keyword];
    if(nil == predicate)
    {
        //bail
        goto bail;
    }

    //evaluate
    // ->wrap, as (task-only) keys will throw for binaries
    @try
    {
        //evaluate
        fulfills = [predicate evaluateWithObject:binary];
    }
    @catch(NSException* exception)
    {
        //no match
        fulfills = NO;
    }

bail:

    return fulfills;
}

//check if a task fulfills a keyword
-(BOOL)taskFulfillsKeyword:(NSString*)keyword task:(Task*)task
{
    //flag
    BOOL fulfills = NO;

    //predicate
    NSPredicate* predicate = nil;

    //get predicate
    predicate = [self predicateForKeyword:keyword];
    if(nil == predicate)
    {
        //bail
        goto bail;
    }

    //evaluate
    // ->task forwards binary keys, so binary keywords work too
    @try
    {
        //evaluate
        fulfills = [predicate evaluateWithObject:task];
    }
    @catch(NSException* exception)
    {
        //no match
        fulfills = NO;
    }

bail:

    return fulfills;
}

@end
