//
//  ItemView.h
//  TaskExplorer
//
//  Created by Patrick Wardle on 5/23/15.
//  Copyright (c) 2015 Lucas Derraugh. All rights reserved.
//

#import "File.h"
#import "Task.h"
#import "Binary.h"
#import "Connection.h"

#import <Foundation/Foundation.h>


/* METHODS */

//create customize item view
NSTableCellView* createItemView(NSTableView* tableView, id owner, id item);

//create & customize flagged item view
NSTableCellView* createFlaggedItemView(NSTableView* tableView, id owner, id item);

//create & customize task view
NSTableCellView* createTaskView(NSTableView* tableView, id owner, id item);

//create & customize dylib view
NSTableCellView* createDylibView(NSTableView* tableView, id owner, Binary* dylib);

//create & customize file view
NSTableCellView* createFileView(NSTableView* tableView, id owner, File* file);

//create & customize networking view
NSTableCellView* createNetworkView(NSTableView* tableView, id owner, Connection* connection);

//add a tracking area to a view within the item view
void addTrackingArea(NSTableCellView* itemView, NSUInteger subviewTag, id owner);

//set code signing image
// ->either signed, unsigned, or unknown
NSImage* getCodeSigningIcon(Binary* binary);

//configure the VT button
// ->also set's binary name to red if known malware
void configVTButton(NSTableCellView *itemCell, id owner, Binary* binary);