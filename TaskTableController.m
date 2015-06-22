//
//  ItemTableController.m
//  KnockKnock
//
//  Created by Patrick Wardle on 2/18/15.
//  Copyright (c) 2015 Objective-See. All rights reserved.
//

//TODO: list of what's running on my Mac on website!!!!

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

//TODO: need to do some sync or logic to handle swaps -otherwise crashes!!!

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
    if(YES != didInit)
    {
        //init selected row
        self.selectedRow = -1;
        
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
        //when not filtered
        // ->use tasks
        if(YES != isFiltered)
        {
            //get tasks
            tasks = ((AppDelegate*)[[NSApplication sharedApplication] delegate]).taskEnumerator.tasks;
        
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
    //TODO: filter support
    else
    {
        //set row count
        rows = self.tableItems.count;
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
        taskIndex = [tasks indexOfKey:selectedTask.pid];
        
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


//TODO: make sure this works for outline view!!!
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
    
    //TODO: add check for filterItems.count
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
    
    //when not filtered, use all tasks
    //if(YES != isFiltered)
    //{
        //extract task
        // ->pid of task is view's id :)
        task = tasks[[NSNumber numberWithInteger:(rowView.tag - PID_TAG_DELTA)]];
    //}
    //when filtered, use filtered items
    //else
    //{
    //    task = self.filteredItems[
    //}
    
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
    //item
    // ->task, dylib, file, etc
    id item =  nil;
    
    //path to binary
    NSString* path = nil;
    
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

    //open Finder
    // ->will reveal binary
    [[NSWorkspace sharedWorkspace] selectFile:path inFileViewerRootedAtPath:nil];
    
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
    Binary* item = nil;
    
    //for top pane
    // ->get task
    if(YES != self.isBottomPane)
    {
        //get task
        item = [(Task*)[self taskForRow:sender] binary];
    }
    
    //bottom pane
    else
    {
        //get item
        item = (Binary*)[self itemForRow:sender];
    }

    //bail on nil items
    if(nil == item)
    {
        //bail
        goto bail;
    }
    
    //alloc/init info window
    vtWindowController = [[VTInfoWindowController alloc] initWithItem:item];
    
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
    tasks = ((AppDelegate*)[[NSApplication sharedApplication] delegate]).taskEnumerator.tasks;
    
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
    tasks = ((AppDelegate*)[[NSApplication sharedApplication] delegate]).taskEnumerator.tasks;
    
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


//TODO: combine logic -
//TODO: when combine, use pid of task is view's id - to lookup task :)
- (void)outlineViewSelectionDidChange:(NSNotification *)notification
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
    static NSString* const kRowIdentifier = @"RowView";
    
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
    tasks = ((AppDelegate*)[[NSApplication sharedApplication] delegate]).taskEnumerator.tasks;
    
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
    
    //get row that's about to be selected
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
        
        //make hide it after 1/4th second
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            
            //reset color
            ((kkRowCell*)selectedView).color = nil;
            
            //remove task
            [((AppDelegate*)[[NSApplication sharedApplication] delegate]).taskEnumerator removeTask:task];
            
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
        });
        
        //bail
        goto bail;
        
    }
    
    //ignore if row selection and task didn't change
    if( ([self.itemView selectedRow] == self.selectedRow) &&
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
    
    
//bail
bail:
    
    
    return;

}


@end
