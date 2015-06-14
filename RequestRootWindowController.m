//
//  PrefsWindowController.m
//  KnockKnock
//
//  Created by Patrick Wardle on 2/6/15.
//  Copyright (c) 2015 Objective-See, LLC. All rights reserved.
//


#import "Utilities.h"
#import "AppDelegate.h"

#import "RequestRootWindowController.h"


@implementation RequestRootWindowController

@synthesize statusMsg;
@synthesize shouldExit;

//TODO: add 'why' / info button :)


//automatically called when nib is loaded
// ->center window
-(void)awakeFromNib
{
    //center
    [self.window center];
    
    return;
}

//automatically invoked when window is loaded
// ->set to white
-(void)windowDidLoad
{
    //super
    [super windowDidLoad];
    
    //make white
    [self.window setBackgroundColor: NSColor.whiteColor];
    
    //set version sting
    //[self.versionLabel setStringValue:[NSString stringWithFormat:@"version: %@", getAppVersion()]];

    return;
}


//automatically invoked when window is closing
// ->make ourselves unmodal and possibly exit app
-(void)windowWillClose:(NSNotification *)notification
{
    //save prefs
    //[self savePrefs];
    
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
    //status var
    BOOL authdOK = NO;
    
    //authorization ref
    AuthorizationRef authorizationRef = {0};
    
    //args
    const char* installArgs[0x10] = {0};
    
    //status code
    OSStatus osStatus = -1;
    
    //path to XPC service
    NSString* xpcService = nil;
    
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
    
    //create authorization ref
    osStatus = AuthorizationCreate(NULL, kAuthorizationEmptyEnvironment, kAuthorizationFlagDefaults, &authorizationRef);
    if(errAuthorizationSuccess != osStatus)
    {
        //err msg
        NSLog(@"ERROR: AuthorizationCreate() failed with %d", osStatus);
        
        //set exit flag
        self.shouldExit = YES;
        
        //bail
        goto bail;
    }
    
    //chown XPC service as r00t
    osStatus = AuthorizationExecuteWithPrivileges(authorizationRef, "/usr/sbin/chown", 0, (char* const*)installArgs, NULL);
    if(errAuthorizationSuccess != osStatus)
    {
        //err msg
        NSLog(@"ERROR: AuthorizationExecuteWithPrivileges() failed with %d", osStatus);
        
        //set result msg
        [self.statusMsg setStringValue: [NSString stringWithFormat:@"error: failed with %d", osStatus]];
         
        //set font to red
        self.statusMsg.textColor = [NSColor redColor];
        
        //set exit flag
        self.shouldExit = YES;
         
        //bail
        goto bail;
    }
    
    /* then setuid */
    
    //1st arg: recursive flag
    installArgs[0] = "-R";
    
    //2nd arg: permissions
    // ->4 at front is setuid
    //TODO: make 4755
    installArgs[1] = "4777";
    
    //3rd arg: XPC service
    installArgs[2] = [xpcService UTF8String];
    
    //end w/ NULL
    installArgs[3] = NULL;
    
    //chmod XPC service w/ setuid
    osStatus = AuthorizationExecuteWithPrivileges(authorizationRef, "/bin/chmod", 0, (char* const*)installArgs, NULL);
    
    //check
    if(errAuthorizationSuccess != osStatus)
    {
        //err msg
        NSLog(@"ERROR: AuthorizationExecuteWithPrivileges() failed with %d", osStatus);
        
        //set result msg
        [self.statusMsg setStringValue: [NSString stringWithFormat:@"error: failed with %d", osStatus]];
        
        //set font to red
        self.statusMsg.textColor = [NSColor redColor];
        
        //set exit flag
        self.shouldExit = YES;
        
        //bail
        goto bail;
    }
    
    //no errors
    authdOK = YES;
    
    //no exit
    self.shouldExit = NO;
    
    //start enumerating tasks
    [((AppDelegate*)[[NSApplication sharedApplication] delegate]) exploreTasks];
    
//bail
bail:
    
    //free auth ref
    if(0 != authorizationRef)
    {
        //free
        AuthorizationFree(authorizationRef, kAuthorizationFlagDefaults);
    }
    
    //on auth/'install' success
    // ->close window
    if(YES == authdOK)
    {
        //close window
        [self.window close];
    }
    
    return;
}

//invoked when user clicks 'cancel' button
// ->set exit flag and close window
-(IBAction)close:(id)sender
{
    //set flag to exit
    self.shouldExit = YES;
    
    //exit
    [self.window close];
}

@end
