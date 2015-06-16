//
//  ItemTableController.m
//  KnockKnock
//
//  Created by Patrick Wardle on 2/18/15.
//  Copyright (c) 2015 Objective-See. All rights reserved.
//

//TODO: list of what's running on my Mac!!!!

#import "Binary.h"
#import "Consts.h"
#import "ItemView.h"
#import "VTButton.h"


#import "Utilities.h"
#import "AppDelegate.h"
#import "ItemBase.h"
#import "TaskTableController.h"
#import "InfoWindowController.h"

#import "KKRow.h"
#import "kkRowCell.h"

#import <AppKit/AppKit.h>

@implementation TaskTableController

@synthesize itemView;
@synthesize tableItems;
@synthesize selectedRow;
@synthesize isBottomPane;
@synthesize vtWindowController;
@synthesize infoWindowController;



//@synthesize tasks;
-(void)awakeFromNib
{
    self.selectedRow = -1;
    
    /*
    NSString *title = @"[ all tasks ]";
    NSTableColumn *yourColumn = self.itemView.tableColumns.lastObject;
    [yourColumn.headerCell setStringValue:title];
    
    [self.itemView setIndicatorImage:[NSImage imageNamed:@"NSDescendingSortIndicator"] inTableColumn:self.itemView.tableColumns.lastObject];
     
    */
}


/*
//invoked automatically while nib is loaded
// ->note: outlets are nil here...
-(id)init
{
    self = [super init];
    if(nil != self)
    {
        self.selectedRow = -1;
    }
    
    return self;
}
*/

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
        //grab tasks
        tasks = ((AppDelegate*)[[NSApplication sharedApplication] delegate]).taskEnumerator.tasks;
        
        //set row count
        rows = tasks.count;
    }
    //bottom pane uses table items
    else
    {
        //set row count
        rows = self.tableItems.count;
    }
    
    return rows;
    
    /*
    
     
     
    //plugin object
    PluginBase* selectedPluginObj = nil;
    
    //set selected plugin
    selectedPluginObj =  ((AppDelegate*)[[NSApplication sharedApplication] delegate]).selectedPlugin;
    
    //invoke helper function to get array
    // ->then grab count
    rows = [[self getTableItems] count];
    
    //if not items have been found
    // ->display 'not found' msg
    if( (0 == rows) &&
        (nil != selectedPluginObj) )
    {
        //set string (to include plugin's name)
        [self.noItemsLabel setStringValue:[NSString stringWithFormat:@"no %@ found", [selectedPluginObj.name lowercaseString]]];
        
        //show label
        self.noItemsLabel.hidden = NO;
    }
    else
    {
        //hide label
        self.noItemsLabel.hidden = YES;
    }

    return rows;
    */
}

//automatically invoked when user selects row
// ->only care about for top pane, trigger load bottom view
-(void)tableViewSelectionDidChange:(NSNotification *)notification
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
    
    //get index of newly selected row
    newlySelectedRow = [self.itemView selectedRow];
    
    //get row that's about to be selected
    selectedView = [self.itemView viewAtColumn:0 row:newlySelectedRow makeIfNecessary:YES];
    
    //grab task
    task = [self taskForRow:nil];
    
    //check if task is dead
    if(YES != isAlive([task.pid intValue]))
    {
        //make it red
        ((kkRowCell*)selectedView).color = [NSColor redColor];
        
        //draw
        [selectedView setNeedsDisplay:YES];
        
        //make hide it after 1/4th second
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            
            //reset color
            ((kkRowCell*)selectedView).color = nil;
            
            //get tasks
            tasks = ((AppDelegate*)[[NSApplication sharedApplication] delegate]).taskEnumerator.tasks;
            
            //remove (now dead) task
            [tasks removeObjectForKey:task.pid];
            
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
            
            //re-select
            [self.itemView selectRowIndexes:[NSIndexSet indexSetWithIndex:newlySelectedRow] byExtendingSelection:NO];
            
        });

        //bail
        goto bail;
        
    }
    
    //ignore if row selection didn't change
    if([self.itemView selectedRow] == self.selectedRow)
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


//bail
bail:

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
    // ->use tasks from enumerator
    if(YES != self.isBottomPane)
    {
        //grab tasks
        tasks = ((AppDelegate*)[[NSApplication sharedApplication] delegate]).taskEnumerator.tasks;
        
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
    
    //for BOTTOM PANE
    else
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
    
    //create custom item view
    if(nil != item)
    {
        //create
        rowView = createItemView(tableView, self, item);
    }
    
    return rowView;
    
    
    /*
    //item cell
    NSTableCellView *itemCell = nil;
    
    //tasks
    OrderedDictionary* tasks = nil;
    
    //task
    Task* task =  nil;
    
    //signature icon
    NSImageView* signatureImageView = nil;
    
    //VT detection ratio
    NSString* vtDetectionRatio = nil;
    
    //virus total button
    // ->for File objects only...
    VTButton* vtButton;
    
    //(for files) signed/unsigned icon
    NSImage* signatureStatus = nil;
    
    //task's name frame
    CGRect nameFrame = {0};
    
    //attribute dictionary
    NSMutableDictionary *stringAttributes = nil;
    
    //paragraph style
    NSMutableParagraphStyle *paragraphStyle = nil;
    
    //truncated path
    //NSString* truncatedPath = nil;
    
    //truncated plist
    //NSString* truncatedPlist = nil;
    
    //tracking area
    NSTrackingArea* trackingArea = nil;
    
    //flag indicating row has tracking area
    // ->ensures we don't add 2x
    BOOL hasTrackingArea = NO;
    
    //grab tasks
    tasks = ((AppDelegate*)[[NSApplication sharedApplication] delegate]).taskEnumerator.tasks;
    
    //sanity check
    // ->make sure there is table item for row
    if(tasks.count <= row)
    {
        //bail
        goto bail;
    }
  
    //get task object
    // ->by index to get key, then by key
    task = tasks[[tasks keyAtIndex:row]];
    
    //make table cell
    itemCell = [tableView makeViewWithIdentifier:@"ImageCell" owner:self];
    if(nil == itemCell)
    {
        //bail
        goto bail;
    }
    
    //check if cell was previously used (by checking the item name)
    // ->if so, set flag to indicated tracking area does not need to be added
    if(YES != [itemCell.textField.stringValue isEqualToString:@"Item Name"])
    {
        //set flag
        hasTrackingArea = YES;
    }
    
    //default
    // ->set main textfield's color to black
    itemCell.textField.textColor = [NSColor blackColor];
    
    //set main text
    // ->name
    if( (nil != task.binary) &&
        (nil != task.binary.name) )
    {
       
        [itemCell.textField setStringValue:task.binary.name];
    }
    
    //get name frame
    nameFrame = itemCell.textField.frame;
    
    //adjust width to fit text
    nameFrame.size.width = [itemCell.textField.stringValue sizeWithAttributes: @{NSFontAttributeName: itemCell.textField.font}].width + 5;
    
    //disable autolayout
    itemCell.textField.translatesAutoresizingMaskIntoConstraints = YES;
    
    //update frame
    // ->should now be exact size of text
    itemCell.textField.frame = nameFrame;
    
    //[itemCell.textField setDrawsBackground:YES];
    
    //NSLog(@"size after: %f", itemCell.textField.frame.size.width);
    
    //itemCell.textField.backgroundColor = [NSColor redColor];
    
    //set pid
    [((NSTextField*)[itemCell viewWithTag:TABLE_ROW_PID_LABEL]) setStringValue:[NSString stringWithFormat:@"(%@)", task.pid]];
    
    //only have to add tracking area once
    // ->add it the first time
    if(NO == hasTrackingArea)
    {
        //init tracking area
        // ->for 'show' button
        trackingArea = [[NSTrackingArea alloc] initWithRect:[[itemCell viewWithTag:TABLE_ROW_SHOW_BUTTON] bounds]
                        options:(NSTrackingInVisibleRect | NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways)
                        owner:self userInfo:@{@"tag":[NSNumber numberWithUnsignedInteger:TABLE_ROW_SHOW_BUTTON]}];
        
        //add tracking area to 'show' button
        [[itemCell viewWithTag:TABLE_ROW_SHOW_BUTTON] addTrackingArea:trackingArea];
        
        //init tracking area
        // ->for 'info' button
        trackingArea = [[NSTrackingArea alloc] initWithRect:[[itemCell viewWithTag:TABLE_ROW_INFO_BUTTON] bounds]
                        options:(NSTrackingInVisibleRect | NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways)
                        owner:self userInfo:@{@"tag":[NSNumber numberWithUnsignedInteger:TABLE_ROW_INFO_BUTTON]}];
        
        //add tracking area to 'info' button
        [[itemCell viewWithTag:TABLE_ROW_INFO_BUTTON] addTrackingArea:trackingArea];
    }
    
    //get signature image view
    signatureImageView = [itemCell viewWithTag:TABLE_ROW_SIGNATURE_ICON];
    
    //set detailed text
    // ->path
    //if(YES == [item isKindOfClass:[File class]])
    //{
        //grab virus total button
        // ->need it for frame computations, etc
        vtButton = [itemCell viewWithTag:TABLE_ROW_VT_BUTTON];
        
        //set image
        // ->app's icon
        itemCell.imageView.image = task.binary.icon;

    
        //set signature status icon
        //switch on signing status
        if( (nil != task.binary.signingInfo) &&
            (STATUS_SUCCESS == [task.binary.signingInfo[KEY_SIGNATURE_STATUS] integerValue]) )
        {
            //signed
            signatureStatus = [NSImage imageNamed:@"signed"];
        }
        //signature not present or invalid
        // ->just set text unsigned
        else
        {
            //signed
            signatureStatus = [NSImage imageNamed:@"unsigned"];
        }
        

        //set signature icon
        signatureImageView.image = signatureStatus;
        
        //show signature icon
        signatureImageView.hidden = NO;
    
        //set detailed text
        // ->always item's path
        [[itemCell viewWithTag:TABLE_ROW_SUB_TEXT_TAG] setStringValue:task.binary.path];
    
        /*
        //for files w/ plist
        // ->set/show
        if(nil != task.plist)
        {
            //shift up frame
            pathFrame.origin.y = 20;
        
            //set new frame
            ((NSTextField*)[itemCell viewWithTag:TABLE_ROW_PATH_LABEL]).frame = pathFrame;
            
            //truncate plist
            truncatedPlist = stringByTruncatingString([itemCell viewWithTag:TABLE_ROW_SUB_TEXT_TAG], ((File*)item).plist, itemCell.frame.size.width-TABLE_BUTTONS_FILE);
        
            //set plist
            [((NSTextField*)[itemCell viewWithTag:TABLE_ROW_PLIST_LABEL]) setStringValue:truncatedPlist];
            
            //show
            [((NSTextField*)[itemCell viewWithTag:TABLE_ROW_PLIST_LABEL]) setHidden:NO];
        }
        */
    
    /*
        //configure/show VT info
        // ->only if 'disable' preference not set
        if(YES != ((AppDelegate*)[[NSApplication sharedApplication] delegate]).prefsWindowController.disableVTQueries)
        {
            //set button delegate
            vtButton.delegate = self;
            
            //save file obj
            vtButton.fileObj = task
            
            //check if have vt results
            if(nil != ((File*)item).vtInfo)
            {
                //set font
                [vtButton setFont:[NSFont fontWithName:@"Menlo-Bold" size:25]];
                
                //enable
                vtButton.enabled = YES;
                
                //got VT results
                // ->check 'permalink' to determine if file is known to VT
                //   then, show ratio and set to red if file is flagged
                if(nil != ((File*)item).vtInfo[VT_RESULTS_URL])
                {
                    //alloc paragraph style
                    paragraphStyle = [[NSMutableParagraphStyle alloc] init];
                    
                    //center the text
                    [paragraphStyle setAlignment:NSCenterTextAlignment];
                    
                    //alloc attributes dictionary
                    stringAttributes = [NSMutableDictionary dictionary];
                    
                    //set underlined attribute
                    stringAttributes[NSUnderlineStyleAttributeName] = @(NSUnderlineStyleSingle);
                    
                    //set alignment (center)
                    stringAttributes[NSParagraphStyleAttributeName] = paragraphStyle;
                    
                    //set font
                    stringAttributes[NSFontAttributeName] = [NSFont fontWithName:@"Menlo-Bold" size:15];
                    
                    //compute detection ratio
                    vtDetectionRatio = [NSString stringWithFormat:@"%lu/%lu", (unsigned long)[((File*)item).vtInfo[VT_RESULTS_POSITIVES] unsignedIntegerValue], (unsigned long)[((File*)item).vtInfo[VT_RESULTS_TOTAL] unsignedIntegerValue]];
                    
                    //known 'good' files (0 positivies)
                    if(0 == [((File*)item).vtInfo[VT_RESULTS_POSITIVES] unsignedIntegerValue])
                    {
                        //(re)set title black
                        itemCell.textField.textColor = [NSColor blackColor];
                        
                        //set color (black)
                        stringAttributes[NSForegroundColorAttributeName] = [NSColor blackColor];
                        
                        //set string (vt ratio), with attributes
                        [vtButton setAttributedTitle:[[NSAttributedString alloc] initWithString:vtDetectionRatio attributes:stringAttributes]];
                        
                        //set color (gray)
                        stringAttributes[NSForegroundColorAttributeName] = [NSColor grayColor];
                        
                        //set selected text color
                        [vtButton setAttributedAlternateTitle:[[NSAttributedString alloc] initWithString:vtDetectionRatio attributes:stringAttributes]];
                    }
                    //files flagged by VT
                    // ->set name and detection to red
                    else
                    {
                        //set title red
                        itemCell.textField.textColor = [NSColor redColor];
                        
                        //set color (red)
                        stringAttributes[NSForegroundColorAttributeName] = [NSColor redColor];
                        
                        //set string (vt ratio), with attributes
                        [vtButton setAttributedTitle:[[NSAttributedString alloc] initWithString:vtDetectionRatio attributes:stringAttributes]];
                        
                        //set selected text color
                        [vtButton setAttributedAlternateTitle:[[NSAttributedString alloc] initWithString:vtDetectionRatio attributes:stringAttributes]];
                        
                    }
                    
                    //enable
                    [vtButton setEnabled:YES];
                }
            
                //file is not known
                // ->reset title to '?'
                else
                {
                    //set title
                    [vtButton setTitle:@"?"];
                }
            }
        
            //no VT results (e.g. unknown file)
            else
            {
                //set font
                [vtButton setFont:[NSFont fontWithName:@"Menlo-Bold" size:8]];
                
                //set title
                [vtButton setTitle:@"▪ ▪ ▪"];
                
                //disable
                vtButton.enabled = NO;
            }
            
            //show virus total button
            vtButton.hidden = NO;
            
            //show virus total label
            [[itemCell viewWithTag:TABLE_ROW_VT_BUTTON+1] setHidden:NO];
            
        }//show VT info (pref not disabled)
        
        //hide VT info
        else
        {
            //hide virus total button
            vtButton.hidden = YES;
            
            //hide virus total button label
            [[itemCell viewWithTag:TABLE_ROW_VT_BUTTON+1] setHidden:YES];
        }
     
    */
    

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
    static NSString* const kRowIdentifier = @"RowView";
    
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
-(void)mouseEntered:(NSEvent*)theEvent
{
    //mouse entered
    // ->highlight (visual) state
    [self buttonAppearance:theEvent shouldReset:NO];
    
    return;
}

//automaticall invoked when mouse exits
-(void)mouseExited:(NSEvent*)theEvent
{
    //mouse exited
    // ->so reset button to original (visual) state
    [self buttonAppearance:theEvent shouldReset:YES];
    
    return;
}

//set or unset button's highlight
-(void)buttonAppearance:(NSEvent*)theEvent shouldReset:(BOOL)shouldReset
{
    //mouse point
    NSPoint mousePoint = {0};
    
    //row index
    NSUInteger rowIndex = -1;
    
    //current row
    NSTableCellView* currentRow = nil;
    
    //tag
    NSUInteger tag = 0;
    
    //button
    NSButton* button = nil;
    
    //button's label
    NSTextField* label = nil;
    
    //image name
    NSString* imageName =  nil;
    
    //extract tag
    tag = [((NSDictionary*)theEvent.userData)[@"tag"] unsignedIntegerValue];
    
    //restore button back to default (visual) state
    if(YES == shouldReset)
    {
        //set image name
        // ->'info'
        if(TABLE_ROW_INFO_BUTTON == tag)
        {
            //set
            imageName = @"info";
        }
        //set image name
        // ->'info'
        else if(TABLE_ROW_SHOW_BUTTON == tag)
        {
            //set
            imageName = @"show";
        }
    }
    //highlight button
    else
    {
        //set image name
        // ->'info'
        if(TABLE_ROW_INFO_BUTTON == tag)
        {
            //set
            imageName = @"infoOver";
        }
        //set image name
        // ->'info'
        else if(TABLE_ROW_SHOW_BUTTON == tag)
        {
            //set
            imageName = @"showOver";
        }
    }
    
    //grab mouse point
    mousePoint = [self.itemView convertPoint:[theEvent locationInWindow] fromView:nil];
    
    //compute row indow
    rowIndex = [self.itemView rowAtPoint:mousePoint];
    
    //sanity check
    if(-1 == rowIndex)
    {
        //bail
        goto bail;
    }
    
    //get row that's about to be selected
    currentRow = [self.itemView viewAtColumn:0 row:rowIndex makeIfNecessary:YES];
    
    //get button
    // ->tag id of button, passed in userData var
    button = [currentRow viewWithTag:[((NSDictionary*)theEvent.userData)[@"tag"] unsignedIntegerValue]];
    label = [currentRow viewWithTag: 1 + [((NSDictionary*)theEvent.userData)[@"tag"] unsignedIntegerValue]];

    //restore default button image
    // ->for 'info' and 'show' buttons
    if(nil != imageName)
    {
        //set image
        [button setImage:[NSImage imageNamed:imageName]];
    }
    
//bail
bail:
    
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
    tasks = ((AppDelegate*)[[NSApplication sharedApplication] delegate]).taskEnumerator.tasks;
    
    //get task
    selectedTask = [self taskForRow:nil];
    
    //always reload
    [self.itemView reloadData];
    
    //when an item was selected
    // ->get its index and make sure that's still selected
    if(nil != selectedTask)
    {
        //get task's index
        taskIndex = [tasks indexOfKey:selectedTask.pid];
        
        //(re)select task's row
        // ->but only if task still exists (e.g. didn't exit)
        if(NSNotFound != taskIndex)
        {
            //(re)select
            [self.itemView selectRowIndexes:[NSIndexSet indexSetWithIndex:taskIndex] byExtendingSelection:NO];
        }
    }
    
    return;
}

//grab a task at a row
-(Task*)taskForRow:(id)sender
{
    //index of row
    NSInteger taskRow = 0;
    
    //tasks
    OrderedDictionary* tasks = nil;
    
    //task
    Task* task = nil;
    
    //grab tasks
    tasks = ((AppDelegate*)[[NSApplication sharedApplication] delegate]).taskEnumerator.tasks;
    
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
    // ->make sure row has item
    if( (-1 == taskRow) ||
        (tasks.count < taskRow) )
    {
        //bail
        goto bail;
    }
    
    //get task object
    // ->by index to get key, then by key
    task = tasks[[tasks keyAtIndex:taskRow]];
    
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
        (self.tableItems.count < itemRow) )
    {
        //bail
        goto bail;
    }

    //get item object
    item = self.tableItems[itemRow];
    
//bail
bail:
    
    return item;
}


/*
//helper function
// ->get items array (either all or just unknown)
-(NSArray*)getTableItems
{
    //array backing table
    // ->based on filtering options, will either be all items, or only unknown ones
    NSArray* tableItems = nil;
    
    //plugin object
    PluginBase* selectedPluginObj = nil;

    //set selected plugin from app delegate
    selectedPluginObj =  ((AppDelegate*)[[NSApplication sharedApplication] delegate]).selectedPlugin;
    
    //set array backing table
    // ->case: no filtering (i.e., all items)
    if(YES == ((AppDelegate*)[[NSApplication sharedApplication] delegate]).prefsWindowController.showTrustedItems)
    {
        //set count
        tableItems = selectedPluginObj.allItems;
    }
    //set array backing table
    // ->case: filtering (i.e., unknown items)
    else
    {
        //set count
        tableItems = selectedPluginObj.unknownItems;
    }
    
    return tableItems;
}
*/


//automatically invoked when user clicks the 'show in finder' icon
// ->open Finder to show item
-(IBAction)showInFinder:(id)sender
{
    //task
    Task* task =  nil;
    
    //get task
    //TODO: this used to be called w/ nil
    task = [self taskForRow:sender];
    
    //open Finder
    // ->will reveal binary
    [[NSWorkspace sharedWorkspace] selectFile:task.binary.path inFileViewerRootedAtPath:nil];
    
//bail
bail:
        
    return;
}

//automatically invoked when user clicks the 'info' icon
// ->create/configure/display info window
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
-(void)showVTInfo:(NSView*)button
{
    //array backing table
    NSArray* tableItems = nil;
    
    //selected item
    File* selectedItem = nil;

    //row that button was clicked on
    NSUInteger rowIndex = -1;
    
    //get row index
    rowIndex = [self.itemView rowForView:button];
    
    //grab item table items
    tableItems = [self getTableItems];
    
    //sanity check
    // ->make sure row has item
    if(tableItems.count < rowIndex)
    {
        //bail
        goto bail;
    }

    //sanity check
    if(-1 != rowIndex)
    {
        //extract selected item
        // ->invoke helper function to get array backing table
        selectedItem = tableItems[rowIndex];
        
        //alloc/init info window
        vtWindowController = [[VTInfoWindowController alloc] initWithItem:selectedItem rowIndex:rowIndex];
        
        //show it
        [self.vtWindowController.windowController showWindow:self];
      
        /*
        //make it modal
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            
            //modal!
            [[NSApplication sharedApplication] runModalForWindow:vtWindowController.windowController.window];
            
        });
        */
    }
    
//bail
bail:
    
    return;
}


@end
