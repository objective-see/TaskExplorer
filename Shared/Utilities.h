//
//  Utilities.h
//  TaskExplorer (shared)
//
//  Created by Patrick Wardle on 2/7/15.
//  Copyright (c) 2015 Objective-See. All rights reserved.
//
//  note: shared between app & extension
//        so, no AppKit! (see App/UIUtilities.h for UI helpers)

#ifndef TE_Utilities_h
#define TE_Utilities_h

#import <Foundation/Foundation.h>

//private dyld api
extern bool _dyld_shared_cache_contains_path(const char* path);

/* FUNCTIONS */

//given a path to binary
// parse it back up to find app's bundle
NSBundle* findAppBundle(NSString* binaryPath);

//hash (sha1/md5) a file
//escape a string for embedding in (hand-built) JSON
NSString* jsonEscape(NSString* string);

//hash a file
NSDictionary* hashFile(NSString* filePath);

//get app's version
// ->extracted from Info.plist
NSString* getAppVersion(void);

//exec a process and grab it's output
NSMutableDictionary* execTask(NSString* binaryPath, NSArray* arguments, BOOL shouldWait);

//exec path of a process (from 'KERN_PROCARGS2')
NSString* getProcessExecPath(pid_t pid);

//given a pid, get its parent (ppid)
pid_t getParentID(int pid);

//given a pid, get its path
NSString* getProcessPath(pid_t pid);

//get task's commandline args
NSMutableArray* getProcessArguments(pid_t pid);

//find (running) processes by name
// returns array of pids
NSMutableArray* findProcesses(NSString* processName);

//get path to kernel
NSString* path2Kernel(void);

//determine if process is (still) alive
BOOL isAlive(pid_t targetPID);

//check if computer has network connection
BOOL isNetworkConnected(void);

//check if file is in shared cache
// uses private _dyld_shared_cache_contains_path API
BOOL isInSharedCache(NSString* path);

//save a (generic password) keychain item
// note: empty value deletes existing
BOOL saveKeychainItem(NSString* service, NSString* value);

//load a (generic password) keychain item
NSString* loadKeychainItem(NSString* service);

//delete a (generic password) keychain item
void deleteKeychainItem(NSString* service);

//save (user's) VT API key to keychain
// note: empty key deletes existing
BOOL saveAPIKeyToKeychain(NSString* apiKey);

//(re)load VT API key from keychain
NSString* loadAPIKeyFromKeychain(void);

//open a regular file (no devices, fifos, etc) of at most 'maxSize'
// returns fd (or -1), and optionally the file's size
int openRegularFile(NSString* path, off_t maxSize, off_t* size);

#endif
