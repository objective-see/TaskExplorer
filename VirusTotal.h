//
//  VirusTotal.h
//  KnockKnock
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
@property (nonatomic, retain)NSMutableArray* items;


/* METHODS */

//add item
// ->will query VT when 25 items are hit
-(void)addItem:(Binary*)binary;

//thread function
// ->runs in the background to get virus total info about a plugin's items
//-(void)getInfo:(PluginBase*)plugin;

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

//call back up to update item in UI
// ->will either reload task table (top), or just row in item (bottom) table
-(void)updateUI:(Binary*)item;

@end
