//
//  FlaggedItems.m
//  TaskExplorer
//
//  Created by Patrick Wardle on 8/14/15.
//  Copyright (c) 2015 Objective-See. All rights reserved.
//

#import "AppDelegate.h"
#import "FlaggedItems.h"
#import "ItemView.h"
#import "KKRow.h"
#import "Utilities.h"

@interface FlaggedItems ()

@end

@implementation FlaggedItems

@synthesize didInit;
@synthesize flaggedItems;
@synthesize flaggedItemTable;
@synthesize vtWindowController;
@synthesize infoWindowController;

//automatically called when nib is loaded
// ->first time (when outlets aren't nil), init UI
-(void)awakeFromNib
{
    //single time init
    if(YES != self.didInit)
    {
        //init UI
        [self initUI];
        
        //set flag
        self.didInit = YES;
    }
    
    return;
}

//init/prepare
// ->make sure everything is cleanly init'd before displaying
-(void)prepare
{
    //array of flagged tasks
    NSMutableArray* flaggedTasks = nil;
    
    //init array for flagged items
    flaggedItems = [NSMutableArray array];
    
    //first time outlets are nil
    // ->thus 'initUI' method called in 'awakeFromNib'
    if(nil != self.window)
    {
        //can init UI
        // ->center window, etc
        [self initUI];
        
        //set flag
        self.didInit = YES;
    }
    
    //populate flagged items array
    for(Binary* flaggedItem in ((AppDelegate*)[[NSApplication sharedApplication] delegate]).flaggedItems)
    {
        //when binary is task binary
        // ->find/save all tasks instances
        if(YES == flaggedItem.isTaskBinary)
        {
            //get all tasks instances
            flaggedTasks = [((AppDelegate*)[[NSApplication sharedApplication] delegate]).taskEnumerator tasksForBinary:flaggedItem];
            
            //sync to save
            @synchronized(self.flaggedItems)
            {
                //save all tasks
                [self.flaggedItems addObjectsFromArray:flaggedTasks];
            }
        }
        //when binary is dylib
        // ->just add, since will be processed as single item
        else
        {
            //sync to save
            @synchronized(self.flaggedItems)
            {
                //add
                [self.flaggedItems addObject:flaggedItem];
            }
        }
    }
    
    //always reload
    [self.flaggedItemTable reloadData];
    
    return;
}


//init the UI
// ->each time window is shown, reset, show spinner if needed, etc
-(void)initUI
{
    //center
    [self.window center];
    
    //table reload
    // ->make sure all is reset
    [self.flaggedItemTable reloadData];

    return;
}


//table delegate
// ->return number of rows, which is just number of items in the currently selected plugin
-(NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return self.flaggedItems.count;
}

//table delegate method
// ->return cell for row
-(NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
    //row view
    NSView* rowView = nil;
    
    //sanity check
    // ->make sure there is table item for row
    if(row >= self.flaggedItems.count)
    {
        //bail
        goto bail;
    }
    
    //create the view
    // ->inits row w/ all required info
    rowView = createItemView(tableView, self, [self.flaggedItems objectAtIndex:row]);
    
//bail
bail:
    
    return rowView;
}

//automatically invoked
// ->create custom (sub-classed) NSTableRowView
-(NSTableRowView *)tableView:(NSTableView *)tableView rowViewForRow:(NSInteger)row
{
    //row view
    KKRow* rowView = nil;
    
    //row ID
    static NSString* const kRowIdentifier = @"TableRowView";
    
    //try grab existing row view
    rowView = [tableView makeViewWithIdentifier:kRowIdentifier owner:self];
    
    //make new if needed
    if(nil == rowView)
    {
        //create new
        // ->size doesn't matter
        rowView = [[KKRow alloc] initWithFrame:NSZeroRect];
        
        //set row ID
        rowView.identifier = kRowIdentifier;
    }
    
    return rowView;
}

//automatically invoked when mouse entered
// ->highlight button
-(void)mouseEntered:(NSEvent*)theEvent
{
    //mouse entered
    // ->highlight (visual) state
    buttonAppearance(self.flaggedItemTable, theEvent, NO);
    
    return;
}

//automatically invoked when mouse exits
// ->unhighlight/reset button
-(void)mouseExited:(NSEvent*)theEvent
{
    //mouse exited
    // ->so reset button to original (visual) state
    buttonAppearance(self.flaggedItemTable, theEvent, YES);
    
    return;
}

//invoked when the user clicks 'virus total' icon
// ->launch browser and browse to virus total's page
-(void)showVTInfo:(id)sender
{
    //binary
    Binary* item = nil;
    
    //row
    NSInteger itemRow = 0;
    
    //grab sender's row
    itemRow = [self.flaggedItemTable rowForView:sender];
    
    //sanity check(s)
    // ->make sure row is decent
    if( (-1 == itemRow) ||
        (itemRow >= self.flaggedItems.count) )
    {
        //bail
        goto bail;
    }
    
    //extract item for row
    item = self.flaggedItems[itemRow];
    
    //alloc/init info window
    vtWindowController = [[VTInfoWindowController alloc] initWithItem:item];
    
    //show it
    [self.vtWindowController.windowController showWindow:self];
    
    
//bail
bail:
    
    return;
}

//automatically invoked when user clicks the 'info' icon
// ->create/configure/display info window for task/dylib/file/etc
-(IBAction)showInfo:(id)sender
{
    //item
    // ->task, dylib, file, etc
    id item =  nil;
    
    //row
    NSInteger itemRow = 0;
    
    //grab sender's row
    itemRow = [self.flaggedItemTable rowForView:sender];
    
    //sanity check(s)
    // ->make sure row is decent
    if( (-1 == itemRow) ||
       (itemRow >= self.flaggedItems.count) )
    {
        //bail
        goto bail;
    }
    
    //grab item
    item = self.flaggedItems[itemRow];
    
    //alloc/init info window
    infoWindowController = [[InfoWindowController alloc] initWithItem:item];
    
    //show it
    [self.infoWindowController.windowController showWindow:self];
    
//bail
bail:
    
    return;
}


//automatically invoked when user clicks the 'show in finder' icon
// ->open Finder to show item
-(IBAction)showInFinder:(id)sender
{
    //item
    // ->task, dylib, or file
    id item = nil;
    
    //path to item
    NSString* path = nil;
    
    //row
    NSInteger itemRow = 0;
    
    //grab sender's row
    itemRow = [self.flaggedItemTable rowForView:sender];
    
    //sanity check(s)
    // ->make sure row is decent
    if( (-1 == itemRow) ||
        (itemRow >= self.flaggedItems.count) )
    {
        //bail
        goto bail;
    }
    
    //extract item for row
    item = self.flaggedItems[itemRow];
    
    //tasks
    // ->grab path from binary
    if(YES == [item isKindOfClass:[Task class]])
    {
        //get path
        path = ((Task*)item).binary.path;
    }
    //dylib
    // ->use as is, to extract path
    else if(YES == [item isKindOfClass:[Binary class]])
    {
        //get path
        path = [item path];
    }
    
    //sanity check
    if(nil == path)
    {
        //bail
        goto bail;
    }
    
    //open Finder
    // ->will reveal binary
    [[NSWorkspace sharedWorkspace] selectFile:path inFileViewerRootedAtPath:nil];
    
    //bail
bail:
    
    return;
}

@end
