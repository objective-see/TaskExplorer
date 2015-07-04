//
//  PrefsWindowController.h
//  DHS
//
//  Created by Patrick Wardle on 2/6/15.
//  Copyright (c) 2015 Objective-See, LLC. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface RequestRootWindowController : NSWindowController <NSWindowDelegate>
{
    
}

/* PROPERTIES */

//auth button
@property (weak) IBOutlet NSButton *authButton;

//arrow icon
@property (weak) IBOutlet NSImageView *arrowIcon;

//help button
@property (weak) IBOutlet NSButton *helpButton;

//status msg
@property (weak) IBOutlet NSTextField *statusMsg;

//flag indicating app should exit
@property BOOL shouldExit;

/* METHODS */

//invoked when user clicks 'auth' button
// ->auths user!
-(IBAction)authenticate:(id)sender;

//invoked when user clicks 'help' button
// ->open product's page w/ anchor to help
-(IBAction)help:(id)sender;

//invoked when user clicks 'cancel' button
// ->exits app
-(IBAction)close:(id)sender;

@end
