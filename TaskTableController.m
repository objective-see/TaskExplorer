//
//  ItemTableController.m
//  TaskExplorer
//
//  Created by Patrick Wardle on 2/18/15.
//  Copyright (c) 2015 Objective-See. All rights reserved.
//

#import "KKRow.h"
#import "Binary.h"
#import "Consts.h"
#import "ItemBase.h"
#import "ItemView.h"
#import "VTButton.h"
#import "kkRowCell.h"
#import "Utilities.h"
#import "AppDelegate.h"
#import "TaskTableController.h"
#import "InfoWindowController.h"

@implementation TaskTableController

@synthesize itemView;
@synthesize isFiltered;
@synthesize tableItems;
@synthesize selectedRow;
@synthesize isBottomPane;
@synthesize filteredItems;
@synthesize ignoreSelection;
@synthesize vtWindowController;
@synthesize infoWindowController;

@synthesize didInit;

-(void)awakeFromNib
{
    //single time init
    if(YES != self.didInit)
    {
        //init selected row
        self.selectedRow = 0;
        
        //alloc array for filtered items
        filteredItems = [NSMutableArray array];
        
        //extand tree view
        if(YES == [self.itemView isKindOfClass:[NSOutlineView class]])
        {
            //expand
            [(NSOutlineView*)self.itemView expandItem:nil expandChildren:YES];
        }
        
        //set flag
        self.didInit = YES;
    }
    
    return;
}

//table delegate
// ->return number of rows, which is just number of items in the currently selected plugin
-(NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    //rows
    NSUInteger rows = 0;
    
    //tasks
    OrderedDictionary* tasks = nil;
    
    //for top pane
    // ->use tasks from enumerator
    if(YES != self.isBottomPane)
    {
        //when not filtered
        // ->use all tasks
        if(YES != isFiltered)
        {
            //get tasks
            tasks = taskEnumerator.tasks;
        
            //set count
            rows = tasks.count;
        }
        //when filtered
        // ->use filtered items
        else
        {
            //set count
            rows = self.filteredItems.count;
        }
    }
    //bottom pane uses 'tableItems' iVar
    else
    {
        //when not filtered
        // ->use all items
        if(YES != isFiltered)
        {
            //set row count
            rows = self.tableItems.count;
        }
        //when filtered
        // ->use filtered items
        else
        {
            //set count
            rows = self.filteredItems.count;
        }
    }
    
    return rows;
    
}

//automatically invoked when user selects row
// ->only care about for top pane, trigger load bottom view
-(void)tableViewSelectionDidChange:(NSNotification *)notification
{
    //only handle user selections
    // ->not those from 'reloadData'
    if(YES != self.ignoreSelection)
    {
        //handle selection
        [self handleRowSelection];
    }
    
    return;
}

//table delegate method
// ->return cell for row
-(NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
    //tasks
    OrderedDictionary* tasks = nil;
    
    //item obj
    // ->contains data for view
    id item = nil;
    
    //row view
    NSView* rowView = nil;
    
    //for TOP PANE
    // ->use tasks from enumerator or filtered items
    if(YES != self.isBottomPane)
    {
        //when not filtered
        // ->use tasks
        if(YES != isFiltered)
        {
            //grab tasks
            tasks = taskEnumerator.tasks;
            
            //sanity check
            // ->make sure there is table item for row
            if(tasks.count <= row)
            {
                //bail
                goto bail;
            }
            
            //get task object
            // ->by index to get key, then by key
            item = tasks[[tasks keyAtIndex:row]];
        
        }
        
        //when filtered
        // ->use filtered items
        else
        {
            //sanity check
            // ->make sure there is table item for row
            if(self.filteredItems.count <= row)
            {
                //bail
                goto bail;
            }

            //get task object
            item = self.filteredItems[row];
        }
    }
    
    //for BOTTOM PANE
    else
    {
        
        //when not filtered
        // ->use all items
        if(YES != isFiltered)
        {
            //sanity check
            // ->make sure there is table item for row
            if(self.tableItems.count <= row)
            {
                //bail
                goto bail;
            }
            
            //grab item
            // ->dylib/file/network item
            item = [self.tableItems objectAtIndex:row];
        }
        
        //when filtered
        // ->use filtered items
        else
        {
            //sanity check
            // ->make sure there is table item for row
            if(self.filteredItems.count <= row)
            {
                //bail
                goto bail;
            }
            
            //set count
            item = [self.filteredItems objectAtIndex:row];
        }
        
    }
    
    //create custom item view
    if(nil != item)
    {
        //create
        rowView = createItemView(tableView, self, item);
    }
    
    return rowView;
    
    
//bail
bail:
    
    return nil;
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
    buttonAppearance(self.itemView, theEvent, NO);
    
    return;
}

//automatically invoked when mouse exits
// ->unhighlight/reset button
-(void)mouseExited:(NSEvent*)theEvent
{
    //mouse exited
    // ->so reset button to original (visual) state
    buttonAppearance(self.itemView, theEvent, YES);
    
    return;
}

//scroll back up to top of table
-(void)scrollToTop
{
    //scroll if more than 1 row
    if([self.itemView numberOfRows] > 0)
    {
        //top
        [self.itemView scrollRowToVisible:0];
    }
}

//reload table
-(void)reloadTable
{
    //reload table
    [self.itemView reloadData];
    
    //scroll to top
    [self scrollToTop];
    
    return;
}

//custom reload
// ->ensures selected row remains selected
-(void)refresh
{
    //tasks
    OrderedDictionary* tasks = nil;
    
    //selected task
    Task* selectedTask = nil;
    
    //task index after reload
    NSUInteger taskIndex = 0;
    
    //grab tasks
    tasks = taskEnumerator.tasks;
    
    //get task
    selectedTask = [self taskForRow:nil];
    
    //ignore selection change though
    self.ignoreSelection = YES;

    //always reload
    [self.itemView reloadData];
    
    //don't ignore selection
    self.ignoreSelection = NO;
    
    //when an item was selected
    // ->get its index and make sure that's still selected
    if(nil != selectedTask)
    {
        //get task's index
        // ->flat view, can do a straight lookup
        if(YES != [self.itemView isKindOfClass:[NSOutlineView class]])
        {
            //get index
            taskIndex = [tasks indexOfKey:selectedTask.pid];
        }
        //get task's index
        // ->outline view, use 'rowForItem' method
        else
        {
            taskIndex = [(NSOutlineView*)self.itemView rowForItem:selectedTask];
        }
        
        //(re)select task's row
        // ->but only if task still exists (e.g. didn't exit)
        if(NSNotFound != taskIndex)
        {
            //begin updates
            [self.itemView beginUpdates];
            
            //(re)select
            [self.itemView selectRowIndexes:[NSIndexSet indexSetWithIndex:taskIndex] byExtendingSelection:NO];
            
            //end updates
            [self.itemView endUpdates];
        }
    }
    
    /*
    //otherwise select first row
    else
    {
        //selected row cell
        NSTableCellView* rowView = nil;
        
        //default to first row
        self.selectedRow = 0;
        
        //sanity check
        if(0 == [self numberOfRowsInTableView:self.itemView])
        {
            //bail
            goto bail;
        }
        
        //get first row
        rowView = [self.itemView viewAtColumn:0 row:0 makeIfNecessary:YES];

        //extract task
        // ->pid of task is view's id :)
        Task* task = tasks[[NSNumber numberWithInteger:(rowView.tag - PID_TAG_DELTA)]];
        
        //save task
        ((AppDelegate*)[[NSApplication sharedApplication] delegate]).currentTask = task;
        
        //reload bottom pane
        [((AppDelegate*)[[NSApplication sharedApplication] delegate]) selectBottomPaneContent:nil];
    }
    */
    
    
//bail
bail:
    
    return;
}

//grab a task at a row
-(Task*)taskForRow:(id)sender
{
    //index of row
    NSInteger taskRow = 0;
    
    //selected row cell
    NSTableCellView* rowView = nil;
    
    //tasks
    OrderedDictionary* tasks = nil;
    
    //task
    Task* task = nil;
    
    //grab tasks
    tasks = taskEnumerator.tasks;
    
    //use sender if provided
    if(nil != sender)
    {
        //grab row
        taskRow = [self.itemView rowForView:sender];
    }
    //otherwise use selected row
    else
    {
        //grab row
        taskRow = [self.itemView selectedRow];
    }
    
    //sanity check(s)
    // ->make sure row is decent
    if( (-1 == taskRow) ||
        ((YES != self.isFiltered) && (tasks.count < taskRow)) ||
        ((YES == self.isFiltered) && (self.filteredItems.count < taskRow)) )
    {
        //bail
        goto bail;
    }
    
    //get row that's about to be selected
    rowView = [self.itemView viewAtColumn:0 row:taskRow makeIfNecessary:YES];
    
    //extract task
    // ->pid of task is view's id :)
    task = tasks[[NSNumber numberWithInteger:(rowView.tag - PID_TAG_DELTA)]];
    
//bail
bail:
    
    return task;
}

 
//grab an item at a row
-(ItemBase*)itemForRow:(id)sender
{
    //index of row
    NSInteger itemRow = 0;
    
    //item
    ItemBase* item = nil;
    
    //grab row
    itemRow = [self.itemView rowForView:sender];

    //sanity check(s)
    // ->make sure row has item
    if( (-1 == itemRow) ||
        ((YES != self.isFiltered) && (self.tableItems.count < itemRow)) ||
        ((YES == self.isFiltered) && (self.filteredItems.count < itemRow)) )
    {
        //bail
        goto bail;
    }

    //when not filtered
    // ->just grab item
    if(YES != self.isFiltered)
    {
        //get item
        item = self.tableItems[itemRow];
    }
    //when filtered
    // ->grab from filtered item
    else
    {
        //get item
        item = self.filteredItems[itemRow];
    }
    
//bail
bail:
    
    return item;
}


//automatically invoked when user clicks the 'show in finder' icon
// ->open Finder to show item
-(IBAction)showInFinder:(id)sender
{
    //item
    // ->task, dylib, file, etc
    id item =  nil;
    
    //path to binary
    NSString* path = nil;
    
    //file open error alert
    NSAlert* errorAlert = nil;
    
    //for top pane
    // ->get task
    if(YES != self.isBottomPane)
    {
        //get task
        item = [self taskForRow:sender];
        
        //get path
        path = ((Task*)item).binary.path;
    }
    
    //bottom pane
    else
    {
        //get item
        item = [self itemForRow:sender];
        
        //get path
        path = ((Binary*)item).path;
    }
    
    //sanity check
    if(nil == path)
    {
        //bail
        goto bail;
    }

    //open item in Finder
    // ->error alert shown if file open fails
    if(YES != [[NSWorkspace sharedWorkspace] selectFile:path inFileViewerRootedAtPath:@""])
    {
        //alloc/init alert
        errorAlert = [NSAlert alertWithMessageText:[NSString stringWithFormat:@"ERROR:\nfailed to open %@", path] defaultButton:@"OK" alternateButton:nil otherButton:nil informativeTextWithFormat:@"errno value: %d", errno];
        
        //show it
        [errorAlert runModal];
    }

    
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

    //for top pane
    // ->get task
    if(YES != self.isBottomPane)
    {
        //get task
        item = [self taskForRow:sender];
    }
    
    //bottom pane
    else
    {
        //get item
        item = [self itemForRow:sender];
    }
    
    //alloc/init info window
    infoWindowController = [[InfoWindowController alloc] initWithItem:item];
    
    //show it
    [self.infoWindowController.windowController showWindow:self];
    
//bail
bail:
    
    return;
}

//invoked when the user clicks 'virus total' icon
// ->launch browser and browse to virus total's page
-(void)showVTInfo:(id)sender
{
    //item
    // ->task, dylib, file, etc
    Binary* binary = nil;
    
    //for top pane
    // ->get binary from task
    if(YES != self.isBottomPane)
    {
        //get task's binary
        binary = [(Task*)[self taskForRow:sender] binary];
    }
    
    //bottom pane
    // ->straight assign
    else
    {
        //get item
        binary = (Binary*)[self itemForRow:sender];
    }

    //bail on nil binaries
    if(nil == binary)
    {
        //bail
        goto bail;
    }
    
    //alloc/init info window
    vtWindowController = [[VTInfoWindowController alloc] initWithItem:binary];
    
    //show it
    [self.vtWindowController.windowController showWindow:self];
    
    
//bail
bail:
    
    return;
}


//OUTLINE VIEW STUFFZ

-(NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item
{
    //tasks
    OrderedDictionary* tasks = nil;
    
    //grab tasks
    tasks = taskEnumerator.tasks;
    
    //number of children
    NSUInteger numberOfChildren = 0;
    
    //when item is nil
    // ->count is number of root items children
    if(nil == item)
    {
        //kids
        numberOfChildren = ((Task*)[tasks objectForKey:@0]).children.count;
    }
    //otherwise
    // ->give number of item's kids
    else
    {
        //kids
        numberOfChildren = [((Task*)item).children count];
    }
    
    return numberOfChildren;
}

-(BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item
{
    //only no for leafs
    // ->items w/o kids
    if( (nil != item) &&
        (0 == [[item children] count]) )
    {
        return NO;
    }
    else
    {
        return YES;
    }
    //return !item ? YES : [[item children] count] != 0;
}


//return child
-(id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item
{
    //tasks
    OrderedDictionary* tasks = nil;
    
    //task
    Task* task = nil;
    
    //grab all tasks
    tasks = taskEnumerator.tasks;
    
    //root item
    if(nil == item)
    {
        //root
        task = [tasks objectForKey:@0];
    }
    //non-root items
    // ->return *their* child!
    else
    {
        task = [tasks objectForKey:[(Task*)item children][index]];
    }
    
    return task;
}


//automatically ccalled when row is selected in outline view
// ->invoke helper function to handle selection
-(void)outlineViewSelectionDidChange:(NSNotification *)notification
{
    //handle selection
    [self handleRowSelection];
    
    return;
}

//table delegate method
// ->return cell for row
-(NSView *)outlineView:(NSOutlineView *)outlineView viewForTableColumn:(NSTableColumn *)tableColumn item:(id)item
{
    return createItemView(outlineView, self, (Task*)item);
}

//automatically invoked
// ->create custom (sub-classed) NSTableRowView
-(NSTableRowView *)outlineView:(NSOutlineView *)outlineView rowViewForItem:(id)item
{
    //row view
    KKRow* rowView = nil;
    
    //row ID
    static NSString* const kRowIdentifier = @"OutlineRowView";
    
    //try grab existing row view
    rowView = [outlineView makeViewWithIdentifier:kRowIdentifier owner:self];
    
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

/* LOGIC FOR BOTH */

//handle when user clicks row
// ->update bottom pane w/ task's dylibs/files/etc
-(void)handleRowSelection
{
    //tasks
    __block OrderedDictionary* tasks = nil;
    
    //task
    Task* task = nil;
    
    //newly selected row (index)
    __block NSInteger newlySelectedRow = -1;
    
    //selected row cell
    NSTableCellView* selectedView = nil;
    
    //ignore events for bottom-pane
    if(YES == self.isBottomPane)
    {
        //ignore
        goto bail;
    }
    
    //grab tasks
    tasks = taskEnumerator.tasks;
    
    //get index of newly selected row
    newlySelectedRow = [self.itemView selectedRow];
    
    //sanity check
    if( (-1 == newlySelectedRow) ||
        ((YES != self.isFiltered) && (newlySelectedRow >= tasks.count)) ||
        ((YES == self.isFiltered) && (newlySelectedRow >= self.filteredItems.count)) )
    {
        //bail
        goto bail;
    }
    
    //get view that's about to be selected
    selectedView = [self.itemView viewAtColumn:0 row:newlySelectedRow makeIfNecessary:YES];
       
    //extract task
    // ->pid of task is view's id :)
    task = tasks[[NSNumber numberWithInteger:(selectedView.tag - PID_TAG_DELTA)]];
    
    //check if task is dead
    if(YES != isAlive([task.pid intValue]))
    {
        //make it red
        ((kkRowCell*)selectedView).color = [NSColor redColor];
        
        //draw
        [selectedView setNeedsDisplay:YES];
        
        //make hidden it after .33 second
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(.33 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            
            //reset color
            ((kkRowCell*)selectedView).color = nil;
            
            //remove task from task emumerator
            [taskEnumerator removeTask:task];
            
            //when filtering
            // ->remove deceased task from filter tasks
            if(YES == isFiltered)
            {
                //remove
                [self.filteredItems removeObject:task];
            }
            
            //reload table
            [self.itemView reloadData];
            
            //sanity check
            // ->make sure removed task wasn't last
            if(tasks.count <= newlySelectedRow)
            {
                //reset to (new) last
                newlySelectedRow = tasks.count - 1;
            }
            //sanity check
            // ->reset to first item on other errors
            else if(-1 == newlySelectedRow)
            {
                //set to first
                newlySelectedRow = 0;
            }
            
            //begin updates
            [self.itemView beginUpdates];
            
            //re-select
            [self.itemView selectRowIndexes:[NSIndexSet indexSetWithIndex:newlySelectedRow] byExtendingSelection:NO];
            
            //end updates
            [self.itemView endUpdates];
            
            //reload bottom pane
            [((AppDelegate*)[[NSApplication sharedApplication] delegate]) selectBottomPaneContent:nil];
            
        });
        
        //bail
        goto bail;
    }
    
    //ignore if row selection and task didn't change
    if( (newlySelectedRow == self.selectedRow) &&
        (((AppDelegate*)[[NSApplication sharedApplication] delegate]).currentTask == task) )
    {
        //ignore
        goto bail;
    }
    
    //save newly selected row index
    self.selectedRow = [self.itemView selectedRow];
    
    //save currently selected task
    ((AppDelegate*)[[NSApplication sharedApplication] delegate]).currentTask = task;
    
    //reload bottom pane
    [((AppDelegate*)[[NSApplication sharedApplication] delegate]) selectBottomPaneContent:nil];
    

bail:
    ;
    
    return;
}


@end
