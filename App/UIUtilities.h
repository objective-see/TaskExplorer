//
//  UIUtilities.h
//  TaskExplorer (app)
//
//  Created by Patrick Wardle on 2/7/15.
//  Copyright (c) 2015 Objective-See. All rights reserved.
//
//  note: app-only (AppKit) helpers
//        (shared helpers live in Shared/Utilities.h)

#ifndef TE_UIUtilities_h
#define TE_UIUtilities_h

#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>

/* FUNCTIONS */

//check if app is translocated
// ->based on http://lapcatsoftware.com/articles/detect-app-translocation.html
NSURL* getUnTranslocatedURL(void);

//give a list of paths
// convert any `~` to all or current user
NSMutableArray* expandPaths(const __strong NSString* const paths[], int count);

//bring an app to foreground (to get an icon in the dock) or background
void transformProcess(ProcessApplicationTransformState location);

//show an alert
NSModalResponse showAlert(NSAlertStyle style, NSString* messageText, NSString* informativeText, NSArray* buttons);

//check for full disk access
BOOL hasFullDiskAccess(void);

//(registered) preference defaults
NSDictionary* preferenceDefaults(void);

//get a (bool) preference (or its registered default)
BOOL getPreferenceBool(NSString* key);

//set a preference
void setPreference(NSString* key, id value);

#endif
