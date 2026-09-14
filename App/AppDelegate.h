//
//  AppDelegate.h
//  TaskExplorer
//
//  Created by Patrick Wardle
//  Copyright (c) 2015 Objective-See. All rights reserved.
//
//  note: app lifecycle (extension activation, termination, etc)
//        ...the UI itself is swift (see MainWindowController, etc)

#import <Cocoa/Cocoa.h>

#import "Task.h"
#import "Binary.h"
#import "VirusTotal.h"
#import "Extension.h"
#import "TaskEnumerator.h"
#import "XPCExtensionClient.h"

/* GLOBALS */

//shared enumerator
extern TaskEnumerator* taskEnumerator;

//shared virustotal object
extern VirusTotal* virusTotal;

//network connected flag

@interface AppDelegate : NSObject <NSApplicationDelegate>
{

}

/* PROPERTIES */

//xpc client
// ->talks to (system) extension
@property(nonatomic, retain)XPCExtensionClient* xpcClient;

//uninstall (deactivate extension, trash app)
-(IBAction)uninstall:(id)sender;

//extension (activation) object
// ->must be retained, as it's the delegate for the (async) activation request
@property(nonatomic, retain)Extension* extension;

//flag
// ->extension is activated & checked in (and has full disk access)
@property BOOL extensionReady;

//uninstalling?
// ->settings are removed (not saved) on the way out
@property BOOL uninstalling;

//main window controller (swift)
@property(nonatomic, retain)NSWindowController* mainWindowController;

//welcome window controller (swift)
@property(nonatomic, retain)NSWindowController* welcomeWindowController;

//preferences window controller (swift)
@property(nonatomic, retain)NSWindowController* prefsWindowController;

/* METHODS */

//show main window
-(void)showMainWindow;

//(re)activate extension, wait for it to check in (& have full disk access), then go!
// ->status updates are posted via 'notifyStatus'
-(void)startExtension;

//wait for extension to be running & checked in (via XPC)
// ->invokes reply (on background thread) w/ result
-(void)waitForExtension:(void (^)(BOOL))reply NS_SWIFT_NAME(waitForExtension(_:));

//wait for extension to have full disk access (polls via XPC)
// ->invokes reply (on background thread) once granted, or w/ NO on timeout
-(void)waitForFullDiskAccess:(void (^)(BOOL))reply NS_SWIFT_NAME(waitForFullDiskAccess(_:));

//complete initialization
// ->invoked by welcome window once extension is approved/running
-(void)completeInitialization;

//stop extension
// ->stops (live) monitoring, tears down XPC, & deactivates extension (approval is retained)
-(void)stopExtension:(void (^)(void))completion;

//begin task enumeration
-(void)exploreTasks;

//(re)enumerate all tasks
-(IBAction)refreshTasks:(id)sender;

//about
-(IBAction)about:(id)sender;

//show preferences
-(IBAction)showPreferences:(id)sender;

//check for update
-(IBAction)check4Update:(id)sender;

@end
