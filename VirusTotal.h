//
//  VirusTotal.h
//  TaskExplorer
//
//  Created by Patrick Wardle on 3/8/15.
//  Copyright (c) 2015 Objective-See. All rights reserved.
//

#import "Binary.h"
#import <Foundation/Foundation.h>

@interface VirusTotal : NSObject
{
    
}

/* PROPERTIES */

//array for (up to 25) items
@property(nonatomic, retain)NSMutableArray* items;

//array for all threads
@property(nonatomic, retain)NSMutableArray* vtThreads;

/* METHODS */

//add item
// ->will query VT when 25 items are hit
-(void)addItem:(Binary*)binary;

//make the (POST)query to VT
-(NSDictionary*)postRequest:(NSURL*)url parameters:(id)params;

//submit a file to VT
-(NSDictionary*)submit:(Binary*)item;

//submit a rescan request
-(NSDictionary*)reScan:(Binary*)item;

//process results
// ->updates items (found, detection ratio, etc)
-(void)processResults:(NSMutableDictionary*)queriedItems results:(NSDictionary*)results;

//get info for a single item
// ->will callback into AppDelegate to reload item
-(void)getInfoForItem:(Binary*)item scanID:(NSString*)scanID;

@end
