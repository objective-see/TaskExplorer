//
//  FlaggedItems.h
//  TaskExplorer
//
//  Created by Patrick Wardle on 8/14/15.
//  Copyright (c) 2015 Objective-See. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "InfoWindowController.h"

@interface FlaggedItems : NSWindowController

/* PROPERTIES */

//flag for first time init's
@property BOOL didInit;

//table
@property (weak) IBOutlet NSTableView *flaggedItemTable;

//table items
@property(nonatomic, retain)NSMutableArray* flaggedItems;

//vt window controller
@property (nonatomic, retain)VTInfoWindowController* vtWindowController;

//info window controller
@property(retain, nonatomic)InfoWindowController* infoWindowController;

/* METHODS */

//init/prepare
// ->make sure everything is cleanly init'd before displaying
-(void)prepare;

@end
