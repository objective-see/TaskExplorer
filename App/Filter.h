//
//  Filter.h
//  TaskExplorer
//
//  Created by Patrick Wardle on 2/21/15.
//  Copyright (c) 2015 Objective-See. All rights reserved.
//
//  note: '#keyword' filters are backed by (KVC) predicates over Task/Binary objects
//        ...the same predicates are usable by the assistant tools

#import "File.h"
#import "Task.h"
#import "Binary.h"

#import <Foundation/Foundation.h>

@interface Filter : NSObject
{

}

/* METHODS */

//determine if search string is (an exact) #keyword
-(BOOL)isKeyword:(NSString*)searchString;

//description of a keyword
-(NSString*)keywordDescription:(NSString*)keyword;

//predicate for a keyword
// ->nil if unknown
-(NSPredicate*)predicateForKeyword:(NSString*)keyword;

//check if a binary fulfills a keyword
-(BOOL)binaryFulfillsKeyword:(NSString*)keyword binary:(Binary*)binary;

//check if a task fulfills a keyword
-(BOOL)taskFulfillsKeyword:(NSString*)keyword task:(Task*)task;

/* PROPERTIES */

//binary filter keywords
// ->all keywords (sorted); used for auto-complete
@property(nonatomic, retain)NSMutableArray* binaryFilters;

//keyword -> predicate
@property(nonatomic, retain)NSDictionary* keywordPredicates;

//keyword -> description
@property(nonatomic, retain)NSDictionary* keywordDescriptions;

@end
