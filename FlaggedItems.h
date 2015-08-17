//
//  FlaggedItems.h
//  TaskExplorer
//
//  Created by Patrick Wardle on 8/14/15.
//  Copyright (c) 2015 Lucas Derraugh. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface FlaggedItems : NSWindowController

//PROPERTIES

//flag for first time init's
@property BOOL didInit;

//table
@property (weak) IBOutlet NSTableView *flaggedItemTable;

//vt window controller
@property (nonatomic, retain)VTInfoWindowController* vtWindowController;

@end
