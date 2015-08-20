//
//  FlaggedItems.h
//  TaskExplorer
//
//  Created by Patrick Wardle on 8/14/15.
//  Copyright (c) 2015 Objective-See. All rights reserved.
//

#import <Cocoa/Cocoa.h>

#import "InfoWindowController.h"
#import "VTInfoWindowController.h"


@interface SearchWindowController : NSWindowController

//automatically invoked when user presses 'Enter' in search box
// ->search!
-(IBAction)search:(id)sender;

//PROPERTIES

//flag for first time init's
@property BOOL didInit;

//search box
@property (weak) IBOutlet NSTextField *searchBox;

//table
@property (weak) IBOutlet NSTableView *searchTable;

//table items
@property(nonatomic, retain)NSMutableArray* searchResults;

//filter object
@property(nonatomic, retain)Filter* filterObj;

//vt window controller
@property (nonatomic, retain)VTInfoWindowController* vtWindowController;

//info window controller
@property(retain, nonatomic)InfoWindowController* infoWindowController;


//TODO: remove!
//tasks
@property(nonatomic, retain)NSMutableDictionary* tasks;

//dylibs
@property(nonatomic, retain)NSMutableDictionary* dylibs;

//files
@property(nonatomic, retain)NSMutableDictionary* files;

//connections
@property(nonatomic, retain)NSMutableDictionary* connections;

/* METHODS */

//init/prepare
// ->make sure everything is cleanly init'd
-(void)prepare;


@end
