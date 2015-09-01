//
//  Filter.h
//  TaskExplorer
//
//  Created by Patrick Wardle on 2/21/15.
//  Copyright (c) 2015 Objective-See. All rights reserved.
//
#import "File.h"
#import "Binary.h"

#import <Foundation/Foundation.h>

@interface Filter : NSObject
{
    
}

/* METHODS */

//determine if search string is #keyword
-(BOOL)isKeyword:(NSString*)searchString;

//check if a binary fulfills a keyword
-(BOOL)binaryFulfillsKeyword:(NSString*)keyword binary:(Binary*)binary;

//keyword filter '#apple'
// ->determine if binary is signed by apple
-(BOOL)isApple:(Binary*)item;

//keyword filter '#signed' (and indirectly #unsigned)
// ->determine if binary is signed
-(BOOL)isSigned:(Binary*)item;

//keyword filter '#flagged'
// ->determine if binary is flagged by VT
-(BOOL)isFlagged:(Binary*)item;

//filter tasks
-(void)filterTasks:(NSString*)filterText items:(NSMutableDictionary*)items results:(NSMutableArray*)results;

//filter dylibs and files
-(void)filterFiles:(NSString*)filterText items:(NSMutableArray*)items results:(NSMutableArray*)results;

//filter network connections
-(void)filterConnections:(NSString*)filterText items:(NSMutableArray*)items results:(NSMutableArray*)results;

/* PROPERTIES */

//binary filter keywords
@property(nonatomic, retain)NSMutableArray* binaryFilters;

//file filter keywords
@property(nonatomic, retain)NSMutableArray* fileFilters;


@end
