//
//  AppDelegate.m
//  TaskExplorer
//

#import "Consts.h"
#import "Binary.h"
#import "Connection.h"
#import "Exception.h"
#import "Utilities.h"
#import "AppDelegate.h"
#import "serviceInterface.h"

#import "TaskTableController.h"
#import "RequestRootWindowController.h"

#import "Task.h"

//TODO: filter out dup'd networks (airportd 0:0..) -not sure want to do this
//TODO: autolayout vertically
//TODO: show 'from where' via quarantine attrz or database!! (simon email)
//TODO: detect as procs die via GCD (simon blog post)
//TODO: missing icon (128) - new icon?
//TODO: exception handling for mutated array!
//TODO: check for "Apple Mac OS Application Signing" for Apple Apps - and add to 'OBJ-See' TODO doc

@implementation AppDelegate


@synthesize topPane;
@synthesize filterObj;
@synthesize startTime;
@synthesize vtThreads;
@synthesize bottomPane;
@synthesize saveButton;
@synthesize currentTask;
@synthesize isConnected;
@synthesize flaggedItems;
@synthesize searchButton;
@synthesize viewSelector;
@synthesize scannerThread;
@synthesize virusTotalObj;
@synthesize taskEnumerator;
@synthesize taskViewFormat;
@synthesize commandHandling;
@synthesize completePosting;
@synthesize customItemsFilter;
@synthesize customTasksFilter;
@synthesize progressIndicator;
@synthesize taskTableController;
@synthesize bottomViewController;
@synthesize aboutWindowController;
@synthesize searchWindowController;
@synthesize resultsWindowController;
@synthesize flagItemsWindowController;
@synthesize requestRootWindowController;

//center window
// ->also make front
-(void)awakeFromNib
{
    //center
    [self.window center];
    
    //make it key window
    [self.window makeKeyAndOrderFront:self];
    
    //make window front
    [NSApp activateIgnoringOtherApps:YES];
    
    return;
}

//automatically invoked by OS
// ->main entry point
-(void)applicationDidFinishLaunching:(NSNotification *)notification
{
    //first thing...
    // ->install exception handlers!
    installExceptionHandlers();
    
    //init virus total object
    virusTotalObj = [[VirusTotal alloc] init];
    
    //init filter obj
    filterObj = [[Filter alloc] init];
    
    //alloc flagged items
    flaggedItems = [NSMutableArray array];
    
    //alloc/init custom search field for tasks
    customTasksFilter = [[CustomTextField alloc] init];
    
    //set owner
    self.customTasksFilter.owner = self;
    
    //alloc/init custom search field for items
    customItemsFilter = [[CustomTextField alloc] init];
    
    //set owner
    self.customItemsFilter.owner = self;
    
    //set field editor for tasks
    [self.customTasksFilter setFieldEditor:YES];
    
    //set field editor for items
    [self.customItemsFilter setFieldEditor:YES];
    
    //set start time
    self.startTime = [NSDate timeIntervalSinceReferenceDate];
    
    //center
    [self.window center];
    
    //no need to have a first responder
    [self.window makeFirstResponder:nil];
    
    //make main window front
    [self.window makeKeyAndOrderFront:self];
    
    //make app front
    [NSApp activateIgnoringOtherApps:YES];
    
    //check that OS is supported
    if(YES != isSupportedOS())
    {
        //show alert
        [self showUnsupportedAlert];
        
        //exit
        exit(0);
    }
    
    //register for hotkey presses
    [self registerKeypressHandler];
    
    //check if authenticated
    // ->display authentication request if needed
    if(YES != [self isAuthenticated])
    {
        //display auth popup
        // ->will invoke 'go' method on successful auth
        [self askForRoot];
    }
    //go!
    // ->setup tracking areas and begin thread that explores tasks
    else
    {
        //go!
        [self go];
    }
    
    //set default top pane view to flat
    self.taskViewFormat = FLAT_VIEW;
    
    //set initial view for top pane
    // ->default is flat (non-tree) view
    [self changeViewController];
    
    //alloc/init bottom pane controller
    self.bottomViewController = [[TaskTableController alloc] initWithNibName:@"FlatView" bundle:nil];
    
    //set flag
    self.bottomViewController.isBottomPane = YES;
   
    //disable autosize translations
    self.bottomViewController.view.translatesAutoresizingMaskIntoConstraints = NO;
    
    //add subview
    [self.bottomPane addSubview:self.bottomViewController.view];
    
    //set frame
    [[self.bottomViewController view] setFrame:[self.bottomPane bounds]];
    
    //constrain to parent
    [self constrainView:self.bottomPane subView:self.bottomViewController.view];
    
    //add 'items' not found msg
    [self.bottomViewController.view addSubview:self.noItemsLabel];

    //set delegate
    // ->ensures our 'windowWillClose' method, which has logic to fully exit app
    self.window.delegate = self;
    
    /*
    //init list of keyword strings for our type completion dropdown list in NSSearchField
    self.builtInKeywords = [NSMutableArray array];
    
    //iterate over all const keywords
    // ->add to array
    for(NSUInteger i=0; i<sizeof(KEYWORDS)/sizeof(KEYWORDS[0]); i++)
    {
        //add
        [self.builtInKeywords addObject:KEYWORDS[i]];
    }
    */
    
    return;
}

//register handler for hot keys
-(void)registerKeypressHandler
{
    NSEvent * (^keypressHandler)(NSEvent *);
    
    keypressHandler = ^NSEvent * (NSEvent * theEvent){
        
        return [self handleKeypress:theEvent];
        
    };

    //register for key-down events
    [NSEvent addLocalMonitorForEventsMatchingMask:NSKeyDownMask handler:keypressHandler];
    
    return;
}

//invoked for any (but only) key-down events
-(NSEvent*)handleKeypress:(NSEvent*)event
{
    //flag indicating event was handled
    BOOL wasHandled = NO;
    
    //only care about 'cmd' + something
    if(NSCommandKeyMask != (event.modifierFlags & NSCommandKeyMask))
    {
        //bail
        goto bail;
    }
    
    //handle key-code
    // refresh (cmd+r)
    // save (cmd+s)
    // search (cmd+f)
    // close window (cmd+w)
    // info for selected task (cmd+i)
    switch ([event keyCode])
    {
        //'r' (refresh)
        case KEYCODE_R:
            
            //refresh
            [self refreshTasks:nil];
            
            //set flag
            wasHandled = YES;
            
            break;
        
        //'f' (find, search)
        case KEYCODE_F:
            
            //find
            [self search:nil];
            
            //set flag
            wasHandled = YES;
            
            break;
            
            
        //'s' (save)
        case KEYCODE_S:
            
            //save
            [self saveResults:nil];
            
            //set flag
            wasHandled = YES;
            
            break;
            
        //'i' (info)
        //case KEYCODE_I:
            
            //info
            //TODO...this will take some work, search, flagged, item....
            
            //set flag
            //wasHandled = YES;
            
            //break;
        
        //'w' (close window)
        case KEYCODE_W:
            
            //close
            // ->if not main window
            if(self.window != [[NSApplication sharedApplication] keyWindow])
            {
                //close window
                [[[NSApplication sharedApplication] keyWindow] close];
                
                //set flag
                wasHandled = YES;
            }
            
            break;
            
            
        default:
            break;
    }

//bail
bail:
    
    //nil out event if it was handled
    if(YES == wasHandled)
    {
        event = nil;
    }
    
    // Return the event, a new event, or, to stop
    // the event from being dispatched, nil
    return event;



}

//complete a few inits
// ->then invoke helper method to start enum'ing task (in bg thread)
-(void)go
{
    //init mouse-over areas
    [self initTrackingAreas];
    
    //go!
    [self exploreTasks];
    
//bail
bail:
    
    return;
}


//check if app is auth'd
// ->specifically, if XPC service is setuid
-(BOOL)isAuthenticated
{
    //flag
    BOOL isAuthenticated = NO;
    
    //path to XPC service
    NSString* xpcService = nil;
    
    //file attributes
    NSDictionary* fileAttributes = nil;
    
    //get path to XPC service
    xpcService = getPath2XPC();
    
    //sanity check
    if(nil == xpcService)
    {
        //err msg
        syslog(LOG_ERR, "OBJECTIVE-SEE ERROR: failed to get path to XPC service");
        
        //bail
        goto bail;
    }
    
    //get XPC services' attributes
    fileAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:xpcService error:nil];
    
    //sanity check
    if(nil == fileAttributes)
    {
        //err msg
        syslog(LOG_ERR, "OBJECTIVE-SEE ERROR: failed to file attributes for XPC service");
        
        //bail
        goto bail;
    }
    
    //check if (fully) auth'd
    // ->owned by r00t & SETUID
    if( (0 == [fileAttributes[NSFileOwnerAccountID] unsignedLongValue]) &&
        (0 != (S_ISUID & [fileAttributes[NSFilePosixPermissions] unsignedLongValue])) )
    {
        //set flag
        isAuthenticated = YES;
    }
    
//bail
bail:

    return isAuthenticated;
}

//display window that asks for r00t
// ->if user agrees, execs cmd to set XPC to be setuid!
-(void)askForRoot
{
    //alloc/init request window
    if(nil == self.requestRootWindowController)
    {
        //alloc/init
        requestRootWindowController = [[RequestRootWindowController alloc] initWithWindowNibName:@"RequestRootWindow"];
    }
    
    //center window
    [[self.requestRootWindowController window] center];
    
    //show it
    [self.requestRootWindowController showWindow:self];
    
    //invoke function in background that will make window modal
    // ->waits until window is non-nil
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        
        //make modal
        makeModal(self.requestRootWindowController);
        
    });
    
    return;
}


//begin task enumeration
-(void)exploreTasks
{
    //alloc task enumerator
    if(nil == self.taskEnumerator)
    {
        //alloc
        taskEnumerator = [[TaskEnumerator alloc] init];
    }
    
    //kick off thread to enum task
    // ->will update table as results come in
    [NSThread detachNewThreadSelector:@selector(enumerateTasks) toTarget:self.taskEnumerator withObject:nil];
    
    return;
}

//change top pane
// ->switch between either flat (default) or tree-based (hierachical) view
-(void)changeViewController
{
    //remove old view
    if([self.taskTableController view] != nil)
    {
        //remove
        [[self.taskTableController view] removeFromSuperview];
        
        //'free'
        self.taskTableController = nil;
    }
    
    switch(self.taskViewFormat)
    {
        case FLAT_VIEW:
        {
            //alloc/init
            taskTableController = [[TaskTableController alloc] initWithNibName:@"FlatView" bundle:nil];
            
            break;
        }
        case TREE_VIEW:
        {
            //alloc/init
            taskTableController = [[TaskTableController alloc] initWithNibName:@"TreeView" bundle:nil];
            
            break;
        }
    }
    
    //set bottom view?
    self.bottomPaneBtn.selectedSegment = DYLIBS_VIEW;
    
    //add subview
    [self.topPane addSubview:self.taskTableController.view];
    
    //disable autosize translations
    self.taskTableController.view.translatesAutoresizingMaskIntoConstraints = NO;
    
    //set frame
    [[self.taskTableController view] setFrame:[self.topPane bounds]];
    
    //constrain to parent
    [self constrainView:self.topPane subView:self.taskTableController.view];
    
    return;
}

//smartly reload a specific row in table
// ->arg determines pane (top/bottom) and for bottom pane, the active view the item belongs to
-(void)reloadRow:(id)item;
{
    //table view
    __block NSTableView* tableView = nil;
    
    //row
    __block NSUInteger row = 0;
    
    //run everything on main thread
    // ->ensures table view isn't changed out from under us....
    dispatch_async(dispatch_get_main_queue(), ^{
    
    //top table (pane)
    if(YES == [item isKindOfClass:[Task class]])
    {
        //top table view
        tableView = [((id)self.taskTableController) itemView];
        
        //reload item
        // ->flat view
        if(YES != [tableView isKindOfClass:[NSOutlineView class]])
        {
            //no filtering
            // ->grab row from all tasks
            if(YES != self.taskTableController.isFiltered)
            {
                //get row
                row = [self.taskEnumerator.tasks indexOfKey:((Task*)item).pid];
            }
            //filtering
            // ->grab row from filtered tasks
            else
            {
                //get row
                row = [self.taskTableController.filteredItems indexOfObject:item];
            }
        }
        //reload item
        // ->tree view, so no need to worry about filtering
        else
        {
            //get row
            row = [(NSOutlineView*)tableView rowForItem:item];
        }
        
        //sanity check
        if(NSNotFound == row)
        {
            //bail
            goto bail;
        }
        
        //begin updates
        [tableView beginUpdates];
        
        //reload row
        [tableView reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:(row)] columnIndexes:[NSIndexSet indexSetWithIndex:0]];
        
        //end updates
        [tableView endUpdates];
    }
    //bottom pane
    else
    {
        //bottom table view
        tableView = [((id)self.bottomViewController) itemView];
        
        //no filtering
        // ->grab row from all items
        if(YES != self.bottomViewController.isFiltered)
        {
            //get row
            row = [self.bottomViewController.tableItems indexOfObject:item];
        }
        //filtering
        // ->grab row from filtered item
        else
        {
            //get row
            row = [self.bottomViewController.filteredItems indexOfObject:item];
        }

        //make sure item was found
        if(NSNotFound == row)
        {
            //bail
            goto bail;
        }
        
        //begin updates
        [tableView beginUpdates];
        
        //reload row
        [tableView reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:(row)] columnIndexes:[NSIndexSet indexSetWithIndex:0]];
        
        //end updates
        [tableView endUpdates];
    
    }//bottom pane
        
//bail
bail:
        ;
        
    }); //dispatch on main thread
    
    return;
}

//smartly, reload bottom pane on main thread
// ->checks if task & item type (e.g. files) are both selected
-(void)reloadBottomPane:(Task*)task itemView:(NSUInteger)itemView
{
    //tag
    NSUInteger segmentTag = 0;
    
    //not found msg
    NSString* noItemsMsg = nil;
    
    //get segment tag
    segmentTag = [[self.bottomPaneBtn selectedCell] tagForSegment:[self.bottomPaneBtn selectedSegment]];
    
    //ignore reloads for unselected tasks
    // ->note: when no task is passed in, always reload though
    if( (nil != task) &&
        (self.currentTask != task))
    {
        //ignore
        goto bail;
    }
    
    //ignore reloads for unselected views
    if( (segmentTag != itemView) &&
        (CURRENT_VIEW != itemView))
    {
        //ignore
        goto bail;
    }
    
    //set input
    switch(segmentTag)
    {
        //dylibs
        case DYLIBS_VIEW:
            
            //set table items
            self.bottomViewController.tableItems = self.currentTask.dylibs;
            
            //if there is none
            noItemsMsg = @"no dylibs found";
        
            break;
            
        //files
        case FILES_VIEW:
            
            ///set table items
            self.bottomViewController.tableItems = self.currentTask.files;
            
            //if there is none
            noItemsMsg = @"no files found";
            
            break;
            
        //networking
        case NETWORKING_VIEW:
            
            //set table items
            self.bottomViewController.tableItems = self.currentTask.connections;
            
            //if there is none
            noItemsMsg = @"no network connections found";
            
            break;
            
        default:
            break;
    }
    
    //execute on current thread
    if(YES == [NSThread isMainThread])
    {
        //set not found label
        self.noItemsLabel.stringValue = noItemsMsg;
        
        //finalize
        [self finalizeBottomReload];
    }
    else
    {
        //reload
        // ->in main UI thread
        dispatch_sync(dispatch_get_main_queue(), ^{
            
            //set not found label
            self.noItemsLabel.stringValue = noItemsMsg;
            
            //finalize
            [self finalizeBottomReload];
            
        });
    }
    
//bail
bail:

    return;
}

//finish bottom reload
-(void)finalizeBottomReload
{
    //stop progress indicator
    [self.bottomPaneSpinner stopAnimation:nil];
    
    //invoke refresh
    [(id)self.bottomViewController reloadTable];
    
    //no items?
    if(0 == self.bottomViewController.tableItems.count)
    {
        //how
        self.noItemsLabel.hidden = NO;
        
    }
    //got items?
    else
    {
        //hide
        self.noItemsLabel.hidden = YES;
    }
    
    return;
}

//VT callback to reload a binary
// ->task binary: reload all instances that match in top pane
//   dylib:       reload row if dylib is loaded in current/selected task
-(void)reloadBinary:(Binary*)binary
{
    //all tasks
    OrderedDictionary* tasks = nil;
    
    //task
    Task* task = nil;
    
    //task binary
    // ->reload all instances that match in top pane
    if(YES == binary.isTaskBinary)
    {
        //when not filtered
        // ->use all tasks
        if(YES != self.taskTableController.isFiltered)
        {
            //sync
            @synchronized(self.taskEnumerator.tasks)
            {
                
            //get tasks
            tasks = self.taskEnumerator.tasks;
            
            //reload each row w/ new VT info
            for(NSNumber* taskPid in tasks)
            {
                //extract task
                task = tasks[taskPid];
                
                //check for match
                if(task.binary == binary)
                {
                    //reload
                    [self reloadRow:task];
                }
            }

            }//sync
            
        }
        //when filtered
        // ->use filtered items
        else
        {
            //sync
            @synchronized(self.taskTableController.filteredItems)
            {
            
            //filtered items
            for(Task* task in self.taskTableController.filteredItems)
            {
                //check for match
                if(task.binary == binary)
                {
                    //reload
                    [self reloadRow:task];
                }
            }
                
            }//sync
        }
        
    }//top pane
    
    //bottom pane
    // ->can just invoke 'reloadRow' method (which has logic to handle filtering, ignoring 'not found' items, etc.)
    else
    {
        //reload
        [self reloadRow:binary];
    }
    
    return;
}

//display alert about OS not being supported
-(void)showUnsupportedAlert
{
    //alert box
    NSAlert* fullScanAlert = nil;
    
    //alloc/init alert
    fullScanAlert = [NSAlert alertWithMessageText:[NSString stringWithFormat:@"OS X %@ is not supported", [[NSProcessInfo processInfo] operatingSystemVersionString]] defaultButton:@"Ok" alternateButton:nil otherButton:nil informativeTextWithFormat:@"sorry for the inconvenience!"];
    
    //and show it
    [fullScanAlert runModal];
    
    return;
}

//init tracking areas for buttons
// ->provide mouse over effects
-(void)initTrackingAreas
{
    //tracking area for buttons
    NSTrackingArea* trackingArea = nil;
    
    //init tracking area
    // ->for 'refresh' button
    trackingArea = [[NSTrackingArea alloc] initWithRect:[self.refreshButton bounds] options:(NSTrackingInVisibleRect|NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways) owner:self userInfo:@{@"tag":[NSNumber numberWithUnsignedInteger:self.refreshButton.tag]}];
    
    //add tracking area to pref button
    [self.refreshButton addTrackingArea:trackingArea];
    
    //init tracking area
    // ->for search button
    trackingArea = [[NSTrackingArea alloc] initWithRect:[self.searchButton bounds] options:(NSTrackingInVisibleRect|NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways) owner:self userInfo:@{@"tag":[NSNumber numberWithUnsignedInteger:self.searchButton.tag]}];
    
    //add tracking area to search button
    [self.searchButton addTrackingArea:trackingArea];
    
    //init tracking area
    // ->for save button
    trackingArea = [[NSTrackingArea alloc] initWithRect:[self.saveButton bounds] options:(NSTrackingInVisibleRect|NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways) owner:self userInfo:@{@"tag":[NSNumber numberWithUnsignedInteger:self.saveButton.tag]}];
    
    //add tracking area to search button
    [self.saveButton addTrackingArea:trackingArea];
    
    //init tracking area
    // ->for logo button
    trackingArea = [[NSTrackingArea alloc] initWithRect:[self.logoButton bounds] options:(NSTrackingInVisibleRect|NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways) owner:self userInfo:@{@"tag":[NSNumber numberWithUnsignedInteger:self.logoButton.tag]}];
    
    //add tracking area to logo button
    [self.logoButton addTrackingArea:trackingArea];

    //init tracking area
    // ->for flagged items button
    trackingArea = [[NSTrackingArea alloc] initWithRect:[self.flaggedButton bounds] options:(NSTrackingInVisibleRect|NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways) owner:self userInfo:@{@"tag":[NSNumber numberWithUnsignedInteger:self.flaggedButton.tag]}];
    
    //add tracking area to flaggd items button
    [self.flaggedButton addTrackingArea:trackingArea];
    
    return;
}

//automatically invoked when user clicks logo
// ->load objective-see's html page
-(IBAction)logoButtonHandler:(id)sender
{
    //open URL
    // ->invokes user's default browser
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://objective-see.com"]];
    
    return;
}

//sort tasks
// ->just by name (for flat view)
-(void)sortTasksForView:(OrderedDictionary*)tasks;
{
    //sort tasks
    // ->flat view, sort by name
    if(FLAT_VIEW == self.taskViewFormat)
    {
        //sort
        [tasks sort:SORT_BY_NAME];
    }
    
    return;
}

//reload task table
// invoke custom refresh method on main thread
-(void)reloadTaskTable
{
    //sort tasks
    [self sortTasksForView:self.taskEnumerator.tasks];
    
    //when exec'ing on background thread
    // ->exec on main thread
    if(YES != [NSThread isMainThread])
    {
        //refresh on main thread
        dispatch_async(dispatch_get_main_queue(), ^{
            
            //refresh
            [(id)self.taskTableController refresh];
            
        });
    }
    
    //on main thread
    // ->just refresh
    else
    {
        //refresh
        [(id)self.taskTableController refresh];
    }
    
    return;
}

//callback when user has updated prefs
// ->reload table, etc
-(void)applyPreferences
{
    //currently selected category
    //NSUInteger selectedCategory = 0;
    
    /*
    
    //get currently selected category
    //selectedCategory = self.categoryTableController.categoryTableView.selectedRow;
    
    //reload category table
    [self.categoryTableController customReload];
    
    //reloading the category table resets the selected plugin
    // ->so manually (re)set it here
    self.selectedPlugin = self.plugins[selectedCategory];
    
    //reload item table
    [self.taskTableController.itemTableView reloadData];
    
    //if VT query was never done (e.g. scan was started w/ pref disabled)
    // ->kick off VT queries now
    if( (0 == self.vtThreads.count) &&
        (YES != self.prefsWindowController.disableVTQueries) )
    {
        //iterate over all plugins
        // ->do VT query for each
        for(PluginBase* plugin in self.plugins)
        {
            //do query
            [self queryVT:plugin];
        }
    }
    
    //save results?
    // ->if there was a previous scan
    if( (nil != self.scannerThread) &&
        (YES == self.prefsWindowController.shouldSaveNow))
    {
        //save
        [self saveResults];
        
        //alloc/init alert
        saveAlert = [NSAlert alertWithMessageText:[NSString stringWithFormat:@"current results saved to %@", OUTPUT_FILE] defaultButton:@"OK" alternateButton:nil otherButton:nil informativeTextWithFormat:@"subsequent scans will overwrite this file"];
        
        //show it
        [saveAlert runModal];
    }
     
    */
   
    return;
}

//automatically invoked when window is closing
// ->terminate app
-(void)windowWillClose:(NSNotification *)notification
{
    //exit
    [NSApp terminate:self];
    
    return;
}

//automatically invoked when mouse entered
-(void)mouseEntered:(NSEvent*)theEvent
{
    //mouse entered
    // ->highlight (visual) state
    [self buttonAppearance:theEvent shouldReset:NO];
    
    return;
}

//automatically invoked when mouse exits
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
    //tag
    NSUInteger tag = 0;
    
    //image name
    NSString* imageName =  nil;
    
    //button
    NSButton* button = nil;
    
    //extract tag
    tag = [((NSDictionary*)theEvent.userData)[@"tag"] unsignedIntegerValue];
    
    //restore button back to default (visual) state
    if(YES == shouldReset)
    {
        //set original refresh image
        if(REFRESH_BUTTON_TAG == tag)
        {
            //set
            imageName = @"refreshIcon";
        }
        
        //set original search image
        else if(SEARCH_BUTTON_TAG == tag)
        {
            //set
            imageName = @"search";
        }
        
        //set original save image
        else if(SAVE_BUTTON_TAG == tag)
        {
            //set
            imageName = @"saveIcon";
        }
        
        //set original logo image
        else if(LOGO_BUTTON_TAG == tag)
        {
            //set
            imageName = @"logoApple";
        }
        
        //set original flagged items image
        // ->but also handle case where there are still flagged items
        else if(FLAGGED_BUTTON_TAG == tag)
        {
            //when no flagged items
            if(0 == self.flaggedItems.count)
            {
                //set
                imageName = @"flagged";
            }
            //flagged items
            else
            {
                //set
                imageName = @"flaggedRed";
            }

        }
    }
    //highlight button
    else
    {
        //set original refresh image
        if(REFRESH_BUTTON_TAG == tag)
        {
            //set
            imageName = @"refreshIconOver";
        }
        //set mouse over search image
        else if(SEARCH_BUTTON_TAG == tag)
        {
            //set
            imageName = @"searchOver";
        }
        //set mouse over 'save' image
        else if(SAVE_BUTTON_TAG == tag)
        {
            //set
            imageName = @"saveIconOver";
        }
        //set mouse over logo image
        else if(LOGO_BUTTON_TAG == tag)
        {
            //set
            imageName = @"logoAppleOver";
        }
        
        //set mouse over flagged items image
        // ->also handles case where flagged items are present
        else if(FLAGGED_BUTTON_TAG == tag)
        {
            //when no flagged items
            if(0 == self.flaggedItems.count)
            {
                //set
                imageName = @"flaggedOver";
            }
            //flagged items
            else
            {
                //set
                imageName = @"flaggedRedOver";
            }
        }
    }
    
    //set image
    
    //grab button
    button = [[[self window] contentView] viewWithTag:tag];
    if(YES != [button isKindOfClass:[NSButton class]])
    {
        //wtf
        goto bail;
    }
    
    //when enabled
    // ->set image
    if(YES == [button isEnabled])
    {
        //set
        [button setImage:[NSImage imageNamed:imageName]];
    }
    
//bail
bail:
    
    return;    
}

//invoked when user clicks 'save' icon
// ->show popup that allows user to save results
-(IBAction)saveResults:(id)sender
{
    //save panel
    NSSavePanel *panel = nil;
    
    //save results popup
    __block NSAlert* saveResultPopup = nil;
    
    //output
    // ->json of all tasks/dylibs, etc
    __block NSMutableString* output = nil;
    
    //error
    __block NSError* error = nil;
    
    //create panel
    panel = [NSSavePanel savePanel];
    
    //suggest file name
    [panel setNameFieldStringValue:@"tasks.json"];
    
    //show panel
    // ->completion handler will invoked when user clicks 'ok'
    [panel beginWithCompletionHandler:^(NSInteger result)
    {
        //only need to handle 'ok'
        if(NSFileHandlingPanelOKButton == result)
        {
            //alloc output JSON
            output = [NSMutableString string];
            
            //start JSON
            [output appendString:@"{\"tasks:\":["];
            
            //sync
            @synchronized(self.taskEnumerator.tasks)
            {
                
            //get tasks
            for(NSNumber* taskPid in self.taskEnumerator.tasks)
            {
                //append task JSON
                [output appendFormat:@"{%@},", [self.taskEnumerator.tasks[taskPid] toJSON]];
            }
            
            }//sync
                
            //remove last ','
            if(YES == [output hasSuffix:@","])
            {
                //remove
                [output deleteCharactersInRange:NSMakeRange([output length]-1, 1)];
            }
            
            //terminate list/output
            [output appendString:@"]}"];
        
            //save JSON to disk
            // ->on error will show err msg in popup
            if(YES != [output writeToURL:[panel URL] atomically:NO encoding:NSUTF8StringEncoding error:&error])
            {
                //err msg
                syslog(LOG_ERR, "OBJECTIVE-SEE ERROR: saving output to %s failed with %s", [[panel URL] fileSystemRepresentation], [[error description] UTF8String]);
                
                //init popup w/ error msg
                saveResultPopup = [NSAlert alertWithMessageText:@"ERROR: failed to save output" defaultButton:@"Ok" alternateButton:nil otherButton:nil informativeTextWithFormat:@"details: %@", error];
                
            }
            //happy
            // ->set result msg
            else
            {
                //init popup w/ msg
                saveResultPopup = [NSAlert alertWithMessageText:@"Succesfully saved output" defaultButton:@"Ok" alternateButton:nil otherButton:nil informativeTextWithFormat:@"file: %s", [[panel URL] fileSystemRepresentation]];
            }
            
            //show popup
            [saveResultPopup runModal];
        }
        
    }];
    
//bail
bail:
    
    return;
}

//automatically invoked when user clicks 'search' button/ cmd+f hotkey
// ->perform global search
-(IBAction)search:(id)sender
{
    //alloc/init flagged items window
    if(nil == self.searchWindowController)
    {
        //alloc/init
        searchWindowController = [[SearchWindowController alloc] initWithWindowNibName:@"SearchWindow"];
    }
    
    //init/prep it
    [self.searchWindowController prepare];
    
    //show it
    [self.searchWindowController showWindow:self];
    
    //reset search string
    [self.searchWindowController.searchBox setStringValue:@""];

    
    return;
}

#pragma mark Menu Handler(s) #pragma mark -

//automatically invoked when user clicks 'About/Info'
// ->show about window
-(IBAction)about:(id)sender
{
    //alloc/init settings window
    if(nil == self.aboutWindowController)
    {
        //alloc/init
        aboutWindowController = [[AboutWindowController alloc] initWithWindowNibName:@"AboutWindow"];
    }
    
    //center window
    [[self.aboutWindowController window] center];
    
    //show it
    [self.aboutWindowController showWindow:self];

    return;
}

/*

//automatically invoked when user clicks gear icon
// ->show preferences
-(IBAction)showPreferences:(id)sender
{
    //alloc/init settings window
    if(nil == self.prefsWindowController)
    {
        //alloc/init
        prefsWindowController = [[PrefsWindowController alloc] initWithWindowNibName:@"PrefsWindow"];
    }
    
    //show it
    [self.prefsWindowController showWindow:self];
    
    //invoke function in background that will make window modal
    // ->waits until window is non-nil
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{

        //make modal
        makeModal(self.prefsWindowController);
        
    });

    return;
}
 
*/

/*
//automatically invoked when menu is clicked
// ->tell menu to disable 'Preferences' when scan is running
-(BOOL)validateMenuItem:(NSMenuItem *)item
{
    //enable
    BOOL bEnabled = YES;
    
    //check if item is 'Preferences'
    if(PREF_MENU_ITEM_TAG == item.tag)
    {
        //unset enabled flag if scan is running
        if(YES != [[self.scanButtonLabel stringValue] isEqualToString:START_SCAN])
        {
            //disable
            bEnabled = NO;
        }
 
    }
         

    return bEnabled;
}
*/


//automatically invoked when user clicks on Flat/Tree view
// ->invoke helper function to change view
-(IBAction)switchView:(id)sender
{
    //ignore same selection
    if(self.taskViewFormat == [[sender selectedCell] tag])
    {
        //bail
        goto bail;
    }
    
    //save selected view
    self.taskViewFormat = [[sender selectedCell] tag];
    
    //flat view
    // ->enable 'filter tasks' search field
    if(FLAT_VIEW == self.taskViewFormat)
    {
        //enable
        self.filterTasksBox.enabled = YES;
    }
    //tree view
    // ->disable 'filter tasks' search field
    else
    {
        //disable
        self.filterTasksBox.enabled = NO;
    }
    
    //switch (top) view/pane
    [self changeViewController];
    
    //always unset filter flag
    self.taskTableController.isFiltered = NO;
    
    //always reset filter text
    [self.filterTasksBox setStringValue:@""];
    
    //sync
    @synchronized(self.taskTableController.filteredItems)
    {

    //remove all filtered tasks
    [self.taskTableController.filteredItems removeAllObjects];
        
    }//sync
    
    //reset current task
    self.currentTask = nil;
    
    //reload top pane
    [self reloadTaskTable];
    
    //select top row
    [self.taskTableController.itemView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    
    //reload bottom pane
    // ->ensures correct info is shown for selected (top) task
    [((AppDelegate*)[[NSApplication sharedApplication] delegate]) selectBottomPaneContent:nil];
    
//bail
bail:
    
    return;
}

//(automatically) invoked on segmented button click or (manually) on task (top pane) switch
// ->change input (for pane) & then refresh it
-(IBAction)selectBottomPaneContent:(id)sender
{
    //tag
    NSUInteger segmentTag = 0;
 
    //filter box placeholder text
    NSString* filterPlaceholder = nil;
    
    //always reset filter flag
    self.bottomViewController.isFiltered = NO;
    
    //always reset filter box's text
    self.filterItemsBox.stringValue = @"";
    
    //remove all filtered items
    [self.bottomViewController.filteredItems removeAllObjects];
    
    //for currently selected tasks
    // ->check if its still alive
    if(nil != self.currentTask)
    {
        //helper method that takes care of all check/handling dead tasks :)
        [self.taskTableController handleRowSelection];
    }
    
    //when no current task
    // ->set to first task in sorted tasks
    if(nil == self.currentTask)
    {
        //set to first
        self.currentTask = self.taskEnumerator.tasks[[self.taskEnumerator.tasks keyAtIndex:0]];
    }

    //get segment tag
    segmentTag = [[self.bottomPaneBtn selectedCell] tagForSegment:[self.bottomPaneBtn selectedSegment]];
    
    //always hide 'no items' label
    self.noItemsLabel.hidden = YES;
    
    //unset existing items
    self.bottomViewController.tableItems = nil;
    
    //when in a background thread
    // ->perform UI stuff on main thread
    if(YES != [NSThread isMainThread])
    {
        //refresh on main thread
        dispatch_sync(dispatch_get_main_queue(), ^{
            
            //reload to clear
            [(id)self.bottomViewController reloadTable];
            
            //start progress indicator
            [self.bottomPaneSpinner startAnimation:nil];
            
        });
    }
    //in main thread already
    // ->just perform UI actions directly
    else
    {
        //reload to clear
        [(id)self.bottomViewController reloadTable];
        
        //start progress indicator
        [self.bottomPaneSpinner startAnimation:nil];
    }

    //set input
    switch(segmentTag)
    {
        //dylibs
        case DYLIBS_VIEW:
            
            //init placeholder text for dylibs
            filterPlaceholder =  @"Filter Dylibs";
            
            //remove all task's dylibs
            [self.currentTask.dylibs removeAllObjects];
            
            //(re)enumerate dylibs via XPC
            // ->triggers table reload when done
            [self.currentTask enumerateDylibs:self.taskEnumerator.dylibs];
            
            break;
            
        //files
        case FILES_VIEW:
            
            //init placeholder text for files
            filterPlaceholder = @"Filter Files";
            
            //remove all task's dylibs
            [self.currentTask.files removeAllObjects];
            
            //(re)enumerate files via XPC
            // ->triggers table reload when done
            [self.currentTask enumerateFiles];

            break;
            
        //networking
        case NETWORKING_VIEW:
            
            //init placeholder text for network
            filterPlaceholder = @"Filter Connections";
            
            //(re)enumerate network connections via XPC
            // ->triggers table reload when done
            [self.currentTask enumerateNetworking];
            
            break;
            
        default:
            break;
    }
    
    //when in a background thread
    // ->perform UI stuff on main thread
    if(YES != [NSThread isMainThread])
    {
        //set filter box's placeholder text
        // ->UI change, so do on main thread
        dispatch_sync(dispatch_get_main_queue(), ^{
            
            //set placeholder
            [[self.filterItemsBox cell] setPlaceholderString:filterPlaceholder];
        });
    }
    //in main thread already
    // ->just perform UI actions directly
    else
    {
        //set placeholder
        [[self.filterItemsBox cell] setPlaceholderString:filterPlaceholder];
    }
    
    
//bail
bail:
    

    return;
}

//automatically invoked when user enters text in filter search boxes
// ->filter tasks and/or items
-(void)controlTextDidChange:(NSNotification *)aNotification
{
    //search text
    NSTextView* search = nil;
    
    //tag for bottom pane selector
    NSUInteger segmentTag = 0;
    
    //extract search (text) view
    search = aNotification.userInfo[@"NSFieldEditor"];
    
    //sanity check
    if(nil == search)
    {
        //bail
        goto bail;
    }
    
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

    //top pane
    if(YES == [aNotification.object isEqualTo:self.filterTasksBox])
    {
        //when text is reset
        // ->just reset flag
        if(0 == search.string.length)
        {
            //set flag
            self.taskTableController.isFiltered = NO;
        }
        //filter tasks
        else
        {
            //'#' indicates a keyword search
            // ->this is handled by customized auto-complete logic, so ignore
            if(YES == [search.string hasPrefix:@"#"])
            {
                //ignore
                goto bail;
            }
            
            //sync
            @synchronized(self.taskTableController.filteredItems)
            {

            //normal filter
            [self.filterObj filterTasks:search.string items:self.taskEnumerator.tasks results:self.taskTableController.filteredItems];
            
            }
                
            //set flag
            self.taskTableController.isFiltered = YES;
        }
        
        //finalize filtering/search
        // ->updates UI, etc
        [self finalizeFiltration:PANE_TOP];
    }
    //bottom pane
    else if(YES == [aNotification.object isEqualTo:self.filterItemsBox])
    {
        //when text is reset
        // ->just reset flag
        if(0 == search.string.length)
        {
            //set flag
            self.bottomViewController.isFiltered = NO;
        }
        
        //filter items
        else
        {
            //'#' indicates a keyword search
            // ->this is handled by customized auto-complete logic, so ignore
            if(YES == [search.string hasPrefix:@"#"])
            {
                //ignore
                goto bail;
            }
            
            //get segment tag
            segmentTag = [[self.bottomPaneBtn selectedCell] tagForSegment:[self.bottomPaneBtn selectedSegment]];
            
            //get item
            // ->will bail if item isn't in (current) view, etc
            switch(segmentTag)
            {
                //dylibs
                case DYLIBS_VIEW:
                {
                    //normal filter
                    [self.filterObj filterFiles:search.string items:self.currentTask.dylibs results:self.bottomViewController.filteredItems];
                    
                    break;
                }
                
                //files
                case FILES_VIEW:
                {
                    //filter
                    [self.filterObj filterFiles:search.string items:self.currentTask.files results:self.bottomViewController.filteredItems];
                    
                    break;
                }
                    
                //network connections
                case NETWORKING_VIEW:
                {
                    //filter
                    [self.filterObj filterConnections:search.string items:self.currentTask.connections results:self.bottomViewController.filteredItems];
                    
                    break;
                }
                    
                default:
                    break;
                    
            }//switch
            
            //set flag
            self.bottomViewController.isFiltered = YES;
        }
        
        //finalize filtering/searching
        // ->updates UI, etc
        [self finalizeFiltration:PANE_BOTTOM];
    }
    
//bail
bail:
    
    return;
}

//code to complete filtering/search
// ->reload table/scroll to top etc
-(void)finalizeFiltration:(NSUInteger)pane
{
    //top pane (task)
    if(PANE_TOP == pane)
    {
        //always reload task (top) pane
        // ->will trigger bottom load too
        [self.taskTableController.itemView reloadData];
        
        //scroll to top
        [self.taskTableController scrollToTop];
        
        //when nothing matches
        // ->reset current task and bottom pane
        if( (YES == self.taskTableController.isFiltered) &&
            (0 == self.taskTableController.filteredItems.count) )
        {
            //unset bottom pane's items
            self.bottomViewController.tableItems = nil;
            
            //reset current task
            self.currentTask = nil;
            
            //stop progress indicator
            [self.bottomPaneSpinner stopAnimation:nil];
            
            //reload bottom pane
            [self.bottomViewController.itemView reloadData];
        }
    }
    //bottom pane (dylibs, files, etc)
    else
    {
        //always reload item (bottom) pane
        [self.bottomViewController.itemView reloadData];
        
        //scroll to top
        [self.bottomViewController scrollToTop];
    }
    
    return;
}

//action for 'refresh' button/cmd+r hotkey
// ->query OS to refresh/reload all tasks
-(IBAction)refreshTasks:(id)sender
{
    //unselect current task
    self.currentTask = nil;
    
    //TODO: don't reset filtered items?
    // ...will require some smart filtering :/
    
    //unset filter flag
    self.taskTableController.isFiltered = NO;
    
    //sync
    @synchronized(self.taskTableController.filteredItems)
    {
        //remove all filtered items
        [self.taskTableController.filteredItems removeAllObjects];
    }
    
    //reset filter box
    self.filterTasksBox.stringValue = @"";
    
    //reset segment (bottom pane) back to dylibs
    self.bottomPaneBtn.selectedSegment = DYLIBS_VIEW;
    
    //scroll to top
    [self.taskTableController scrollToTop];

    //select top row
    [self.taskTableController.itemView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    
    //get tasks
    // ->background thread will enum tasks, update table, etc
    [self exploreTasks];
    
    return;
}

//constrain subview to parent view
-(void)constrainView:(NSView*)containerView subView:(NSView*)subView
{
    //remove top constraint
    if(nil != self.topConstraint)
    {
        //remove
        [containerView removeConstraint:self.topConstraint];
    }
    
    //remove bottom constraint
    if(nil != self.bottomConstraint)
    {
        //remove
        [containerView removeConstraint:self.bottomConstraint];
    }
    
    //remove leading constraint
    if(nil != self.leadingConstraint)
    {
        //remove
        [containerView removeConstraint:self.leadingConstraint];
    }
    
    //remove trailing constraint
    if(nil != self.trailingConstraint)
    {
        //remove
        [containerView removeConstraint:self.trailingConstraint];
    }
    
    //create top constraint
    self.topConstraint = [NSLayoutConstraint constraintWithItem:subView attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationEqual toItem:containerView attribute:NSLayoutAttributeTop multiplier:1.0 constant:0.0];
    
    //add top constraint
    [containerView addConstraint:self.topConstraint];
    
    //create bottom constraint
    self.bottomConstraint = [NSLayoutConstraint constraintWithItem:subView attribute:NSLayoutAttributeBottom relatedBy:NSLayoutRelationEqual toItem:containerView attribute:NSLayoutAttributeBottom multiplier:1.0 constant:0.0];
    
    //add bottom constraint
    [containerView addConstraint:self.bottomConstraint];
    
    //create leading constraint
    self.leadingConstraint = [NSLayoutConstraint constraintWithItem:subView attribute:NSLayoutAttributeLeading relatedBy:NSLayoutRelationEqual toItem:containerView attribute:NSLayoutAttributeLeading multiplier:1.0 constant:0.0];
    
    //add leading constraint
    [containerView addConstraint:self.leadingConstraint];
    
    //create trailing constraint
    self.trailingConstraint = [NSLayoutConstraint constraintWithItem:subView attribute:NSLayoutAttributeTrailing relatedBy:NSLayoutRelationEqual toItem:containerView attribute:NSLayoutAttributeTrailing multiplier:1.0 constant:0.0];
    
    //add trailing constraint
    [containerView addConstraint:self.trailingConstraint];
    
    return;
}

//save a flagged item
// ->also set text flagged items button label to red
-(void)saveFlaggedBinary:(Binary*)binary
{
    //first check if item is already flagged
    if(YES == [self.flaggedItems containsObject:binary])
    {
        //no need to add
        // ->so bail
        goto bail;
    }
    
    //sync to save
    @synchronized(self.flaggedItems)
    {
        //save
        [self.flaggedItems addObject:binary];
    }
    
    //when count is 1
    // ->means first flagged file so set image to red
    if(1 == self.flaggedItems.count)
    {
        //set main image
        [self.flaggedButton setImage:[NSImage imageNamed:@"flaggedRed"]];
        
        //set alternate image
        [self.flaggedButton setAlternateImage:[NSImage imageNamed:@"flaggedRedBG"]];
    
    }
    
//bail
bail:
    
    return;
}

//button handle for 'flagged items' button
// ->display (in separate popup) all flagged items
-(IBAction)showFlaggedItems:(id)sender
{
    //alert box
    NSAlert* alert = nil;
    
    //handle case where there aren't any flagged items
    // ->just show alert
    if(0 == self.flaggedItems.count)
    {
        //alloc/init alert
        alert = [NSAlert alertWithMessageText:[NSString stringWithFormat:@"No items flagged by VirusTotal"] defaultButton:@"Ok" alternateButton:nil otherButton:nil informativeTextWithFormat:@"hooray! 😇"];
        
        //and show it
        [alert runModal];
    }
    
    //show flagged items
    else
    {
        //alloc/init flagged items window
        if(nil == self.flagItemsWindowController)
        {
            //alloc/init
            flagItemsWindowController = [[FlaggedItems alloc] initWithWindowNibName:@"FlaggedItems"];
        }
        
        //init/prep it
        [self.flagItemsWindowController prepare];
                
        //show it
        [self.flagItemsWindowController showWindow:self];
        
        /*
        //invoke function in background that will make window modal
        // ->waits until window is non-nil
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            
            //make modal
            makeModal(self.flagItemsWindowController);
            
        });
        */
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
    
    //segment tag
    NSUInteger segmentTag = 0;
    
    //init array for matches
    matches = [[NSMutableArray alloc] init];
    
    //init range options
    rangeOptions = NSAnchoredSearch | NSCaseInsensitiveSearch;
    
    //grab segment tag
    segmentTag = [[self.bottomPaneBtn selectedCell] tagForSegment:[self.bottomPaneBtn selectedSegment]];
    
    //for now, only filter binaries
    // ->top pane: any (well, just tasks)
    //   bottom pane: only dylibs
    if( (textView != self.customTasksFilter) &&
        (DYLIBS_VIEW != segmentTag) )
    {
        //bail
        goto bail;
    }
    
    //check all filters
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
- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector
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
    //filter string
    NSString* filterString = nil;
    
    //extract filter
    filterString = textView.textStorage.string;
    
    //handle top pane (tasks)
    if(textView == self.customTasksFilter)
    {
        //sync
        @synchronized(self.taskTableController.filteredItems)
        {
            //filter
            [self.filterObj filterTasks:filterString items:self.taskEnumerator.tasks results:self.taskTableController.filteredItems];
        }
        
        //set flag
        self.taskTableController.isFiltered = YES;
        
        //finalize filtering
        [self finalizeFiltration:PANE_TOP];
        
    }
    //handle bottom pane
    // ->just dylibs
    else if(textView == self.customItemsFilter)
    {
        //filter
        [self.filterObj filterFiles:filterString items:self.currentTask.dylibs results:self.bottomViewController.filteredItems];
        
        //set flag
        self.bottomViewController.isFiltered = YES;
        
        //finalize filtering
        [self finalizeFiltration:PANE_BOTTOM];
    }
    
//bail
bail:
    
    return;
}

//automatically invoked
// ->set all NSSearchFields to be instances of our custom NSTextView
-(id)windowWillReturnFieldEditor:(NSWindow *)sender toObject:(id)client
{
    //field editor
    id fieldEditor = nil;
    
    //ignore non-NSSearchField classes
    if(YES != [client isKindOfClass:[NSSearchField class]])
    {
        //ingnore
        goto bail;
    }
    
    //set task's filter search field
    if(client == self.filterTasksBox)
    {
        //assign for return
        fieldEditor = self.customTasksFilter;
    }
    //set item's filter search field
    else if(client == self.filterItemsBox)
    {
        //assign for return
        fieldEditor = self.customItemsFilter;
    }
    
    
//bail
bail:
    
    return fieldEditor;
}



@end
