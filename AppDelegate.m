//
//  AppDelegate.m
//  KnockKnock
//

#import "Consts.h"
#import "Binary.h"
#import "Exception.h"
#import "Utilities.h"
#import "AppDelegate.h"

#import "TaskTableController.h"
#import "RequestRootWindowController.h"

#import "Task.h"

//TODO: bottom pane's progress indicator: center via autolayout

@implementation AppDelegate


@synthesize filterObj;
@synthesize vtThreads;
@synthesize virusTotalObj;
@synthesize taskTableController;
@synthesize aboutWindowController;
@synthesize prefsWindowController;
@synthesize showPreferencesButton;
@synthesize resultsWindowController;
@synthesize bottomPane;
@synthesize bottomViewController;
@synthesize currentTask;
@synthesize requestRootWindowController;
@synthesize taskViewFormat;

@synthesize scannerThread;
@synthesize versionString;
@synthesize progressIndicator;

@synthesize topPane;
@synthesize taskEnumerator;
//@synthesize treeViewController;
//@synthesize currentViewController;
@synthesize viewSelector;


//@synthesize taskScrollView;
//TODO: check if VT can be reached! if not, error? or don't show '0 VT results detected' etc...

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
    
    //set initial view
    // ->default is flat (non-tree) view
    //[self changeViewController:[self.viewSelector selectedItem].tag];
    
    return;
}

//automatically invoked by OS
// ->main entry point
-(void)applicationDidFinishLaunching:(NSNotification *)notification
{
    //user defaults
    //NSUserDefaults* defaults = nil;
    
    //flag for first time
    //BOOL isFirstRun = NO;
    
    //first thing...
    // ->install exception handlers!
    //TODO: re-enable
    //installExceptionHandlers();
    
    //self.taskScrollView.wantsLayer = TRUE;
    //self.taskScrollView.layer.cornerRadius = 20;
    
    //init filter object
    //filterObj = [[Filter alloc] init];
    
    //init virus total object
    //virusTotalObj = [[VirusTotal alloc] init];
    
    //init array for virus total threads
    //vtThreads = [NSMutableArray array];
    
    //check that OS is supported
    if(YES != isSupportedOS())
    {
        //show alert
        [self showUnsupportedAlert];
        
        //exit
        exit(0);
    }
    
    //check if authenticated
    // ->display authentication request if needed
    if(YES != [self isAuthenticated])
    {
        //ask
        // ->displays popup
        [self askForRoot];
        
        //TODO: make sure we call 'explore' once successfully auth'd :)
    }
    else
    {
        //init mouse-over areas
        [self initTrackingAreas];
        
        //go!
        [self exploreTasks];
    }
    
    
    
    /*
    //load defaults
    defaults = [NSUserDefaults standardUserDefaults];
    
    //extact first run key
    // ->nil means first time!
    if(nil == [defaults objectForKey:PREF_FIRST_RUN])
    {
        //set flag
        isFirstRun = YES;
        
        //set flag persistently
        [defaults setBool:NO forKey:PREF_FIRST_RUN];
        
        //flush/save
        [defaults synchronize];
    }
    */
    
    //set default top pane view to flat
    self.taskViewFormat = FLAT_VIEW;
    
    //set initial view for top pane
    // ->default is flat (non-tree) view
    [self changeViewController];
    
    //alloc/init bottom pane controller
    self.bottomViewController = [[TaskTableController alloc] initWithNibName:@"FlatView" bundle:nil];
    
    //set flag
    self.bottomViewController.isBottomPane = YES;
    
    //set input
    //self.bottomViewController.tableItems = currentTask.dylibs;
    
    //add subview
    [self.bottomPane addSubview:[self.bottomViewController view]];
    
    //[self.bottomPane addSubview:self.noItemsLabel];
    
    //set frame
    [[self.bottomViewController view] setFrame:[self.bottomPane bounds]];
    
    //set default msg
    [self.bottomViewController.view addSubview:self.noItemsLabel];






    //set delegate
    // ->ensures our 'windowWillClose' method, which has logic to fully exit app
    self.window.delegate = self;
    
    
    
    
    //kick off thread to begin enumerating shared objects
    // ->this takes awhile, so do it now!
    //[self.sharedItemEnumerator start];

    //instantiate all plugins objects
    //self.plugins = [self instantiatePlugins];
    
    //set selected plugin to first
    //self.selectedPlugin = [self.plugins firstObject];
    
    //dbg msg
    //NSLog(@"KNOCKKNOCK: registered plugins: %@", self.plugins);
    
    //pre-populate category table w/ each plugin title
    //[self.categoryTableController initTable:self.plugins];
    
    //make category table active/selected
    //[[self.categoryTableController.categoryTableView window] makeFirstResponder:self.categoryTableController.categoryTableView];
    
    //hide status msg
    // ->when user clicks scan, will show up..
    //[self.statusText setStringValue:@""];
    
    //hide progress indicator
    //self.progressIndicator.hidden = YES;
    
    //init button label
    // ->start scan
    //[self.scanButtonLabel setStringValue:START_SCAN];
    
    //set version info
    //[self.versionString setStringValue:[NSString stringWithFormat:@"version: %@", getAppVersion()]];
    
    //init tracking areas
    //[self initTrackingAreas];
    
    //set delegate
    // ->ensures our 'windowWillClose' method, which has logic to fully exit app
    //self.window.delegate = self;

    return;
}


//check if app is auth'd
// ->specifically, if XPC service is setuid
//TODO: error checking!?
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
    
    //get XPC services' attributes
    fileAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:xpcService error:nil];
    
    //check if (fully) auth'd
    // ->owned by r00t & SETUID
    if( (0 == [fileAttributes[NSFileOwnerAccountID] unsignedLongValue]) &&
        (0 != (S_ISUID & [fileAttributes[NSFilePosixPermissions] unsignedLongValue])) )
    {
        //set flag
        isAuthenticated = YES;
    }

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
    taskEnumerator = [[TaskEnumerator alloc] init];
    
    [NSThread detachNewThreadSelector:@selector(enumerateTasks) toTarget:self.taskEnumerator withObject:nil];
    
    /*
    //invoke function in background begin process enumeration
    //TODO: DISPATCH_QUEUE_PRIORITY_HIGH ok?
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        
        //start enumerating
        // ->will update table procs come in
        //[self.taskEnumerator enumerateTasks];
        
    });
    */
    
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
    }
    
    switch(self.taskViewFormat)
    {
        case FLAT_VIEW:
        {
            //alloc/init
            taskTableController = [[TaskTableController alloc] initWithNibName:@"FlatView" bundle:nil];
            /*if(self.taskTableController != nil)
            {
                //update iVar
                self.currentViewController = self.taskTableController;
            }*/
            break;
        }
        case TREE_VIEW:
        {
            //alloc/init
            taskTableController = [[TaskTableController alloc] initWithNibName:@"TreeView" bundle:nil];
            
            
            
            /*if(self.taskTableController != nil)
            {
                //update iVar
                self.currentViewController = self.taskTableController;
            }*/
            break;
        }
    }
    
    //add subview
    [self.topPane addSubview:[self.taskTableController view]];
    
    //set frame
    [[self.taskTableController view] setFrame:[self.topPane bounds]];
    
    return;
}

//TODO: add checks to make sure or handle switch to tree view!!!!
//reload (to re-draw) a specific row in table
-(void)reloadRow:(Task*)task item:(ItemBase*)item pane:(NSUInteger)pane
{
    //table view
    NSTableView* tableView = nil;
    
    //row
    NSUInteger row = 0;
    
    //top table (pane)
    if(PANE_TOP == pane)
    {
        //get row that task is loaded in
        tableView = [((id)self.taskTableController) itemView];
        
        //reloadItem
        // ->flat view
        if(YES != [tableView isKindOfClass:[NSOutlineView class]])
        {
            //get index where task is
            // TODO: doesn't account for filtering, etc!!!
            row = [self.taskEnumerator.tasks indexOfKey:task.pid];
            if(NSNotFound == row)
            {
                //bail
                goto bail;
            }
            
            //reload just the row
            // ->on main thread
            dispatch_async(dispatch_get_main_queue(), ^{
                
                //begin updates
                [tableView beginUpdates];
                
                //reload row
                [tableView reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:(row)] columnIndexes:[NSIndexSet indexSetWithIndex:0]];
                
                //end updates
                [tableView endUpdates];
                
            });
        }
        //reload item
        // ->tree view
        else
        {
            //begin updates
            [tableView beginUpdates];
            
            //reload
            [(NSOutlineView*)tableView reloadItem:task];
            
            //end updates
            [tableView endUpdates];
        }
            
        
    }
    
    //TODO: bottom pane
    
    
//bail
bail:
    
    return;
}

//smartly, reload bottom pane on main thread
// ->checks if task & item type (e.g. files) are both selected
-(void)reloadBottomPane:(Task*)task itemView:(NSUInteger)itemView
{
    //tag
    NSUInteger segmentTag = 0;
    
    /*
    if(YES == [task.binary.name isEqualToString:@"launchd"])
    {
        NSLog(@"asdf");
    }*/
    
    //get segment tag
    segmentTag = [[self.bottomPaneBtn selectedCell] tagForSegment:[self.bottomPaneBtn selectedSegment]];
    
    //ignore reloads for unselected tasks
    if(self.currentTask != task)
    {
        //NSLog(@"selected task: %@ not match %@", self.currentTask.binary.name, task.binary.name);
        
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
        
            break;
            
        //files
        case FILES_VIEW:
            
            ///set table items
            self.bottomViewController.tableItems = self.currentTask.files;
            
            break;
            
        //networking
        case NETWORKING_VIEW:
            
            //set table items
            self.bottomViewController.tableItems = self.currentTask.connections;
            break;
            
        default:
            break;
    }
    
    if(YES == [NSThread isMainThread])
    {
        [self finalizeBottomReload];
    }
    else
    {
        //reload
        // ->in main UI thread
        dispatch_sync(dispatch_get_main_queue(), ^{
            
            [self finalizeBottomReload];
        });
    }
    
//bail
bail:

    return;
}

-(void)finalizeBottomReload
{
   //stop progress indicator
    [self.bottomPaneSpinner stopAnimation:nil];
    
    //invoke refresh
    [(id)self.bottomViewController reloadTable];
    
    //no items?
    if(0 == self.bottomViewController.tableItems.count)
    {
        self.noItemsLabel.hidden = NO;
        
    }
    //no items?
    else
    {
        self.noItemsLabel.hidden = YES;
    }
    
    return;
}

//display alert about OS not being supported
-(void)showUnsupportedAlert
{
    //response
    // ->index of button click
    NSModalResponse response = 0;
    
    //alert box
    NSAlert* fullScanAlert = nil;
    
    //alloc/init alert
    fullScanAlert = [NSAlert alertWithMessageText:[NSString stringWithFormat:@"OS X %@ is not supported", [[NSProcessInfo processInfo] operatingSystemVersionString]] defaultButton:@"Ok" alternateButton:nil otherButton:nil informativeTextWithFormat:@"sorry for the inconvenience!"];
    
    //and show it
    response = [fullScanAlert runModal];
    
    return;
}

//init tracking areas for buttons
// ->provide mouse over effects
-(void)initTrackingAreas
{
    //tracking area for buttons
    NSTrackingArea* trackingArea = nil;
    
    //init tracking area
    // ->for scan button
    //trackingArea = [[NSTrackingArea alloc] initWithRect:[self.scanButton bounds] options:(NSTrackingInVisibleRect|NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways) owner:self userInfo:@{@"tag":[NSNumber numberWithUnsignedInteger:self.scanButton.tag]}];
    
    //add tracking area to scan button
    //[self.scanButton addTrackingArea:trackingArea];

    //init tracking area
    // ->for preference button
    trackingArea = [[NSTrackingArea alloc] initWithRect:[self.showPreferencesButton bounds] options:(NSTrackingInVisibleRect|NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways) owner:self userInfo:@{@"tag":[NSNumber numberWithUnsignedInteger:self.showPreferencesButton.tag]}];
    
    //add tracking area to pref button
    [self.showPreferencesButton addTrackingArea:trackingArea];
    
    //init tracking area
    // ->for logo button
    trackingArea = [[NSTrackingArea alloc] initWithRect:[self.logoButton bounds] options:(NSTrackingInVisibleRect|NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways) owner:self userInfo:@{@"tag":[NSNumber numberWithUnsignedInteger:self.logoButton.tag]}];
    
    //add tracking area to logo button
    [self.logoButton addTrackingArea:trackingArea];
    
    return;
}


//automatically invoked when window is un-minimized
// since the progress indicator is stopped (bug?), restart it
-(void)windowDidDeminiaturize:(NSNotification *)notification
{
    //make sure scan is going on
    // ->and then restart spinner
    if(YES == [self.scannerThread isExecuting])
    {
        //show
        [self.progressIndicator setHidden:NO];
        
        //start spinner
        [self.progressIndicator startAnimation:nil];
    }
    
    return;
}


/*
//kickoff a thread to query VT
-(void)queryVT:(PluginBase*)plugin
{
    //virus total thread
    NSThread* virusTotalThread = nil;
    
    //alloc thread
    // ->will query virus total to get info about all detected items
    virusTotalThread = [[NSThread alloc] initWithTarget:virusTotalObj selector:@selector(getInfo:) object:plugin];
    
    //start thread
    [virusTotalThread start];
    
    //sync
    @synchronized(self.vtThreads)
    {
        //save it into array
        [self.vtThreads addObject:virusTotalThread];
    }
    
    return;
}
*/

//automatically invoked when user clicks logo
// ->load objective-see's html page
-(IBAction)logoButtonHandler:(id)sender
{
    //open URL
    // ->invokes user's default browser
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://objective-see.com"]];
    
    return;
}

//TODO: don't think we need to sort by pid, since tree view, just uses kids!!!
//sort tasks
// ->either name (flat view) or pid (tree view)
-(void)sortTasksForView:(OrderedDictionary*)tasks;
{
    //sort tasks
    // ->flat view, sort by name
    if(FLAT_VIEW == self.taskViewFormat)
    {
        //sort
        [tasks sort:SORT_BY_NAME];
    }
    //sort tasks
    // ->tree view, sort by pid
    else
    {
        //sort
        [tasks sort:SORT_BY_PID];
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
            //[self.taskTableController refresh];
            [(id)self.taskTableController refresh];
            
        });
    }
    
    //on main thread
    // ->just refresh
    else
    {
        //TODO: currentViewCont?!?
        //refresh
        //[(id)self.taskTableController refresh];
        [(id)self.taskTableController refresh];
    }
    
    return;
}


/*
//callback method, invoked by virus total when plugin's items have been processed
// ->reload table if plugin matches active plugin
-(void)itemsProcessed:(PluginBase*)plugin
{
    //if there are any flagged items
    // ->reload category table (to trigger title turning red)
    if(0 != plugin.flaggedItems.count)
    {
        //execute on main (UI) thread
        dispatch_sync(dispatch_get_main_queue(), ^{
            
            //reload category table
            [self.categoryTableController customReload];
            
        });
    }

    //check if active plugin matches
    if(plugin == self.selectedPlugin)
    {
        //execute on main (UI) thread
        dispatch_sync(dispatch_get_main_queue(), ^{
        
            //scroll to top of item table
            [self.taskTableController scrollToTop];
            
            //reload item table
            [self.taskTableController.itemTableView reloadData];

        });
    }
    
    return;
}
*/

/*
 
//update a single row
-(void)itemProcessed:(File*)fileObj rowIndex:(NSUInteger)rowIndex
{
    //reload category table (on main thread)
    // ->ensures correct title color (red, or reset)
    dispatch_sync(dispatch_get_main_queue(), ^{
        
        //reload category table
        [self.categoryTableController customReload];
        
    });
    
 

    //check if active plugin matches
    if(fileObj.plugin == self.selectedPlugin)
    {
        //execute on main (UI) thread
        dispatch_sync(dispatch_get_main_queue(), ^{
            
            //start table updates
            [self.taskTableController.itemTableView beginUpdates];
            
            //update
            [self.taskTableController.itemTableView reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:rowIndex] columnIndexes:[NSIndexSet indexSetWithIndex:0]];
            
            //end table updates
            [self.taskTableController.itemTableView endUpdates];
            
        });
    }
 
     
    return;
}

*/


//callback when user has updated prefs
// ->reload table, etc
-(void)applyPreferences
{
    //currently selected category
    NSUInteger selectedCategory = 0;
    
    //save alert
    NSAlert* saveAlert = nil;
    
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


//update the UI to reflect that the fact the scan was stopped
// ->set text back to 'start scan', etc...
-(void)stopScanUI:(NSString*)statusMsg
{
    //status msg's frame
    CGRect newFrame = {};

    //stop spinner
    [self.progressIndicator stopAnimation:nil];
    
    //hide progress indicator
    self.progressIndicator.hidden = YES;
    
    //grab status msg's frame
    newFrame = self.statusText.frame;
    
    //shift it over (since activity spinner is gone)
    newFrame.origin.x += 50;
    
    //update status msg w/ new frame
    self.statusText.frame = newFrame;
    
    //set status msg
    [self.statusText setStringValue:statusMsg];
    
    //update button's image
    //self.scanButton.image = [NSImage imageNamed:@"startScan"];
    
    //update button's backgroud image
    //self.scanButton.alternateImage = [NSImage imageNamed:@"startScanBG"];
    
    //set label text
    // ->'Start Scan'
    //[self.scanButtonLabel setStringValue:START_SCAN];
    
    //re-enable gear (show prefs) button
    self.showPreferencesButton.enabled = YES;
    
    //only show scan stats for completed scan
    if(YES == [statusMsg isEqualToString:SCAN_MSG_COMPLETE])
    {
        //display scan stats in UI (popup)
        [self displayScanStats];
    }

    return;
}

/*
//shows alert stating that that scan is complete (w/ stats)
-(void)displayScanStats
{
    //detailed scan msg
    NSMutableString* details = nil;
    
    //item count
    NSUInteger itemCount = 0;
    
    //flagged item count
    NSUInteger flaggedItemCount =  0;
    
    //iterate over all plugins
    // ->sum up their item counts and flag items count
    for(PluginBase* plugin in self.plugins)
    {
        //when showing all findings
        // ->sum em all up!
        if(YES == self.prefsWindowController.showTrustedItems)
        {
            //add up
            itemCount += plugin.allItems.count;
            
            //add plugin's flagged items
            flaggedItemCount += plugin.flaggedItems.count;
            
            //init detailed msg
            details = [NSMutableString stringWithFormat:@"■ found %lu items", (unsigned long)itemCount];
        }
        //otherwise just unknown items
        else
        {
            //add up
            itemCount += plugin.unknownItems.count;
            
            //manually check if each unknown item is flagged
            // ->gotta do this since flaggedItems includes all items
            for(ItemBase* item in plugin.unknownItems)
            {
                //check if item it flagged
                if(YES == [plugin.flaggedItems containsObject:item])
                {
                    //inc
                    flaggedItemCount++;
                }
            }
            
            //init detailed msg
            details = [NSMutableString stringWithFormat:@"■ found %lu non-OS items", (unsigned long)itemCount];
        }
    }

    //when VT integration is enabled
    // ->add flagged items
    if(YES != self.prefsWindowController.disableVTQueries)
    {
        //add flagged items
        [details appendFormat:@" \r\n■ %lu item(s) flagged by VirusTotal", flaggedItemCount];
    }
    
    //when 'save results' is enabled
    // ->add msg about saving
    if(YES == self.prefsWindowController.saveOutput)
    {
        //add save msg
        [details appendFormat:@" \r\n■ saved findings to '%@'", OUTPUT_FILE];
    }
    
    //alloc/init settings window
    if(nil == self.resultsWindowController)
    {
        //alloc/init
        resultsWindowController = [[ResultsWindowController alloc] initWithWindowNibName:@"ResultsWindow"];
        
        //set details
        self.resultsWindowController.details = details;
    }
    
    //subsequent times
    // ->set details directly
    if(nil != self.resultsWindowController.detailsLabel)
    {
        //set
        self.resultsWindowController.detailsLabel.stringValue = details;
    }
    
    //show it
    [self.resultsWindowController showWindow:self];
    
    //invoke function in background that will make window modal
    // ->waits until window is non-nil
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        
        //make modal
        makeModal(self.resultsWindowController);
        
    });
    
    return;
} 
*/
 
 
//automatically invoked when window is closing
// ->tell OS that we are done with window so it can (now) be freed
//TODO: still needed!?
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
        /*
        //set original scan image
        if(SCAN_BUTTON_TAG == tag)
        {
            //scan running?
            if(YES == [self.scanButtonLabel.stringValue isEqualToString:@"Stop Scan"])
            {
                //set
                imageName = @"stopScan";

            }
            //scan not running
            else
            {
                //set
                imageName = @"startScan";
            }
            
        }*/
         
        //set original preferences image
        if(PREF_BUTTON_TAG == tag)
        {
            //set
            imageName = @"settings";
        }
        //set original logo image
        else if(LOGO_BUTTON_TAG == tag)
        {
            //set
            imageName = @"logoApple";
        }
    }
    //highlight button
    else
    {
        /*
        //set original scan image
        if(SCAN_BUTTON_TAG == tag)
        {
            //scan running
            if(YES == [self.scanButtonLabel.stringValue isEqualToString:@"Stop Scan"])
            {
                //set
                imageName = @"stopScanOver";
                
            }
            //scan not running
            else
            {
                //set
                imageName = @"startScanOver";
            }
            
        }
        */
        //set mouse over preferences image
        if(PREF_BUTTON_TAG == tag)
        {
            //set
            imageName = @"settingsOver";
        }
        //set mouse over logo image
        else if(LOGO_BUTTON_TAG == tag)
        {
            //set
            imageName = @"logoAppleOver";
        }
    }
    
    //set image
    
    //grab button
    button = [[[self window] contentView] viewWithTag:tag];
    
    if(YES == [button isEnabled])
    {
        //set
        [button setImage:[NSImage imageNamed:imageName]];
    }
    
    return;    
}

//save results to disk
// ->JSON dumped to current directory
-(void)saveResults
{
    //output
    NSMutableString* output = nil;
    
    //plugin items
    NSArray* items = nil;

    //output directory
    NSString* outputDirectory = nil;
    
    //output file
    NSString* outputFile = nil;
    
    //error
    NSError* error = nil;
    
    //init output string
    output = [NSMutableString string];
    
    //start JSON
    [output appendString:@"{"];
    
    /*
    
    //iterate over all plugins
    // ->format/add items to output
    for(PluginBase* plugin in self.plugins)
    {
        //set items
        // ->all?
        if(YES == self.prefsWindowController.showTrustedItems)
        {
            //set
            items = plugin.allItems;
        }
        //set items
        // ->just unknown items
        else
        {
            //set
            items = plugin.unknownItems;
        }
        
        //add plugin name
        [output appendString:[NSString stringWithFormat:@"\"%@\":[", plugin.name]];
    
        //sync
        // ->since array will be reset if user clicks 'stop' scan
        @synchronized(items)
        {
        
        //iterate over all items
        // ->convert to JSON/append to output
        for(ItemBase* item in items)
        {
            //add item
            [output appendFormat:@"{%@},", [item toJSON]];
            
        }//all plugin items
            
        }//sync
        
        //remove last ','
        if(YES == [output hasSuffix:@","])
        {
            //remove
            [output deleteCharactersInRange:NSMakeRange([output length]-1, 1)];
        }
        
        //terminate list
        [output appendString:@"],"];

    }//all plugins
    
    //remove last ','
    if(YES == [output hasSuffix:@","])
    {
        //remove
        [output deleteCharactersInRange:NSMakeRange([output length]-1, 1)];
    }
    
    //terminate list/output
    [output appendString:@"}"];
    
    //init output directory
    // ->app's directory
    outputDirectory = [[[NSBundle mainBundle] bundlePath] stringByDeletingLastPathComponent];
    
    //init full path to output file
    outputFile = [NSString stringWithFormat:@"%@/%@", outputDirectory, OUTPUT_FILE];
    
    //save JSON to disk
    if(YES != [output writeToFile:outputFile atomically:YES encoding:NSUTF8StringEncoding error:nil])
    {
        //err msg
        NSLog(@"OBJECTIVE-SEE ERROR: saving output to %@ failed with %@", outputFile, error);
        
        //bail
        goto bail;
    }
    */
    
//bail
bail:
    
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

//automatically invoked when menu is clicked
// ->tell menu to disable 'Preferences' when scan is running
-(BOOL)validateMenuItem:(NSMenuItem *)item
{
    //enable
    BOOL bEnabled = YES;
    
    //check if item is 'Preferences'
    if(PREF_MENU_ITEM_TAG == item.tag)
    {
        /*
        //unset enabled flag if scan is running
        if(YES != [[self.scanButtonLabel stringValue] isEqualToString:START_SCAN])
        {
            //disable
            bEnabled = NO;
        }
        */
    }
         

    return bEnabled;
}

//automatically invoked when user clicks on Flat/Tree view
// ->invoke helper function to change view
-(IBAction)switchView:(id)sender
{
    //save selected view
    self.taskViewFormat = [[sender selectedCell] tag];

    //switch (top) view/pane
    [self changeViewController];
    
    //reload top pane
    [self reloadTaskTable];
    
    return;
}

//(automatically) invoked on segmented button click or (manually) on task (top pane) switch
// ->change input (for pane) & then refresh it
//TODO: make xpcConnection appDelegate iVar
-(IBAction)selectBottomPaneContent:(id)sender
{
    //tag
    NSUInteger segmentTag = 0;

    //get segment tag
    segmentTag = [[self.bottomPaneBtn selectedCell] tagForSegment:[self.bottomPaneBtn selectedSegment]];
    
    /*
    //for dylibs
    // ->don't want to re-enum if initial enumerations is still occuring
    if( (DYLIBS_VIEW == segmentTag) &&
        (YES != [self.taskEnumerator shouldEnumDylibs]) &&
        (0 != self.currentTask.dylibs.count) )
    {
        //just reload pane
        [self reloadBottomPane:self.currentTask itemView:segmentTag];
            
        //bail
        goto bail;
    }
    */
    
    //always hide 'no items' label
    self.noItemsLabel.hidden = YES;
    
    //clear out existing items
    [self.bottomViewController.tableItems removeAllObjects];
    
    //reload to clear
    [(id)self.bottomViewController reloadTable];
    
    //start progress indicator
    [self.bottomPaneSpinner startAnimation:nil];
    
    //set input
    switch(segmentTag)
    {
        //dylibs
        case DYLIBS_VIEW:
            
            //(re)enumerate dylibs via XPC
            // ->triggers table reload when done
            [self.currentTask enumerateDylibs:self.taskEnumerator.xpcConnection allDylibs:self.taskEnumerator.dylibs];
            
            break;
            
        //files
        case FILES_VIEW:
            
            //(re)enumerate files via XPC
            // ->triggers table reload when done
            [self.currentTask enumerateFiles:self.taskEnumerator.xpcConnection];

            break;
            
        //networking
        case NETWORKING_VIEW:
            
            //(re)enumerate network connections via XPC
            // ->triggers table reload when done
            [self.currentTask enumerateNetworking:self.taskEnumerator.xpcConnection];
            
            break;
            
        default:
            break;
    }
    
//bail
bail:
    

    return;
}

@end
