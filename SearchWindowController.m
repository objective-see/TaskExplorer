//
//  SearchWindowController.m
//  TaskExplorer
//
//  Created by Patrick Wardle on 8/14/15.
//  Copyright (c) 2015 Objective-See. All rights reserved.
//

#import <syslog.h>

#import "KKRow.h"
#import "Consts.h"
#import "Filter.h"
#import "ItemView.h"
#import "Utilities.h"
#import "AppDelegate.h"
#import "SearchWindowController.h"


@implementation SearchWindowController

@synthesize didInit;
@synthesize filterObj;
@synthesize searchBox;
@synthesize searchTable;
@synthesize stateMonitor;
@synthesize searchResults;
@synthesize commandHandling;
@synthesize completePosting;
@synthesize customSearchField;
@synthesize vtWindowController;
@synthesize infoWindowController;
@synthesize searchResultsMessage;

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
    
    //alloc/init custom search field for items
    customSearchField = [[CustomTextField alloc] init];
    
    //set owner
    self.customSearchField.owner = self;

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
    //not done?
    // ->make spinner keep spinning
    if(ENUMERATION_STATE_COMPLETE != ((AppDelegate*)[[NSApplication sharedApplication] delegate]).taskEnumerator.state)
    {
        //(re)start
        [self.activityIndicator startAnimation:nil];
    }
    
    return;
}

//init the UI
// ->each time window is shown, reset, show enumeration status, etc
-(void)initUI
{
    //center
    [self.window center];
    
    //table reload
    // ->make sure all is reset
    [self.searchTable reloadData];
    
    //reset search string
    [self.searchBox setStringValue:@""];

    //make search box first responder
    [self.window makeFirstResponder:self.searchBox];
    
    //hide search results
    self.searchResultsMessage.hidden = YES;
    
    //still enumerating?
    // ->show the spinner
    if(ENUMERATION_STATE_COMPLETE != ((AppDelegate*)[[NSApplication sharedApplication] delegate]).taskEnumerator.state)
    {
        //show
        self.activityIndicator.hidden = NO;
        
        //start
        [self.activityIndicator startAnimation:nil];
    }
    
    //complete?
    // ->stop spinner
    else
    {
        //stop
        [self.activityIndicator stopAnimation:nil];
    }
    
    //set enumeration message
    [self showEnumerationState];

    //spin up thread to monitor update enumeration state
    [NSThread detachNewThreadSelector:@selector(updateEnumerationState) toTarget:self withObject:nil];
    
    return;
}

//monitor enumeration state to update status message
-(void)updateEnumerationState
{
    //save thread into iVar
    self.stateMonitor = [NSThread currentThread];
    
    //go until canceled or state is complete
    while(YES != [[NSThread currentThread] isCancelled])
    {
        //nap
        [NSThread sleepForTimeInterval:1.0];
        
        //update on main thread
        dispatch_async(dispatch_get_main_queue(), ^{
            
            //update
            [self showEnumerationState];
        });
        
        //done?
        if(ENUMERATION_STATE_COMPLETE == ((AppDelegate*)[[NSApplication sharedApplication] delegate]).taskEnumerator.state)
        {
            //stop spinner
            [self.activityIndicator stopAnimation:nil];
            
            //done
            break;
        }
    }
    
    return;
}

//set the status message/enumeration state
-(void)showEnumerationState
{
    //set status
    switch(((AppDelegate*)[[NSApplication sharedApplication] delegate]).taskEnumerator.state) {
            
        //tasks
        case ENUMERATION_STATE_TASKS:
            self.activityIndicatorLabel.stringValue = @"enumerating tasks...";
            break;
            
        //dylibs
        case ENUMERATION_STATE_DYLIBS:
            self.activityIndicatorLabel.stringValue = @"enumerating dylibs...";
            break;
            
        //files
        case ENUMERATION_STATE_FILES:
            self.activityIndicatorLabel.stringValue = @"enumerating files...";
            break;
            
        //network
        case ENUMERATION_STATE_NETWORK:
            self.activityIndicatorLabel.stringValue = @"enumerating network...";
            break;
            
        //done
        case ENUMERATION_STATE_COMPLETE:
            self.activityIndicatorLabel.stringValue = @"enumeration complete!";
            break;
            
        default:
            break;
    }
}

//callback for when searching is done
// ->update UI by removing overlay and reloading table
-(void)completeSearch
{
    //always (attempt to) hide overlay
    self.overlay.hidden = YES;
    
    //stop spinner
    [self.overlaySpinner stopAnimation:nil];
    
    //enable search box
    self.searchBox.enabled = YES;
    
    //reload table
    [self.searchTable reloadData];
    
    //search was performed?
    if(0 != [self.searchBox stringValue].length)
    {
        //nothing found
        if(0 == self.searchResults.count)
        {
            //set msg
            self.searchResultsMessage.stringValue = @"nothing found";
        }
        
        //update status mesasge with count
        else
        {
            //set msg
            self.searchResultsMessage.stringValue = [NSString stringWithFormat:@"found %lu items\n", (unsigned long)self.searchResults.count];
        }
    }
    else
    {
        //reset
        self.searchResultsMessage.stringValue = @"";
    }

    //show
    self.searchResultsMessage.hidden = NO;
    
    return;
}

//automatically invoked when user enters text in filter search boxes
// ->filter tasks and/or items
-(void)controlTextDidChange:(NSNotification *)aNotification
{
    //prevent calling "complete" too often
    if( (YES != self.completePosting) &&
        (YES != self.commandHandling) )
    {
        //set flag
        self.completePosting = YES;
        
        //invoke complete
        [aNotification.userInfo[@"NSFieldEditor"] complete:nil];
        
        //unset flag
        self.completePosting = NO;
    }

    return;
}

//delegate method, automatically called
// ->generate list of matches to return for drop-down
-(NSArray *)control:(NSControl *)control textView:(NSTextView *)textView completions:(NSArray *)words forPartialWordRange:(NSRange)charRange indexOfSelectedItem:(NSInteger *)index
{
    //matches
    NSMutableArray *matches = nil;
    
    //range options
    NSUInteger rangeOptions = {0};
    
    //init array for matches
    matches = [[NSMutableArray alloc] init];
    
    //init range options
    rangeOptions = NSAnchoredSearch | NSCaseInsensitiveSearch;
    
    //check all filters
    // note: really check Binary ones, but this should include all!
    for(NSString* filter in self.filterObj.binaryFilters)
    {
        //check if found
        // ->add to match when found
        if([filter rangeOfString:textView.string options:rangeOptions range:NSMakeRange(0, filter.length)].location != NSNotFound)
        {
            //add
            [matches addObject:filter];
        }
    }
    
    //sort matches
    [matches sortUsingComparator:^(NSString *a, NSString *b)
     {
         //sort
         return [a localizedStandardCompare:b];
     }];
    
//bail
bail:
    
    return matches;
}

//delegate method, automatically invoked
// ->handle invocations for text view
-(BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector
{
    //flag
    BOOL didPerformRequestedSelectorOnTextView = NO;
    
    //invocation
    NSInvocation *textViewInvocationForSelector = nil;
    
    //check if text view can handle selector
    if(YES != [textView respondsToSelector:commandSelector])
    {
        //bail
        goto bail;
    }
    
    //first handle 'enter'
    // ->trigger a search
    if(commandSelector == @selector(insertNewline:))
    {
        //search
        [self search];
    }
    //handle all others
    else
    {
        //set iVar flag
        self.commandHandling = YES;
        
        //init invocation
        textViewInvocationForSelector = [NSInvocation invocationWithMethodSignature:[textView methodSignatureForSelector:commandSelector]];
        
        //set target
        [textViewInvocationForSelector setTarget:textView];
        
        //set selector
        [textViewInvocationForSelector setSelector:commandSelector];
        
        //invoke selector
        [textViewInvocationForSelector invoke];
        
        //unset iVar
        self.commandHandling = NO;
    }
    
    //indicate that selector was performed
    didPerformRequestedSelectorOnTextView = YES;
    
//bail
bail:
    
    return didPerformRequestedSelectorOnTextView;
}


//callback for custom search fields
// ->handle auto-complete filterings
-(void)filterAutoComplete:(NSTextView*)textView
{
    //just call search method
    // ->has logic to handle searching
    [self search];

    return;
}

//automatically invoked
// ->set all NSSearchFields to be instances of our custom NSTextView
-(id)windowWillReturnFieldEditor:(NSWindow *)sender toObject:(id)client
{
    //field editor
    id fieldEditor = nil;
    
    //ignore non-NSSearchField classes
    if(YES != [client isKindOfClass:[NSTextField class]])
    {
        //ingnore
        goto bail;
    }
    
    //set task's filter search field
    if(client == self.searchBox)
    {
        //assign for return
        fieldEditor = self.customSearchField;
    }
    
    
//bail
bail:
    
    return fieldEditor;
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

//do the search
-(void)search
{
    //search string
    NSString* searchString = nil;
    
    //all tasks
    OrderedDictionary* allTasks = nil;
    
    //reset search results
    [self.searchResults removeAllObjects];
    
    //reload table
    // ->clears out everything
    [self.searchTable reloadData];
    
    //grab search string
    searchString = [self.searchBox stringValue];
    
    //update search message
    if(0 != searchString.length)
    {
        //update
        self.searchResultsMessage.stringValue = [NSString stringWithFormat:@"searching (%@)", searchString];
    }
    
    //pre-req
    [self.overlay setWantsLayer:YES];
    
    //rounded corners
    self.overlay.layer.cornerRadius = 20.0;
    
    //maks
    self.overlay.layer.masksToBounds = YES;
    
    //set overlay's view color to black
    self.overlay.layer.backgroundColor = [NSColor grayColor].CGColor;
    
    //make it semi-transparent
    self.overlay.alphaValue = 0.95;
    
    //show overlay
    self.overlay.hidden = NO;
    
    //start spinner
    [self.overlaySpinner startAnimation:nil];

    //show
    self.searchResultsMessage.hidden = NO;
    
    //disable search input box
    self.searchBox.enabled = NO;
    
    //grab all tasks
    // ->make copy to avoid threading issues
    allTasks = [((AppDelegate*)[[NSApplication sharedApplication] delegate]).taskEnumerator.tasks copy];
    
    //kick off filtering in background
    // ->will call back into to refresh UI when done
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        
        //nap to allow message to show
        [NSThread sleepForTimeInterval:0.5];
        
        //filter
        [self.filterObj filterAll:searchString items:allTasks results:self.searchResults];
        
    });
    
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
    [[NSWorkspace sharedWorkspace] selectFile:path inFileViewerRootedAtPath:@""];
    
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

//automatically invoked when window is closing
// ->cancel enumeration state monitoring thread
-(void)windowWillClose:(NSNotification *)notification
{
    //cancel
    [self.stateMonitor cancel];
    
    return;
}




@end
