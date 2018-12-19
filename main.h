//
//  main.h
//  TaskExplorer
//
//  Created by Patrick Wardle on 12/16/18.
//  Copyright © 2018 Lucas Derraugh. All rights reserved.
//

#ifndef main_h
#define main_h

#import "Consts.h"
#import "Filter.h"
#import "Utilities.h"
#import "VirusTotal.h"
#import "AppDelegate.h"

#import "TaskEnumerator.h"

#import <Cocoa/Cocoa.h>

//(privacy) protected directories
NSString * const PROTECTED_DIRECTORIES[] = {@"~/Library/Application Support/AddressBook", @"~/Library/Calendars", @"~/Pictures", @"~/Library/Mail", @"~/Library/Messages", @"~/Library/Safari", @"~/Library/Cookies", @"~/Library/HomeKit", @"~/Library/IdentityServices", @"~/Library/Metadata/CoreSpotlight", @"~/Library/PersonalizationPortrait", @"~/Library/Suggestions"};

/* GLOBALS */

//task enumerator obj
TaskEnumerator* taskEnumerator = nil;

//virustotal obj
VirusTotal* virusTotal = nil;

//network connected flag
BOOL isConnected = NO;

//(privacy) protected directories
NSArray* protectedDirectories = nil;

/* FUNCTIONS */

//print usage
void usage(void);

//perform a cmdline enumeration
void cmdlineExplore(void);

//block until vt queries are done
void completeVTQuery(void);

//pretty print JSON
void prettyPrintJSON(NSString* output);

#endif /* main_h */
