//
//  RequestRootWindowController.m
//  TaskExplorer
//
//  Created by Patrick Wardle on 2/6/15.
//  Copyright (c) 2015 Objective-See, LLC. All rights reserved.
//


#import "Utilities.h"
#import "AppDelegate.h"
#import "RequestRootWindowController.h"

#import <syslog.h>


@implementation RequestRootWindowController

@synthesize statusMsg;
@synthesize authButton;
@synthesize shouldExit;
@synthesize cancelButton;

//automatically called when nib is loaded
// ->center window
-(void)awakeFromNib
{
    //center
    [self.window center];
    
    //make auth button one in focus
    [self.window makeFirstResponder:self.authButton];
    
    //default to exit app
    // ->unset if auth is succesful
    self.shouldExit = YES;
    
    return;
}

//automatically invoked when window is loaded
// ->set to white
-(void)windowDidLoad
{
    //super
    [super windowDidLoad];
    
    //no dark mode?
    // make window white
    if(YES != isDarkMode())
    {
        //make white
        self.window.backgroundColor = NSColor.whiteColor;
    }
    
    //set version sting
    //[self.versionLabel setStringValue:[NSString stringWithFormat:@"version: %@", getAppVersion()]];

    return;
}


//automatically invoked when window is closing
// ->make ourselves unmodal and possibly exit app
-(void)windowWillClose:(NSNotification *)notification
{
    //make un-modal
    [[NSApplication sharedApplication] stopModal];
    
    //on errors, cancels
    // ->exit app
    if(YES == self.shouldExit)
    {
        //exit
        [NSApp terminate:self];
    }
    
    return;
}

//invoked when user clicks 'auth' button
// ->auth user, then set XPC service as root/setuid
-(IBAction)authenticate:(id)sender
{
    //authorization ref
    AuthorizationRef authorizationRef = {0};
    
    //args
    const char* installArgs[0x10] = {0};
    
    //status code
    OSStatus osStatus = -1;
    
    //path to XPC service
    NSString* xpcService = nil;
    
    //hide arrow icon
    self.arrowIcon.hidden = YES;
    
    //hide help button
    self.helpButton.hidden = YES;
    
    //get path to XPC service
    xpcService = getPath2XPC();
    if(nil == xpcService)
    {
        //bail
        goto bail;
    }
    
    /* first chown as root */
    
    //1st arg: recursive flag
    installArgs[0] = "-R";
    
    //2nd arg: group/owner
    installArgs[1] = "root:wheel";
    
    //3rd arg: XPC service
    installArgs[2] = [xpcService UTF8String];
    
    //end w/ NULL
    installArgs[3] = NULL;
    
    //reset text color
    self.statusMsg.textColor = NSColor.controlTextColor;
    
    //create authorization ref
    osStatus = AuthorizationCreate(NULL, kAuthorizationEmptyEnvironment, kAuthorizationFlagDefaults, &authorizationRef);
    if(errAuthorizationSuccess != osStatus)
    {
        //err msg
        syslog(LOG_ERR, "OBJECTIVE-SEE ERROR: AuthorizationCreate() failed with %d", osStatus);
        
        //bail
        goto bail;
    }
    
    //chown XPC service as r00t
    osStatus = AuthorizationExecuteWithPrivileges(authorizationRef, "/usr/sbin/chown", 0, (char* const*)installArgs, NULL);
    if(errAuthorizationSuccess != osStatus)
    {
        //err msg
        syslog(LOG_ERR, "OBJECTIVE-SEE ERROR: AuthorizationExecuteWithPrivileges() failed with %d", osStatus);
        
        //set result msg
        [self.statusMsg setStringValue: [NSString stringWithFormat:@"error: failed with %d", osStatus]];
         
        //set font to red
        self.statusMsg.textColor = [NSColor redColor];
        
        //bail
        goto bail;
    }
    
    /* then setuid */
    
    //1st arg: recursive flag
    installArgs[0] = "-R";
    
    //2nd arg: permissions
    // ->note: 4 at front is setuid
    installArgs[1] = "4755";
    
    //3rd arg: XPC service
    installArgs[2] = [xpcService UTF8String];
    
    //end w/ NULL
    installArgs[3] = NULL;
    
    //chmod XPC service w/ setuid
    osStatus = AuthorizationExecuteWithPrivileges(authorizationRef, "/bin/chmod", 0, (char* const*)installArgs, NULL);
    if(errAuthorizationSuccess != osStatus)
    {
        //err msg
        syslog(LOG_ERR, "OBJECTIVE-SEE ERROR: AuthorizationExecuteWithPrivileges() failed with %d", osStatus);
        
        //set result msg
        [self.statusMsg setStringValue: [NSString stringWithFormat:@"error: failed with %d", osStatus]];
        
        //set font to red
        self.statusMsg.textColor = [NSColor redColor];
        
        //bail
        goto bail;
    }

    //no exit
    self.shouldExit = NO;
    
    //disable auth button
    self.authButton.enabled = NO;
    
    //disable cancel button
    self.cancelButton.enabled = NO;
    
    //update auth message
    self.statusMsg.stringValue = @"...authorization successful!";
    
    //wait a bit
    // ->then hide window & kick off action
    {
        
    //dispatch, then action
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(.50 * NSEC_PER_SEC)), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        
        //close window
        [self.window close];
        
        //exec UI actions etc on main thread
        dispatch_async(dispatch_get_main_queue(), ^{

            //make sure app's key window is (still) front
            [((AppDelegate*)[[NSApplication sharedApplication] delegate]).window makeKeyAndOrderFront:self];
            
            //make sure app is (still) front
            [NSApp activateIgnoringOtherApps:YES];
            
            //call back into app delegate
            // ->kick off task enum, etc
            [((AppDelegate*)[[NSApplication sharedApplication] delegate]) go];
            
        });
    });
        
    }

//bail
bail:
    
    //free auth ref
    if(0 != authorizationRef)
    {
        //free
        AuthorizationFree(authorizationRef, kAuthorizationFlagDestroyRights);
    }
    
    
    
    return;
}

//invoked when user clicks 'cancel' button
// ->close window, which will trigger app exit
-(IBAction)close:(id)sender
{
    //exit
    [self.window close];
}

//invoked when user clicks 'help' button
// ->open product's page w/ anchor to help
-(IBAction)help:(id)sender
{
    //open URL
    // ->invokes user's default browser
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://objective-see.com/products/taskexplorer.html#help"]];
    
    return;
}
@end
