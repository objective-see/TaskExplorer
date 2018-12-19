//
//  PrefsWindowController.m
//  TaskExplorer
//
//  Created by Patrick Wardle on 2/6/15.
//  Copyright (c) 2015 Objective-See, LLC. All rights reserved.
//


#import "Utilities.h"
#import "AppDelegate.h"
#import "PrefsWindowController.h"


@implementation PrefsWindowController

@synthesize okButton;
@synthesize saveOutput;
@synthesize shouldSaveNow;
@synthesize disableVTQueries;
@synthesize showTrustedItems;


//automatically called when nib is loaded
// ->center window
-(void)awakeFromNib
{
    //center
    [self.window center];
}


//automatically invoked when window is loaded
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
    
    //make button selected
    [self.window makeFirstResponder:self.okButton];
    
    //capture existing prefs
    // needed to trigger re-saves
    [self captureExistingPrefs];
    
    return;
}

//save existing prefs
-(void)captureExistingPrefs
{
    //save current state of 'include os/trusted' components
    self.showTrustedItems = self.showTrustedItemsBtn.state;
    
    //save current state of 'disable VT'
    self.disableVTQueries = self.disableVTQueriesBtn.state;
    
    //save current state of 'save' button
    self.saveOutput = self.saveOutputBtn.state;
    
    return;
}

//automatically invoked when window is closing
// ->make ourselves unmodal
-(void)windowWillClose:(NSNotification *)notification
{
    //save prefs
    //[self savePrefs];
    
    //make un-modal
    [[NSApplication sharedApplication] stopModal];
    
    return;
}

//'OK' button handler
// ->save prefs and close window
-(IBAction)closeWindow:(id)sender
{
    //close
    [self.window close];
    
    return;
}
@end
