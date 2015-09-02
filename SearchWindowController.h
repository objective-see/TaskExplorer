//
//  FlaggedItems.h
//  TaskExplorer
//
//  Created by Patrick Wardle on 8/14/15.
//  Copyright (c) 2015 Objective-See. All rights reserved.
//

#import <Cocoa/Cocoa.h>

#import "CustomTextField.h"
#import "InfoWindowController.h"
#import "VTInfoWindowController.h"


@interface SearchWindowController : NSWindowController <NSWindowDelegate>

//PROPERTIES

//flag for first time init's
@property BOOL didInit;

//search box
@property (weak) IBOutlet NSTextField *searchBox;

//table
@property (weak) IBOutlet NSTableView *searchTable;

//table items
@property(nonatomic, retain)NSMutableArray* searchResults;

//activity indicator
@property (weak) IBOutlet NSProgressIndicator *activityIndicator;

//activity indicator label
@property (weak) IBOutlet NSTextField *activityIndicatorLabel;

//filter object
@property(nonatomic, retain)Filter* filterObj;

//vt window controller
@property (nonatomic, retain)VTInfoWindowController* vtWindowController;

//info window controller
@property(nonatomic, retain)InfoWindowController* infoWindowController;

//'pls wait' label
@property(nonatomic, retain)NSString* plsWaitMessage;

//overlay view
@property (weak) IBOutlet NSView *overlayView;

//flag for filter field (autocomplete)
@property BOOL completePosting;

//flag for filter field (autocomplete)
@property BOOL commandHandling;

//custom search field
@property (nonatomic, retain)CustomTextField* customSearchField;


/* METHODS */

//init/prepare
// ->make sure everything is cleanly init'd
-(void)prepare;

//search
-(void)search;


@end
