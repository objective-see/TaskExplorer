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

//TODO: mouse over for info/show in finder buttons!

@interface FlaggedItems ()

@end

@implementation FlaggedItems

@synthesize didInit;
@synthesize flaggedItemTable;
@synthesize vtWindowController;

//automatically called when nib is loaded
// ->center window
-(void)awakeFromNib
{
    //single time init
    if(YES != self.didInit)
    {
        //center
        [self.window center];
        
        //set flag
        self.didInit = YES;
    }
    
    return;
}

//automatically invoked when window is loaded
// ->set to white
-(void)windowDidLoad
{
    //super
    [super windowDidLoad];
    
    //table reload
    [self.flaggedItemTable reloadData];
}

//TODO: don't need
//automatically invoked when window is closing
// ->make ourselves unmodal
-(void)windowWillClose:(NSNotification *)notification
{
    //make un-modal
    //[[NSApplication sharedApplication] stopModal];
    
    return;
}

//table delegate
// ->return number of rows, which is just number of items in the currently selected plugin
-(NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return ((AppDelegate*)[[NSApplication sharedApplication] delegate]).flaggedItems.count;
}

//table delegate method
// ->return cell for row
-(NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
    //flagged items
    NSMutableArray* flaggedItems = nil;
    
    //row view
    NSView* rowView = nil;
    
    //grab flagged items
    flaggedItems = ((AppDelegate*)[[NSApplication sharedApplication] delegate]).flaggedItems;
    
    //sanity check
    // ->make sure there is table item for row
    if(row >= flaggedItems.count)
    {
        //bail
        goto bail;
    }
    
    //create the view
    // ->inits row w/ all required info
    rowView = createItemView(tableView, self, [flaggedItems objectAtIndex:row]);
    
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

//invoked when the user clicks 'virus total' icon
// ->launch browser and browse to virus total's page
-(void)showVTInfo:(id)sender
{
    //binary
    Binary* item = nil;
    
    //row
    NSInteger itemRow = 0;
    
    //flagged items
    NSMutableArray* flaggedItems = nil;
    
    //grab flagged items
    flaggedItems = ((AppDelegate*)[[NSApplication sharedApplication] delegate]).flaggedItems;
    
    //grab sender's row
    itemRow = [self.flaggedItemTable rowForView:sender];
    
    //sanity check(s)
    // ->make sure row is decent
    if( (-1 == itemRow) ||
        (itemRow >= flaggedItems.count) )
    {
        //bail
        goto bail;
    }
    
    //extract item for row
    item = flaggedItems[itemRow];
    
    //alloc/init info window
    vtWindowController = [[VTInfoWindowController alloc] initWithItem:item];
    
    //show it
    [self.vtWindowController.windowController showWindow:self];
    
    
//bail
bail:
    
    return;
}

@end
