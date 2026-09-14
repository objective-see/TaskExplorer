//
//  AppDelegate.m
//  TaskExplorer
//
//  Created by Patrick Wardle
//  Copyright (c) 2015 Objective-See. All rights reserved.
//
//  note: app lifecycle (extension activation, termination, etc)
//        ...the UI itself is swift (see MainWindowController, etc)

#import "Consts.h"
#import "Update.h"
#import "Utilities.h"
#import "UIUtilities.h"
#import "ModelNotify.h"
#import "AppDelegate.h"

#import "TaskExplorer-Swift.h"

#import <os/log.h>

/* GLOBALS */

//log handle
extern os_log_t logHandle;

@implementation AppDelegate

@synthesize xpcClient;
@synthesize extension;
@synthesize extensionReady;
@synthesize mainWindowController;
@synthesize prefsWindowController;
@synthesize welcomeWindowController;

//automatically invoked by OS
// ->main entry point for app (UI)
-(void)applicationDidFinishLaunching:(NSNotification *)notification
{
    //dbg msg
    os_log_debug(logHandle, "%s", __PRETTY_FUNCTION__);

    //another instance already running?
    // ->activate it & exit (the extension only serves one client; a second instance would silently steal its events)
    //   note: exit(), not terminate:, so no teardown (e.g. 'stop monitoring') hits the extension on behalf of the other instance
    for(NSRunningApplication* instance in [NSRunningApplication runningApplicationsWithBundleIdentifier:NSBundle.mainBundle.bundleIdentifier])
    {
        //other instance?
        if(instance.processIdentifier != getpid())
        {
            //dbg msg
            os_log_debug(logHandle, "another instance (pid: %d) is already running, activating it & exiting", instance.processIdentifier);

            //activate (the other instance)
            // ->'activateFromApplication:' hands over this (just launched, so activation-eligible) app's right to activate;
            //   a plain 'activateWithOptions:' from a non-frontmost app is ignored by cooperative activation (macOS 14+)
            [instance activateFromApplication:NSRunningApplication.currentApplication options:NSApplicationActivateIgnoringOtherApps];

            //exit
            exit(0);
        }
    }

    //install (main) menu
    [MenuBuilder install];

    //init virus total object
    // ->loads api key from keychain, etc
    virusTotal = [[VirusTotal alloc] init];

    //Apple: item's w/ System Extensions must be run from /Applications
    // ->offer to move (copy) it there & relaunch
    if(YES != [NSBundle.mainBundle.bundlePath hasPrefix:@"/Applications/"])
    {
        //dbg msg
        os_log_debug(logHandle, "TaskExplorer running from %{public}@, not from within /Applications", NSBundle.mainBundle.bundlePath);

        //show alert
        // ->default button: move & relaunch
        if(NSAlertFirstButtonReturn == showAlert(NSAlertStyleInformational, @"TaskExplorer must run from within /Applications", @"Move it to /Applications and relaunch?", @[@"Move & Relaunch", @"Quit"]))
        {
            //move & relaunch
            // ->on success, this relaunches (new copy) then exits
            [self moveToApplicationsAndRelaunch];
        }

        //exit
        [NSApplication.sharedApplication terminate:self];
    }

    //init xpc client
    xpcClient = [[XPCExtensionClient alloc] init];

    //first time run?
    // show welcome window (walks user thru extension approval, etc)
    // note: on completion, invokes 'completeInitialization' to show main window
    if(YES != [[NSUserDefaults standardUserDefaults] boolForKey:NOT_FIRST_TIME])
    {
        //dbg msg
        os_log_debug(logHandle, "first launch, showing welcome window");

        //alloc/init
        welcomeWindowController = [[WelcomeWindowController alloc] init];

        //show
        [self.welcomeWindowController showWindow:self];

        //front
        [self.welcomeWindowController.window makeKeyAndOrderFront:self];

        //front
        [NSApp activateIgnoringOtherApps:YES];
    }
    //subsequent launches
    // ->show main window, (re)activate extension, then go
    else
    {
        //show main window
        [self showMainWindow];

        //wait to allow app to become front
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, .33 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{

            //start extension
            // will invoke 'go' method once its running
            [self startExtension];
        });
    }

    return;
}

//show main window
-(void)showMainWindow
{
    //alloc/init
    if(nil == self.mainWindowController)
    {
        //alloc/init
        mainWindowController = [[MainWindowController alloc] init];
    }

    //show
    [self.mainWindowController showWindow:self];

    //front
    [self.mainWindowController.window makeKeyAndOrderFront:self];

    //make app front
    [NSApp activateIgnoringOtherApps:YES];

    return;
}

//exit when (main) window is closed
-(BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
    return YES;
}

//move (copy) app into /Applications & relaunch it (from there)
// ->on success, launches new copy (caller then exits); on failure, shows error
-(void)moveToApplicationsAndRelaunch
{
    //destination
    NSString* destination = nil;

    //error
    NSError* error = nil;

    //init destination
    destination = [@"/Applications" stringByAppendingPathComponent:NSBundle.mainBundle.bundlePath.lastPathComponent];

    //dbg msg
    os_log_debug(logHandle, "moving %{public}@ to %{public}@", NSBundle.mainBundle.bundlePath, destination);

    //remove any existing copy
    if(YES == [NSFileManager.defaultManager fileExistsAtPath:destination])
    {
        //move existing copy to the trash (recoverable), rather than deleting it
        if(YES != [NSFileManager.defaultManager trashItemAtURL:[NSURL fileURLWithPath:destination] resultingItemURL:nil error:&error])
        {
            //err msg
            os_log_error(logHandle, "ERROR: failed to remove existing %{public}@: %{public}@", destination, error);

            //show alert
            showAlert(NSAlertStyleCritical, @"ERROR: failed to move TaskExplorer", [NSString stringWithFormat:@"Could not replace existing %@\r\n\r\n%@", destination, error.localizedDescription], @[@"OK"]);

            //bail
            goto bail;
        }
    }

    //copy
    if(YES != [NSFileManager.defaultManager copyItemAtPath:NSBundle.mainBundle.bundlePath toPath:destination error:&error])
    {
        //err msg
        os_log_error(logHandle, "ERROR: failed to copy to %{public}@: %{public}@", destination, error);

        //show alert
        showAlert(NSAlertStyleCritical, @"ERROR: failed to move TaskExplorer", [NSString stringWithFormat:@"Could not copy to %@\r\n\r\n%@", destination, error.localizedDescription], @[@"OK"]);

        //bail
        goto bail;
    }

    //dbg msg
    os_log_debug(logHandle, "relaunching from %{public}@", destination);

    //relaunch (new copy)
    // ->'open -n' allows two instances (us, and the new one) to briefly co-exist
    execTask(OPEN, @[@"-n", @"-a", destination], NO);

    //exit (now)
    // ->nothing has been started yet, and the new copy's single-instance guard must not find us still tearing down
    exit(0);

bail:

    return;
}

//(re)activate extension, wait for it to check in (& have full disk access), then go!
// ->status updates are posted via 'notifyStatus'
-(void)startExtension
{
    //status
    notifyStatus(@"Starting system extension…");

    //init extension object
    // ->retained (iVar), as it's the delegate for the (async) activation request
    self.extension = [[Extension alloc] init];

    //in background
    // activate extension, then wait for it to check in
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{

        //kick off extension activation request
        [self.extension toggleExtension:ACTION_ACTIVATE reply:^(NSError* error)
        {
            //dbg msg
            os_log_debug(logHandle, "extension 'activate' returned (error: %{public}@)", error);

            //restart required?
            if( (nil != error) &&
                (YES == [error.domain isEqualToString:@BUNDLE_ID]) &&
                (OSSystemExtensionRequestWillCompleteAfterReboot == error.code) )
            {
                //log msg
                os_log(logHandle, "system extension update requires a restart");

                //show alert on main thread
                dispatch_async(dispatch_get_main_queue(), ^{

                    //show alert
                    showAlert(NSAlertStyleInformational, @"Restart Required", @"TaskExplorer's system extension update will complete after your Mac restarts.", @[@"OK"]);

                    //exit
                    [NSApplication.sharedApplication terminate:self];
                });

                //bail
                return;
            }

            //error?
            if(nil != error)
            {
                //err msg
                os_log_error(logHandle, "ERROR: failed to activate extension: %{public}@", error);

                //show alert on main thread
                dispatch_async(dispatch_get_main_queue(), ^{

                    //show alert
                    showAlert(NSAlertStyleCritical, @"ERROR: activation failed", [NSString stringWithFormat:@"Failed to activate TaskExplorer's system extension.\r\n\r\n%@", error.localizedDescription], @[@"OK"]);

                    //exit
                    [NSApplication.sharedApplication terminate:self];
                });

                //bail
                return;
            }

            //dbg msg
            os_log_debug(logHandle, "activated system extension, waiting for it to check in...");

            //wait for extension to check in
            [self waitForExtension:^(BOOL ready) {

                //not ready?
                if(YES != ready)
                {
                    //on main thread
                    dispatch_async(dispatch_get_main_queue(), ^{

                        //show alert
                        showAlert(NSAlertStyleCritical, @"ERROR: extension not responding", @"TaskExplorer's system extension is not responding.\r\n\r\nMake sure it's approved (System Settings > General > Login Items & Extensions). A reboot might also fix this!", @[@"OK"]);

                        //exit
                        [NSApplication.sharedApplication terminate:self];
                    });

                    //bail
                    return;
                }

                //extension has full disk access?
                // ->required for endpoint security
                if(YES == [self.xpcClient extensionHasFullDiskAccess])
                {
                    //on main thread
                    dispatch_async(dispatch_get_main_queue(), ^{

                        //set flag
                        self.extensionReady = YES;

                        //clear status
                        notifyStatus(nil);

                        //go!
                        [self exploreTasks];
                    });

                    //done
                    return;
                }

                //no full disk access
                // ->tell user, open system settings, & wait
                notifyStatus(@"Grant Full Disk Access to “TaskExplorer Extension”\n(System Settings › Privacy & Security › Full Disk Access)");

                //open system settings (full disk access)
                dispatch_async(dispatch_get_main_queue(), ^{

                    //open
                    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:URL_SYSTEM_SETTINGS_FDA]];
                });

                //wait for full disk access
                [self waitForFullDiskAccess:^(BOOL granted) {

                    //on main thread
                    dispatch_async(dispatch_get_main_queue(), ^{

                        //not granted?
                        if(YES != granted)
                        {
                            //show alert
                            showAlert(NSAlertStyleCritical, @"ERROR: extension lacks Full Disk Access", @"TaskExplorer's system extension requires Full Disk Access (System Settings > Privacy & Security > Full Disk Access).", @[@"OK"]);

                            //exit
                            [NSApplication.sharedApplication terminate:self];

                            //bail
                            return;
                        }

                        //set flag
                        self.extensionReady = YES;

                        //clear status
                        notifyStatus(nil);

                        //go!
                        [self exploreTasks];
                    });
                }];
            }];
        }];

        //user approval needed?
        // update status message
        [NSThread sleepForTimeInterval:1.0f];
        if( (YES == self.extension.needsApproval) &&
            (YES != self.extensionReady) )
        {
            //status
            notifyStatus(@"Approve the extension in System Settings\n(General › Login Items & Extensions)");
        }
    });

    return;
}

//wait for extension to be running & checked in (via XPC)
// ->invokes reply (on background thread) w/ result
-(void)waitForExtension:(void (^)(BOOL))reply
{
    //in background
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{

        //extension
        Extension* extensionObj = nil;

        //flag
        BOOL ready = NO;

        //init extension object
        extensionObj = [[Extension alloc] init];

        //wait for extension process
        // ->user might need to approve it, so wait (a long time)
        for(NSUInteger i = 0; i < 60 * 30; i++)
        {
            //running?
            if(YES == [extensionObj isExtensionRunning])
            {
                //dbg msg
                os_log_debug(logHandle, "extension is running");

                //done
                break;
            }

            //nap
            [NSThread sleepForTimeInterval:0.5f];
        }

        //wait for extension to check in
        ready = [self.xpcClient waitForExtension:40];

        //reply
        reply(ready);
    });

    return;
}

//wait for extension to have full disk access (polls via XPC)
// ->invokes reply (on background thread) once granted, or w/ NO on timeout
-(void)waitForFullDiskAccess:(void (^)(BOOL))reply
{
    //in background
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{

        //flag
        BOOL granted = NO;

        //poll
        // ->user might need to find the setting, so wait (a long time)
        for(NSUInteger i = 0; i < 60 * 30; i++)
        {
            //granted?
            if(YES == [self.xpcClient extensionHasFullDiskAccess])
            {
                //dbg msg
                os_log_debug(logHandle, "extension has full disk access");

                //set flag
                granted = YES;

                //done
                break;
            }

            //nap
            [NSThread sleepForTimeInterval:1.0f];
        }

        //reply
        reply(granted);
    });

    return;
}

//complete initialization
// ->invoked by welcome window once extension is approved/running
-(void)completeInitialization
{
    //dbg msg
    os_log_debug(logHandle, "completing initialization (extension is ready)");

    //set key
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:NOT_FIRST_TIME];

    //set flag
    self.extensionReady = YES;

    //show main window
    //done with the welcome window (if any)
    // ->note: released here (not just closed), as reopen (dock click) is gated on it being gone
    self.welcomeWindowController = nil;

    [self showMainWindow];

    //go!
    [self exploreTasks];

    return;
}

//begin task enumeration
-(void)exploreTasks
{
    //alloc task enumerator
    if(nil == taskEnumerator)
    {
        //alloc
        taskEnumerator = [[TaskEnumerator alloc] initWithClient:self.xpcClient];
    }

    //kick off thread to enum task
    // ->will notify UI as results come in
    [NSThread detachNewThreadSelector:@selector(enumerateTasks:) toTarget:taskEnumerator withObject:nil];

    return;
}

//(re)enumerate all tasks
-(IBAction)refreshTasks:(id)sender
{
    //not ready?
    if(YES != self.extensionReady)
    {
        //bail
        return;
    }

    //coalesce
    // ->a refresh already pending (waiting for the running enumeration) covers this one too; the refresh queue is
    //   serial, so two enumerations can never run concurrently (they'd race on state, and double all the work)
    static BOOL pending = NO;
    @synchronized(self)
    {
        //pending?
        if(YES == pending)
        {
            //bail
            return;
        }

        //set
        pending = YES;
    }

    //wait till (existing) task enumerator thread is done
    dispatch_async(taskEnumerator.refreshQueue, ^{

        //wait
        while(YES == [taskEnumerator.enumerator isExecuting])
        {
            //nap
            [NSThread sleepForTimeInterval:0.5f];
        }

        //(re)explore tasks
        dispatch_sync(dispatch_get_main_queue(), ^{

            //unset
            @synchronized(self) { pending = NO; }

            //explore
            [self exploreTasks];
        });
    });

    return;
}

//uninstall
// ->deactivates the system extension (macOS asks the user for admin credentials; this only works from the GUI app,
//   not from a root/cli process, and not while terminating), then moves the app to the trash and quits
//   note: re-activating later requires approving the extension in System Settings again, hence not done on quit
-(IBAction)uninstall:(id)sender
{
    //confirm
    if(NSAlertFirstButtonReturn != showAlert(NSAlertStyleWarning, @"Uninstall TaskExplorer?", @"This removes the system extension, settings, and API keys, then moves TaskExplorer to the Trash.", @[@"Uninstall", @"Cancel"]))
    {
        //bail
        return;
    }

    //in background (the admin prompt & deactivation block)
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{

        //deactivate (blocks until the user answers the prompt; generous timeout)
        BOOL deactivated = [[[Extension alloc] init] deactivate:300];

        //on main thread
        dispatch_async(dispatch_get_main_queue(), ^{

            //error
            NSError* error = nil;

            //failed (or cancelled)?
            if(YES != deactivated)
            {
                //err msg
                os_log_error(logHandle, "ERROR: uninstall: extension deactivation failed (or was cancelled)");

                //show alert
                showAlert(NSAlertStyleWarning, @"TaskExplorer was not uninstalled", @"The system extension was not deactivated (cancelled, or not authorized).", @[@"OK"]);

                //bail
                return;
            }

            //dbg msg
            os_log_debug(logHandle, "uninstall: extension deactivated, removing settings, cache, keys, & trashing app");

            //remove VirusTotal cache (~/Library/Caches/<bundle id>)
            // ->unset the path first, so a (debounced) save can't recreate it
            virusTotal.cachePath = nil;
            [VirusTotal deleteCache];

            //remove api keys (VirusTotal, assistant providers)
            deleteKeychainItem(VT_API_KEYCHAIN_ATTR);
            deleteKeychainItem(ANTHROPIC_API_KEYCHAIN_ATTR);
            deleteKeychainItem(OPENAI_API_KEYCHAIN_ATTR);

            //remove settings
            // ->note: also on the way out (see 'applicationShouldTerminate'), as window state, etc may be saved meanwhile
            self.uninstalling = YES;
            [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:APP_ID];

            //trash app
            if(YES != [NSFileManager.defaultManager trashItemAtURL:[NSURL fileURLWithPath:NSBundle.mainBundle.bundlePath] resultingItemURL:nil error:&error])
            {
                //err msg
                os_log_error(logHandle, "ERROR: failed to trash %{public}@: %{public}@", NSBundle.mainBundle.bundlePath, error);

                //show alert
                showAlert(NSAlertStyleWarning, @"Extension deactivated", [NSString stringWithFormat:@"The system extension was deactivated, but TaskExplorer could not be moved to the Trash:\r\n\r\n%@", error.localizedDescription], @[@"OK"]);
            }
            else
            {
                //show alert
                showAlert(NSAlertStyleInformational, @"TaskExplorer was uninstalled", @"The system extension was deactivated and TaskExplorer was moved to the Trash.", @[@"Quit"]);
            }

            //quit (extension already gone: skip the 'stop monitoring' teardown)
            self.extensionReady = NO;
            [NSApp terminate:self];
        });
    });

    return;
}

//(re)open (dock icon clicked, 'open -a' while running)
// ->show the main window again (e.g. after it was closed while Settings stayed open)
-(BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag
{
    //main window (once initialized)?
    if( (YES == self.extensionReady) &&
        (nil == self.welcomeWindowController) )
    {
        //show
        [self showMainWindow];
    }

    return YES;
}

//automatically invoked when app is terminating
// ->stop/deactivate extension first (async), then allow termination
//   note: we don't want the extension running when the app isn't, but deactivation retains approval
-(NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender
{
    //reply
    NSApplicationTerminateReply reply = NSTerminateNow;

    //once
    static BOOL stopping = NO;

    //save VirusTotal results cache (if dirty)
    // ->skipped when uninstalling (would recreate what was just removed)
    if(YES != self.uninstalling)
    {
        //flush
        [virusTotal flushCache];
    }
    //uninstalling?
    // ->remove settings (again; anything saved since)
    else
    {
        //remove
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:APP_ID];
    }

    //extension never started (or already stopping)?
    // ->nothing to do, terminate now
    if( (YES != self.extensionReady) ||
        (YES == stopping) )
    {
        //bail
        goto bail;
    }

    //set flag
    stopping = YES;

    //terminate later
    // ->once extension is stopped
    reply = NSTerminateLater;

    //dbg msg
    os_log_debug(logHandle, "app terminating, stopping extension...");

    //stop extension
    // ->then complete termination
    [self stopExtension:^{

        //on main thread
        dispatch_async(dispatch_get_main_queue(), ^{

            //terminate
            [NSApp replyToApplicationShouldTerminate:YES];
        });
    }];

bail:

    return reply;
}

//stop extension
// ->stops (live) monitoring, tears down XPC, & deactivates extension (approval is retained)
-(void)stopExtension:(void (^)(void))completion
{
    //in background
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{

        //stop (live) monitoring
        // ->extension deletes its ES client, and goes idle (but stays resident & approved)
        //   note: deactivating (via OSSystemExtensionRequest) requires admin authorization (OSSystemExtensionErrorAuthorizationRequired),
        //         and an extension that exits is simply relaunched by launchd, so 'idle' is the best we can do w/o prompting the user
        [taskEnumerator stopMonitoring];

        //tear down XPC
        [self.xpcClient.extension invalidate];

        //done
        if(nil != completion)
        {
            //invoke
            completion();
        }
    });

    return;
}

//about
// ->standard about panel, w/ patrons as credits
-(IBAction)about:(id)sender
{
    //patrons
    NSString* patrons = nil;

    //credits
    NSAttributedString* credits = nil;

    //load patrons
    patrons = [NSString stringWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"patrons" ofType:@"txt"] encoding:NSUTF8StringEncoding error:NULL];
    if(0 != patrons.length)
    {
        //init credits
        credits = [[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"Mahalo to all the patrons!\n\n%@", patrons] attributes:@{NSFontAttributeName:[NSFont systemFontOfSize:11]}];
    }

    //show
    [NSApp orderFrontStandardAboutPanelWithOptions:(nil != credits) ? @{NSAboutPanelOptionCredits:credits} : @{}];

    return;
}

//show preferences
-(IBAction)showPreferences:(id)sender
{
    //alloc/init
    if(nil == self.prefsWindowController)
    {
        //alloc/init
        prefsWindowController = [[PreferencesWindowController alloc] init];
    }

    //show
    [self.prefsWindowController showWindow:self];

    //front
    [self.prefsWindowController.window makeKeyAndOrderFront:self];

    return;
}

//check for update
-(IBAction)check4Update:(id)sender
{
    //update obj
    Update* update = nil;

    //init
    update = [[Update alloc] init];

    //check
    // ->result shown via alert
    [update checkForUpdate:^(NSUInteger result, NSString* latestVersion) {

        //handle result
        switch(result)
        {
            //error
            case UPDATE_ERROR:
                showAlert(NSAlertStyleWarning, @"Update Check Failed", @"Failed to check for an update.", @[@"OK"]);
                break;

            //no updates
            case UPDATE_NOTHING_NEW:
                showAlert(NSAlertStyleInformational, @"No Update Available", [NSString stringWithFormat:@"You're all up to date! (v. %@)", getAppVersion()], @[@"OK"]);
                break;

            //new version
            case UPDATE_NEW_VERSION:

                //show alert, w/ option to go to product page
                if(NSAlertFirstButtonReturn == showAlert(NSAlertStyleInformational, @"Update Available", [NSString stringWithFormat:@"A new version (%@) is available!", latestVersion], @[@"Update", @"Close"]))
                {
                    //open product url
                    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:PRODUCT_URL]];
                }
                break;

            default:
                break;
        }
    }];

    return;
}

@end
