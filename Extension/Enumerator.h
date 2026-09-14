//
//  file: Enumerator.h
//  project: TaskExplorer (extension)
//  description: enumerate processes, dylibs, files (header)
//
//  created by Patrick Wardle
//  copyright (c) 2026 Objective-See. All rights reserved.
//

#ifndef Enumerator_h
#define Enumerator_h

#import <Foundation/Foundation.h>

@interface Enumerator : NSObject

/* METHODS */

//enumerate all (running) processes
// returns array of process dictionaries (see KEY_PROCESS_* in Consts.h)
-(NSArray*)enumerateProcesses;

//build a process dictionary for a pid
-(NSDictionary*)processInfo:(pid_t)pid;

//enumerate (loaded) dylibs for a process
// returns array of paths
-(NSArray*)enumerateDylibs:(pid_t)pid;

//enumerate (open) files for a process
// returns array of paths
-(NSArray*)enumerateFiles:(pid_t)pid;

//enumerate all dylibs (incl. dyld shared cache) via vmmap
-(NSArray*)enumerateAllDylibs:(pid_t)pid;

@end

#endif /* Enumerator_h */
