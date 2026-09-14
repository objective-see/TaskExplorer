//
//  ItemBase.h
//  TaskExplorer
//
//  Created by Patrick Wardle on 9/25/14.
//  Copyright (c) 2014 Objective-See. All rights reserved.
//

#import <Foundation/Foundation.h>

@class Task;

@interface ItemBase : NSObject
{

}

//name
@property(retain, nonatomic)NSString* name;

//path
@property(retain, nonatomic)NSString* path;

//icon
@property(nonatomic, retain)NSImage* icon;

//file attributes
@property(nonatomic, retain)NSDictionary* attributes;

//hosts
// ->pids of tasks this item is 'in' (loaded dylib, open file, connection, etc)
//   maintained (live) by the task enumerator, so queries such as 'loaded in' are O(1)
@property(nonatomic, retain)NSMutableSet* hosts;

/* METHODS */

//init method
-(id)initWithParams:(NSDictionary*)params;

//return a path that can be opened in Finder.app
-(NSString*)pathForFinder;

//add a host (pid)
-(void)addHost:(NSNumber*)pid;

//remove a host (pid)
-(void)removeHost:(NSNumber*)pid;

//is item hosted by pid?
-(BOOL)isHostedBy:(NSNumber*)pid;

//number of hosts
-(NSUInteger)hostCount;

//host tasks
// ->resolves host pids to (live) task objects
-(NSArray<Task*>*)hostTasks;

//convert object to JSON string
-(NSString*)toJSON;

@end
