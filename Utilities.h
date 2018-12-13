//
//  Utilities.h
//  DHS
//
//  Created by Patrick Wardle on 2/7/15.
//  Copyright (c) 2015 Objective-See. All rights reserved.
//

#ifndef DHS_Utilities_h
#define DHS_Utilities_h

#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>


/* FUNCTIONS */

//loads a framework
// note: assumes it is in 'Framework' dir
NSBundle* loadFramework(NSString* name);

//init crash reporting
void initCrashReporting(void);

//check if OS is supported
BOOL isSupportedOS(void);

//get OS's major or minor version
SInt32 getVersion(OSType selector);

//given a path to binary
// parse it back up to find app's bundle
NSBundle* findAppBundle(NSString* binaryPath);

//given a directory and a filter predicate
// ->return all matches
NSArray* directoryContents(NSString* directory, NSString* predicate);

//hash (sha1/md5) a file
NSDictionary* hashFile(NSString* filePath);

//get app's version
// ->extracted from Info.plist
NSString* getAppVersion();

//convert a textview to a clickable hyperlink
void makeTextViewHyperlink(NSTextField* textField, NSURL* url);

//determine if a file is signed by Apple proper
BOOL isApple(NSString* path);

//set the color of an attributed string
NSMutableAttributedString* setStringColor(NSAttributedString* string, NSColor* color);

//exec a process and grab it's output
NSMutableDictionary* execTask(NSString* binaryPath, NSArray* arguments, BOOL shouldWait);

//wait until a window is non nil
// ->then make it modal
void makeModal(NSWindowController* windowController);

//given a pid, get its parent (ppid)
pid_t getParentID(int pid);

//get path to XPC service
NSString* getPath2XPC();

//get path to kernel
NSString* path2Kernel();

//determine if process is (still) alive
BOOL isAlive(pid_t targetPID);

//check if computer has network connection
BOOL isNetworkConnected();

//set or unset button's highlight
void buttonAppearance(NSTableView* table, NSEvent* event, BOOL shouldReset);

//check	if remote process is i386
BOOL Is32Bit(pid_t targetPID);

//check if app is translocated
// ->based on http://lapcatsoftware.com/articles/detect-app-translocation.html
NSURL* getUnTranslocatedURL();

//check if (full) dark mode
// meaning, Mojave+ and dark mode enabled
BOOL isDarkMode();

#endif
