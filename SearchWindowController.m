//
//  SearchWindowController.m
//  TaskExplorer
//
//  Created by Patrick Wardle on 8/14/15.
//  Copyright (c) 2015 Objective-See. All rights reserved.
//


//TODO: mouse over for info/show in finder buttons!


#import "AppDelegate.h"
#import "SearchWindowController.h"
#import "ItemView.h"
#import "KKRow.h"
#import "Filter.h"
#import "Utilities.h"
#import "Consts.h"


@implementation SearchWindowController

@synthesize didInit;
@synthesize filterObj;
@synthesize searchBox;
@synthesize overlayView;
@synthesize searchTable;
@synthesize searchResults;
@synthesize plsWaitMessage;
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
    //init filter obj
    filterObj = [[Filter alloc] init];
    
    //init array for search results
    searchResults = [NSMutableArray array];
    
    //first time outlets are nil
    // ->thus 'initUI' method called in 'awakeFromNib'
    if(nil != self.window)
    {
        //can init UI
        [self initUI];
        
        //set flag
        self.didInit = YES;
    }

    return;
}

//automatically invoked when window is un-minimized
// since the progress indicator is stopped/hidden (bug?), restart it
-(void)windowDidDeminiaturize:(NSNotification *)notification
{
    //current time
    NSTimeInterval currentTime = 0.0f;
    
    //grab current time
    currentTime = [NSDate timeIntervalSinceReferenceDate];
    
    //make sure search is still waiting...
    // ->and then restart spinner
    if((currentTime - ((AppDelegate*)[[NSApplication sharedApplication] delegate]).startTime) < SEARCH_WAIT_TIME)
    {
        //update UI on main thread
        dispatch_async(dispatch_get_main_queue(), ^{
            
            //show
            self.activityIndicator.hidden = NO;
            
            //start spinner
            [self.activityIndicator startAnimation:nil];
            
        });
    }
    
    return;
}

//init the UI
// ->each time window is shown, reset, show spinner if needed, etc
-(void)initUI
{
    //current time
    NSTimeInterval currentTime = 0.0f;
    
    //time left
    NSTimeInterval timeRemaining = 0.0f;
    
    //center
    [self.window center];
    
    //table reload
    // ->make sure all is reset
    [self.searchTable reloadData];
    
    //reset search string
    [self.searchBox setStringValue:@""];
    
    //grab current time
    currentTime = [NSDate timeIntervalSinceReferenceDate];
    
    //check if search timeout has been hit
    // ->when this occur, no need to show activity indicator, etc
    if((currentTime - ((AppDelegate*)[[NSApplication sharedApplication] delegate]).startTime) > SEARCH_WAIT_TIME)
    {
        //make search box first responder
        [self.window makeFirstResponder:self.searchBox];
    }
    //show activity indicator while tasks are still being enumerated
    else
    {
        //calc time remaining
        timeRemaining = SEARCH_WAIT_TIME - (currentTime - ((AppDelegate*)[[NSApplication sharedApplication] delegate]).startTime);
        
        //pre-req
        [self.overlayView setWantsLayer:YES];
        
        //rounded corners
        self.overlayView.layer.cornerRadius = 20.0;
        
        //maks
        self.overlayView.layer.masksToBounds = YES;
        
        //set overlay's view color to black
        self.overlayView.layer.backgroundColor = [NSColor blackColor].CGColor;
        
        //make it semi-transparent
        self.overlayView.alphaValue = 0.20;
        
        //show overlay
        self.overlayView.hidden = NO;

        //disable search box
        self.searchBox.enabled = NO;
        
        //show activity indicator
        [self.activityIndicator setHidden:NO];
        
        //show activity indicator label
        self.activityIndicatorLabel.hidden = NO;
        
        //start spinner
        [self.activityIndicator startAnimation:nil];
        
        //update w/ time
        self.activityIndicatorLabel.stringValue = [NSString stringWithFormat:@"%@ (%d)", PLS_WAIT_MESSAGE, (int)timeRemaining];

        //spin up thread to watch/wait until task enumeration is pau
        [NSThread detachNewThreadSelector:@selector(waitTillPau) toTarget:self withObject:nil];
    }
    
    return;
}

//thread function
// ->wait until task enumeration is done, then allow user to search
-(void)waitTillPau
{
    //time left
    NSTimeInterval timeRemaining = 0.0f;
    
    //calc time remaining
    timeRemaining = SEARCH_WAIT_TIME - ([NSDate timeIntervalSinceReferenceDate] - ((AppDelegate*)[[NSApplication sharedApplication] delegate]).startTime);
    
    //nap/check/etc
    while(timeRemaining > 0.0f)
    {
        //nap
        [NSThread sleepForTimeInterval:1.0f];
        
        //calc time remaining
        timeRemaining = SEARCH_WAIT_TIME - ([NSDate timeIntervalSinceReferenceDate] - ((AppDelegate*)[[NSApplication sharedApplication] delegate]).startTime);
        
        //update UI on main thread
        dispatch_async(dispatch_get_main_queue(), ^{
            
            //update w/ time
            self.activityIndicatorLabel.stringValue = [NSString stringWithFormat:@"%@ (%d)", PLS_WAIT_MESSAGE, (int)timeRemaining];
        
        });

    }
    
    //update UI on main thread
    dispatch_async(dispatch_get_main_queue(), ^{
        
        //hide overlay
        self.overlayView.hidden = YES;

        //yay all done
        // ->hide activity indicator
        self.activityIndicator.hidden = YES;
        
        //hide activity indicator label
        self.activityIndicatorLabel.hidden = YES;
        
        //enable search box
        self.searchBox.enabled = YES;
        
        //make search box first responder
        [self.window makeFirstResponder:self.searchBox];
        
    });
    
    return;
}

//table delegate
// ->return number of rows
-(NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    //count
    return self.searchResults.count;
}

//table delegate method
// ->return cell for row
-(NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
    //row view
    NSView* rowView = nil;
    
    //sanity check
    // ->make sure there is table item for row
    if(row >= self.searchResults.count)
    {
        //bail
        goto bail;
    }
    
    //create the view
    // ->inits row w/ all required info
    rowView = createItemView(tableView, self, [self.searchResults objectAtIndex:row]);
    
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
    buttonAppearance(self.searchTable, theEvent, NO);
    
    return;
}

//automatically invoked when mouse exits
// ->unhighlight/reset button
-(void)mouseExited:(NSEvent*)theEvent
{
    //mouse exited
    // ->so reset button to original (visual) state
    buttonAppearance(self.searchTable, theEvent, YES);
    
    return;
}

//automatically invoked when user presses 'Enter' in search box
// ->search!
-(IBAction)search:(id)sender
{
    //search string
    NSString* searchString = nil;
    
    //all tasks
    OrderedDictionary* allTasks = nil;
    
    //matching items
    NSMutableArray* matchingItems = nil;
    
    //matching tasks
    NSMutableArray* matchingTasks = nil;
    
    //matching dylibs
    NSMutableDictionary* matchingDylibs = nil;
    
    //matching files
    NSMutableDictionary* matchingFiles = nil;
    
    //task
    Task* task = nil;
    
    //alloc array for matching items
    matchingItems = [NSMutableArray array];
    
    //alloc array for matching tasks
    matchingTasks = [NSMutableArray array];
    
    //alloc dictionary for matching dylibs
    matchingDylibs = [NSMutableDictionary dictionary];
    
    //alloc dictionary for matching files
    matchingFiles = [NSMutableDictionary dictionary];
    
    //reset search results
    [self.searchResults removeAllObjects];
    
    //reload table
    // ->clears out everything
    [self.searchTable reloadData];
    
    //grab search string
    searchString = [sender stringValue];
    
    //grab all tasks
    allTasks = ((AppDelegate*)[[NSApplication sharedApplication] delegate]).taskEnumerator.tasks;
    
    //'#' indicates a keyword search
    // ->check for keyword match, then filter by keyword
    if(YES == [searchString hasPrefix:@"#"])
    {
        //ignore #search strings that don't match a keyword
        if(YES != [filterObj isKeyword:searchString])
        {
            //ignore
            goto bail;
        }
     }
    
    //1st: search for all matching tasks
    //sync
    @synchronized(allTasks)
    {
        
    //search for all matching tasks
    [self.filterObj filterTasks:searchString items:allTasks results:matchingTasks];
    
    }//sync
    
    //add all tasks
    [self.searchResults addObjectsFromArray:matchingTasks];
    
    //refresh table to display task matches
    [self.searchTable reloadData];
    
    //2nd: search for all matching dylibs
    //sync
    @synchronized(allTasks)
    {
        
    //walk all tasks
    // ->scan each for dylib matches, only processing first match
    for(NSNumber* taskPid in allTasks)
    {
        //extract task
        task = allTasks[taskPid];
        
        //filter
        [self.filterObj filterFiles:searchString items:task.dylibs results:matchingItems];
        
        //process all matching dylibs
        // ->but first check if processed due to matching in another task already
        for(Binary* dylib in matchingItems)
        {
            //ignore if already seen/processed
            if(nil != matchingDylibs[dylib.path])
            {
                //skip
                continue;
            }
            
            //process
            [self.searchResults addObject:dylib];
            
            //save
            matchingDylibs[dylib.path] = dylib;
        }

    }//all tasks
        
    }//sync
        
    //refresh table to display dylib
    [self.searchTable reloadData];
    
    //3rd: search for all matching files
    //sync
    @synchronized(allTasks)
    {
        //walk all tasks
        // ->scan each for file matches, only processing first match
        for(NSNumber* taskPid in allTasks)
        {
            //extract task
            task = allTasks[taskPid];
            
            //filter
            [self.filterObj filterFiles:searchString items:task.files results:matchingItems];
            
            //process all matching dylibs
            // ->but first check if processed due to matching in another task already
            for(File* file in matchingItems)
            {
                //ignore if already seen/processed
                if(nil != matchingFiles[file.path])
                {
                    //skip
                    continue;
                }
                
                //process
                [self.searchResults addObject:file];
                
                //save
                matchingFiles[file.path] = file;
            }
            
        }//all tasks
        
    }//sync
    
    //refresh table to display dylib
    [self.searchTable reloadData];
    
//bail
bail:
    
    return;
    
}

//invoked when the user clicks 'virus total' icon
// ->launch browser and browse to virus total's page
-(void)showVTInfo:(id)sender
{
    //item
    // ->task or dylib
    id item = nil;
    
    //binary
    Binary* binary = nil;
    
    //row
    NSInteger itemRow = 0;
    
    //grab sender's row
    itemRow = [self.searchTable rowForView:sender];
    
    //sanity check(s)
    // ->make sure row is decent
    if( (-1 == itemRow) ||
       (itemRow >= self.searchResults.count) )
    {
        //bail
        goto bail;
    }
    
    //extract item for row
    item = self.searchResults[itemRow];
    
    //tasks
    // ->grab binary
    if(YES == [item isKindOfClass:[Task class]])
    {
        //get binary
        binary = ((Task*)item).binary;
    }
    //binaries
    // ->can use as is
    else if(YES == [item isKindOfClass:[Binary class]])
    {
        //set
        binary = item;
    }
    
    //sanity check
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
    itemRow = [self.searchTable rowForView:sender];
    
    //sanity check(s)
    // ->make sure row is decent
    if( (-1 == itemRow) ||
       (itemRow >= self.searchResults.count) )
    {
        //bail
        goto bail;
    }
    
    //extract item for row
    item = self.searchResults[itemRow];

    //tasks
    // ->grab path from binary
    if(YES == [item isKindOfClass:[Task class]])
    {
        //get path
        path = ((Task*)item).binary.path;
    }
    //binary/files
    // ->use as is
    else if( (YES == [item isKindOfClass:[Binary class]]) ||
             (YES == [item isKindOfClass:[File class]]) )
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
    itemRow = [self.searchTable rowForView:sender];
    
    //sanity check(s)
    // ->make sure row is decent
    if( (-1 == itemRow) ||
       (itemRow >= self.searchResults.count) )
    {
        //bail
        goto bail;
    }
    
    //grab item
    item = self.searchResults[itemRow];
    
    //alloc/init info window
    infoWindowController = [[InfoWindowController alloc] initWithItem:item];
    
    //show it
    [self.infoWindowController.windowController showWindow:self];
    
//bail
bail:
    
    return;
}


@end
